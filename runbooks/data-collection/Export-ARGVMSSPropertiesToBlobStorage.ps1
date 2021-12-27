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
$referenceRegion = Get-AutomationVariable -Name "AzureOptimization_ReferenceRegion" -ErrorAction SilentlyContinue # e.g., westeurope
if ([string]::IsNullOrEmpty($referenceRegion))
{
    $referenceRegion = "westeurope"
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
$storageAccountSinkContainer = Get-AutomationVariable -Name  "AzureOptimization_ARGVMSSContainer" -ErrorAction SilentlyContinue
if ([string]::IsNullOrEmpty($storageAccountSinkContainer))
{
    $storageAccountSinkContainer = "argvmssexports"
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

$sizes = Get-AzVMSize -Location $referenceRegion

$cloudSuffix = ""

if (-not([string]::IsNullOrEmpty($externalCredentialName)))
{
    Connect-AzAccount -ServicePrincipal -EnvironmentName $externalCloudEnvironment -Tenant $externalTenantId -Credential $externalCredential 
    $cloudSuffix = $externalCloudEnvironment.ToLower() + "-"
    $cloudEnvironment = $externalCloudEnvironment   
}

$tenantId = (Get-AzContext).Tenant.Id

$allvmss = @()

if ($TargetSubscription)
{
    $subscriptions = $TargetSubscription
    $subscriptionSuffix = "-" + $TargetSubscription
}
else
{
    $subscriptions = Get-AzSubscription | Where-Object { $_.State -eq "Enabled" } | ForEach-Object { "$($_.Id)"}
    $subscriptionSuffix = $cloudSuffix + "all-" + $tenantId
}

$armVmssTotal = @()

$resultsSoFar = 0

$argQuery = @"
resources
| where type =~ 'microsoft.compute/virtualmachinescalesets'
| project id, tenantId, name, location, resourceGroup, subscriptionId, skUName = tostring(sku.name),
    computerNamePrefix = tostring(properties.virtualMachineProfile.osProfile.computerNamePrefix),
    usesManagedDisks = iif(isnull(properties.virtualMachineProfile.storageProfile.osDisk.managedDisk), 'false', 'true'),
	capacity = tostring(sku.capacity), priority = tostring(properties.virtualMachineProfile.priority), tags, zones,
	osType = iif(isnotnull(properties.virtualMachineProfile.osProfile.linuxConfiguration), "Linux", "Windows"),
	osDiskSize = tostring(properties.virtualMachineProfile.storageProfile.osDisk.diskSizeGB),
	osDiskCaching = tostring(properties.virtualMachineProfile.storageProfile.osDisk.caching),
	osDiskSKU = tostring(properties.virtualMachineProfile.storageProfile.osDisk.managedDisk.storageAccountType),
	dataDiskCount = iif(isnotnull(properties.virtualMachineProfile.storageProfile.dataDisks), array_length(properties.virtualMachineProfile.storageProfile.dataDisks), 0),
	nicCount = array_length(properties.virtualMachineProfile.networkProfile.networkInterfaceConfigurations),
    imagePublisher = iif(isnotempty(properties.virtualMachineProfile.storageProfile.imageReference.publisher),tostring(properties.virtualMachineProfile.storageProfile.imageReference.publisher),'Custom'),
    imageOffer = iif(isnotempty(properties.virtualMachineProfile.storageProfile.imageReference.offer),tostring(properties.virtualMachineProfile.storageProfile.imageReference.offer),tostring(properties.virtualMachineProfile.storageProfile.imageReference.id)),
    imageSku = tostring(properties.virtualMachineProfile.storageProfile.imageReference.sku),
    imageVersion = tostring(properties.virtualMachineProfile.storageProfile.imageReference.version),
    imageExactVersion = tostring(properties.virtualMachineProfile.storageProfile.imageReference.exactVersion),
	singlePlacementGroup = tostring(properties.singlePlacementGroup),
	upgradePolicy = tostring(properties.upgradePolicy.mode),
	overProvision = tostring(properties.overprovision),
	platformFaultDomainCount = tostring(properties.platformFaultDomainCount),
    zoneBalance = tostring(properties.zoneBalance)		
| order by id asc
"@

do
{
    if ($resultsSoFar -eq 0)
    {
        $armVmss = Search-AzGraph -Query $argQuery -First $ARGPageSize -Subscription $subscriptions
    }
    else
    {
        $armVmss = Search-AzGraph -Query $argQuery -First $ARGPageSize -Skip $resultsSoFar -Subscription $subscriptions 
    }

    if ($armVmss -and $armVmss.GetType().Name -eq "PSResourceGraphResponse")
    {
        $armVmss = $armVmss.Data
    }
    $resultsCount = $armVmss.Count
    $resultsSoFar += $resultsCount
    $armVmssTotal += $armVmss

} while ($resultsCount -eq $ARGPageSize)

$datetime = (get-date).ToUniversalTime()
$timestamp = $datetime.ToString("yyyy-MM-ddTHH:mm:00.000Z")
$statusDate = $datetime.ToString("yyyy-MM-dd")

Write-Output "Building $($armVmssTotal.Count) VMSS entries"

foreach ($vmss in $armVmssTotal)
{
    $vmSize = $sizes | Where-Object {$_.name -eq $vmss.skUName}

    $logentry = New-Object PSObject -Property @{
        Timestamp = $timestamp
        Cloud = $cloudEnvironment
        TenantGuid = $vmss.tenantId
        SubscriptionGuid = $vmss.subscriptionId
        ResourceGroupName = $vmss.resourceGroup.ToLower()
        Zones = $vmss.zones
        Location = $vmss.location
        VMSSName = $vmss.name.ToLower()
        ComputerNamePrefix = $vmss.computerNamePrefix.ToLower()
        InstanceId = $vmss.id.ToLower()
        VMSSSize = $vmSize.name.ToLower()
        CoresCount = $vmSize.NumberOfCores
        MemoryMB = $vmSize.MemoryInMB
        OSType = $vmss.osType
        DataDiskCount = $vmss.dataDiskCount
        NicCount = $vmss.nicCount
        StatusDate = $statusDate
        Tags = $vmss.tags
        Capacity = $vmss.capacity
        Priority = $vmss.priority
        OSDiskSize = $vmss.osDiskSize
        OSDiskCaching = $vmss.osDiskCaching
        OSDiskSKU = $vmss.osDiskSKU
        SinglePlacementGroup = $vmss.singlePlacementGroup
        UpgradePolicy = $vmss.upgradePolicy
        OverProvision = $vmss.overProvision
        PlatformFaultDomainCount = $vmss.platformFaultDomainCount
        ZoneBalance = $vmss.zoneBalance
        UsesManagedDisks = $vmss.usesManagedDisks
        ImagePublisher = $vmss.imagePublisher
        ImageOffer = $vmss.imageOffer
        ImageSku = $vmss.imageSku
        ImageVersion = $vmss.imageVersion
        ImageExactVersion = $vmss.imageExactVersion
    }
    
    $allvmss += $logentry
}

Write-Output "Uploading CSV to Storage"

$today = $datetime.ToString("yyyyMMdd")
$csvExportPath = "$today-vmss-$subscriptionSuffix.csv"

$allvmss | Export-Csv -Path $csvExportPath -NoTypeInformation

$csvBlobName = $csvExportPath

$csvProperties = @{"ContentType" = "text/csv"};

Set-AzStorageBlobContent -File $csvExportPath -Container $storageAccountSinkContainer -Properties $csvProperties -Blob $csvBlobName -Context $sa.Context -Force

Write-Output "DONE"