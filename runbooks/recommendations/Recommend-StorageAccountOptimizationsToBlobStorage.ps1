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

# storage account thresholds variables
$growthPercentageThreshold = [int] (Get-AutomationVariable -Name  "AzureOptimization_RecommendationStorageAcountGrowthThresholdPercentage" -ErrorAction SilentlyContinue)
if (-not($growthPercentageThreshold -gt 0)) {
    $growthPercentageThreshold = 5
}
$monthlyCostThreshold = [int] (Get-AutomationVariable -Name  "AzureOptimization_RecommendationStorageAcountGrowthMonthlyCostThreshold" -ErrorAction SilentlyContinue)
if (-not($monthlyCostThreshold -gt 0)) {
    $monthlyCostThreshold = 50
}
$growthLookbackDays = [int] (Get-AutomationVariable -Name  "AzureOptimization_RecommendationStorageAcountGrowthLookbackDays" -ErrorAction SilentlyContinue)
if (-not($growthLookbackDays -gt 0)) {
    $growthLookbackDays = 30
}

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
        $Cmd.CommandText = "SELECT * FROM [dbo].[$LogAnalyticsIngestControlTable] WHERE CollectedType IN ('ARGResourceContainers','AzureConsumption')"
    
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

$subscriptionsTableName = $lognamePrefix + ($controlRows | Where-Object { $_.CollectedType -eq 'ARGResourceContainers' }).LogAnalyticsSuffix + "_CL"
$consumptionTableName = $lognamePrefix + ($controlRows | Where-Object { $_.CollectedType -eq 'AzureConsumption' }).LogAnalyticsSuffix + "_CL"

Write-Output "Will run query against tables $subscriptionsTableName and $consumptionTableName"

$Conn.Close()    
$Conn.Dispose()            

$recommendationSearchTimeSpan = $growthLookbackDays + $consumptionOffsetDaysStart

# Grab a context reference to the Storage Account where the recommendations file will be stored

Select-AzSubscription -SubscriptionId $storageAccountSinkSubscriptionId
$sa = Get-AzStorageAccount -ResourceGroupName $storageAccountSinkRG -Name $storageAccountSink

if ($workspaceSubscriptionId -ne $storageAccountSinkSubscriptionId)
{
    Select-AzSubscription -SubscriptionId $workspaceSubscriptionId
}

Write-Output "Looking for ever growing Storage Accounts, with more than $monthlyCostThreshold/month costs, growing more than $growthPercentageThreshold% over the last $growthLookbackDays days..."

$dailyCostThreshold = [Math]::Round($monthlyCostThreshold / 30)

$baseQuery = @"
let interval = $($growthLookbackDays)d; // observation window
let etime = endofday(todatetime(toscalar($consumptionTableName | where UsageDate_t < now() | summarize max(UsageDate_t))));
let etime_subs = endofday(todatetime(toscalar($subscriptionsTableName | summarize max(TimeGenerated))));
let stime = endofday(etime-interval);
let lastday_stime = endofday(etime-1d);
let lastday_stime_subs = endofday(etime_subs-1d);
let costThreshold = $dailyCostThreshold; // minimum daily cost threshold
let growthPercentageThreshold = $growthPercentageThreshold; 
let StorageAccountsWithLastTags = $consumptionTableName
| where UsageDate_t between (lastday_stime..etime)
| where MeterCategory_s == 'Storage' and ConsumedService_s == 'Microsoft.Storage' and MeterName_s endswith 'Data Stored' and ChargeType_s == 'Usage'
| distinct InstanceId_s, Tags_s;
$consumptionTableName
| where UsageDate_t between (stime..etime)
| where MeterCategory_s == 'Storage' and ConsumedService_s == 'Microsoft.Storage' and MeterName_s endswith 'Data Stored' and ChargeType_s == 'Usage'
| make-series CostSum=sum(todouble(Cost_s)) default=0.0 on UsageDate_t from stime to etime step 1d by InstanceId_s, InstanceName_s, ResourceGroupName_s, SubscriptionGuid_g, Cloud_s, TenantGuid_g
| extend InitialDailyCost = todouble(CostSum[0]), CurrentDailyCost = todouble(CostSum[array_length(CostSum)-1])
| extend GrowthPercentage = round((CurrentDailyCost-InitialDailyCost)/InitialDailyCost*100)
| where InitialDailyCost > 0 and CurrentDailyCost > costThreshold and GrowthPercentage > growthPercentageThreshold 
| project InstanceId_s, InitialDailyCost, CurrentDailyCost, GrowthPercentage, InstanceName_s, ResourceGroupName_s, SubscriptionGuid_g, Cloud_s, TenantGuid_g
| join kind=leftouter (StorageAccountsWithLastTags) on InstanceId_s
| join kind=leftouter ( 
    $subscriptionsTableName
    | where TimeGenerated > lastday_stime_subs
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
    Write-Warning -Message $error[0]
    throw "Execution aborted"
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
    $queryText = @"
    $consumptionTableName 
    | where MeterCategory_s == 'Storage' and ConsumedService_s == 'Microsoft.Storage' and MeterName_s endswith 'Data Stored' and ChargeType_s == 'Usage'
    | extend InstanceId = tolower(InstanceId_s)
    | where InstanceId_s == '$queryInstanceId' 
    | summarize DailyCosts = sum(todouble(Cost_s)) by bin(UsageDate_t, 1d)
    | render timechart
"@

    switch ($cloudEnvironment)
    {
        "AzureCloud" { $azureTld = "com" }
        "AzureChinaCloud" { $azureTld = "cn" }
        "AzureUSGovernment" { $azureTld = "us" }
        default { $azureTld = "com" }
    }

    $encodedQuery = [System.Uri]::EscapeDataString($queryText)
    $detailsQueryStart = $datetime.AddDays(-1 * $recommendationSearchTimeSpan).ToString("yyyy-MM-dd")
    $detailsQueryEnd = $datetime.AddDays(8).ToString("yyyy-MM-dd")
    $detailsURL = "https://portal.azure.$azureTld#@$workspaceTenantId/blade/Microsoft_Azure_Monitoring_Logs/LogsBlade/resourceId/%2Fsubscriptions%2F$workspaceSubscriptionId%2Fresourcegroups%2F$workspaceRG%2Fproviders%2Fmicrosoft.operationalinsights%2Fworkspaces%2F$workspaceName/source/LogsBlade.AnalyticsShareLinkToQuery/query/$encodedQuery/timespan/$($detailsQueryStart)T00%3A00%3A00.000Z%2F$($detailsQueryEnd)T00%3A00%3A00.000Z"

    $additionalInfoDictionary = @{}

    $costsAmount = ([double] $result.InitialDailyCost + [double] $result.CurrentDailyCost) / 2 * 30

    $additionalInfoDictionary["InitialDailyCost"] = $result.InitialDailyCost
    $additionalInfoDictionary["CurrentDailyCost"] = $result.CurrentDailyCost
    $additionalInfoDictionary["GrowthPercentage"] = $result.GrowthPercentage
    $additionalInfoDictionary["CostsAmount"] = $costsAmount
    $additionalInfoDictionary["savingsAmount"] = $costsAmount * 0.25 # estimated 25% savings

    $fitScore = 4 # savings are estimated with a significant error margin
    
    $fitScore = [Math]::max(0.0, $fitScore)

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
        Timestamp                   = $timestamp
        Cloud                       = $result.Cloud_s
        Category                    = "Cost"
        ImpactedArea                = "Microsoft.Storage/storageAccounts"
        Impact                      = "Medium"
        RecommendationType          = "Saving"
        RecommendationSubType       = "StorageAccountsGrowing"
        RecommendationSubTypeId     = "08e049ca-18b0-4d22-b174-131a91d0381c"
        RecommendationDescription   = "Storage Account without retention policy in place"
        RecommendationAction        = "Review whether the Storage Account has a retention policy for example via Lifecycle Management"
        InstanceId                  = $result.InstanceId_s
        InstanceName                = $result.InstanceName_s
        AdditionalInfo              = $additionalInfoDictionary
        ResourceGroup               = $result.ResourceGroupName_s
        SubscriptionGuid            = $result.SubscriptionGuid_g
        SubscriptionName            = $result.SubscriptionName
        TenantGuid                  = $result.TenantGuid_g
        FitScore                    = $fitScore
        Tags                        = $tags
        DetailsURL                  = $detailsURL
    }

    $recommendations += $recommendation        
}

# Export the recommendations as JSON to blob storage

Write-Output "Exporting final $($recommendations.Count) results as a JSON file..."

$fileDate = $datetime.ToString("yyyy-MM-dd")
$jsonExportPath = "storageaccounts-costsgrowing-$fileDate.json"
$recommendations | ConvertTo-Json | Out-File $jsonExportPath

$jsonBlobName = $jsonExportPath
$jsonProperties = @{"ContentType" = "application/json"};
Set-AzStorageBlobContent -File $jsonExportPath -Container $storageAccountSinkContainer -Properties $jsonProperties -Blob $jsonBlobName -Context $sa.Context -Force

$now = (Get-Date).ToUniversalTime().ToString("yyyy'-'MM'-'dd'T'HH':'mm':'ss'.'fff'Z'")
Write-Output "[$now] Uploaded $jsonBlobName to Blob Storage..."

Remove-Item -Path $jsonExportPath -Force

$now = (Get-Date).ToUniversalTime().ToString("yyyy'-'MM'-'dd'T'HH':'mm':'ss'.'fff'Z'")
Write-Output "[$now] Removed $jsonExportPath from local disk..."
