param(
    [Parameter(Mandatory = $false)]
    [string] $targetSubscription = "",

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
    $authenticationOption = "RunAsAccount"
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
$advisorFilter = Get-AutomationVariable -Name  "AzureOptimization_AdvisorFilter" -ErrorAction SilentlyContinue # set to 'all' to obtain all recommendations
if ([string]::IsNullOrEmpty($advisorFilter))
{
    $advisorFilter = "cost"
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
    $subscriptions = Get-AzSubscription | Where-Object { $_.State -eq "Enabled" } | ForEach-Object { "$($_.Id)"}
}

$recommendations = @()

<#
   Getting Advisor recommendations for each subscription and building CSV entries
#>

$datetime = (get-date).ToUniversalTime()
$timestamp = $datetime.ToString("yyyy-MM-ddTHH:mm:00.000Z")

foreach ($subscription in $subscriptions)
{
    Select-AzSubscription -SubscriptionId $subscription

    switch ($advisorFilter)
    {
        "cost" {
            $advisorRecommendations = Get-AzAdvisorRecommendation -Category Cost
            break
        }
        "highavailability" {
            $advisorRecommendations = Get-AzAdvisorRecommendation -Category HighAvailability
            break
        }
        "operationalexcellence" {
            $advisorRecommendations = Get-AzAdvisorRecommendation -Category OperationalExcellence
            break
        }
        "performance" {
            $advisorRecommendations = Get-AzAdvisorRecommendation -Category Performance
            break
        }
        "security" {
            $advisorRecommendations = Get-AzAdvisorRecommendation -Category Security
            break
        }
        default {
            $advisorRecommendations = Get-AzAdvisorRecommendation
        }
    }

    foreach ($advisorRecommendation in $advisorRecommendations)
    {
        # compute instance ID, resource group and subscription for the recommendation
        $resourceIdParts = $advisorRecommendation.ResourceId.Split('/')
        if ($resourceIdParts.Count -ge 9)
        {
            # if the Resource ID is made of 9 parts, then the recommendation is relative to a specific Azure resource
            $realResourceIdParts = $resourceIdParts[1..8]
            $instanceId = ""
            for ($i = 0; $i -lt $realResourceIdParts.Count; $i++)
            {
                $instanceId += "/" + $realResourceIdParts[$i]
            }

            $resourceGroup = $realResourceIdParts[3]
            $subscriptionId = $realResourceIdParts[1]
        }
        else
        {
            # otherwise it is not a resource-specific recommendation (e.g., reservations)
            $instanceId = $advisorRecommendation.ResourceId
            $resourceGroup = "NotAvailable"
            $subscriptionId = $resourceIdParts[2]
        }

        $recommendation = New-Object PSObject -Property @{
            Timestamp = $timestamp
            Cloud = $cloudEnvironment
            Impact = $advisorRecommendation.Impact
            ImpactedArea = $advisorRecommendation.ImpactedField
            Description = $advisorRecommendation.ShortDescription.Problem
            RecommendationText = $advisorRecommendation.ShortDescription.Problem
            RecommendationTypeId = $advisorRecommendation.RecommendationTypeId
            InstanceId = $instanceId.ToLower()
            Category = $advisorRecommendation.Category
            InstanceName = $advisorRecommendation.ImpactedValue.ToLower()
            AdditionalInfo = $advisorRecommendation.ExtendedProperties
            ResourceGroup = $resourceGroup.ToLower()
            SubscriptionGuid = $subscriptionId
        }
    
        $recommendations += $recommendation    
    }

    <#
    Actually exporting CSV to Azure Storage
    #>

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
}

Write-Output "DONE!"