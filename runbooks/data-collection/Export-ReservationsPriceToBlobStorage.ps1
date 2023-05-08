param(
    [Parameter(Mandatory = $false)] 
    [string] $Filter = "serviceName eq 'Virtual Machines' and priceType eq 'Reservation'" # e.g., serviceName eq 'Virtual Machines' and priceType eq 'Reservation' and armRegionName eq 'northeurope'
)

$ErrorActionPreference = "Stop"

function Authenticate-AzureWithOption {
    param (
        [string] $authOption = "ManagedIdentity",
        [string] $cloudEnv = "AzureCloud"
    )

    switch ($authOption) {
        "RunAsAccount" { 
            $ArmConn = Get-AutomationConnection -Name AzureRunAsConnection
            Connect-AzAccount -ServicePrincipal -EnvironmentName $cloudEnv -Tenant $ArmConn.TenantID -ApplicationId $ArmConn.ApplicationID -CertificateThumbprint $ArmConn.CertificateThumbprint
            break
        }
        "ManagedIdentity" { 
            Connect-AzAccount -Identity -EnvironmentName $cloudEnv
            break
        }
        Default {
            $ArmConn = Get-AutomationConnection -Name AzureRunAsConnection
            Connect-AzAccount -ServicePrincipal -EnvironmentName $cloudEnv -Tenant $ArmConn.TenantID -ApplicationId $ArmConn.ApplicationID -CertificateThumbprint $ArmConn.CertificateThumbprint
            break
        }
    }        
}

$cloudEnvironment = Get-AutomationVariable -Name "AzureOptimization_CloudEnvironment" -ErrorAction SilentlyContinue # AzureCloud|AzureChinaCloud
if ([string]::IsNullOrEmpty($cloudEnvironment))
{
    $cloudEnvironment = "AzureCloud"
}
$authenticationOption = Get-AutomationVariable -Name  "AzureOptimization_AuthenticationOption" -ErrorAction SilentlyContinue # RunAsAccount|ManagedIdentity
if ([string]::IsNullOrEmpty($authenticationOption))
{
    $authenticationOption = "ManagedIdentity"
}

# get Consumption exports sink (storage account) details
$storageAccountSink = Get-AutomationVariable -Name  "AzureOptimization_StorageSink"
$storageAccountSinkRG = Get-AutomationVariable -Name  "AzureOptimization_StorageSinkRG"
$storageAccountSinkSubscriptionId = Get-AutomationVariable -Name  "AzureOptimization_StorageSinkSubId"
$storageAccountSinkContainer = Get-AutomationVariable -Name  "AzureOptimization_ReservationsPriceContainer" -ErrorAction SilentlyContinue
if ([string]::IsNullOrEmpty($storageAccountSinkContainer))
{
    $storageAccountSinkContainer = "reservationspriceexports"
}

$filterVar = Get-AutomationVariable -Name "AzureOptimization_RetailPricesFilter" -ErrorAction SilentlyContinue
$currencyCode = Get-AutomationVariable -Name "AzureOptimization_RetailPricesCurrencyCode"

Write-Output "Logging in to Azure with $authenticationOption..."

Authenticate-AzureWithOption -authOption $authenticationOption -cloudEnv $cloudEnvironment

# get reference to storage sink
Select-AzSubscription -SubscriptionId $storageAccountSinkSubscriptionId
$sa = Get-AzStorageAccount -ResourceGroupName $storageAccountSinkRG -Name $storageAccountSink

if (-not([string]::IsNullOrEmpty($externalCredentialName)))
{
    Connect-AzAccount -ServicePrincipal -EnvironmentName $externalCloudEnvironment -Tenant $externalTenantId -Credential $externalCredential 
    $cloudEnvironment = $externalCloudEnvironment   
}

if (-not([string]::IsNullOrEmpty($filterVar)))
{
    $Filter = $filterVar
}

Write-Output "Starting retails prices export process with $currencyCode currency code and filter: $Filter ..."

$RetailPricesApiPath = "https://prices.azure.com/api/retail/prices?currencyCode='$currencyCode'&`$filter=$Filter"

$prices = @()

do
{
    $Response = Invoke-RestMethod -Method Get -Uri $RetailPricesApiPath
    if ($Response.Items.Count -gt 0)
    {
        $prices += $Response.Items
    }
    $RetailPricesApiPath = $Response.NextPageLink
} while ($Response.NextPageLink)

$datetime = (get-date).ToUniversalTime()
$timestamp = $datetime.ToString("yyyyMMdd")

$fileFriendlyFilter = $Filter.Replace(" ","").Replace("'","")
$csvExportPath = "reservationsprice-$timestamp-$fileFriendlyFilter.csv"

$ci = [CultureInfo]::new([System.Threading.Thread]::CurrentThread.CurrentCulture.Name)
if ($ci.NumberFormat.NumberDecimalSeparator -ne '.')
{
    Write-Output "Current culture ($($ci.Name)) does not use . as decimal separator"    
    $ci.NumberFormat.NumberDecimalSeparator = '.'
    [System.Threading.Thread]::CurrentThread.CurrentCulture = $ci
}

$prices | Export-Csv -NoTypeInformation -Path $csvExportPath
        
Write-Output "Reservations price CSV exported to $csvExportPath successfully."

$csvBlobName = $csvExportPath
$csvProperties = @{"ContentType" = "text/csv"};
Set-AzStorageBlobContent -File $csvExportPath -Container $storageAccountSinkContainer -Properties $csvProperties -Blob $csvBlobName -Context $sa.Context -Force

$now = (Get-Date).ToUniversalTime().ToString("yyyy'-'MM'-'dd'T'HH':'mm':'ss'.'fff'Z'")
Write-Output "[$now] Uploaded $csvBlobName to Blob Storage..."

Remove-Item -Path $csvExportPath -Force

$now = (Get-Date).ToUniversalTime().ToString("yyyy'-'MM'-'dd'T'HH':'mm':'ss'.'fff'Z'")
Write-Output "[$now] Removed $csvExportPath from local disk..."                    
