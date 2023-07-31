param(
    [Parameter(Mandatory = $false)]
    [string] $targetSubscription = "",

    [Parameter(Mandatory = $false)]
    [string] $advisorFilter = "all",

    [Parameter(Mandatory = $false)]
    [string] $externalCloudEnvironment = "",

    [Parameter(Mandatory = $false)]
    [string] $externalTenantId = "",

    [Parameter(Mandatory = $false)]
    [string] $externalCredentialName = ""
)

$ErrorActionPreference = "Stop"

$cloudEnvironment = Get-AutomationVariable -Name "AzureOptimization_CloudEnvironment" -ErrorAction SilentlyContinue # AzureCloud|AzureChinaCloud
if ([string]::IsNullOrEmpty($cloudEnvironment))
{
    $cloudEnvironment = "AzureCloud"
}
$authenticationOption = Get-AutomationVariable -Name  "AzureOptimization_AuthenticationOption" -ErrorAction SilentlyContinue # RunAsAccount|ManagedIdentity
if ([string]::IsNullOrEmpty($authenticationOption))
{
    $authenticationOption = "ManagedIdentity"
}

# get Advisor exports sink (storage account) details
$storageAccountSink = Get-AutomationVariable -Name  "AzureOptimization_StorageSink"
$storageAccountSinkRG = Get-AutomationVariable -Name  "AzureOptimization_StorageSinkRG"
$storageAccountSinkSubscriptionId = Get-AutomationVariable -Name  "AzureOptimization_StorageSinkSubId"
$storageAccountSinkContainer = Get-AutomationVariable -Name  "AzureOptimization_AdvisorContainer" -ErrorAction SilentlyContinue
if ([string]::IsNullOrEmpty($storageAccountSinkContainer))
{
    $storageAccountSinkContainer = "advisorexports"
}

if (-not([string]::IsNullOrEmpty($externalCredentialName)))
{
    $externalCredential = Get-AutomationPSCredential -Name $externalCredentialName
}

Write-Output "Logging in to Azure with $authenticationOption..."

switch ($authenticationOption) {
    "RunAsAccount" { 
        $ArmConn = Get-AutomationConnection -Name AzureRunAsConnection
        Connect-AzAccount -ServicePrincipal -EnvironmentName $cloudEnvironment -Tenant $ArmConn.TenantID -ApplicationId $ArmConn.ApplicationID -CertificateThumbprint $ArmConn.CertificateThumbprint
        break
    }
    "ManagedIdentity" { 
        Connect-AzAccount -Identity -EnvironmentName $cloudEnvironment 
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

if (-not([string]::IsNullOrEmpty($externalCredentialName)))
{
    Connect-AzAccount -ServicePrincipal -EnvironmentName $externalCloudEnvironment -Tenant $externalTenantId -Credential $externalCredential 
    $cloudEnvironment = $externalCloudEnvironment   
}

Write-Output "Getting subscriptions target $TargetSubscription"

$tenantId = (Get-AzContext).Tenant.Id

$ARGPageSize = 1000

if (-not([string]::IsNullOrEmpty($TargetSubscription)))
{
    $subscriptions = $TargetSubscription
    $scope = $TargetSubscription
}
else
{
    $subscriptions = Get-AzSubscription | Where-Object { $_.State -eq "Enabled" -and $_.SubscriptionPolicies.QuotaId -notlike "AAD*" } | ForEach-Object { "$($_.Id)"}
    $scope = $tenantId
}


<#
   Getting Advisor recommendations for each subscription and building CSV entries
#>

$datetime = (get-date).ToUniversalTime()
$timestamp = $datetime.ToString("yyyy-MM-ddTHH:mm:00.000Z")

$recommendationsARG = @()

$resultsSoFar = 0

$filter = ""
if ($advisorFilter -ne "all" -and -not([string]::IsNullOrEmpty($advisorFilter)))
{
    $filter = " and properties.category =~ '$advisorFilter'"
}

$argQuery = @"
advisorresources
| where type == 'microsoft.advisor/recommendations'
| where isnull(properties.suppressionIds)$filter
| project id, category = properties.category, impact = properties.impact, impactedArea = properties.impactedField,
    description = properties.shortDescription.problem, recommendationText = properties.shortDescription.solution,
    recommendationTypeId = properties.recommendationTypeId, instanceName = properties.impactedValue,
    additionalInfo = properties.extendedProperties
| order by id asc
"@

do
{
    if ($resultsSoFar -eq 0)
    {
        $recs = Search-AzGraph -Query $argQuery -First $ARGPageSize -Subscription $subscriptions
    }
    else
    {
        $recs = Search-AzGraph -Query $argQuery -First $ARGPageSize -Skip $resultsSoFar -Subscription $subscriptions
    }
    if ($recs -and $recs.GetType().Name -eq "PSResourceGraphResponse")
    {
        $recs = $recs.Data
    }
    $resultsCount = $recs.Count
    $resultsSoFar += $resultsCount
    $recommendationsARG += $recs

} while ($resultsCount -eq $ARGPageSize)

Write-Output "Building $($recommendationsARG.Count) recommendations entries"

$recommendations = @()

foreach ($advisorRecommendation in $recommendationsARG)
{
    $resourceIdParts = $advisorRecommendation.id.Split('/')
    if ($resourceIdParts.Count -ge 9)
    {
        # if the Resource ID is made of 9 parts, then the recommendation is relative to a specific Azure resource
        $realResourceIdParts = $resourceIdParts[0..8]
        $instanceId = ($realResourceIdParts -join "/").ToLower()
        $resourceGroup = $realResourceIdParts[4].ToLower()
        $subscriptionId = $realResourceIdParts[2]
    }
    else
    {
        # otherwise it is not a resource-specific recommendation (e.g., reservations)
        $resourceGroup = "notavailable"
        $instanceId = $advisorRecommendation.id.ToLower()
        $subscriptionId = $resourceIdParts[2]
    }

    if (-not([string]::IsNullOrEmpty($advisorRecommendation.additionalInfo)))
    {
        $additionalInfo = $advisorRecommendation.additionalInfo | ConvertTo-Json
    }
    else
    {
        $additionalInfo = $null
    }
    
    $recommendation = New-Object PSObject -Property @{
        Timestamp = $timestamp
        Cloud = $cloudEnvironment
        Category = $advisorRecommendation.category
        Impact = $advisorRecommendation.impact
        ImpactedArea = $advisorRecommendation.impactedArea
        Description = $advisorRecommendation.description
        RecommendationText = $advisorRecommendation.recommendationText
        RecommendationTypeId = $advisorRecommendation.recommendationTypeId
        InstanceId = $instanceId
        InstanceName = $advisorRecommendation.instanceName
        AdditionalInfo = $additionalInfo
        ResourceGroup = $resourceGroup
        SubscriptionGuid = $subscriptionId
        TenantGuid = $tenantId
    }

    $recommendations += $recommendation    
}

Write-Output "Found $($recommendations.Count) ($advisorFilter) recommendations..."

$fileDate = $datetime.ToString("yyyyMMdd")
$advisorFilter = $advisorFilter.ToLower()
$csvExportPath = "$fileDate-$advisorFilter-$scope.csv"

$recommendations | Export-Csv -NoTypeInformation -Path $csvExportPath
Write-Output "Export to $csvExportPath"

$csvBlobName = $csvExportPath
$csvProperties = @{"ContentType" = "text/csv"};

Set-AzStorageBlobContent -File $csvExportPath -Container $storageAccountSinkContainer -Properties $csvProperties -Blob $csvBlobName -Context $sa.Context -Force

$now = (Get-Date).ToUniversalTime().ToString("yyyy'-'MM'-'dd'T'HH':'mm':'ss'.'fff'Z'")
Write-Output "[$now] Uploaded $csvBlobName to Blob Storage..."

Remove-Item -Path $csvExportPath -Force

$now = (Get-Date).ToUniversalTime().ToString("yyyy'-'MM'-'dd'T'HH':'mm':'ss'.'fff'Z'")
Write-Output "[$now] Removed $csvExportPath from local disk..."    

Write-Output "DONE!"