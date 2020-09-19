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

$vmsTableSuffix = "VMsV1_CL"
$vmsTableName = $lognamePrefix + $vmsTableSuffix

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
    $vmsTableName 
    | where TimeGenerated > ago(1d) and UsesManagedDisks_s == 'false'
    | distinct InstanceId_s, VMName_s, ResourceGroupName_s, SubscriptionGuid_g, DeploymentModel_s, Tags_s, Cloud_s
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
    $detailsURL = "https://portal.azure.com/#@$workspaceTenantId/resource/$queryInstanceId/overview"

    $additionalInfoDictionary = @{}

    $additionalInfoDictionary["DeploymentModel"] = $result.DeploymentModel_s

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
        Category = "HighAvailability"
        ImpactedArea = "Microsoft.Compute/virtualMachines"
        Impact = "High"
        RecommendationType = "BestPractices"
        RecommendationSubType = "UnmanagedDisks"
        RecommendationSubTypeId = "b576a069-b1f2-43a6-9134-5ee75376402a"
        RecommendationDescription = "Virtual Machines should use Managed Disks for higher availability and manageability"
        RecommendationAction = "Migrate Virtual Machines disks to Managed Disks"
        InstanceId = $result.InstanceId_s
        InstanceName = $result.VMName_s
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
$jsonExportPath = "unmanageddisks-$fileDate.json"
$recommendations | ConvertTo-Json | Out-File $jsonExportPath

$jsonBlobName = $jsonExportPath
$jsonProperties = @{"ContentType" = "application/json"};
Set-AzStorageBlobContent -File $jsonExportPath -Container $storageAccountSinkContainer -Properties $jsonProperties -Blob $jsonBlobName -Context $sa.Context -Force
