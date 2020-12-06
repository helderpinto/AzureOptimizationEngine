param(
    [Parameter(Mandatory = $false)]
    [string] $TargetSubscription = $null,

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
$storageAccountSinkContainer = Get-AutomationVariable -Name  "AzureOptimization_ConsumptionContainer" -ErrorAction SilentlyContinue
if ([string]::IsNullOrEmpty($storageAccountSinkContainer))
{
    $storageAccountSinkContainer = "consumptionexports"
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

# compute start+end dates

if ([string]::IsNullOrEmpty($targetStartDate) -or [string]::IsNullOrEmpty($targetEndDate))
{
    $targetStartDate = (Get-Date).Date.AddDays($consumptionOffsetDays * -1).ToString("yyyy-MM-dd")
    $targetEndDate = $targetStartDate    
}

if (-not([string]::IsNullOrEmpty($TargetSubscription)))
{
    $subscriptions = $TargetSubscription
}
else
{
    $subscriptions = Get-AzSubscription | ForEach-Object { "$($_.Id)"}
}

# for each subscription, get billing data

$datetime = (get-date).ToUniversalTime()
$timestamp = $datetime.ToString("yyyy-MM-ddTHH:mm:00.000Z")

foreach ($subscription in $subscriptions)
{
    $consumption = $null
    $billingEntries = @()

    $BillingApiPath = "/subscriptions/$subscription/providers/Microsoft.Consumption/usageDetails?api-version=2019-10-01&%24expand=properties%2FmeterDetails%2Cproperties%2FadditionalInfo&%24filter=properties%2FusageStart%20ge%20%27$targetStartDate%27%20and%20properties%2FusageEnd%20le%20%27$targetEndDate%27"

    Write-Output "Starting billing export process from $targetStartDate to $targetEndDate for subscription $subscription..."

    do
    {
        if (-not([string]::IsNullOrEmpty($consumption.nextLink)))
        {
            $BillingApiPath = $consumption.nextLink.Substring($consumption.nextLink.IndexOf("/subscriptions/"))
        }
        $tries = 0
        $requestSuccess = $false
        do 
        {        
            try {
                $tries++
                $consumption = (Invoke-AzRestMethod -Path $BillingApiPath -Method GET).Content | ConvertFrom-Json                    
                $requestSuccess = $true
            }
            catch {
                $ErrorMessage = $_.Exception.Message
                Write-Warning "Error getting consumption data: $ErrorMessage. $tries of 3 tries. Waiting 60 seconds..."
                Start-Sleep -s 60   
            }
        } while ( -not($requestSuccess) -and $tries -lt 3 )

        foreach ($consumptionLine in $consumption.value)
        {
            $additionalInfo = $null
            if (-not([string]::IsNullOrEmpty($consumptionLine.properties.additionalInfo)))
            {
                try {
                    $additionalInfo = ConvertFrom-Json $consumptionLine.properties.additionalInfo   
                }
                catch {
                    # do nothing
                }
            }

            $instanceId = $null
            if ($null -ne $consumptionLine.properties.resourceId)
            {
                $instanceId = $consumptionLine.properties.resourceId.ToLower()
            }

            $instanceName = $null
            if ($null -ne $consumptionLine.properties.resourceName)
            {
                $instanceName = $consumptionLine.properties.resourceName.ToLower()
            }

            $rgName = $null
            if ($null -ne $consumptionLine.properties.resourceGroup)
            {
                $rgName = $consumptionLine.properties.resourceGroup.ToLower()
            }

            $billingEntry = New-Object PSObject -Property @{
                Timestamp = $timestamp
                Cloud = $cloudEnvironment
                SubscriptionGuid = $consumptionLine.properties.subscriptionId
                ResourceGroupName = $rgName
                InstanceName = $instanceName
                InstanceId = $instanceId
                UsageDate = $consumptionLine.properties.date
                Tags = $consumptionLine.tags
                AdditionalInfo = $additionalInfo
                BillingCurrency = $consumptionLine.properties.billingCurrency
                ChargeType = $consumptionLine.properties.chargeType
                ConsumedService = $consumptionLine.properties.consumedService
                Cost = $consumptionLine.properties.cost
                EffectivePrice = $consumptionLine.properties.effectivePrice
                Frequency = $consumptionLine.properties.frequency
                MeterCategory = $consumptionLine.properties.meterDetails.meterCategory
                MeterId = $consumptionLine.properties.meterId
                MeterName = $consumptionLine.properties.meterDetails.meterName
                MeterSubCategory = $consumptionLine.properties.meterDetails.meterSubCategory
                ServiceFamily = $consumptionLine.properties.meterDetails.serviceFamily
                PartNumber = $consumptionLine.properties.partNumber
                Product = $consumptionLine.properties.product
                Quantity = $consumptionLine.properties.quantity
                UnitOfMeasure = $consumptionLine.properties.meterDetails.unitOfMeasure
                UnitPrice = $consumptionLine.properties.unitPrice
                Location = $consumptionLine.properties.resourceLocation
                ReservationId = $consumptionLine.properties.reservationId
                ReservationName = $consumptionLine.properties.reservationName
                UsageId = $consumptionLine.id
                UsageName = $consumptionLine.name
            }            
            $billingEntries += $billingEntry
        }    
    }
    while ($requestSuccess -and -not([string]::IsNullOrEmpty($consumption.nextLink)))

    Write-Output "Generated $($billingEntries.Count) entries..."

    $csvExportPath = "$targetStartDate-$subscription.csv"

    $billingEntries | Export-Csv -Path $csvExportPath -NoTypeInformation

    $csvBlobName = $csvExportPath
    $csvProperties = @{"ContentType" = "text/csv"};
    Set-AzStorageBlobContent -File $csvExportPath -Container $storageAccountSinkContainer -Properties $csvProperties -Blob $csvBlobName -Context $sa.Context -Force
}
