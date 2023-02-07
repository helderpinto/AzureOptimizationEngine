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
    $authenticationOption = "ManagedIdentity"
}

# get ARG exports sink (storage account) details
$storageAccountSink = Get-AutomationVariable -Name  "AzureOptimization_StorageSink"
$storageAccountSinkRG = Get-AutomationVariable -Name  "AzureOptimization_StorageSinkRG"
$storageAccountSinkSubscriptionId = Get-AutomationVariable -Name  "AzureOptimization_StorageSinkSubId"
$storageAccountSinkContainer = Get-AutomationVariable -Name  "AzureOptimization_ARGNICContainer" -ErrorAction SilentlyContinue
if ([string]::IsNullOrEmpty($storageAccountSinkContainer))
{
    $storageAccountSinkContainer = "argnicexports"
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

$tenantId = (Get-AzContext).Tenant.Id

$allnics = @()

Write-Output "Getting subscriptions target $TargetSubscription"
if (-not([string]::IsNullOrEmpty($TargetSubscription)))
{
    $subscriptions = $TargetSubscription
    $subscriptionSuffix = $TargetSubscription
}
else
{
    $subscriptions = Get-AzSubscription | Where-Object { $_.State -eq "Enabled" } | ForEach-Object { "$($_.Id)"}
    $subscriptionSuffix = $cloudSuffix + "all-" + $tenantId
}

$nicsTotal = @()

$resultsSoFar = 0

Write-Output "Querying for NIC properties"

$argQuery = @"
    resources
    | where type =~ 'microsoft.network/networkinterfaces'
    | extend isPrimary = properties.primary
    | extend enableAcceleratedNetworking = properties.enableAcceleratedNetworking
    | extend enableIPForwarding = properties.enableIPForwarding
    | extend tapConfigurationsCount = array_length(properties.tapConfigurations)
    | extend hostedWorkloadsCount = array_length(properties.hostedWorkloads)
    | extend internalDomainNameSuffix = properties.dnsSettings.internalDomainNameSuffix
    | extend appliedDnsServers = properties.dnsSettings.appliedDnsServers
    | extend dnsServers = properties.dnsSettings.dnsServers
    | extend ownerVMId = tolower(properties.virtualMachine.id)
    | extend ownerPEId = tolower(properties.privateEndpoint.id)
    | extend macAddress = properties.macAddress
    | extend nicType = properties.nicType
    | extend nicNsgId = tolower(properties.networkSecurityGroup.id)
	| mv-expand ipconfigs = properties.ipConfigurations
    | project-away properties
    | extend privateIPAddressVersion = tostring(ipconfigs.properties.privateIPAddressVersion)
    | extend privateIPAllocationMethod = tostring(ipconfigs.properties.privateIPAllocationMethod)
    | extend isIPConfigPrimary = tostring(ipconfigs.properties.primary)
    | extend privateIPAddress = tostring(ipconfigs.properties.privateIPAddress)
    | extend publicIPId = tolower(ipconfigs.properties.publicIPAddress.id)
    | extend IPConfigName = tostring(ipconfigs.name)
    | extend subnetId = tolower(ipconfigs.properties.subnet.id)
    | project-away ipconfigs
    | order by id asc
"@

do
{
    if ($resultsSoFar -eq 0)
    {
        $nics = Search-AzGraph -Query $argQuery -First $ARGPageSize -Subscription $subscriptions
    }
    else
    {
        $nics = Search-AzGraph -Query $argQuery -First $ARGPageSize -Skip $resultsSoFar -Subscription $subscriptions
    }
    if ($nics -and $nics.GetType().Name -eq "PSResourceGraphResponse")
    {
        $nics = $nics.Data
    }
    $resultsCount = $nics.Count
    $resultsSoFar += $resultsCount
    $nicsTotal += $nics

} while ($resultsCount -eq $ARGPageSize)

$datetime = (Get-Date).ToUniversalTime()
$timestamp = $datetime.ToString("yyyy-MM-ddTHH:mm:00.000Z")
$statusDate = $datetime.ToString("yyyy-MM-dd")

Write-Output "Building $($nicsTotal.Count) ARM VNet nic entries"

foreach ($nic in $nicsTotal)
{
    $logentry = New-Object PSObject -Property @{
        Timestamp = $timestamp
        Cloud = $cloudEnvironment
        TenantGuid = $nic.tenantId
        SubscriptionGuid = $nic.subscriptionId
        ResourceGroupName = $nic.resourceGroup.ToLower()
        Location = $nic.location
        Name = $nic.name.ToLower()
        InstanceId = $nic.id.ToLower()
        IsPrimary = $nic.isPrimary
        EnableAcceleratedNetworking = $nic.enableAcceleratedNetworking
        EnableIPForwarding = $nic.enableIPForwarding
        TapConfigurationsCount = $nic.tapConfigurationsCount
        HostedWorkloadsCount = $nic.hostedWorkloadsCount
        InternalDomainNameSuffix = $nic.internalDomainNameSuffix
        AppliedDnsServers = $nic.appliedDnsServers
        DnsServers = $nic.dnsServers
        OwnerVMId = $nic.ownerVMId
        OwnerPEId = $nic.ownerPEId
        MacAddress = $nic.macAddress
        NicType = $nic.nicType
        NicNSGId = $nic.nicNsgId
        PrivateIPAddressVersion = $nic.privateIPAddressVersion
        PrivateIPAllocationMethod = $nic.privateIPAllocationMethod
        IsIPConfigPrimary = $nic.isIPConfigPrimary
        PrivateIPAddress = $nic.privateIPAddress
        PublicIPId = $nic.publicIPId
        IPConfigName = $nic.IPConfigName
        SubnetId = $nic.subnetId
        Tags = $nic.tags
        StatusDate = $statusDate
    }
    
    $allnics += $logentry
}

Write-Output "Uploading CSV to Storage"

$today = $datetime.ToString("yyyyMMdd")
$csvExportPath = "$today-nics-$subscriptionSuffix.csv"

$allnics | Export-Csv -Path $csvExportPath -NoTypeInformation

$csvBlobName = $csvExportPath

$csvProperties = @{"ContentType" = "text/csv"};

Set-AzStorageBlobContent -File $csvExportPath -Container $storageAccountSinkContainer -Properties $csvProperties -Blob $csvBlobName -Context $sa.Context -Force

$now = (Get-Date).ToUniversalTime().ToString("yyyy'-'MM'-'dd'T'HH':'mm':'ss'.'fff'Z'")
Write-Output "[$now] Uploaded $csvBlobName to Blob Storage..."

Remove-Item -Path $csvExportPath -Force

$now = (Get-Date).ToUniversalTime().ToString("yyyy'-'MM'-'dd'T'HH':'mm':'ss'.'fff'Z'")
Write-Output "[$now] Removed $csvExportPath from local disk..."    