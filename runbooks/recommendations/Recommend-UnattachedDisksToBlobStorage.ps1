$ErrorActionPreference = "Stop"

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

$disksTableSuffix = "DisksV1_CL"
$disksTableName = $lognamePrefix + $disksTableSuffix

$recommendationSearchTimeSpan = 1

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

Select-AzSubscription -SubscriptionId $storageAccountSinkSubscriptionId
$sa = Get-AzStorageAccount -ResourceGroupName $storageAccountSinkRG -Name $storageAccountSink

if ($workspaceSubscriptionId -ne $storageAccountSinkSubscriptionId)
{
    Select-AzSubscription -SubscriptionId $workspaceSubscriptionId
}

$baseQuery = @"
    $disksTableName 
    | where OwnerVMId_s == ""
    | project DiskName_s, InstanceId_s, SubscriptionGuid_g, ResourceGroupName_s, SKU_s, DiskSizeGB_s, Tags_s, Cloud_s 
"@

$queryResults = Invoke-AzOperationalInsightsQuery -WorkspaceId $workspaceId -Query $baseQuery -Timespan (New-TimeSpan -Days $recommendationSearchTimeSpan)
$results = [System.Linq.Enumerable]::ToArray($queryResults.Results)

$recommendations = @()
$datetime = (get-date).ToUniversalTime()
$hour = $datetime.Hour
if ($hour -lt 10)
{
    $hour = "0" + $hour
}
$min = $datetime.Minute
if ($min -lt 10)
{
    $min = "0" + $min
}
$timestamp = $datetime.ToString("yyyy-MM-ddT$($hour):$($min):00.000Z")

foreach ($result in $results)
{
    $queryInstanceId = $result.InstanceId_s
    $querySubscriptionId = $result.SubscriptionGuid_g
    $queryText = @"
    $disksTableName
    | extend InstanceId = tolower(InstanceId_s)
    | where InstanceId == tolower(`'$queryInstanceId`')  and OwnerVMId_s == ''
    | project DiskName_s, DiskSizeGB_s, SKU_s, TimeGenerated
    | summarize LastAttachedDate = min(TimeGenerated) by DiskName_s, DiskSizeGB_s, SKU_s
"@
    $encodedQuery = [System.Uri]::EscapeDataString($queryText)
    $detailsQueryStart = $deploymentDate
    $detailsQueryEnd = $datetime.AddDays(1).ToString("yyyy-MM-dd")
    $detailsURL = "https://portal.azure.com#@$workspaceTenantId/blade/Microsoft_Azure_Monitoring_Logs/LogsBlade/resourceId/%2Fsubscriptions%2F$querySubscriptionId%2Fresourcegroups%2F$workspaceRG%2Fproviders%2Fmicrosoft.operationalinsights%2Fworkspaces%2F$workspaceName/source/LogsBlade.AnalyticsShareLinkToQuery/query/$encodedQuery/timespan/$($detailsQueryStart)T00%3A00%3A00.000Z%2F$($detailsQueryEnd)T00%3A00%3A00.000Z"

    $additionalInfoDictionary = @{}

    $additionalInfoDictionary["DiskType"] = "Managed"
    $additionalInfoDictionary["currentSku"] = $result.SKU_s
    $additionalInfoDictionary["DiskSizeGB"] = [int] $result.DiskSizeGB_s 

    $confidenceScore = 5

    $tags = @{}

    if (-not([string]::IsNullOrEmpty($result.Tags_s)))
    {
        $tagPairs = $result.Tags_s.Substring(2, $result.Tags_s.Length - 3).Split(';')
        foreach ($tagPairString in $tagPairs)
        {
            $tagPair = $tagPairString.Split('=')
            $tagName = $tagPair[0].Trim()
            $tagValue = $tagPair[1].Trim()
            $tags[$tagName] = $tagValue
        }
    }

    $recommendation = New-Object PSObject -Property @{
        Timestamp = $timestamp
        Cloud = $result.Cloud_s
        Category = "Cost"
        ImpactedArea = "Microsoft.Compute/disks"
        Impact = "Medium"
        RecommendationType = "Saving"
        RecommendationSubType = "UnattachedDisks"
        RecommendationSubTypeId = "c84d5e86-e2d6-4d62-be7c-cecfbd73b0db"
        RecommendationDescription = "Unattached disks (without owner VM) incur in unnecessary costs"
        RecommendationAction = "Delete or downgrade disk to Standard SKU"
        InstanceId = $result.InstanceId_s
        InstanceName = $result.DiskName_s
        AdditionalInfo = $additionalInfoDictionary
        ResourceGroup = $result.ResourceGroupName_s
        SubscriptionGuid = $result.SubscriptionGuid_g
        ConfidenceScore = $confidenceScore
        Tags = $tags
        DetailsURL = $detailsURL
    }

    $recommendations += $recommendation
}

$fileDate = $datetime.ToString("yyyy-MM-dd")
$jsonExportPath = "unattacheddisks-$fileDate.json"
$recommendations | ConvertTo-Json | Out-File $jsonExportPath

$jsonBlobName = $jsonExportPath
$jsonProperties = @{"ContentType" = "application/json"};
Set-AzStorageBlobContent -File $jsonExportPath -Container $storageAccountSinkContainer -Properties $jsonProperties -Blob $jsonBlobName -Context $sa.Context -Force
