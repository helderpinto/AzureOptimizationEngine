param(
    [Parameter(Mandatory = $false)]
    [string] $TargetScope = $null,

    [Parameter(Mandatory = $true)]
    [string] $BillingAccountID,

    [Parameter(Mandatory = $false)]
    [string] $externalCloudEnvironment = "",

    [Parameter(Mandatory = $false)]
    [string] $externalTenantId = "",

    [Parameter(Mandatory = $false)]
    [string] $externalCredentialName = "",

    [Parameter(Mandatory = $false)] 
    [string] $targetStartDate = "", # YYYY-MM-DD format

    [Parameter(Mandatory = $false)] 
    [string] $targetEndDate = "" # YYYY-MM-DD format
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

# get Consumption exports sink (storage account) details
$storageAccountSink = Get-AutomationVariable -Name  "AzureOptimization_StorageSink"
$storageAccountSinkRG = Get-AutomationVariable -Name  "AzureOptimization_StorageSinkRG"
$storageAccountSinkSubscriptionId = Get-AutomationVariable -Name  "AzureOptimization_StorageSinkSubId"
$storageAccountSinkContainer = Get-AutomationVariable -Name  "AzureOptimization_ReservationsContainer" -ErrorAction SilentlyContinue
if ([string]::IsNullOrEmpty($storageAccountSinkContainer))
{
    $storageAccountSinkContainer = "reservationsexports"
}

if (-not([string]::IsNullOrEmpty($externalCredentialName)))
{
    $externalCredential = Get-AutomationPSCredential -Name $externalCredentialName
}

$consumptionOffsetDays = [int] (Get-AutomationVariable -Name  "AzureOptimization_ConsumptionOffsetDays")

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

# get reference to storage sink
Select-AzSubscription -SubscriptionId $storageAccountSinkSubscriptionId
$sa = Get-AzStorageAccount -ResourceGroupName $storageAccountSinkRG -Name $storageAccountSink

if (-not([string]::IsNullOrEmpty($externalCredentialName)))
{
    Connect-AzAccount -ServicePrincipal -EnvironmentName $externalCloudEnvironment -Tenant $externalTenantId -Credential $externalCredential 
    $cloudEnvironment = $externalCloudEnvironment   
}

$tenantId = (Get-AzContext).Tenant.Id

# compute start+end dates

if ([string]::IsNullOrEmpty($targetStartDate) -or [string]::IsNullOrEmpty($targetEndDate))
{
    $targetStartDate = (Get-Date).Date.AddDays($consumptionOffsetDays * -1).ToString("yyyy-MM-dd")
    $targetEndDate = $targetStartDate    
}

if (-not([string]::IsNullOrEmpty($TargetScope)))
{
    $scope = $TargetScope
}
else
{
    $scope = "/providers/Microsoft.Billing/billingaccounts/$BillingAccountID"
}

$now = (Get-Date).ToUniversalTime().ToString("yyyy'-'MM'-'dd'T'HH':'mm':'ss'.'fff'Z'")
Write-Output "[$now] Starting reservations export process from $targetStartDate to $targetEndDate for scope $scope..."

# get reservations details

$reservationsDetailsResponse = $null
$reservationsDetails = @()
$reservationsDetailsPath = "/providers/Microsoft.Billing/billingAccounts/$BillingAccountID/reservations?api-version=2020-05-01&&refreshSummary=true"

do
{
    if (-not([string]::IsNullOrEmpty($reservationsDetailsResponse.nextLink)))
    {
        $reservationsDetailsPath = $reservationsDetailsResponse.nextLink.Substring($reservationsDetailsResponse.nextLink.IndexOf("/providers/"))
    }

    $reservationsDetailsResponse = (Invoke-AzRestMethod -Path $reservationsDetailsPath -Method GET).Content | ConvertFrom-Json
    $reservationsDetails += $reservationsDetailsResponse.value
}
while (-not([string]::IsNullOrEmpty($reservationsDetailsResponse.nextLink)))

$now = (Get-Date).ToUniversalTime().ToString("yyyy'-'MM'-'dd'T'HH':'mm':'ss'.'fff'Z'")
Write-Output "[$now] Found $($reservationsDetails.Count) reservation details."

# get reservations usage

$reservationsUsage = @()
$reservationsUsagePath = "$scope/providers/Microsoft.Consumption/reservationSummaries?api-version=2021-10-01&`$filter=properties/UsageDate ge $targetStartDate and properties/UsageDate le $targetEndDate&grain=daily"
$reservationsUsageResponse = (Invoke-AzRestMethod -Path $reservationsUsagePath -Method GET).Content | ConvertFrom-Json
$reservationsUsage += $reservationsUsageResponse.value

$now = (Get-Date).ToUniversalTime().ToString("yyyy'-'MM'-'dd'T'HH':'mm':'ss'.'fff'Z'")
Write-Output "[$now] Found $($reservationsUsage.Count) reservation usages."

$datetime = (get-date).ToUniversalTime()
$timestamp = $datetime.ToString("yyyy-MM-ddTHH:mm:00.000Z")

$reservations = @()

foreach ($usage in $reservationsUsage)
{
    $reservationResourceId = "/providers/microsoft.capacity/reservationorders/$($usage.properties.reservationOrderId)/reservations/$($usage.properties.reservationId)"
    $reservationDetail = $reservationsDetails | Where-Object { $_.id -eq $reservationResourceId }
    $reservationEntry = New-Object PSObject -Property @{
        ReservationResourceId = $reservationResourceId
        ReservationOrderId = $usage.properties.reservationOrderId
        ReservationId = $usage.properties.reservationId
        DisplayName = $reservationDetail.properties.displayName
        SKUName = $usage.properties.skuName
        Location = $reservationDetail.location
        ResourceType = $reservationDetail.properties.reservedResourceType
        AppliedScopeType = $reservationDetail.properties.userFriendlyAppliedScopeType
        Term = $reservationDetail.properties.term
        ProvisioningState = $reservationDetail.properties.displayProvisioningState
        RenewState = $reservationDetail.properties.userFriendlyRenewState
        PurchaseDate = $reservationDetail.properties.purchaseDate
        ExpiryDate = $reservationDetail.properties.expiryDate
        Archived = $reservationDetail.properties.archived
        ReservedHours = $usage.properties.reservedHours
        UsedHours = $usage.properties.usedHours
        UsageDate = $usage.properties.usageDate
        MinUtilPercentage = $usage.properties.minUtilizationPercentage
        AvgUtilPercentage = $usage.properties.avgUtilizationPercentage
        MaxUtilPercentage = $usage.properties.maxUtilizationPercentage
        PurchasedQuantity = $usage.properties.purchasedQuantity
        RemainingQuantity = $usage.properties.remainingQuantity
        TotalReservedQuantity = $usage.properties.totalReservedQuantity
        UsedQuantity = $usage.properties.usedQuantity
        UtilizedPercentage = $usage.properties.utilizedPercentage
        UtilTrend = $reservationDetail.properties.utilization.trend
        Util1Days = ($reservationDetail.properties.utilization.aggregates | Where-Object { $_.grain -eq 1 }).value
        Util7Days = ($reservationDetail.properties.utilization.aggregates | Where-Object { $_.grain -eq 7 }).value
        Util30Days = ($reservationDetail.properties.utilization.aggregates | Where-Object { $_.grain -eq 30 }).value
        Scope = $scope
        TenantGuid = $tenantId
        Cloud = $cloudEnvironment
        CollectedDate = $timestamp
        Timestamp = $timestamp
    }
    $reservations += $reservationEntry
}

$now = (Get-Date).ToUniversalTime().ToString("yyyy'-'MM'-'dd'T'HH':'mm':'ss'.'fff'Z'")
Write-Output "[$now] Generated $($reservations.Count) entries..."

$csvExportPath = "$targetStartDate-$BillingAccountID-$($scope.Split('/')[-1]).csv"

$now = (Get-Date).ToUniversalTime().ToString("yyyy'-'MM'-'dd'T'HH':'mm':'ss'.'fff'Z'")
Write-Output "[$now] Uploading CSV to Storage"

$ci = [CultureInfo]::new([System.Threading.Thread]::CurrentThread.CurrentCulture.Name)
if ($ci.NumberFormat.NumberDecimalSeparator -ne '.')
{
    Write-Output "Current culture ($($ci.Name)) does not use . as decimal separator"    
    $ci.NumberFormat.NumberDecimalSeparator = '.'
    [System.Threading.Thread]::CurrentThread.CurrentCulture = $ci
}

$reservations | Export-Csv -Path $csvExportPath -NoTypeInformation

$csvBlobName = $csvExportPath
$csvProperties = @{"ContentType" = "text/csv"};
Set-AzStorageBlobContent -File $csvExportPath -Container $storageAccountSinkContainer -Properties $csvProperties -Blob $csvBlobName -Context $sa.Context -Force
    
$now = (Get-Date).ToUniversalTime().ToString("yyyy'-'MM'-'dd'T'HH':'mm':'ss'.'fff'Z'")
Write-Output "[$now] Uploaded $csvBlobName to Blob Storage..."

Remove-Item -Path $csvExportPath -Force

$now = (Get-Date).ToUniversalTime().ToString("yyyy'-'MM'-'dd'T'HH':'mm':'ss'.'fff'Z'")
Write-Output "[$now] Removed $csvExportPath from local disk..."    