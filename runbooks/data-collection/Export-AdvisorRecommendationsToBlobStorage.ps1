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

if (-not([string]::IsNullOrEmpty($TargetSubscription)))
{
    $subscriptions = $TargetSubscription
}
else
{
    $AllowUnsupportedSubscriptions = [bool] (Get-AutomationVariable -Name  "AzureOptimization_AllowUnsupportedSubscriptions" -ErrorAction SilentlyContinue)
    if (-not($AllowUnsupportedSubscriptions))
    {
        $supportedQuotaIDs = @('EnterpriseAgreement_2014-09-01','PayAsYouGo_2014-09-01','MSDN_2014-09-01','MSDNDevTest_2014-09-01')
        $subscriptions = Get-AzSubscription | Where-Object { $_.State -eq "Enabled" -and $_.SubscriptionPolicies.QuotaId -in $supportedQuotaIDs } | ForEach-Object { "$($_.Id)"}    
    }
    else
    {
        Write-Output "Allowing unsupported subscriptions"
        $subscriptions = Get-AzSubscription | Where-Object { $_.State -eq "Enabled" } | ForEach-Object { "$($_.Id)"}
    }
}

$tenantId = (Get-AzContext).Tenant.Id

<#
   Getting Advisor recommendations for each subscription and building CSV entries
#>

$datetime = (get-date).ToUniversalTime()
$timestamp = $datetime.ToString("yyyy-MM-ddTHH:mm:00.000Z")

$refreshResultsURLs = @()

foreach ($subscription in $subscriptions)
{
    Write-Output "Generating fresh recommendations for subscription $subscription..."

    # refresh recommendations cache
    
    $generateApiPath = "/subscriptions/$subscription/providers/Microsoft.Advisor/generateRecommendations?api-version=2020-01-01"
    $result = Invoke-AzRestMethod -Path $generateApiPath -Method POST
    if ($result.StatusCode -in (200,202))
    {
        $refreshResultsURLs += $result.Headers.Location.PathAndQuery
    }
    else
    {
        Write-Output "Failed to kick off recommendations generation for subscription $subscription. Status code: $($result.StatusCode); Message: $($result.Content)"
    }
}

Write-Output "Waiting 60 seconds to finish refreshing the recommendations..."
Start-Sleep -Seconds 60

foreach ($refreshResultsURL in $refreshResultsURLs)
{
    $generateResult = Invoke-AzRestMethod -Method GET -Path $refreshResultsURL
    if (-not($generateResult.StatusCode -in (202,204)))
    {
        Write-Output "Failed to generate recommendations for $refreshResultsURL. Status code: $($generateResult.StatusCode); Message: $($generateResult.Content)"
    }
    if ($generateResult.StatusCode -eq 202)
    {
        Write-Output "Recommendations not yet refreshed for $refreshResultsURL"
    }
}

foreach ($subscription in $subscriptions)
{
    $recommendations = @()

    # list recommendations from cache
    $filter = ""
    if ($advisorFilter -ne "all" -and -not([string]::IsNullOrEmpty($advisorFilter)))
    {
        $filter = "&`$filter=Category eq '$advisorFilter'"
    }

    $listApiPath = "/subscriptions/$subscription/providers/Microsoft.Advisor/recommendations?api-version=2020-01-01$filter"

    do
    {
        $result = Invoke-AzRestMethod -Path $listApiPath -Method GET

        if ($result.StatusCode -eq 200)
        {
            $recommendationsJson = $result.Content | ConvertFrom-Json

            foreach ($advisorRecommendation in $recommendationsJson.value)
            {
                if (-not($advisorRecommendation.properties.suppressionIds))
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
                            
                    $recommendation = New-Object PSObject -Property @{
                        Timestamp = $timestamp
                        Cloud = $cloudEnvironment
                        Category = $advisorRecommendation.properties.category
                        Impact = $advisorRecommendation.properties.impact
                        ImpactedArea = $advisorRecommendation.properties.impactedField
                        Description = $advisorRecommendation.properties.shortDescription.problem
                        RecommendationText = $advisorRecommendation.properties.shortDescription.solution
                        RecommendationTypeId = $advisorRecommendation.properties.recommendationTypeId
                        InstanceId = $instanceId
                        InstanceName = $advisorRecommendation.properties.impactedValue
                        AdditionalInfo = $advisorRecommendation.properties.extendedProperties
                        ResourceGroup = $resourceGroup
                        SubscriptionGuid = $subscriptionId
                        TenantGuid = $tenantId
                    }
                
                    $recommendations += $recommendation    
                }
            }

            $listApiPath = ([Uri] $recommendationsJson.nextLink).PathAndQuery
        }
        else
        {
            Write-Output "Failed to get recommendations listing. Status code: $($result.StatusCode); Message: $($result.Content)"
        }
    }
    while ($recommendationsJson.nextLink)

    Write-Output "Found $($recommendations.Count) ($advisorFilter) recommendations (filtered out suppressed ones)..."

    $fileDate = $datetime.ToString("yyyyMMdd")
    $advisorFilter = $advisorFilter.ToLower()
    $jsonExportPath = "$fileDate-$advisorFilter-$subscription.json"
    $csvExportPath = "$fileDate-$advisorFilter-$subscription.csv"

    $recommendations | ConvertTo-Json -Depth 10 | Out-File $jsonExportPath
    Write-Output "Exported to JSON: $($recommendations.Count) lines"
    $recommendationsJson = Get-Content -Path $jsonExportPath | ConvertFrom-Json
    Write-Output "JSON Import: $($recommendationsJson.Count) lines"
    $recommendationsJson | Export-Csv -NoTypeInformation -Path $csvExportPath
    Write-Output "Export to $csvExportPath"

    $csvBlobName = $csvExportPath
    $csvProperties = @{"ContentType" = "text/csv"};

    Set-AzStorageBlobContent -File $csvExportPath -Container $storageAccountSinkContainer -Properties $csvProperties -Blob $csvBlobName -Context $sa.Context -Force
    
    $now = (Get-Date).ToUniversalTime().ToString("yyyy'-'MM'-'dd'T'HH':'mm':'ss'.'fff'Z'")
    Write-Output "[$now] Uploaded $csvBlobName to Blob Storage..."
    
    Remove-Item -Path $csvExportPath -Force
    
    $now = (Get-Date).ToUniversalTime().ToString("yyyy'-'MM'-'dd'T'HH':'mm':'ss'.'fff'Z'")
    Write-Output "[$now] Removed $csvExportPath from local disk..."    
    
    Remove-Item -Path $jsonExportPath -Force
    
    $now = (Get-Date).ToUniversalTime().ToString("yyyy'-'MM'-'dd'T'HH':'mm':'ss'.'fff'Z'")
    Write-Output "[$now] Removed $jsonExportPath from local disk..."    
}

Write-Output "DONE!"