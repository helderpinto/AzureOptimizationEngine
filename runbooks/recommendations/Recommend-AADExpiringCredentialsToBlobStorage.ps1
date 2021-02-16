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

$expiringCredsDays = [int] (Get-AutomationVariable -Name  "AzureOptimization_RecommendationAADExpiringCredsDays")

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
        $Cmd.CommandText = "SELECT * FROM [dbo].[$LogAnalyticsIngestControlTable] WHERE CollectedType IN ('AADObjects')"
    
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

$aadObjectsTableName = $lognamePrefix + ($controlRows | Where-Object { $_.CollectedType -eq 'AADObjects' }).LogAnalyticsSuffix + "_CL"

Write-Output "Will run query against tables $aadObjectsTableName"

$Conn.Close()    
$Conn.Dispose()            

$recommendationSearchTimeSpan = 1

# Grab a context reference to the Storage Account where the recommendations file will be stored

Select-AzSubscription -SubscriptionId $storageAccountSinkSubscriptionId
$sa = Get-AzStorageAccount -ResourceGroupName $storageAccountSinkRG -Name $storageAccountSink

if ($workspaceSubscriptionId -ne $storageAccountSinkSubscriptionId)
{
    Select-AzSubscription -SubscriptionId $workspaceSubscriptionId
}

# Execute the recommendation query against Log Analytics

$baseQuery = @" 
    let expiryInterval = $($expiringCredsDays)d;
    let AppsAndKeys = materialize ($aadObjectsTableName
    | where TimeGenerated > ago(1d)
    | where PrincipalNames_s !has 'https://identity.azure.net'
    | where Keys_s startswith '['
    | extend Keys = parse_json(Keys_s)
    | project-away Keys_s
    | mv-expand Keys
    | evaluate bag_unpack(Keys)
    | union ( 
        $aadObjectsTableName
        | where TimeGenerated > ago(1d)
        | where PrincipalNames_s !has 'https://identity.azure.net'
        | where isnotempty(Keys_s) and Keys_s !startswith '['
        | extend Keys = parse_json(Keys_s)
        | project-away Keys_s
        | evaluate bag_unpack(Keys)
    )
    );
    let ExpirationInRisk = AppsAndKeys
    | where EndDate < now()+expiryInterval
    | project ApplicationId_g, KeyId, RiskDate = EndDate;
    let NotInRisk = AppsAndKeys
    | where EndDate > now()+expiryInterval
    | project ApplicationId_g, KeyId, ComfortDate = EndDate;
    let ApplicationsInRisk = ExpirationInRisk
    | join kind=leftouter ( NotInRisk ) on ApplicationId_g
    | where isempty(ComfortDate)
    | summarize ExpiresOn = max(RiskDate) by ApplicationId_g;
    AppsAndKeys
    | join kind=inner (ApplicationsInRisk) on ApplicationId_g
    | summarize ExpiresOn = max(EndDate) by ApplicationId_g, ObjectType_s, DisplayName_s, Cloud_s, KeyType, TenantId
    | order by ExpiresOn desc
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
    $queryInstanceId = $result.ApplicationId_g
    $detailsURL = "https://portal.azure.com/#blade/Microsoft_AAD_RegisteredApps/ApplicationMenuBlade/Credentials/appId/$queryInstanceId"

    $additionalInfoDictionary = @{}

    $additionalInfoDictionary["ObjectType"] = $result.ObjectType_s
    $additionalInfoDictionary["KeyType"] = $result.KeyType
    $additionalInfoDictionary["ExpiresOn"] = $result.ExpiresOn
    $additionalInfoDictionary["TenantId"] = $result.TenantId

    $fitScore = 5

    $tags = @{}

    $recommendation = New-Object PSObject -Property @{
        Timestamp = $timestamp
        Cloud = $result.Cloud_s
        Category = "OperationalExcellence"
        ImpactedArea = "Microsoft.AzureActiveDirectory/objects"
        Impact = "Medium"
        RecommendationType = "BestPractices"
        RecommendationSubType = "AADExpiringCredentials"
        RecommendationSubTypeId = "3292c489-2782-498b-aad0-a4cef50f6ca2"
        RecommendationDescription = "Azure AD application with credentials expired or about to expire"
        RecommendationAction = "Update the Azure AD application credential before the expiration date"
        InstanceId = $result.ApplicationId_g
        InstanceName = $result.DisplayName_s
        AdditionalInfo = $additionalInfoDictionary
        ResourceGroup = "N/A"
        SubscriptionGuid = "N/A"
        FitScore = $fitScore
        Tags = $tags
        DetailsURL = $detailsURL
    }

    $recommendations += $recommendation
}

# Export the recommendations as JSON to blob storage

$fileDate = $datetime.ToString("yyyy-MM-dd")
$jsonExportPath = "aadexpiringcerts-$fileDate.json"
$recommendations | ConvertTo-Json | Out-File $jsonExportPath

$jsonBlobName = $jsonExportPath
$jsonProperties = @{"ContentType" = "application/json"};
Set-AzStorageBlobContent -File $jsonExportPath -Container $storageAccountSinkContainer -Properties $jsonProperties -Blob $jsonBlobName -Context $sa.Context -Force