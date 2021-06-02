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
$deploymentDate = $deploymentDate.Replace('"', "")

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

$subnetMaxUsedThresholdVar = Get-AutomationVariable -Name  "AzureOptimization_RecommendationVNetSubnetMaxUsedPercentageThreshold" -ErrorAction SilentlyContinue
if ([string]::IsNullOrEmpty($subnetMaxUsedThresholdVar) -or $subnetMaxUsedThresholdVar -eq 0)
{
    $subnetMaxUsedThreshold = 80
}
else
{
    $subnetMaxUsedThreshold = [int] $subnetMaxUsedThresholdVar
}

$subnetMinUsedThresholdVar = Get-AutomationVariable -Name  "AzureOptimization_RecommendationVNetSubnetMinUsedPercentageThreshold" -ErrorAction SilentlyContinue
if ([string]::IsNullOrEmpty($subnetMinUsedThresholdVar) -or $subnetMinUsedThresholdVar -eq 0)
{
    $subnetMinUsedThreshold = 5
}
else
{
    $subnetMinUsedThreshold = [int] $subnetMinUsedThresholdVar
}

# must be a comma-separated, single-quote enclosed list of subnet names, e.g., 'gatewaysubnet','azurebastionsubnet'
$subnetFreeExclusions = Get-AutomationVariable -Name  "AzureOptimization_RecommendationVNetSubnetUsedPercentageExclusions" -ErrorAction SilentlyContinue
if ([string]::IsNullOrEmpty($subnetFreeExclusions))
{
    $subnetFreeExclusions = "'gatewaysubnet'"
}

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
        $Cmd.CommandText = "SELECT * FROM [dbo].[$LogAnalyticsIngestControlTable] WHERE CollectedType IN ('ARGNetworkInterface','ARGVirtualNetwork','ARGResourceContainers')"
    
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

$nicsTableName = $lognamePrefix + ($controlRows | Where-Object { $_.CollectedType -eq 'ARGNetworkInterface' }).LogAnalyticsSuffix + "_CL"
$vNetsTableName = $lognamePrefix + ($controlRows | Where-Object { $_.CollectedType -eq 'ARGVirtualNetwork' }).LogAnalyticsSuffix + "_CL"
$subscriptionsTableName = $lognamePrefix + ($controlRows | Where-Object { $_.CollectedType -eq 'ARGResourceContainers' }).LogAnalyticsSuffix + "_CL"

Write-Output "Will run query against tables $nicsTableName, $subscriptionsTableName and $vNetsTableName"

$Conn.Close()    
$Conn.Dispose()            

$recommendationSearchTimeSpan = 30 + $consumptionOffsetDaysStart

# Grab a context reference to the Storage Account where the recommendations file will be stored

Select-AzSubscription -SubscriptionId $storageAccountSinkSubscriptionId
$sa = Get-AzStorageAccount -ResourceGroupName $storageAccountSinkRG -Name $storageAccountSink

if ($workspaceSubscriptionId -ne $storageAccountSinkSubscriptionId)
{
    Select-AzSubscription -SubscriptionId $workspaceSubscriptionId
}

<#

Orphaned NICs

AzureOptimizationNICsV1_CL
| where isempty(OwnerVMId_s) and isempty(OwnerPEId_s)

AzureOptimizationVNetsV1_CL
| where toint(SubnetUsedIPs_s) == 0

#>

Write-Output "Looking for subnets with free IP space less than $subnetMaxUsedThreshold%, excluding $subnetFreeExclusions..."

$baseQuery = @"
    $vNetsTableName
    | where TimeGenerated > ago(1d)
    | where SubnetName_s !in ($subnetFreeExclusions)
    | extend FreeIPs = toint(SubnetTotalPrefixIPs_s) - toint(SubnetUsedIPs_s)
    | extend UsedIPPercentage = (todouble(SubnetUsedIPs_s) / todouble(SubnetTotalPrefixIPs_s)) * 100
    | where UsedIPPercentage >= $subnetMaxUsedThreshold
    | join kind=leftouter ( 
        $subscriptionsTableName 
        | where TimeGenerated > ago(1d)
        | where ContainerType_s =~ 'microsoft.resources/subscriptions' 
        | project SubscriptionGuid_g, SubscriptionName = ContainerName_s 
    ) on SubscriptionGuid_g
"@

try
{
    $queryResults = Invoke-AzOperationalInsightsQuery -WorkspaceId $workspaceId -Query $baseQuery -Timespan (New-TimeSpan -Days $recommendationSearchTimeSpan) -Wait 600 -IncludeStatistics
    if ($queryResults)
    {
        $results = [System.Linq.Enumerable]::ToArray($queryResults.Results)        
    }
}
catch
{
    Write-Warning -Message "Query failed. Debug the following query in the AOE Log Analytics workspace: $baseQuery"    
}

Write-Output "Query finished with $($results.Count) results."

Write-Output "Query statistics: $($queryResults.Statistics.query)"

# Build the recommendations objects

$recommendations = @()
$datetime = (get-date).ToUniversalTime()
$timestamp = $datetime.ToString("yyyy-MM-ddTHH:mm:00.000Z")

foreach ($result in $results)
{
    $queryInstanceId = $result.InstanceId_s
    $detailsURL = "https://portal.azure.com/#@$($result.TenantGuid_g)/resource/$queryInstanceId/subnets"

    $additionalInfoDictionary = @{}

    $additionalInfoDictionary["subnetName"] = $result.SubnetName_s
    $additionalInfoDictionary["subnetPrefix"] = $result.SubnetPrefix_s 
    $additionalInfoDictionary["subnetTotalIPs"] = $result.SubnetTotalPrefixIPs_s 
    $additionalInfoDictionary["subnetFreeIPs"] = $result.FreeIPs 
    $additionalInfoDictionary["subnetUsedIPPercentage"] = $result.UsedIPPercentage 

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
        Category = "OperationalExcellence"
        ImpactedArea = "Microsoft.Network/virtualNetworks"
        Impact = "Medium"
        RecommendationType = "BestPractices"
        RecommendationSubType = "HighSubnetIPSpaceUsage"
        RecommendationSubTypeId = "5292525b-5095-4e52-803e-e17192f1d099"
        RecommendationDescription = "Subnets with a high IP space usage may constrain operations"
        RecommendationAction = "Move network devices to a subnet with a larger address space"
        InstanceId = $result.InstanceId_s
        InstanceName = "$($result.VNetName_s)/$($result.SubnetName_s)"
        AdditionalInfo = $additionalInfoDictionary
        ResourceGroup = $result.ResourceGroupName_s
        SubscriptionGuid = $result.SubscriptionGuid_g
        SubscriptionName = $result.SubscriptionName
        TenantGuid = $result.TenantGuid_g
        FitScore = $fitScore
        Tags = $tags
        DetailsURL = $detailsURL
    }

    $recommendations += $recommendation
}

# Export the recommendations as JSON to blob storage

$fileDate = $datetime.ToString("yyyy-MM-dd")
$jsonExportPath = "subnetshighspaceusage-$fileDate.json"
$recommendations | ConvertTo-Json | Out-File $jsonExportPath

$jsonBlobName = $jsonExportPath
$jsonProperties = @{"ContentType" = "application/json"};
Set-AzStorageBlobContent -File $jsonExportPath -Container $storageAccountSinkContainer -Properties $jsonProperties -Blob $jsonBlobName -Context $sa.Context -Force

Write-Output "Looking for subnets with used IP space less than $subnetMinUsedThreshold%..."

$baseQuery = @"
    $vNetsTableName
    | where TimeGenerated > ago(1d)
    | where SubnetName_s !in ($subnetFreeExclusions)
    | extend FreeIPs = toint(SubnetTotalPrefixIPs_s) - toint(SubnetUsedIPs_s)
    | extend UsedIPPercentage = (todouble(SubnetUsedIPs_s) / todouble(SubnetTotalPrefixIPs_s)) * 100
    | where UsedIPPercentage > 0 and UsedIPPercentage <= $subnetMinUsedThreshold
    | join kind=leftouter ( 
        $subscriptionsTableName 
        | where TimeGenerated > ago(1d)
        | where ContainerType_s =~ 'microsoft.resources/subscriptions' 
        | project SubscriptionGuid_g, SubscriptionName = ContainerName_s 
    ) on SubscriptionGuid_g
"@

try
{
    $queryResults = Invoke-AzOperationalInsightsQuery -WorkspaceId $workspaceId -Query $baseQuery -Timespan (New-TimeSpan -Days $recommendationSearchTimeSpan) -Wait 600 -IncludeStatistics
    if ($queryResults)
    {
        $results = [System.Linq.Enumerable]::ToArray($queryResults.Results)        
    }
}
catch
{
    Write-Warning -Message "Query failed. Debug the following query in the AOE Log Analytics workspace: $baseQuery"    
}

Write-Output "Query finished with $($results.Count) results."

Write-Output "Query statistics: $($queryResults.Statistics.query)"

# Build the recommendations objects

$recommendations = @()
$datetime = (get-date).ToUniversalTime()
$timestamp = $datetime.ToString("yyyy-MM-ddTHH:mm:00.000Z")

foreach ($result in $results)
{
    $queryInstanceId = $result.InstanceId_s
    $detailsURL = "https://portal.azure.com/#@$($result.TenantGuid_g)/resource/$queryInstanceId/subnets"

    $additionalInfoDictionary = @{}

    $additionalInfoDictionary["subnetName"] = $result.SubnetName_s
    $additionalInfoDictionary["subnetPrefix"] = $result.SubnetPrefix_s 
    $additionalInfoDictionary["subnetTotalIPs"] = $result.SubnetTotalPrefixIPs_s 
    $additionalInfoDictionary["subnetUsedIPs_s"] = $result.SubnetUsedIPs_s
    $additionalInfoDictionary["subnetUsedIPPercentage"] = $result.UsedIPPercentage 

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
        Category = "OperationalExcellence"
        ImpactedArea = "Microsoft.Network/virtualNetworks"
        Impact = "Medium"
        RecommendationType = "BestPractices"
        RecommendationSubType = "LowSubnetIPSpaceUsage"
        RecommendationSubTypeId = "0f27b41c-869a-4563-86e9-d1c94232ba81"
        RecommendationDescription = "Subnets with a low IP space usage are a waste of virtual network address space"
        RecommendationAction = "Move network devices to a subnet with a smaller address space"
        InstanceId = $result.InstanceId_s
        InstanceName = "$($result.VNetName_s)/$($result.SubnetName_s)"
        AdditionalInfo = $additionalInfoDictionary
        ResourceGroup = $result.ResourceGroupName_s
        SubscriptionGuid = $result.SubscriptionGuid_g
        SubscriptionName = $result.SubscriptionName
        TenantGuid = $result.TenantGuid_g
        FitScore = $fitScore
        Tags = $tags
        DetailsURL = $detailsURL
    }

    $recommendations += $recommendation
}

# Export the recommendations as JSON to blob storage

$fileDate = $datetime.ToString("yyyy-MM-dd")
$jsonExportPath = "subnetslowspaceusage-$fileDate.json"
$recommendations | ConvertTo-Json | Out-File $jsonExportPath

$jsonBlobName = $jsonExportPath
$jsonProperties = @{"ContentType" = "application/json"};
Set-AzStorageBlobContent -File $jsonExportPath -Container $storageAccountSinkContainer -Properties $jsonProperties -Blob $jsonBlobName -Context $sa.Context -Force
