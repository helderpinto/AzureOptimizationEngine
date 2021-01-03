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
$storageAccountSinkContainer = Get-AutomationVariable -Name  "AzureOptimization_ARGVMContainer" -ErrorAction SilentlyContinue
if ([string]::IsNullOrEmpty($storageAccountSinkContainer))
{
    $storageAccountSinkContainer = "argvmexports"
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

# get list of all VM sizes
Write-Output "Getting VM sizes details for $referenceRegion"
$sizes = Get-AzVMSize -Location $referenceRegion

Select-AzSubscription -SubscriptionId $storageAccountSinkSubscriptionId
$sa = Get-AzStorageAccount -ResourceGroupName $storageAccountSinkRG -Name $storageAccountSink

$cloudSuffix = ""

if (-not([string]::IsNullOrEmpty($externalCredentialName)))
{
    Connect-AzAccount -ServicePrincipal -EnvironmentName $externalCloudEnvironment -Tenant $externalTenantId -Credential $externalCredential 
    $cloudSuffix = $externalCloudEnvironment.ToLower() + "-"
    $cloudEnvironment = $externalCloudEnvironment   
}

$allvms = @()

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

$armVmsTotal = @()
$classicVmsTotal = @()

$resultsSoFar = 0

<#
   Getting all ARM VMs properties with Azure Resource Graph query
#>

Write-Output "Querying for ARM VM properties"

$argQuery = @"
    resources
    | where type =~ 'Microsoft.Compute/virtualMachines' 
    | extend dataDiskCount = array_length(properties.storageProfile.dataDisks), nicCount = array_length(properties.networkProfile.networkInterfaces) 
    | extend usesManagedDisks = iif(isnull(properties.storageProfile.osDisk.managedDisk), 'false', 'true')
    | extend availabilitySetId = tostring(properties.availabilitySet.id)
    | extend bootDiagnosticsEnabled = tostring(properties.diagnosticsProfile.bootDiagnostics.enabled)
    | extend bootDiagnosticsStorageAccount = split(split(properties.diagnosticsProfile.bootDiagnostics.storageUri, '/')[2],'.')[0]
    | extend powerState = tostring(properties.extended.instanceView.powerState.code) 
    | order by id asc
"@

do
{
    if ($resultsSoFar -eq 0)
    {
        $armVms = Search-AzGraph -Query $argQuery -First $ARGPageSize -Subscription $subscriptions
    }
    else
    {
        $armVms = Search-AzGraph -Query $argQuery -First $ARGPageSize -Skip $resultsSoFar -Subscription $subscriptions 
    }
    $resultsCount = $armVms.Count
    $resultsSoFar += $resultsCount
    $armVmsTotal += $armVms

} while ($resultsCount -eq $ARGPageSize)

$resultsSoFar = 0

<#
   Getting all Classic VMs properties with Azure Resource Graph query
#>

Write-Output "Querying for Classic VM properties"

$argQuery = @"
    resources
    | where type =~ 'Microsoft.ClassicCompute/virtualMachines' 
    | extend dataDiskCount = iif(isnotnull(properties.storageProfile.dataDisks), array_length(properties.storageProfile.dataDisks), 0), nicCount = iif(isnotnull(properties.networkProfile.virtualNetwork.networkInterfaces), array_length(properties.networkProfile.virtualNetwork.networkInterfaces) + 1, 1) 
	| extend usesManagedDisks = 'false'
	| extend availabilitySetId = tostring(properties.hardwareProfile.availabilitySet)
	| extend bootDiagnosticsEnabled = tostring(properties.debugProfile.bootDiagnosticsEnabled)
    | extend bootDiagnosticsStorageAccount = split(split(properties.debugProfile.serialOutputBlobUri, '/')[2],'.')[0]
    | extend powerState = tostring(properties.instanceView.status)
    | order by id asc
"@

do
{
    if ($resultsSoFar -eq 0)
    {
        $classicVms = Search-AzGraph -Query $argQuery -First $ARGPageSize -Subscription $subscriptions
    }
    else
    {
        $classicVms = Search-AzGraph -Query $argQuery -First $ARGPageSize -Skip $resultsSoFar -Subscription $subscriptions 
    }
    $resultsCount = $classicVms.Count
    $resultsSoFar += $resultsCount
    $classicVmsTotal += $classicVms

} while ($resultsCount -eq $ARGPageSize)

<#
    Merging ARM + Classic VMs, enriching VM size details and building CSV entries 
#>

$datetime = (Get-Date).ToUniversalTime()
$timestamp = $datetime.ToString("yyyy-MM-ddTHH:mm:00.000Z")
$statusDate = $datetime.ToString("yyyy-MM-dd")

Write-Output "Building $($armVmsTotal.Count) ARM VM entries"

foreach ($vm in $armVmsTotal)
{
    $vmSize = $sizes | Where-Object {$_.name -eq $vm.properties.hardwareProfile.vmSize}

    $avSetId = $null
    if ($vm.availabilitySetId)
    {
        $avSetId = $vm.availabilitySetId.ToLower()
    }

    $logentry = New-Object PSObject -Property @{
        Timestamp = $timestamp
        Cloud = $cloudEnvironment
        TenantGuid = $vm.tenantId
        SubscriptionGuid = $vm.subscriptionId
        ResourceGroupName = $vm.resourceGroup.ToLower()
        Zones = $vm.zones
        Location = $vm.location
        VMName = $vm.name.ToLower()
        DeploymentModel = 'ARM'
        InstanceId = $vm.id.ToLower()
        VMSize = $vm.properties.hardwareProfile.vmSize
        CoresCount = $vmSize.NumberOfCores
        MemoryMB = $vmSize.MemoryInMB
        OSType = $vm.properties.storageProfile.osDisk.osType
        DataDiskCount = $vm.dataDiskCount
        NicCount = $vm.nicCount
        UsesManagedDisks = $vm.usesManagedDisks
        AvailabilitySetId = $avSetId
        BootDiagnosticsEnabled = $vm.bootDiagnosticsEnabled
        BootDiagnosticsStorageAccount = $vm.bootDiagnosticsStorageAccount
        StatusDate = $statusDate
        PowerState = $vm.powerState
        Tags = $vm.tags
    }
    
    $allvms += $logentry
}

Write-Output "Building $($classicVmsTotal.Count) Classic VM entries"

foreach ($vm in $classicVmsTotal)
{
    $vmSize = $sizes | Where-Object {$_.name -eq $vm.properties.hardwareProfile.size}

    $avSetId = $null
    if ($vm.availabilitySetId)
    {
        $avSetId = $vm.availabilitySetId.ToLower()
    }

    $logentry = New-Object PSObject -Property @{
        Timestamp = $timestamp
        Cloud = $cloudEnvironment
        TenantGuid = $vm.tenantId
        SubscriptionGuid = $vm.subscriptionId
        ResourceGroupName = $vm.resourceGroup.ToLower()
        VMName = $vm.name.ToLower()
        DeploymentModel = 'Classic'
        Location = $vm.location
        InstanceId = $vm.id.ToLower()
        VMSize = $vm.properties.hardwareProfile.size
        CoresCount = $vmSize.NumberOfCores
        MemoryMB = $vmSize.MemoryInMB
        OSType = $vm.properties.storageProfile.operatingSystemDisk.operatingSystem
        DataDiskCount = $vm.dataDiskCount
        NicCount = $vm.nicCount
        UsesManagedDisks = $vm.usesManagedDisks
        AvailabilitySetId = $avSetId
        BootDiagnosticsEnabled = $vm.bootDiagnosticsEnabled
        BootDiagnosticsStorageAccount = $vm.bootDiagnosticsStorageAccount
        PowerState = $vm.powerState
        StatusDate = $statusDate
        Tags = $null
    }
    
    $allvms += $logentry
}

<#
    Actually exporting CSV to Azure Storage
#>

Write-Output "Uploading CSV to Storage"

$today = $datetime.ToString("yyyyMMdd")
$csvExportPath = "$today-vms-$subscriptionSuffix.csv"

$allvms | Export-Csv -Path $csvExportPath -NoTypeInformation

$csvBlobName = $csvExportPath

$csvProperties = @{"ContentType" = "text/csv"};

Set-AzStorageBlobContent -File $csvExportPath -Container $storageAccountSinkContainer -Properties $csvProperties -Blob $csvBlobName -Context $sa.Context -Force

Write-Output "DONE"