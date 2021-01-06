$ErrorActionPreference = "Stop"

# Collect generic and recommendation-specific variables

$cloudEnvironment = Get-AutomationVariable -Name "AzureOptimization_CloudEnvironment" -ErrorAction SilentlyContinue # AzureCloud|AzureChinaCloud
if ([string]::IsNullOrEmpty($cloudEnvironment))
{
    $cloudEnvironment = "AzureCloud"
}
$authenticationOption = Get-AutomationVariable -Name "AzureOptimization_AuthenticationOption" -ErrorAction SilentlyContinue # RunAsAccount|ManagedIdentity
if ([string]::IsNullOrEmpty($authenticationOption))
{
    $authenticationOption = "RunAsAccount"
}

$workspaceId = Get-AutomationVariable -Name  "AzureOptimization_LogAnalyticsWorkspaceId"
$workspaceName = Get-AutomationVariable -Name  "AzureOptimization_LogAnalyticsWorkspaceName"
$workspaceRG = Get-AutomationVariable -Name  "AzureOptimization_LogAnalyticsWorkspaceRG"
$workspaceSubscriptionId = Get-AutomationVariable -Name  "AzureOptimization_LogAnalyticsWorkspaceSubId"
$workspaceTenantId = Get-AutomationVariable -Name  "AzureOptimization_LogAnalyticsWorkspaceTenantId"

$storageAccountSink = Get-AutomationVariable -Name  "AzureOptimization_StorageSink"
$storageAccountSinkRG = Get-AutomationVariable -Name  "AzureOptimization_StorageSinkRG"
$storageAccountSinkSubscriptionId = Get-AutomationVariable -Name  "AzureOptimization_StorageSinkSubId"
$storageAccountSinkContainer = Get-AutomationVariable -Name  "AzureOptimization_RecommendationsContainer" -ErrorAction SilentlyContinue 
if ([string]::IsNullOrEmpty($storageAccountSinkContainer)) {
    $storageAccountSinkContainer = "recommendationsexports"
}

$deploymentDate = Get-AutomationVariable -Name  "AzureOptimization_DeploymentDate" # yyyy-MM-dd format

$lognamePrefix = Get-AutomationVariable -Name  "AzureOptimization_LogAnalyticsLogPrefix" -ErrorAction SilentlyContinue
if ([string]::IsNullOrEmpty($lognamePrefix))
{
    $lognamePrefix = "AzureOptimization"
}

$sqlserver = Get-AutomationVariable -Name  "AzureOptimization_SQLServerHostname"
$sqlserverCredential = Get-AutomationPSCredential -Name "AzureOptimization_SQLServerCredential"
$SqlUsername = $sqlserverCredential.UserName 
$SqlPass = $sqlserverCredential.GetNetworkCredential().Password 
$sqldatabase = Get-AutomationVariable -Name  "AzureOptimization_SQLServerDatabase" -ErrorAction SilentlyContinue
if ([string]::IsNullOrEmpty($sqldatabase))
{
    $sqldatabase = "azureoptimization"
}

$deallocatedIntervalDays = [int] (Get-AutomationVariable -Name  "AzureOptimization_RecommendationLongDeallocatedVmsIntervalDays")
$consumptionOffsetDays = [int] (Get-AutomationVariable -Name  "AzureOptimization_ConsumptionOffsetDays")
$consumptionOffsetDaysStart = $consumptionOffsetDays + 1

$SqlTimeout = 120
$LogAnalyticsIngestControlTable = "LogAnalyticsIngestControl"

# Authenticate against Azure

Write-Output "Logging in to Azure with $authenticationOption..."

switch ($authenticationOption) {
    "RunAsAccount" { 
        $ArmConn = Get-AutomationConnection -Name AzureRunAsConnection
        Connect-AzAccount -ServicePrincipal -EnvironmentName $cloudEnvironment -Tenant $ArmConn.TenantID -ApplicationId $ArmConn.ApplicationID -CertificateThumbprint $ArmConn.CertificateThumbprint
        break
    }
    "ManagedIdentity" { 
        Connect-AzAccount -Identity
        break
    }
    Default {
        $ArmConn = Get-AutomationConnection -Name AzureRunAsConnection
        Connect-AzAccount -ServicePrincipal -EnvironmentName $cloudEnvironment -Tenant $ArmConn.TenantID -ApplicationId $ArmConn.ApplicationID -CertificateThumbprint $ArmConn.CertificateThumbprint
        break
    }
}

Write-Output "Finding tables where recommendations will be generated from..."

$tries = 0
$connectionSuccess = $false
do {
    $tries++
    try {
        $Conn = New-Object System.Data.SqlClient.SqlConnection("Server=tcp:$sqlserver,1433;Database=$sqldatabase;User ID=$SqlUsername;Password=$SqlPass;Trusted_Connection=False;Encrypt=True;Connection Timeout=$SqlTimeout;") 
        $Conn.Open() 
        $Cmd=new-object system.Data.SqlClient.SqlCommand
        $Cmd.Connection = $Conn
        $Cmd.CommandTimeout = $SqlTimeout
        $Cmd.CommandText = "SELECT * FROM [dbo].[$LogAnalyticsIngestControlTable] WHERE CollectedType IN ('ARGManagedDisk','ARGVirtualMachine','AzureConsumption')"
    
        $sqlAdapter = New-Object System.Data.SqlClient.SqlDataAdapter
        $sqlAdapter.SelectCommand = $Cmd
        $controlRows = New-Object System.Data.DataTable
        $sqlAdapter.Fill($controlRows) | Out-Null            
        $connectionSuccess = $true
    }
    catch {
        Write-Output "Failed to contact SQL at try $tries."
        Write-Output $Error[0]
        Start-Sleep -Seconds ($tries * 20)
    }    
} while (-not($connectionSuccess) -and $tries -lt 3)

if (-not($connectionSuccess))
{
    throw "Could not establish connection to SQL."
}

$vmsTableName = $lognamePrefix + ($controlRows | Where-Object { $_.CollectedType -eq 'ARGVirtualMachine' }).LogAnalyticsSuffix + "_CL"
$disksTableName = $lognamePrefix + ($controlRows | Where-Object { $_.CollectedType -eq 'ARGManagedDisk' }).LogAnalyticsSuffix + "_CL"
$consumptionTableName = $lognamePrefix + ($controlRows | Where-Object { $_.CollectedType -eq 'AzureConsumption' }).LogAnalyticsSuffix + "_CL"

Write-Output "Will run query against tables $vmsTableName, $disksTableName and $consumptionTableName"

$Conn.Close()    
$Conn.Dispose()            

$recommendationSearchTimeSpan = $deallocatedIntervalDays + $consumptionOffsetDaysStart
$offlineInterval = $deallocatedIntervalDays + $consumptionOffsetDays
$billingInterval = 30 + $consumptionOffsetDays

# Grab a context reference to the Storage Account where the recommendations file will be stored

Select-AzSubscription -SubscriptionId $storageAccountSinkSubscriptionId
$sa = Get-AzStorageAccount -ResourceGroupName $storageAccountSinkRG -Name $storageAccountSink

if ($workspaceSubscriptionId -ne $storageAccountSinkSubscriptionId)
{
    Select-AzSubscription -SubscriptionId $workspaceSubscriptionId
}

# Execute the recommendation query against Log Analytics

$baseQuery = @"
    let offlineInterval = $($offlineInterval)d;
    let billingInterval = $($billingInterval)d;
    let billingWindowIntervalEnd = $($consumptionOffsetDays)d; 
    let billingWindowIntervalStart = $($consumptionOffsetDaysStart)d; 
    let etime = todatetime(toscalar($consumptionTableName | summarize max(UsageDate_t))); 
    let stime = etime-offlineInterval;

    let BilledVMs = $consumptionTableName 
    | where UsageDate_t between (stime..etime)
    | where InstanceId_s like 'microsoft.compute/virtualmachines/' 
    | distinct InstanceId_s;

    let BilledDisks = $consumptionTableName 
    | where UsageDate_t between (stime..etime)
    | where InstanceId_s like 'microsoft.compute/disks/'
    | extend BillingInstanceId = InstanceId_s
    | summarize DisksCosts = sum(todouble(Cost_s)) by BillingInstanceId;

    $vmsTableName
    | where TimeGenerated > ago(billingWindowIntervalStart) and TimeGenerated < ago(billingWindowIntervalEnd)
    | where InstanceId_s !in (BilledVMs) 
    | project InstanceId_s, VMName_s, ResourceGroupName_s, SubscriptionGuid_g, Cloud_s, Tags_s 
    | join kind=leftouter (
        $disksTableName 
        | where TimeGenerated > ago(1d)
        | project DiskInstanceId = InstanceId_s, SKU_s, OwnerVMId_s
    ) on `$left.InstanceId_s == `$right.OwnerVMId_s
    | join kind=leftouter (
        BilledDisks
    ) on `$left.DiskInstanceId == `$right.BillingInstanceId
    | summarize TotalDisksCosts = sum(DisksCosts) by InstanceId_s, VMName_s, ResourceGroupName_s, SubscriptionGuid_g, Cloud_s, Tags_s
"@

$queryResults = Invoke-AzOperationalInsightsQuery -WorkspaceId $workspaceId -Query $baseQuery -Timespan (New-TimeSpan -Days $recommendationSearchTimeSpan) -Wait 600 -IncludeStatistics
$results = [System.Linq.Enumerable]::ToArray($queryResults.Results)

Write-Output "Query finished with $($results.Count) results."

Write-Output "Query statistics: $($queryResults.Statistics.query)"

# Build the recommendations objects

$recommendations = @()
$datetime = (get-date).ToUniversalTime()
$timestamp = $datetime.ToString("yyyy-MM-ddTHH:mm:00.000Z")

foreach ($result in $results)
{
    $queryInstanceId = $result.InstanceId_s
    $querySubscriptionId = $result.SubscriptionGuid_g
    $queryText = @"
        let offlineInterval = $($offlineInterval)d;
        $consumptionTableName
        | where InstanceId_s == '$queryInstanceId'
        | join kind=inner (
            $disksTableName
            | extend DiskInstanceId = InstanceId_s
        )
        on `$left.InstanceId_s == `$right.OwnerVMId_s
        | summarize DeallocatedSince = max(UsageDate_t) by DiskName_s, DiskSizeGB_s, SKU_s, DiskInstanceId 
        | join kind=inner
        (
            $consumptionTableName
            | where UsageDate_t > ago(offlineInterval)
            | extend DiskInstanceId = InstanceId_s
            | summarize DiskCosts = sum(todouble(Cost_s)) by DiskInstanceId
        )
        on DiskInstanceId
        | project DeallocatedSince, DiskName_s, DiskSizeGB_s, SKU_s, MonthlyCosts = DiskCosts
"@
    $encodedQuery = [System.Uri]::EscapeDataString($queryText)
    $detailsQueryStart = $deploymentDate
    $detailsQueryEnd = $datetime.AddDays(1).ToString("yyyy-MM-dd")
    $detailsURL = "https://portal.azure.com#@$workspaceTenantId/blade/Microsoft_Azure_Monitoring_Logs/LogsBlade/resourceId/%2Fsubscriptions%2F$querySubscriptionId%2Fresourcegroups%2F$workspaceRG%2Fproviders%2Fmicrosoft.operationalinsights%2Fworkspaces%2F$workspaceName/source/LogsBlade.AnalyticsShareLinkToQuery/query/$encodedQuery/timespan/$($detailsQueryStart)T00%3A00%3A00.000Z%2F$($detailsQueryEnd)T00%3A00%3A00.000Z"

    $additionalInfoDictionary = @{}

    $additionalInfoDictionary["LongDeallocatedThreshold"] = $deallocatedIntervalDays
    $additionalInfoDictionary["CostsAmount"] = [double] $result.TotalDisksCosts 
    $additionalInfoDictionary["savingsAmount"] = [double] $result.TotalDisksCosts 

    $fitScore = 5

    $tags = @{}

    if (-not([string]::IsNullOrEmpty($result.Tags_s)))
    {
        $tagPairs = $result.Tags_s.Substring(2, $result.Tags_s.Length - 3).Split(';')
        foreach ($tagPairString in $tagPairs)
        {
            $tagPair = $tagPairString.Split('=')
            if (-not([string]::IsNullOrEmpty($tagPair[0])) -and -not([string]::IsNullOrEmpty($tagPair[1])))
            {
                $tagName = $tagPair[0].Trim()
                $tagValue = $tagPair[1].Trim()
                $tags[$tagName] = $tagValue    
            }
        }
    }

    $recommendation = New-Object PSObject -Property @{
        Timestamp = $timestamp
        Cloud = $result.Cloud_s
        Category = "Cost"
        ImpactedArea = "Microsoft.Compute/virtualMachines"
        Impact = "Medium"
        RecommendationType = "Saving"
        RecommendationSubType = "LongDeallocatedVms"
        RecommendationSubTypeId = "c320b790-2e58-452a-aa63-7b62c383ad8a"
        RecommendationDescription = "Virtual Machine has been deallocated for long with disks still incurring costs"
        RecommendationAction = "Delete Virtual Machine or downgrade its disks to Standard HDD SKU"
        InstanceId = $result.InstanceId_s
        InstanceName = $result.VMName_s
        AdditionalInfo = $additionalInfoDictionary
        ResourceGroup = $result.ResourceGroupName_s
        SubscriptionGuid = $result.SubscriptionGuid_g
        FitScore = $fitScore
        Tags = $tags
        DetailsURL = $detailsURL
    }

    $recommendations += $recommendation
}

# Export the recommendations as JSON to blob storage

$fileDate = $datetime.ToString("yyyy-MM-dd")
$jsonExportPath = "longdeallocatedvms-$fileDate.json"
$recommendations | ConvertTo-Json | Out-File $jsonExportPath

$jsonBlobName = $jsonExportPath
$jsonProperties = @{"ContentType" = "application/json"};
Set-AzStorageBlobContent -File $jsonExportPath -Container $storageAccountSinkContainer -Properties $jsonProperties -Blob $jsonBlobName -Context $sa.Context -Force
