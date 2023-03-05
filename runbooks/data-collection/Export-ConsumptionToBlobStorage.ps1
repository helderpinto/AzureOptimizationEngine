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

Authenticate-AzureWithOption -authOption $authenticationOption -cloudEnv $cloudEnvironment

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
    $subscriptions = Get-AzSubscription -SubscriptionId $TargetSubscription
}
else
{
    $supportedQuotaIDs = @('EnterpriseAgreement_2014-09-01','PayAsYouGo_2014-09-01','MSDN_2014-09-01','MSDNDevTest_2014-09-01')
    $subscriptions = Get-AzSubscription | Where-Object { $_.State -eq "Enabled" -and $_.SubscriptionPolicies.QuotaId -in $supportedQuotaIDs }
}

Write-Output "Exporting consumption data from $targetStartDate to $targetEndDate for $($subscriptions.Count) subscriptions..."

# for each subscription, get billing data

$datetime = (get-date).ToUniversalTime()
$timestamp = $datetime.ToString("yyyy-MM-ddTHH:mm:00.000Z")

$CostDetailsSupportedQuotaIDs = @('EnterpriseAgreement_2014-09-01')
$ConsumptionSupportedQuotaIDs = @('PayAsYouGo_2014-09-01','MSDN_2014-09-01','MSDNDevTest_2014-09-01')

$hadErrors = $false

foreach ($subscription in $subscriptions)
{
    $subscriptionQuotaID = $subscription.SubscriptionPolicies.QuotaId

    if ($subscriptionQuotaID -in $ConsumptionSupportedQuotaIDs)
    {
        $consumption = $null
        $billingEntries = @()
    
        $ConsumptionApiPath = "/subscriptions/$($subscription.Id)/providers/Microsoft.Consumption/usageDetails?api-version=2021-10-01&%24expand=properties%2FmeterDetails%2Cproperties%2FadditionalInfo&%24filter=properties%2FusageStart%20ge%20%27$targetStartDate%27%20and%20properties%2FusageEnd%20le%20%27$targetEndDate%27"
    
        Write-Output "Starting consumption export process from $targetStartDate to $targetEndDate for subscription $($subscription.Name)..."
    
        do
        {
            if (-not([string]::IsNullOrEmpty($consumption.nextLink)))
            {
                $ConsumptionApiPath = $consumption.nextLink.Substring($consumption.nextLink.IndexOf("/subscriptions/"))
            }
            $tries = 0
            $requestSuccess = $false
            do 
            {        
                try {
                    $tries++
                    $consumption = (Invoke-AzRestMethod -Path $ConsumptionApiPath -Method GET).Content | ConvertFrom-Json                    
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
                if ($consumptionLine.tags)
                {
                    $tags = $consumptionLine.tags | ConvertTo-Json
                }
                else
                {
                    $tags = $null
                }

                $billingEntry = New-Object PSObject -Property @{
                    Timestamp = $timestamp
                    SubscriptionId = $consumptionLine.properties.subscriptionId
                    SubscriptionName = $consumptionLine.properties.subscriptionName
                    ResourceGroup = $consumptionLine.properties.resourceGroup
                    ResourceName = $consumptionLine.properties.resourceName
                    ResourceId = $consumptionLine.properties.resourceId
                    Date = (Get-Date $consumptionLine.properties.date).ToString("MM/dd/yyyy")
                    Tags = $tags
                    AdditionalInfo = $consumptionLine.properties.additionalInfo
                    BillingCurrencyCode = $consumptionLine.properties.billingCurrency
                    ChargeType = $consumptionLine.properties.chargeType
                    ConsumedService = $consumptionLine.properties.consumedService
                    CostInBillingCurrency = $consumptionLine.properties.cost
                    EffectivePrice = $consumptionLine.properties.effectivePrice
                    Frequency = $consumptionLine.properties.frequency
                    MeterCategory = $consumptionLine.properties.meterDetails.meterCategory
                    MeterId = $consumptionLine.properties.meterId
                    MeterName = $consumptionLine.properties.meterDetails.meterName
                    MeterSubCategory = $consumptionLine.properties.meterDetails.meterSubCategory
                    ServiceFamily = $consumptionLine.properties.meterDetails.serviceFamily
                    PartNumber = $consumptionLine.properties.partNumber
                    ProductName = $consumptionLine.properties.product
                    Quantity = $consumptionLine.properties.quantity
                    UnitOfMeasure = $consumptionLine.properties.meterDetails.unitOfMeasure
                    UnitPrice = $consumptionLine.properties.unitPrice
                    ResourceLocation = $consumptionLine.properties.resourceLocation
                    ReservationId = $consumptionLine.properties.reservationId
                    ReservationName = $consumptionLine.properties.reservationName
                    PublisherType = $consumptionLine.properties.publisherType
                    PublisherName = $consumptionLine.properties.publisherName
                    PlanName = $consumptionLine.properties.planName
                    AccountOwnerId = $consumptionLine.properties.accountOwnerId
                    AccountName = $consumptionLine.properties.accountName
                    BillingAccountId = $consumptionLine.properties.billingAccountId
                    BillingProfileId = $consumptionLine.properties.billingProfileId
                    BillingProfileName= $consumptionLine.properties.billingProfileName
                    BillingPeriodStartDate= $consumptionLine.properties.billingPeriodStartDate
                    BillingPeriodEndDate= $consumptionLine.properties.billingPeriodEndDate
                }            
                $billingEntries += $billingEntry
            }    
        }
        while ($requestSuccess -and -not([string]::IsNullOrEmpty($consumption.nextLink)))
    
        if ($requestSuccess)
        {
            Write-Output "Generated $($billingEntries.Count) entries..."
        
            Write-Output "Uploading CSV to Storage"
        
            $ci = [CultureInfo]::new([System.Threading.Thread]::CurrentThread.CurrentCulture.Name)
            if ($ci.NumberFormat.NumberDecimalSeparator -ne '.')
            {
                Write-Output "Current culture ($($ci.Name)) does not use . as decimal separator"    
                $ci.NumberFormat.NumberDecimalSeparator = '.'
                [System.Threading.Thread]::CurrentThread.CurrentCulture = $ci
            }
        
            $csvExportPath = "$targetStartDate-$($subscription.Id).csv"
    
            $billingEntries | Export-Csv -Path $csvExportPath -NoTypeInformation    
    
            $csvBlobName = $csvExportPath
            $csvProperties = @{"ContentType" = "text/csv"};
            Set-AzStorageBlobContent -File $csvExportPath -Container $storageAccountSinkContainer -Properties $csvProperties -Blob $csvBlobName -Context $sa.Context -Force
            
            $now = (Get-Date).ToUniversalTime().ToString("yyyy'-'MM'-'dd'T'HH':'mm':'ss'.'fff'Z'")
            Write-Output "[$now] Uploaded $csvBlobName to Blob Storage..."
        
            Remove-Item -Path $csvExportPath -Force
        
            $now = (Get-Date).ToUniversalTime().ToString("yyyy'-'MM'-'dd'T'HH':'mm':'ss'.'fff'Z'")
            Write-Output "[$now] Removed $csvExportPath from local disk..."        
        }
        else
        {
            $hadErrors = $true
            Write-Warning "Failed to get consumption data for subscription $($subscription.Name)..."
        }
    }
    elseif ($subscriptionQuotaID -in $CostDetailsSupportedQuotaIDs)
    {
        Write-Output "Starting cost details export process from $targetStartDate to $targetEndDate for subscription $($subscription.Name)..."

        $MaxTries = 9 # The typical Retry-After is set to 20 seconds. We'll give 3 minutes overall to download the cost details report

        $CostDetailsApiPath = "/subscriptions/$($subscription.Id)/providers/Microsoft.CostManagement/generateCostDetailsReport?api-version=2022-05-01"
        $body = "{ `"metric`": `"ActualCost`", `"timePeriod`": { `"start`": `"$targetStartDate`", `"end`": `"$targetEndDate`" } }"
        $result = Invoke-AzRestMethod -Path $CostDetailsApiPath -Method POST -Payload $body
        $requestResultPath = $result.Headers.Location.PathAndQuery
        if ($result.StatusCode -in (200,202))
        {
            $tries = 0
            $requestSuccess = $false

            Write-Output "Obtained cost detail results endpoint: $requestResultPath..."

            Write-Output "Was told to wait $($result.Headers.RetryAfter.Delta.TotalSeconds) seconds."

            $sleepSeconds = 60
            if ($result.Headers.RetryAfter.Delta.TotalSeconds -gt 0)
            {
                $sleepSeconds = $result.Headers.RetryAfter.Delta.TotalSeconds
            }

            do
            {
                $tries++
                Write-Output "Checking whether export is ready (try $tries)..."
                
                Start-Sleep -Seconds $sleepSeconds
                $downloadResult = Invoke-AzRestMethod -Method GET -Path $requestResultPath

                if ($downloadResult.StatusCode -eq 200)
                {

                    Write-Output "Export is ready. Proceeding with CSV download..."

                    $downloadBlobJson = $downloadResult.Content | ConvertFrom-Json

                    $blobCounter = 0
                    foreach ($blob in $downloadBlobJson.manifest.blobs)
                    {
                        $blobCounter++

                        Write-Output "Downloading blob $blobCounter..."

                        $csvExportPath = "$targetStartDate-$($subscription.Id)-$blobCounter.csv"

                        Invoke-WebRequest -Uri $blob.blobLink -OutFile $csvExportPath

                        Write-Output "Blob downloaded to $csvExportPath successfully."

                        $csvBlobName = $csvExportPath
                        $csvProperties = @{"ContentType" = "text/csv"};
                        Set-AzStorageBlobContent -File $csvExportPath -Container $storageAccountSinkContainer -Properties $csvProperties -Blob $csvBlobName -Context $sa.Context -Force
                        
                        $now = (Get-Date).ToUniversalTime().ToString("yyyy'-'MM'-'dd'T'HH':'mm':'ss'.'fff'Z'")
                        Write-Output "[$now] Uploaded $csvBlobName to Blob Storage..."
                    
                        Remove-Item -Path $csvExportPath -Force
                    
                        $now = (Get-Date).ToUniversalTime().ToString("yyyy'-'MM'-'dd'T'HH':'mm':'ss'.'fff'Z'")
                        Write-Output "[$now] Removed $csvExportPath from local disk..."                    
                    }

                    $requestSuccess = $true
                }
                elseif ($downloadResult.StatusCode -eq 202)
                {
                    Write-Output "Was told to wait a bit more... $($downloadResult.Headers.RetryAfter.Delta.TotalSeconds) seconds."

                    $sleepSeconds = 60
                    if ($downloadResult.Headers.RetryAfter.Delta.TotalSeconds -gt 0)
                    {
                        $sleepSeconds = $downloadResult.Headers.RetryAfter.Delta.TotalSeconds
                    }
                }
                elseif ($downloadResult.StatusCode -eq 401)
                {
                    Write-Output "Had an authentication issue. Will login again and sleep just a couple of seconds."

                    Authenticate-AzureWithOption -authOption $authenticationOption -cloudEnv $cloudEnvironment

                    $sleepSeconds = 2
                }
                else
                {
                    $hadErrors = $true
                    Write-Warning "Got an unexpected response code: $($downloadResult.StatusCode)"
                }
            } 
            while (-not($requestSuccess) -and $tries -lt $MaxTries)

            if (-not($requestSuccess))
            {
                $hadErrors = $true
                Write-Warning "Error returned by the Download Cost Details API. Status Code: $($downloadResult.StatusCode). Message: $($downloadResult.Content)"
            }
            else
            {
                Write-Output "Export download processing complete."
            }
        }
        else
        {
            if ($result.StatusCode -ne 204)
            {
                $hadErrors = $true
                Write-Warning "Error returned by the Generate Cost Details API. Status Code: $($result.StatusCode). Message: $($result.Content)"
            }
            else
            {
                Write-Output "Request returned 204 No Content"
            }
        }
    }
    else
    {
        $hadErrors = $true
        Write-Warning "Subscription quota $subscriptionQuotaID not supported"
    }
}

if ($hadErrors)
{
    throw "There were errors during the export process. Please check the output for details."
}