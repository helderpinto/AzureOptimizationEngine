param(
    [Parameter(Mandatory = $false)]
    [string] $TargetSubscription = $null
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

$allvms = @()

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

$armVmsTotal = @()
$classicVmsTotal = @()

$resultsSoFar = 0

<#
   Getting all ARM VMs properties with Azure Resource Graph query
#>

Write-Output "Querying for ARM VM properties"

$argQuery = @"
    where type =~ 'Microsoft.Compute/virtualMachines' 
    | extend dataDiskCount = array_length(properties.storageProfile.dataDisks), nicCount = array_length(properties.networkProfile.networkInterfaces) 
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
    where type =~ 'Microsoft.ClassicCompute/virtualMachines' 
    | extend dataDiskCount = iif(isnotnull(properties.storageProfile.dataDisks), array_length(properties.storageProfile.dataDisks), 0), nicCount = iif(isnotnull(properties.networkProfile.virtualNetwork.networkInterfaces), array_length(properties.networkProfile.virtualNetwork.networkInterfaces) + 1, 1) 
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
$hour = $datetime.Hour
$min = $datetime.Minute
$timestamp = $datetime.ToString("yyyy-MM-ddT$($hour):$($min):00.000Z")
$statusDate = $datetime.ToString("yyyy-MM-dd")

foreach ($vm in $armVmsTotal)
{
    $vmSize = $sizes | Where-Object {$_.name -eq $vm.properties.hardwareProfile.vmSize}

    $logentry = New-Object PSObject -Property @{
        Timestamp = $timestamp
        Cloud = $cloudEnvironment
        TenantGuid = $vm.tenantId
        SubscriptionGuid = $vm.subscriptionId
        ResourceGroupName = $vm.resourceGroup
        Zones = $vm.zones
        VMName = $vm.name
        DeploymentModel = 'ARM'
        InstanceId = $vm.id
        VMSize = $vmSize.name
        CoresCount = $vmSize.NumberOfCores
        MemoryMB = $vmSize.MemoryInMB
        OSType = $vm.properties.storageProfile.osDisk.osType
        DataDiskCount = $vm.dataDiskCount
        NicCount = $vm.nicCount
        StatusDate = $statusDate
        Tags = $vm.tags
    }
    
    $allvms += $logentry
}

foreach ($vm in $classicVmsTotal)
{
    $vmSize = $sizes | Where-Object {$_.name -eq $vm.properties.hardwareProfile.size}

    $logentry = New-Object PSObject -Property @{
        Timestamp = $timestamp
        Cloud = $cloudEnvironment
        TenantGuid = $vm.tenantId
        SubscriptionGuid = $vm.subscriptionId
        ResourceGroupName = $vm.resourceGroup
        VMName = $vm.name
        DeploymentModel = 'Classic'
        InstanceId = $vm.id
        VMSize = $vmSize.name
        CoresCount = $vmSize.NumberOfCores
        MemoryMB = $vmSize.MemoryInMB
        OSType = $vm.properties.storageProfile.operatingSystemDisk.operatingSystem
        DataDiskCount = $vm.dataDiskCount
        NicCount = $vm.nicCount
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

Select-AzSubscription -SubscriptionId $storageAccountSinkSubscriptionId
$sa = Get-AzStorageAccount -ResourceGroupName $storageAccountSinkRG -Name $storageAccountSink

Set-AzStorageBlobContent -File $csvExportPath -Container $storageAccountSinkContainer -Properties $csvProperties -Blob $csvBlobName -Context $sa.Context -Force

Write-Output "DONE"