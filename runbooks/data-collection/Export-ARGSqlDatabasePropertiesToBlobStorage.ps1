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
$storageAccountSinkContainer = Get-AutomationVariable -Name  "AzureOptimization_ARGSqlDatabaseContainer" -ErrorAction SilentlyContinue
if ([string]::IsNullOrEmpty($storageAccountSinkContainer))
{
    $storageAccountSinkContainer = "argsqldbexports"
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

$alldbs = @()

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

$dbsTotal = @()

$resultsSoFar = 0

Write-Output "Querying for SQL Databases properties"

$argQuery = @"
    resources 
    | where type =~ 'microsoft.sql/servers/databases' and name != 'master'
    | extend skuName = sku.name, skuTier = sku.tier, skuCapacity = sku.capacity
    | extend storageAccountType = properties.storageAccountType, licenseType = properties.licenseType, serviceObjectiveName = properties.currentServiceObjectiveName
    | extend zoneRedundant = properties.zoneRedundant, maxSizeBytes = properties.maxSizeBytes, maxLogSizeBytes = properties.maxLogSizeBytes
    | order by id asc
"@

do
{
    if ($resultsSoFar -eq 0)
    {
        $dbs = Search-AzGraph -Query $argQuery -First $ARGPageSize -Subscription $subscriptions
    }
    else
    {
        $dbs = Search-AzGraph -Query $argQuery -First $ARGPageSize -Skip $resultsSoFar -Subscription $subscriptions
    }
    if ($dbs -and $dbs.GetType().Name -eq "PSResourceGraphResponse")
    {
        $dbs = $dbs.Data
    }
    $resultsCount = $dbs.Count
    $resultsSoFar += $resultsCount
    $dbsTotal += $dbs

} while ($resultsCount -eq $ARGPageSize)

$datetime = (Get-Date).ToUniversalTime()
$timestamp = $datetime.ToString("yyyy-MM-ddTHH:mm:00.000Z")
$statusDate = $datetime.ToString("yyyy-MM-dd")

Write-Output "Building $($dbsTotal.Count) SQL Database entries"

foreach ($db in $dbsTotal)
{
    $logentry = New-Object PSObject -Property @{
        Timestamp = $timestamp
        Cloud = $cloudEnvironment
        TenantGuid = $db.tenantId
        SubscriptionGuid = $db.subscriptionId
        ResourceGroupName = $db.resourceGroup.ToLower()
        ZoneRedundant = $db.zoneRedundant
        Location = $db.location
        DBName = $db.name.ToLower()
        InstanceId = $db.id.ToLower()
        SkuName = $db.skuName
        SkuTier = $db.skuTier
        SkuCapacity = $db.skuCapacity
        ServiceObjectiveName = $db.serviceObjectiveName
        StorageAccountType = $db.storageAccountType
        LicenseType = $db.licenseType
        MaxSizeBytes = $db.maxSizeBytes
        MaxLogSizeBytes = $db.maxLogSizeBytes
        Tags = $db.tags
        StatusDate = $statusDate
    }
    
    $alldbs += $logentry
}

Write-Output "Uploading CSV to Storage"

$today = $datetime.ToString("yyyyMMdd")
$csvExportPath = "$today-sqldbs-$subscriptionSuffix.csv"

$alldbs | Export-Csv -Path $csvExportPath -NoTypeInformation

$csvBlobName = $csvExportPath

$csvProperties = @{"ContentType" = "text/csv"};

Set-AzStorageBlobContent -File $csvExportPath -Container $storageAccountSinkContainer -Properties $csvProperties -Blob $csvBlobName -Context $sa.Context -Force

$now = (Get-Date).ToUniversalTime().ToString("yyyy'-'MM'-'dd'T'HH':'mm':'ss'.'fff'Z'")
Write-Output "[$now] Uploaded $csvBlobName to Blob Storage..."

Remove-Item -Path $csvExportPath -Force

$now = (Get-Date).ToUniversalTime().ToString("yyyy'-'MM'-'dd'T'HH':'mm':'ss'.'fff'Z'")
Write-Output "[$now] Removed $csvExportPath from local disk..."    