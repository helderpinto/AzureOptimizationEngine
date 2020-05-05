param(
    [Parameter(Mandatory = $false)]
    [string] $targetSubscription = ""
)

<# 
Scripts provided are not supported under any Microsoft standard support program or service. 
The scripts are provided AS IS without warranty of any kind. Microsoft disclaims all implied warranties including, 
without limitation, any implied warranties of merchantability or of fitness for a particular purpose. The entire 
risk arising out of the use or performance of the scripts and documentation remains with you. In no event shall Microsoft, 
its authors, or anyone else involved in the creation, production, or delivery of the scripts be liable for any damages 
whatsoever (including, without limitation, damages for loss of business profits, business interruption, loss of business 
information, or other pecuniary loss) arising out of the use of or inability to use the scripts or documentation, even 
if Microsoft has been advised of the possibility of such damages.
#>

$ErrorActionPreference = "Stop"

$cloudEnvironment = Get-AutomationVariable -Name "AzureOptimization-CloudEnvironment" -ErrorAction SilentlyContinue # AzureCloud|AzureChinaCloud
if ([string]::IsNullOrEmpty($cloudEnvironment))
{
    $cloudEnvironment = "AzureCloud"
}
$referenceRegion = Get-AutomationVariable -Name "AzureOptimization-ReferenceRegion" -ErrorAction SilentlyContinue # e.g., westeurope|chineast2
if ([string]::IsNullOrEmpty($referenceRegion))
{
    $referenceRegion = "westeurope"
}
$authenticationOption = Get-AutomationVariable -Name  "AzureOptimization-AuthenticationOption" -ErrorAction SilentlyContinue # RunAsAccount|ManagedIdentity|User
if ([string]::IsNullOrEmpty($authenticationOption))
{
    $authenticationOption = "RunAsAccount"
}
else {
    if ($authenticationOption -eq "User")
    {
        $authenticationCredential = Get-AutomationVariable -Name  "AzureOptimization-AuthenticationCredential"
    }
}

# get ARG exports sink (storage account) details
$storageAccountSink = Get-AutomationVariable -Name  "AzureOptimization-StorageSink"
$storageAccountSinkRG = Get-AutomationVariable -Name  "AzureOptimization-StorageSinkRG"
$storageAccountSinkSubscriptionId = Get-AutomationVariable -Name  "AzureOptimization-StorageSinkSubId"
$storageAccountSinkContainer = Get-AutomationVariable -Name  "AzureOptimization-AdvisorContainer" -ErrorAction SilentlyContinue
if ([string]::IsNullOrEmpty($storageAccountSinkContainer))
{
    $storageAccountSinkContainer = "advisorexports"
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
    "User" { 
        $cred = Get-AutomationPSCredential –Name $authenticationCredential
	    Connect-AzAccount -Credential $cred -EnvironmentName $cloudEnvironment 
        break
    }
    Default {
        $ArmConn = Get-AutomationConnection -Name AzureRunAsConnection
        Connect-AzAccount -ServicePrincipal -EnvironmentName $cloudEnvironment -Tenant $ArmConn.TenantID -ApplicationId $ArmConn.ApplicationID -CertificateThumbprint $ArmConn.CertificateThumbprint
        break
    }
}


Write-Output "Getting subscriptions target $TargetSubscription"

if ($TargetSubscription)
{
    $subscriptions = $TargetSubscription
    $subscriptionSuffix = "-" + $TargetSubscription
}
else
{
    $subscriptions = Get-AzSubscription | ForEach-Object { "$($_.Id)"}
    $subscriptionSuffix = ""
}

$recommendations = @()

<#
   Getting Advisor Cost recommendations for each subscription and building CSV entries
#>

$datetime = (get-date).ToUniversalTime()
$hour = $datetime.Hour
$min = $datetime.Minute
$timestamp = $datetime.ToString("yyyy-MM-ddT$($hour):$($min):00.000Z")

foreach ($subscription in $subscriptions)
{
    Select-AzSubscription -SubscriptionId $subscription

    $advisorRecommendations = Get-AzAdvisorRecommendation -Category Cost

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
            RecommendationArea = $advisorRecommendation.ImpactedField.Split('/')[0].Split('.')[1]
            Description = $advisorRecommendation.ShortDescription.Problem
            RecommendationText = $advisorRecommendation.ShortDescription.Problem
            InstanceId = $instanceId
            InstanceName = $advisorRecommendation.ImpactedValue
            AdditionalInfo = $advisorRecommendation.ExtendedProperties
            ResourceGroup = $resourceGroup
            SubscriptionGuid = $subscriptionId
        }
    
        $recommendations += $recommendation    
    }
}

<#
    Actually exporting CSV to Azure Storage
#>

$fileDate = $datetime.ToString("yyyyMMdd")
$jsonExportPath = "cost-$fileDate-$subscriptionSuffix.json"
$csvExportPath = "cost-$fileDate-$subscriptionSuffix.csv"

$recommendations | ConvertTo-Json -Depth 10 | Out-File $jsonExportPath
Write-Output "Exported to JSON: $($recommendations.Count) lines"
$recommendationsJson = Get-Content -Path $jsonExportPath | ConvertFrom-Json
Write-Output "JSON Import: $($recommendationsJson.Count) lines"
$recommendationsJson | Export-Csv -NoTypeInformation -Path $csvExportPath
Write-Output 'Export to CSV'

$csvBlobName = $csvExportPath
$csvProperties = @{"ContentType" = "text/csv"};

Select-AzSubscription -SubscriptionId $storageAccountSinkSubscriptionId
$sa = Get-AzStorageAccount -ResourceGroupName $storageAccountSinkRG -Name $storageAccountSink
Set-AzStorageBlobContent -File $csvExportPath -Container $storageAccountSinkContainer -Properties $csvProperties -Blob $csvBlobName -Context $sa.Context -Force
