Param (
    [Parameter(Mandatory = $false)]
    [string] $TargetSubscription = $null,

    [Parameter(Mandatory = $true)]
    [string] $ResourceType, # ARM resource type

    [Parameter(Mandatory = $false)]
    [string] $ARGFilter, # e.g., name != 'master' and sku.tier in ('Basic','Standard','Premium')

    [Parameter(Mandatory = $true)]
    [string] $MetricNames, # comma-separated metrics names (use Get-AzMetricDefinition for a list of supported metric names for a given resource)

    [Parameter(Mandatory = $true)]
    [ValidateSet("Maximum", "Minimum", "Average", "Total")]
    [string] $AggregationType,

    [Parameter(Mandatory = $true)]
    [string] $TimeSpan, # [d.]hh:mm:ss

    [Parameter(Mandatory = $true)]
    [string] $TimeGrain, # [d.]hh:mm:ss (00:01:00, 00:05:00, 00:15:00, 00:30:00, 01:00:00, 06:00:00, 12:00:00, 1.00:00:00, 7.00:00:00, 30.00:00:00)

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
$storageAccountSinkContainer = Get-AutomationVariable -Name  "AzureOptimization_AzMonitorContainer" -ErrorAction SilentlyContinue
if ([string]::IsNullOrEmpty($storageAccountSinkContainer))
{
    $storageAccountSinkContainer = "azmonitorexports"
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

if (-not([string]::IsNullOrEmpty($TargetSubscription))) {
    $subscriptions = $TargetSubscription
    $subscriptionSuffix = "-" + $TargetSubscription
}
else {
    $subscriptions = Get-AzSubscription | Where-Object { $_.State -eq "Enabled" } | ForEach-Object { "$($_.Id)" }
    $subscriptionSuffix = $cloudSuffix + "-all-" + $tenantId
}

[TimeSpan]::Parse($TimeGrain) | Out-Null
$TimeSpanObj = [TimeSpan]::Parse("-$TimeSpan")

$now = (Get-Date).ToUniversalTime().ToString("yyyy'-'MM'-'dd'T'HH':'mm':'ss'.'fff'Z'")
Write-Output "[$now] Querying for $ResourceType with page size $ARGPageSize and target subscription $TargetSubscription..."

$allResources = @()

$resultsSoFar = 0

$argWhere = ""
if (-not([string]::IsNullOrEmpty($ARGFilter)))
{
    $argWhere = " and $ARGFilter"
}

$argQuery = @"
resources 
| where type =~ '$ResourceType'$argWhere
| project id, name, subscriptionId, resourceGroup, tenantId 
| order by id asc
"@

do {
    if ($resultsSoFar -eq 0) {
        $resources = (Search-AzGraph -Query $argQuery -First $ARGPageSize -Subscription $subscriptions).data
    }
    else {
        $resources = (Search-AzGraph -Query $argQuery -First $ARGPageSize -Skip $resultsSoFar -Subscription $subscriptions).data
    }
    $resultsCount = $resources.Count
    $resultsSoFar += $resultsCount
    $allResources += $resources

} while ($resultsCount -eq $ARGPageSize)

$now = (Get-Date).ToUniversalTime().ToString("yyyy'-'MM'-'dd'T'HH':'mm':'ss'.'fff'Z'")
Write-Output "[$now] Found $($allResources.Count) resources."

$metrics = $MetricNames.Split(',')

$now = Get-Date
$utcNow = $now.ToUniversalTime().ToString("yyyy'-'MM'-'dd'T'HH':'mm':'ss'.'fff'Z'")
$utcAgo = $now.Add($TimeSpanObj).ToUniversalTime().ToString("yyyy'-'MM'-'dd'T'HH':'mm':'ss'.'fff'Z'")

$customMetrics = @()

$now = (Get-Date).ToUniversalTime().ToString("yyyy'-'MM'-'dd'T'HH':'mm':'ss'.'fff'Z'")
Write-Output "[$now] Analyzing resources for $MetricNames metrics ($AggregationType with $TimeGrain time grain) since $utcAgo..."

foreach ($resource in $allResources) {
    $valuesAggregation = @()
    foreach ($metric in $metrics) {
        $metricValues = Get-AzMetric -ResourceId $resource.id -MetricName $metric -TimeGrain $TimeGrain -AggregationType $AggregationType `
            -StartTime $utcAgo -EndTime $utcNow -WarningAction SilentlyContinue -ErrorAction Continue
        if ($metricValues.Data) {
            if ($valuesAggregation.Count -eq 0) {
                $valuesAggregation = $metricValues.Data."$AggregationType"
            }
            else {
                for ($i = 0; $i -lt $valuesAggregation.Count; $i++) {
                    $valuesAggregation[$i] += $metricValues.Data[$i]."$AggregationType"
                }
            }    
        }
    }

    if ($valuesAggregation.Count -gt 0) {
        $aggregatedValue = $null
        switch ($AggregationType) {
            "Maximum" {
                $aggregatedValue = ($valuesAggregation | Measure-Object -Maximum).Maximum
            }
            "Minimum" {
                $aggregatedValue = ($valuesAggregation | Measure-Object -Minimum).Minimum
            }
            "Average" {
                $aggregatedValue = ($valuesAggregation | Measure-Object -Average).Average
            }
            "Total" {
                $aggregatedValue = ($valuesAggregation | Measure-Object -Sum).Sum
            }
        }
    
        $customMetric = New-Object PSObject -Property @{
            Timestamp         = $utcNow
            Cloud             = $cloudEnvironment
            TenantGuid        = $resource.tenantId
            SubscriptionGuid  = $resource.subscriptionId
            ResourceGroupName = $resource.resourceGroup.ToLower()
            ResourceName      = $resource.name.ToLower()
            ResourceId        = $resource.id.ToLower()
            MetricNames       = $MetricNames
            AggregationType   = $AggregationType
            MetricValue       = $aggregatedValue
            TimeGrain         = $TimeGrain
            TimeSpan          = $TimeSpan
        }
    
        $customMetrics += $customMetric
    }
}

$now = (Get-Date).ToUniversalTime().ToString("yyyy'-'MM'-'dd'T'HH':'mm':'ss'.'fff'Z'")
Write-Output "[$now] Found $($customMetrics.Count) resources to collect metrics from..."

$today = (Get-Date).ToUniversalTime().ToString("yyyyMMdd")
$ResourceTypeName = $ResourceType.Split('/')[1].ToLower()
$MetricName = $MetricNames.Replace(',','').Replace(' ','').ToLower()
$AggregationTypeName = $AggregationType.ToLower()
$csvExportPath = "$today-metrics-$ResourceTypeName-$MetricName-$AggregationTypeName-$subscriptionSuffix.csv"

$customMetrics | Export-Csv -Path $csvExportPath -NoTypeInformation

$csvBlobName = $csvExportPath

$csvProperties = @{"ContentType" = "text/csv"};

Set-AzStorageBlobContent -File $csvExportPath -Container $storageAccountSinkContainer -Properties $csvProperties -Blob $csvBlobName -Context $sa.Context -Force
