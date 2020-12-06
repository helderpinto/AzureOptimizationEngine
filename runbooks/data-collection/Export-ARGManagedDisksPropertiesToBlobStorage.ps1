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
$storageAccountSinkContainer = Get-AutomationVariable -Name  "AzureOptimization_ARGDiskContainer" -ErrorAction SilentlyContinue
if ([string]::IsNullOrEmpty($storageAccountSinkContainer))
{
    $storageAccountSinkContainer = "argdiskexports"
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

$alldisks = @()

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

$mdisksTotal = @()
$resultsSoFar = 0

<#
   Getting all Managed Disks properties with Azure Resource Graph query
#>

Write-Output "Querying for ARM Managed Disks properties"

$argQuery = @"
    resources 
    | where type =~ 'Microsoft.Compute/disks' 
    | extend DiskId = tolower(id), OwnerVmId = tolower(managedBy) 
    | join kind=leftouter (
        resources 
        | where type =~ 'Microsoft.Compute/virtualMachines' and array_length(properties.storageProfile.dataDisks) > 0 
        | extend OwnerVmId = tolower(id) 
        | mv-expand DataDisks = properties.storageProfile.dataDisks 
        | extend DiskId = tolower(DataDisks.managedDisk.id), diskCaching = tostring(DataDisks.caching), diskType = 'Data' 
        | project DiskId, OwnerVmId, diskCaching, diskType 
        | union (
            resources 
            | where type =~ 'Microsoft.Compute/virtualMachines' 
            | extend OwnerVmId = tolower(id) 
            | extend DiskId = tolower(properties.storageProfile.osDisk.managedDisk.id), diskCaching = tostring(properties.storageProfile.osDisk.caching), diskType = 'OS' 
            | project DiskId, OwnerVmId, diskCaching, diskType
        )
    ) on OwnerVmId, DiskId 
    | project-away OwnerVmId, DiskId, OwnerVmId1, DiskId1 
    | order by id asc
"@

do
{
    if ($resultsSoFar -eq 0)
    {
        $mdisks = Search-AzGraph -Query $argQuery -First $ARGPageSize -Subscription $subscriptions
    }
    else
    {
        $mdisks = Search-AzGraph -Query $argQuery -First $ARGPageSize -Skip $resultsSoFar -Subscription $subscriptions 
    }
    $resultsCount = $mdisks.Count
    $resultsSoFar += $resultsCount
    $mdisksTotal += $mdisks

} while ($resultsCount -eq $ARGPageSize)

<#
    Building CSV entries 
#>

$datetime = (get-date).ToUniversalTime()
$timestamp = $datetime.ToString("yyyy-MM-ddTHH:mm:00.000Z")
$statusDate = $datetime.ToString("yyyy-MM-dd")

foreach ($disk in $mdisksTotal)
{
    $ownerVmId = $null
    if ($null -ne $disk.managedBy)
    {
        $ownerVmId = $disk.managedBy.ToLower()
    }

    $logentry = New-Object PSObject -Property @{
        Timestamp = $timestamp
        Cloud = $cloudEnvironment
        TenantGuid = $disk.tenantId
        SubscriptionGuid = $disk.subscriptionId
        ResourceGroupName = $disk.resourceGroup.ToLower()
        DiskName = $disk.name.ToLower()
        InstanceId = $disk.id.ToLower()
        Location = $disk.location
        OwnerVMId = $ownerVmId
        DeploymentModel = "Managed"
        DiskType = $disk.diskType 
        Caching = $disk.diskCaching 
        DiskSizeGB = $disk.properties.diskSizeGB
        SKU = $disk.sku.name
        StatusDate = $statusDate
        Tags = $disk.tags
    }
    
    $alldisks += $logentry
}

<#
    Actually exporting CSV to Azure Storage
#>

$today = $datetime.ToString("yyyyMMdd")
$csvExportPath = "$today-disks-$subscriptionSuffix.csv"

$alldisks | Export-Csv -Path $csvExportPath -NoTypeInformation

$csvBlobName = $csvExportPath

$csvProperties = @{"ContentType" = "text/csv"};

Set-AzStorageBlobContent -File $csvExportPath -Container $storageAccountSinkContainer -Properties $csvProperties -Blob $csvBlobName -Context $sa.Context -Force
