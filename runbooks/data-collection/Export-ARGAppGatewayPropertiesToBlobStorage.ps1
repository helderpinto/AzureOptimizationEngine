param(
    [Parameter(Mandatory = $false)]
    [string] $TargetSubscription = $null,

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

# get ARG exports sink (storage account) details
$storageAccountSink = Get-AutomationVariable -Name  "AzureOptimization_StorageSink"
$storageAccountSinkRG = Get-AutomationVariable -Name  "AzureOptimization_StorageSinkRG"
$storageAccountSinkSubscriptionId = Get-AutomationVariable -Name  "AzureOptimization_StorageSinkSubId"
$storageAccountSinkContainer = Get-AutomationVariable -Name  "AzureOptimization_ARGAvailabilitySetContainer" -ErrorAction SilentlyContinue
if ([string]::IsNullOrEmpty($storageAccountSinkContainer))
{
    $storageAccountSinkContainer = "argavailsetexports"
}

if (-not([string]::IsNullOrEmpty($externalCredentialName)))
{
    $externalCredential = Get-AutomationPSCredential -Name $externalCredentialName
}

$ARGPageSize = 1000

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

$cloudSuffix = ""

if (-not([string]::IsNullOrEmpty($externalCredentialName)))
{
    Connect-AzAccount -ServicePrincipal -EnvironmentName $externalCloudEnvironment -Tenant $externalTenantId -Credential $externalCredential 
    $cloudSuffix = $externalCloudEnvironment.ToLower() + "-"
    $cloudEnvironment = $externalCloudEnvironment   
}

$allAvSets = @()

Write-Output "Getting subscriptions target $TargetSubscription"
if (-not([string]::IsNullOrEmpty($TargetSubscription)))
{
    $subscriptions = $TargetSubscription
    $subscriptionSuffix = $TargetSubscription
}
else
{
    $subscriptions = Get-AzSubscription | Where-Object { $_.State -eq "Enabled" } | ForEach-Object { "$($_.Id)"}
    $subscriptionSuffix = $cloudSuffix + "all"
}

$avSetsTotal = @()
$resultsSoFar = 0

Write-Output "Querying for Load Balancer properties"

$argQuery = @"
resources
| where type =~ 'Microsoft.Network/applicationGateways'
| extend gatewayIPsCount = array_length(properties.gatewayIPConfigurations)
| extend sslCertsCount = array_length(properties.sslCertificates)
| extend authCertsCount = array_length(properties.authenticationCertificates)
| extend frontendIPsCount = array_length(properties.frontendIPConfigurations)
| extend frontendPortsCount = array_length(properties.frontendPorts)
| extend backendPoolsCount = array_length(properties.backendAddressPools)
| extend httpSettingsCount = array_length(properties.backendHttpSettingsCollection)
| extend httpListenersCount = array_length(properties.httpListeners)
| extend urlPathMapsCount = array_length(properties.urlPathMaps)
| extend requestRoutingRulesCount = array_length(properties.requestRoutingRules)
| extend probesCount = array_length(properties.probes)
| extend rewriteRulesCount = array_length(properties.rewriteRuleSets)
| extend redirectConfsCount = array_length(properties.redirectConfigurations)
| project id, name, resourceGroup, subscriptionId, location, skuName = properties.sku.name, skuTier = properties.sku.tier, skuCapacity = properties.sku.capacity, enableHttp2 = properties.enableHttp2, gatewayIPsCount, sslCertsCount, authCertsCount, frontendIPsCount, frontendPortsCount, httpSettingsCount, httpListenersCount, backendPoolsCount, urlPathMapsCount, requestRoutingRulesCount, probesCount, rewriteRulesCount, redirectConfsCount
| join kind=leftouter (
	resources
	| where type =~ 'Microsoft.Network/applicationGateways'
	| mvexpand backendPools = properties.backendAddressPools
	| extend backendIPCount = array_length(backendPools.properties.backendIPConfigurations)
	| summarize backendIPCount = sum(backendIPCount) by id
) on id
| project-away id1
| order by id asc
"@

do
{
    if ($resultsSoFar -eq 0)
    {
        $avSets = Search-AzGraph -Query $argQuery -First $ARGPageSize -Subscription $subscriptions
    }
    else
    {
        $avSets = Search-AzGraph -Query $argQuery -First $ARGPageSize -Skip $resultsSoFar -Subscription $subscriptions 
    }
    $resultsCount = $avSets.Count
    $resultsSoFar += $resultsCount
    $avSetsTotal += $avSets

} while ($resultsCount -eq $ARGPageSize)

<#
    Building CSV entries 
#>

$datetime = (get-date).ToUniversalTime()
$timestamp = $datetime.ToString("yyyy-MM-ddTHH:mm:00.000Z")
$statusDate = $datetime.ToString("yyyy-MM-dd")

foreach ($avSet in $avSetsTotal)
{
    $logentry = New-Object PSObject -Property @{
        Timestamp = $timestamp
        Cloud = $cloudEnvironment
        TenantGuid = $avSet.tenantId
        SubscriptionGuid = $avSet.subscriptionId
        ResourceGroupName = $avSet.resourceGroup.ToLower()
        InstanceName = $avSet.name.ToLower()
        InstanceId = $avSet.id.ToLower()
        SkuName = $avSet.skuName
        Location = $avSet.location
        FaultDomains = $avSet.faultDomains
        UpdateDomains = $avSet.updateDomains
        VmCount = $avSet.vmCount
        StatusDate = $statusDate
        Tags = $avSet.tags
        Zones = $avSet.zones
    }
    
    $allAvSets += $logentry
}

<#
    Actually exporting CSV to Azure Storage
#>

$today = $datetime.ToString("yyyyMMdd")
$csvExportPath = "$today-availsets-$subscriptionSuffix.csv"

$allAvSets | Export-Csv -Path $csvExportPath -NoTypeInformation

$csvBlobName = $csvExportPath

$csvProperties = @{"ContentType" = "text/csv"};

Set-AzStorageBlobContent -File $csvExportPath -Container $storageAccountSinkContainer -Properties $csvProperties -Blob $csvBlobName -Context $sa.Context -Force
