param(
    [Parameter(Mandatory = $false)]
    [string] $CategoryFilter = "HighAvailability,Security,Performance,OperationalExcellence" # comma-separated list of categories
)

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

$advisorTableSuffix = "AdvisorV1_CL"
$advisorTableName = $lognamePrefix + $advisorTableSuffix

# must be less than or equal to the advisor exports frequency
$daysBackwards = [int] (Get-AutomationVariable -Name  "AzureOptimization_RecommendAdvisorPeriodInDays" -ErrorAction SilentlyContinue)
if (-not($daysBackwards -gt 0)) {
    $daysBackwards = 7
}

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

# Get the reference to the exports Storage Account
Select-AzSubscription -SubscriptionId $storageAccountSinkSubscriptionId
$sa = Get-AzStorageAccount -ResourceGroupName $storageAccountSinkRG -Name $storageAccountSink

if ($workspaceSubscriptionId -ne $storageAccountSinkSubscriptionId)
{
    Select-AzSubscription -SubscriptionId $workspaceSubscriptionId
}

$FinalCategoryFilter = ""

if (-not([string]::IsNullOrEmpty($CategoryFilter)))
{
    $categories = $CategoryFilter.Split(',')
    for ($i = 0; $i -lt $categories.Count; $i++)
    {
        $categories[$i] = "'" + $categories[$i] + "'"
    }    
    $FinalCategoryFilter = " and Category in (" + ($categories -join ",") + ")"
}

$baseQuery = @"
let advisorInterval = $($daysBackwards)d;

$advisorTableName 
| where todatetime(TimeGenerated) > ago(advisorInterval)$FinalCategoryFilter
| join kind=leftouter (
    $vmsTableName 
    | where TimeGenerated > ago(1d) 
    | project InstanceId_s, Tags_s
) on InstanceId_s 
| summarize by InstanceId_s, InstanceName_s, Category, Description_s, SubscriptionGuid_g, ResourceGroup, Cloud_s, AdditionalInfo_s, RecommendationText_s, ImpactedArea_s, Impact_s, RecommendationTypeId_g, Tags_s            
"@

Write-Output "Getting $CategoryFilter recommendations for $($daysBackwards)d Advisor..."

$queryResults = Invoke-AzOperationalInsightsQuery -WorkspaceId $workspaceId -Query $baseQuery -Timespan (New-TimeSpan -Days $daysBackwards) -Wait 600 -IncludeStatistics
$results = [System.Linq.Enumerable]::ToArray($queryResults.Results)

Write-Output "Query finished with $($results.Count) results."

Write-Output "Query statistics: $($queryResults.Statistics.query)"

$recommendations = @()
$datetime = (get-date).ToUniversalTime()
$hour = $datetime.Hour
if ($hour -lt 10) {
    $hour = "0" + $hour
}
$min = $datetime.Minute
if ($min -lt 10) {
    $min = "0" + $min
}
$timestamp = $datetime.ToString("yyyy-MM-ddT$($hour):$($min):00.000Z")

Write-Output "Generating confidence score..."

foreach ($result in $results) {  

    $tags = @{}

    if (-not([string]::IsNullOrEmpty($result.Tags_s)))
    {
        $tagPairs = $result.Tags_s.Substring(2, $result.Tags_s.Length - 3).Split(';')
        foreach ($tagPairString in $tagPairs)
        {
            $tagPair = $tagPairString.Split('=')
            $tagName = $tagPair[0].Trim()
            if ($tagPair[1])
            {
                $tagValue = $tagPair[1].Trim()
                $tags[$tagName] = $tagValue    
            }
        }
    }
    
    $additionalInfoDictionary = @{ }
    if ($result.AdditionalInfo_s.Length -gt 0) {
        $result.AdditionalInfo_s.Split('{')[1].Split('}')[0].Split(';') | ForEach-Object {
            $key, $value = $_.Trim().Split('=')
            $additionalInfoDictionary[$key] = $value
        }
    }

    $confidenceScore = -1

    $queryInstanceId = $result.InstanceId_s

    $detailsURL = "https://portal.azure.com/#@$workspaceTenantId/resource/$queryInstanceId/overview"

    $recommendationSubType = "Advisor" + $result.Category

    $recommendation = New-Object PSObject -Property @{
        Timestamp                   = $timestamp
        Cloud                       = $result.Cloud_s
        Category                    = $result.Category
        ImpactedArea                = $result.ImpactedArea_s
        Impact                      = $result.Impact_s
        RecommendationType          = "BestPractices"
        RecommendationSubType       = $recommendationSubType
        RecommendationSubTypeId     = $result.RecommendationTypeId_g
        RecommendationDescription   = $result.Description_s
        RecommendationAction        = $result.RecommendationText_s
        InstanceId                  = $result.InstanceId_s
        InstanceName                = $result.InstanceName_s
        AdditionalInfo              = $additionalInfoDictionary
        ResourceGroup               = $result.ResourceGroup
        SubscriptionGuid            = $result.SubscriptionGuid_g
        ConfidenceScore             = $confidenceScore
        Tags                        = $tags
        DetailsURL                  = $detailsURL
    }

    $recommendations += $recommendation
}

Write-Output "Exporting final results as a JSON file..."

$fileDate = $datetime.ToString("yyyyMMdd")
$jsonExportPath = "advisor-asis-$fileDate.json"
$recommendations | ConvertTo-Json | Out-File $jsonExportPath

Write-Output "Uploading $jsonExportPath to blob storage..."

$jsonBlobName = $jsonExportPath
$jsonProperties = @{"ContentType" = "application/json" };
Set-AzStorageBlobContent -File $jsonExportPath -Container $storageAccountSinkContainer -Properties $jsonProperties -Blob $jsonBlobName -Context $sa.Context -Force

Write-Output "DONE"