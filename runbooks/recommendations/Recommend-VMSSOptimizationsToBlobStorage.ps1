$ErrorActionPreference = "Stop"

function Find-SkuHourlyPrice {
    param (
        [object[]] $SKUPriceSheet,
        [string] $SKUName
    )

    $skuPriceObject = $null

    if ($SKUPriceSheet)
    {
        $skuNameParts = $SKUName.Split('_')

        if ($skuNameParts.Count -eq 3) # e.g., Standard_D1_v2
        {
            $skuNameFilter = "*" + $skuNameParts[1] + "*"
            $skuVersionFilter = "*" + $skuNameParts[2]
            $skuPrices = $SKUPriceSheet | Where-Object { $_.MeterDetails.MeterName -like $skuNameFilter `
             -and $_.MeterDetails.MeterName -notlike '*Low Priority' -and $_.MeterDetails.MeterName -notlike '*Expired' `
             -and $_.MeterDetails.MeterName -like $skuVersionFilter -and $_.MeterDetails.MeterSubCategory -notlike '*Windows' -and $_.UnitPrice -ne 0 }
            
            if (($skuPrices -or $skuPrices.Count -ge 1) -and $skuPrices.Count -le 2)
            {
                $skuPriceObject = $skuPrices[0]
            }
            if ($skuPrices.Count -gt 2) # D1-like scenarios
            {
                $skuFilter = "*" + $skuNameParts[1] + " " + $skuNameParts[2] + "*"
                $skuPrices = $skuPrices | Where-Object { $_.MeterDetails.MeterName -like $skuFilter }
    
                if (($skuPrices -or $skuPrices.Count -ge 1) -and $skuPrices.Count -le 2)
                {
                    $skuPriceObject = $skuPrices[0]
                }
            }
        }
    
        if ($skuNameParts.Count -eq 2) # e.g., Standard_D1
        {
            $skuNameFilter = "*" + $skuNameParts[1] + "*"
    
            $skuPrices = $SKUPriceSheet | Where-Object { $_.MeterDetails.MeterName -like $skuNameFilter `
             -and $_.MeterDetails.MeterName -notlike '*Low Priority' -and $_.MeterDetails.MeterName -notlike '*Expired' `
             -and $_.MeterDetails.MeterName -notlike '* v*' -and $_.MeterDetails.MeterSubCategory -notlike '*Windows' -and $_.UnitPrice -ne 0 }
            
            if (($skuPrices -or $skuPrices.Count -ge 1) -and $skuPrices.Count -le 2)
            {
                $skuPriceObject = $skuPrices[0]
            }
            if ($skuPrices.Count -gt 2) # D1-like scenarios
            {
                $skuFilterLeft = "*" + $skuNameParts[1] + "/*"
                $skuFilterRight = "*/" + $skuNameParts[1] + "*"
                $skuPrices = $skuPrices | Where-Object { $_.MeterDetails.MeterName -like $skuFilterLeft -or $_.MeterDetails.MeterName -like $skuFilterRight }
                
                if (($skuPrices -or $skuPrices.Count -ge 1) -and $skuPrices.Count -le 2)
                {
                    $skuPriceObject = $skuPrices[0]
                }
            }
        }    
    }

    $targetHourlyPrice = [double]::MaxValue
    if ($null -ne $skuPriceObject)
    {
        $targetUnitHours = [int] (Select-String -InputObject $skuPriceObject.UnitOfMeasure -Pattern "^\d+").Matches[0].Value
        if ($targetUnitHours -gt 0)
        {
            $targetHourlyPrice = [double] ($skuPriceObject.UnitPrice / $targetUnitHours)
        }
    }

    return $targetHourlyPrice
}

# Collect generic and recommendation-specific variables

$cloudEnvironment = Get-AutomationVariable -Name "AzureOptimization_CloudEnvironment" -ErrorAction SilentlyContinue # AzureCloud|AzureChinaCloud
if ([string]::IsNullOrEmpty($cloudEnvironment))
{
    $cloudEnvironment = "AzureCloud"
}
$authenticationOption = Get-AutomationVariable -Name "AzureOptimization_AuthenticationOption" -ErrorAction SilentlyContinue # RunAsAccount|ManagedIdentity
if ([string]::IsNullOrEmpty($authenticationOption))
{
    $authenticationOption = "RunAsAccount"
}

$workspaceId = Get-AutomationVariable -Name  "AzureOptimization_LogAnalyticsWorkspaceId"
$workspaceName = Get-AutomationVariable -Name  "AzureOptimization_LogAnalyticsWorkspaceName"
$workspaceRG = Get-AutomationVariable -Name  "AzureOptimization_LogAnalyticsWorkspaceRG"
$workspaceSubscriptionId = Get-AutomationVariable -Name  "AzureOptimization_LogAnalyticsWorkspaceSubId"
$workspaceTenantId = Get-AutomationVariable -Name  "AzureOptimization_LogAnalyticsWorkspaceTenantId"

$storageAccountSink = Get-AutomationVariable -Name  "AzureOptimization_StorageSink"
$storageAccountSinkRG = Get-AutomationVariable -Name  "AzureOptimization_StorageSinkRG"
$storageAccountSinkSubscriptionId = Get-AutomationVariable -Name  "AzureOptimization_StorageSinkSubId"
$storageAccountSinkContainer = Get-AutomationVariable -Name  "AzureOptimization_RecommendationsContainer" -ErrorAction SilentlyContinue 
if ([string]::IsNullOrEmpty($storageAccountSinkContainer)) {
    $storageAccountSinkContainer = "recommendationsexports"
}

$deploymentDate = Get-AutomationVariable -Name  "AzureOptimization_DeploymentDate" # yyyy-MM-dd format
$deploymentDate = $deploymentDate.Replace('"', "")

$lognamePrefix = Get-AutomationVariable -Name  "AzureOptimization_LogAnalyticsLogPrefix" -ErrorAction SilentlyContinue
if ([string]::IsNullOrEmpty($lognamePrefix))
{
    $lognamePrefix = "AzureOptimization"
}

$sqlserver = Get-AutomationVariable -Name  "AzureOptimization_SQLServerHostname"
$sqlserverCredential = Get-AutomationPSCredential -Name "AzureOptimization_SQLServerCredential"
$SqlUsername = $sqlserverCredential.UserName 
$SqlPass = $sqlserverCredential.GetNetworkCredential().Password 
$sqldatabase = Get-AutomationVariable -Name  "AzureOptimization_SQLServerDatabase" -ErrorAction SilentlyContinue
if ([string]::IsNullOrEmpty($sqldatabase))
{
    $sqldatabase = "azureoptimization"
}

# percentiles variables
$cpuPercentile = [int] (Get-AutomationVariable -Name  "AzureOptimization_PerfPercentileCpu" -ErrorAction SilentlyContinue)
if (-not($cpuPercentile -gt 0)) {
    $cpuPercentile = 99
}
$memoryPercentile = [int] (Get-AutomationVariable -Name  "AzureOptimization_PerfPercentileMemory" -ErrorAction SilentlyContinue)
if (-not($memoryPercentile -gt 0)) {
    $memoryPercentile = 99
}

# perf thresholds variables
$cpuPercentageThreshold = [int] (Get-AutomationVariable -Name  "AzureOptimization_PerfThresholdCpuPercentage" -ErrorAction SilentlyContinue)
if (-not($cpuPercentageThreshold -gt 0)) {
    $cpuPercentageThreshold = 30
}
$memoryPercentageThreshold = [int] (Get-AutomationVariable -Name  "AzureOptimization_PerfThresholdMemoryPercentage" -ErrorAction SilentlyContinue)
if (-not($memoryPercentageThreshold -gt 0)) {
    $memoryPercentageThreshold = 50
}
$cpuDegradedMaxPercentageThreshold = [int] (Get-AutomationVariable -Name  "AzureOptimization_PerfThresholdCpuDegradedMaxPercentage" -ErrorAction SilentlyContinue)
if (-not($cpuDegradedMaxPercentageThreshold -gt 0)) {
    $cpuDegradedMaxPercentageThreshold = 95
}
$cpuDegradedAvgPercentageThreshold = [int] (Get-AutomationVariable -Name  "AzureOptimization_PerfThresholdCpuDegradedAvgPercentage" -ErrorAction SilentlyContinue)
if (-not($cpuDegradedAvgPercentageThreshold -gt 0)) {
    $cpuDegradedAvgPercentageThreshold = 70
}
$memoryDegradedPercentageThreshold = [int] (Get-AutomationVariable -Name  "AzureOptimization_PerfThresholdMemoryDegradedPercentage" -ErrorAction SilentlyContinue)
if (-not($memoryDegradedPercentageThreshold -gt 0)) {
    $memoryDegradedPercentageThreshold = 80
}

$consumptionOffsetDays = [int] (Get-AutomationVariable -Name  "AzureOptimization_ConsumptionOffsetDays")
$consumptionOffsetDaysStart = $consumptionOffsetDays + 1

$perfDaysBackwards = [int] (Get-AutomationVariable -Name  "AzureOptimization_RecommendPerfPeriodInDays" -ErrorAction SilentlyContinue)
if (-not($perfDaysBackwards -gt 0)) {
    $perfDaysBackwards = 7
}

$perfTimeGrain = Get-AutomationVariable -Name  "AzureOptimization_RecommendPerfTimeGrain" -ErrorAction SilentlyContinue
if (-not($perfTimeGrain)) {
    $perfTimeGrain = "1h"
}

$referenceRegion = Get-AutomationVariable -Name "AzureOptimization_ReferenceRegion"

$SqlTimeout = 120
$LogAnalyticsIngestControlTable = "LogAnalyticsIngestControl"

# Authenticate against Azure

Write-Output "Logging in to Azure with $authenticationOption..."

switch ($authenticationOption) {
    "RunAsAccount" { 
        $ArmConn = Get-AutomationConnection -Name AzureRunAsConnection
        Connect-AzAccount -ServicePrincipal -EnvironmentName $cloudEnvironment -Tenant $ArmConn.TenantID -ApplicationId $ArmConn.ApplicationID -CertificateThumbprint $ArmConn.CertificateThumbprint
        break
    }
    "ManagedIdentity" { 
        Connect-AzAccount -Identity
        break
    }
    Default {
        $ArmConn = Get-AutomationConnection -Name AzureRunAsConnection
        Connect-AzAccount -ServicePrincipal -EnvironmentName $cloudEnvironment -Tenant $ArmConn.TenantID -ApplicationId $ArmConn.ApplicationID -CertificateThumbprint $ArmConn.CertificateThumbprint
        break
    }
}

Write-Output "Finding tables where recommendations will be generated from..."

$tries = 0
$connectionSuccess = $false
do {
    $tries++
    try {
        $Conn = New-Object System.Data.SqlClient.SqlConnection("Server=tcp:$sqlserver,1433;Database=$sqldatabase;User ID=$SqlUsername;Password=$SqlPass;Trusted_Connection=False;Encrypt=True;Connection Timeout=$SqlTimeout;") 
        $Conn.Open() 
        $Cmd=new-object system.Data.SqlClient.SqlCommand
        $Cmd.Connection = $Conn
        $Cmd.CommandTimeout = $SqlTimeout
        $Cmd.CommandText = "SELECT * FROM [dbo].[$LogAnalyticsIngestControlTable] WHERE CollectedType IN ('ARGVMSS','MonitorMetrics','ARGResourceContainers','AzureConsumption')"
    
        $sqlAdapter = New-Object System.Data.SqlClient.SqlDataAdapter
        $sqlAdapter.SelectCommand = $Cmd
        $controlRows = New-Object System.Data.DataTable
        $sqlAdapter.Fill($controlRows) | Out-Null            
        $connectionSuccess = $true
    }
    catch {
        Write-Output "Failed to contact SQL at try $tries."
        Write-Output $Error[0]
        Start-Sleep -Seconds ($tries * 20)
    }    
} while (-not($connectionSuccess) -and $tries -lt 3)

if (-not($connectionSuccess))
{
    throw "Could not establish connection to SQL."
}

$vmssTableName = $lognamePrefix + ($controlRows | Where-Object { $_.CollectedType -eq 'ARGVMSS' }).LogAnalyticsSuffix + "_CL"
$metricsTableName = $lognamePrefix + ($controlRows | Where-Object { $_.CollectedType -eq 'MonitorMetrics' }).LogAnalyticsSuffix + "_CL"
$subscriptionsTableName = $lognamePrefix + ($controlRows | Where-Object { $_.CollectedType -eq 'ARGResourceContainers' }).LogAnalyticsSuffix + "_CL"
$consumptionTableName = $lognamePrefix + ($controlRows | Where-Object { $_.CollectedType -eq 'AzureConsumption' }).LogAnalyticsSuffix + "_CL"

Write-Output "Will run query against tables $vmssTableName, $metricsTableName, $subscriptionsTableName and $consumptionTableName"

$Conn.Close()    
$Conn.Dispose()            

$recommendationSearchTimeSpan = 30 + $consumptionOffsetDaysStart

# Grab a context reference to the Storage Account where the recommendations file will be stored

Select-AzSubscription -SubscriptionId $storageAccountSinkSubscriptionId
$sa = Get-AzStorageAccount -ResourceGroupName $storageAccountSinkRG -Name $storageAccountSink

if ($workspaceSubscriptionId -ne $storageAccountSinkSubscriptionId)
{
    Select-AzSubscription -SubscriptionId $workspaceSubscriptionId
}

Write-Output "Getting Virtual Machine SKUs for the $referenceRegion region..."

$skus = Get-AzComputeResourceSku -Location $referenceRegion | Where-Object { $_.ResourceType -eq "virtualMachines" }

Write-Output "Getting the current Pricesheet..."

if ($cloudEnvironment -eq "AzureCloud")
{
    $pricesheetRegion = "EU West"
}

try 
{
    $pricesheet = $null
    $pricesheetEntries = @()
    $subscription = $workspaceSubscriptionId
    $PriceSheetApiPath = "/subscriptions/$subscription/providers/Microsoft.Consumption/pricesheets/default?api-version=2019-10-01&%24expand=properties%2FmeterDetails"

    do
    {
        if (-not([string]::IsNullOrEmpty($pricesheet.properties.nextLink)))
        {
            $PriceSheetApiPath = $pricesheet.properties.nextLink.Substring($pricesheet.properties.nextLink.IndexOf("/subscriptions/"))
        }
        $tries = 0
        $requestSuccess = $false
        do 
        {        
            try {
                $tries++
                $pricesheet = (Invoke-AzRestMethod -Path $PriceSheetApiPath -Method GET).Content | ConvertFrom-Json

                if ($pricesheet.error)
                {
                    throw "Cost Management not available ($($pricesheet.error.message))"
                }    

                $requestSuccess = $true
            }
            catch {
                $ErrorMessage = $_.Exception.Message
                Write-Warning "Error getting consumption data: $ErrorMessage. $tries of 3 tries. Waiting 30 seconds..."
                Start-Sleep -s 30   
            }
        } while ( -not($requestSuccess) -and $tries -lt 3 )

        if ($pricesheet.error)
        {
            throw "Cost Management not available"
        }

        $pricesheetEntries += $pricesheet.properties.pricesheets | Where-Object { $_.meterDetails.meterLocation -eq $pricesheetRegion -and $_.meterDetails.meterCategory -eq "Virtual Machines" }

    }
    while ($requestSuccess -and -not([string]::IsNullOrEmpty($pricesheet.properties.nextLink)))
}
catch
{
    Write-Output "Consumption pricesheet not available, will estimate savings based in cores count..."
    $pricesheet = $null
}

$skuPricesFound = @{}

Write-Output "Looking for underutilized Scale Sets, with less than $cpuPercentageThreshold% CPU and $memoryPercentageThreshold% RAM usage..."

$baseQuery = @"
    let billingInterval = 30d; 
    let perfInterval = $($perfDaysBackwards)d; 
    let cpuPercentileValue = $cpuPercentile;
    let memoryPercentileValue = $memoryPercentile;
    let etime = todatetime(toscalar($consumptionTableName | summarize max(UsageDate_t))); 
    let stime = etime-billingInterval; 

    let BilledVMs = $consumptionTableName 
    | where UsageDate_t between (stime..etime) and InstanceId_s contains 'virtualmachinescalesets'
    | extend VMConsumedQuantity = iif(InstanceId_s contains 'virtualmachinescalesets' and MeterCategory_s == 'Virtual Machines', todouble(Quantity_s), 0.0)
    | extend VMPrice = iif(InstanceId_s contains 'virtualmachinescalesets' and MeterCategory_s == 'Virtual Machines', todouble(UnitPrice_s), 0.0)
    | extend FinalCost = VMPrice * VMConsumedQuantity
    | summarize Last30DaysCost = sum(FinalCost), Last30DaysQuantity = sum(VMConsumedQuantity) by InstanceId_s;

    let MemoryPerf = $metricsTableName 
    | where TimeGenerated > ago(perfInterval) 
    | where MetricNames_s == "Available Memory Bytes" and AggregationType_s == "Minimum"
    | extend MemoryAvailableMBs = todouble(MetricValue_s)/1024/1024
    | project TimeGenerated, MemoryAvailableMBs, InstanceId_s=ResourceId
    | join kind=inner (
        $vmssTableName 
        | where TimeGenerated > ago(1d)
        | distinct InstanceId_s, MemoryMB_s
    ) on InstanceId_s
    | extend MemoryPercentage = todouble(toint(MemoryMB_s) - toint(MemoryAvailableMBs)) / todouble(MemoryMB_s) * 100 
    | summarize PMemoryPercentage = percentile(MemoryPercentage, memoryPercentileValue) by InstanceId_s;

    let ProcessorPerf = $metricsTableName 
    | where TimeGenerated > ago(perfInterval) 
    | where MetricNames_s == "Percentage CPU" and AggregationType_s == 'Maximum'
    | extend InstanceId_s = ResourceId
    | summarize PCPUPercentage = percentile(todouble(MetricValue_s), cpuPercentileValue) by InstanceId_s;

    $vmssTableName 
    | where TimeGenerated > ago(1d)
    | distinct InstanceId_s, VMSSName_s, ResourceGroupName_s, SubscriptionGuid_g, Cloud_s, TenantGuid_g, VMSSSize_s, NicCount_s, DataDiskCount_s, Tags_s
    | join kind=inner ( BilledVMs ) on InstanceId_s 
    | join kind=leftouter ( MemoryPerf ) on InstanceId_s
    | join kind=leftouter ( ProcessorPerf ) on InstanceId_s
    | project InstanceId_s, VMSSName = VMSSName_s, ResourceGroup = ResourceGroupName_s, SubscriptionId = SubscriptionGuid_g, Cloud_s, TenantGuid_g, VMSSSize_s, NicCount_s, DataDiskCount_s, PMemoryPercentage, PCPUPercentage, Tags_s, Last30DaysCost, Last30DaysQuantity
    | join kind=leftouter ( 
        $subscriptionsTableName
        | where TimeGenerated > ago(1d)
        | where ContainerType_s =~ 'microsoft.resources/subscriptions' 
        | project SubscriptionId = SubscriptionGuid_g, SubscriptionName = ContainerName_s 
    ) on SubscriptionId
    | where isnotempty(PMemoryPercentage) and isnotempty(PCPUPercentage) and PMemoryPercentage < $memoryPercentageThreshold and PCPUPercentage < $cpuPercentageThreshold
"@

try
{
    $queryResults = Invoke-AzOperationalInsightsQuery -WorkspaceId $workspaceId -Query $baseQuery -Timespan (New-TimeSpan -Days $recommendationSearchTimeSpan) -Wait 600 -IncludeStatistics
    if ($queryResults)
    {
        $results = [System.Linq.Enumerable]::ToArray($queryResults.Results)        
    }
}
catch
{
    Write-Warning -Message "Query failed. Debug the following query in the AOE Log Analytics workspace: $baseQuery"    
}

Write-Output "Query finished with $($results.Count) results."

Write-Output "Query statistics: $($queryResults.Statistics.query)"

# Build the recommendations objects

$recommendations = @()
$datetime = (get-date).ToUniversalTime()
$timestamp = $datetime.ToString("yyyy-MM-ddTHH:mm:00.000Z")

foreach ($result in $results)
{

    $targetSku = $null
    $currentSku = $skus | Where-Object { $_.Name -eq $result.VMSSSize_s }

    $currentSkuvCPUs = [int]($currentSku.Capabilities | Where-Object { $_.Name -eq 'vCPUsAvailable' }).Value

    $memoryNeeded = [double]($currentSku.Capabilities | Where-Object { $_.Name -eq 'MemoryGB' }).Value * ([double] $result.PMemoryPercentage / 100)
    $cpuNeeded = [double]$currentSkuvCPUs * ([double] $result.PCPUPercentage / 100)
    $currentPremiumIO = [bool] ($currentSku.Capabilities | Where-Object { $_.Name -eq 'PremiumIO' }).Value

    if ($null -eq $skuPricesFound[$currentSku.Name])
    {
        $skuPricesFound[$currentSku.Name] = Find-SkuHourlyPrice -SKUName $currentSku.Name -SKUPriceSheet $pricesheetEntries
    }

    $targetSkuCandidates = @()

    foreach ($sku in $skus)
    {
        $targetSkuCandidate = $null

        $skuCPUs = [int] ($sku.Capabilities | Where-Object { $_.Name -eq 'vCPUsAvailable' }).Value
        $skuMemory = [int] ($sku.Capabilities | Where-Object { $_.Name -eq 'MemoryGB' }).Value
        $skuMaxDataDisks = [int] ($sku.Capabilities | Where-Object { $_.Name -eq 'MaxDataDiskCount' }).Value
        $skuMaxNICs = [int] ($sku.Capabilities | Where-Object { $_.Name -eq 'MaxNetworkInterfaces' }).Value
        $skuPremiumIO = [bool] ($sku.Capabilities | Where-Object { $_.Name -eq 'PremiumIO' }).Value

        if ($currentSku.Name -ne $sku.Name -and -not($sku.Name -like "*Promo*") -and [double]$skuCPUs -ge $cpuNeeded -and [double]$skuMemory -ge $memoryNeeded `
                -and $skuMaxDataDisks -ge [int] $result.DataDiskCount_s -and $skuMaxNICs -ge [int] $result.NicCount_s `
                -and ($currentPremiumIO -eq $false -or $skuPremiumIO -eq $currentPremiumIO))
        {
            if ($null -eq $skuPricesFound[$sku.Name])
            {
                $skuPricesFound[$sku.Name] = Find-SkuHourlyPrice -SKUName $sku.Name -SKUPriceSheet $pricesheetEntries
            }

            if ($skuPricesFound[$currentSku.Name] -eq 0 -or $skuPricesFound[$sku.Name] -lt $skuPricesFound[$currentSku.Name])
            {
                $targetSkuCandidate = New-Object PSObject -Property @{
                    Name = $sku.Name
                    HourlyPrice = $skuPricesFound[$sku.Name]
                    vCPUsAvailable = $skuCPUs
                    MemoryGB = $skuMemory
                }

                $targetSkuCandidates += $targetSkuCandidate    
            }
        }
    }

    $targetSku = $targetSkuCandidates | Sort-Object -Property HourlyPrice,MemoryGB,vCPUsAvailable | Select-Object -First 1

    if ($null -ne $targetSku)
    {
        $queryInstanceId = $result.InstanceId_s
        $queryText = @"
        let billingInterval = 30d; 
        let armId = `'$queryInstanceId`';
        let gInt = $perfTimeGrain;
        let MemoryPerf = $metricsTableName 
        | where TimeGenerated > ago(billingInterval)
        | extend CollectedDate = todatetime(strcat(format_datetime(TimeGenerated, 'yyyy-MM-dd'),'T',format_datetime(TimeGenerated, 'HH'),':00:00Z'))
        | where ResourceId == armId
        | where MetricNames_s == 'Available Memory Bytes' and AggregationType_s == 'Minimum'
        | extend MemoryAvailableMBs = todouble(MetricValue_s)/1024/1024
        | project CollectedDate, MemoryAvailableMBs, InstanceId_s=ResourceId
        | join kind=inner (
            $vmssTableName 
            | where TimeGenerated > ago(1d)
            | distinct InstanceId_s, MemoryMB_s
        ) on InstanceId_s
        | extend MemoryPercentage = todouble(toint(MemoryMB_s) - toint(MemoryAvailableMBs)) / todouble(MemoryMB_s) * 100 
        | summarize percentile(MemoryPercentage, $memoryPercentile) by bin(CollectedDate, gInt);
        let ProcessorPerf = $metricsTableName 
        | where TimeGenerated > ago(billingInterval) 
        | extend CollectedDate = todatetime(strcat(format_datetime(TimeGenerated, 'yyyy-MM-dd'),'T',format_datetime(TimeGenerated, 'HH'),':00:00Z'))
        | where ResourceId == armId
        | where MetricNames_s == 'Percentage CPU' and AggregationType_s == 'Maximum'
        | extend ProcessorPercentage = todouble(MetricValue_s)
        | summarize percentile(ProcessorPercentage, $cpuPercentile) by bin(CollectedDate, gInt);
        MemoryPerf
        | join kind=inner (ProcessorPerf) on CollectedDate
        | render timechart
"@

        switch ($cloudEnvironment)
        {
            "AzureCloud" { $azureTld = "com" }
            "AzureChinaCloud" { $azureTld = "cn" }
            "AzureUSGovernment" { $azureTld = "us" }
            default { $azureTld = "com" }
        }

        $encodedQuery = [System.Uri]::EscapeDataString($queryText)
        $detailsQueryStart = $datetime.AddDays(-30).ToString("yyyy-MM-dd")
        $detailsQueryEnd = $datetime.AddDays(8).ToString("yyyy-MM-dd")
        $detailsURL = "https://portal.azure.$azureTld#@$workspaceTenantId/blade/Microsoft_Azure_Monitoring_Logs/LogsBlade/resourceId/%2Fsubscriptions%2F$workspaceSubscriptionId%2Fresourcegroups%2F$workspaceRG%2Fproviders%2Fmicrosoft.operationalinsights%2Fworkspaces%2F$workspaceName/source/LogsBlade.AnalyticsShareLinkToQuery/query/$encodedQuery/timespan/$($detailsQueryStart)T00%3A00%3A00.000Z%2F$($detailsQueryEnd)T00%3A00%3A00.000Z"
    
        $additionalInfoDictionary = @{}
    
        $additionalInfoDictionary["SupportsDataDisksCount"] = "true"
        $additionalInfoDictionary["SupportsNICCount"] = "true"
        $additionalInfoDictionary["BelowCPUThreshold"] = "true"
        $additionalInfoDictionary["BelowMemoryThreshold"] = "true"
        $additionalInfoDictionary["currentSku"] = "$($result.VMSSSize_s)"
        $additionalInfoDictionary["targetSku"] = "$($targetSku.Name)"
        $additionalInfoDictionary["DataDiskCount"] = "$($result.DataDiskCount_s)"
        $additionalInfoDictionary["NicCount"] = "$($result.NicCount_s)"
        $additionalInfoDictionary["MetricCPUPercentage"] = "$($result.PCPUPercentage)"
        $additionalInfoDictionary["MetricMemoryPercentage"] = "$($result.PMemoryPercentage)"
    
        $fitScore = 4 # needs disk IOPS and throughput analysis to improve score
        
        $fitScore = [Math]::max(0.0, $fitScore)

        $savingCoefficient = [double] $currentSkuvCPUs / [double] $targetSku.vCPUsAvailable

        if ($targetSku -and $null -eq $skuPricesFound[$targetSku.Name])
        {
            $skuPricesFound[$targetSku.Name] = Find-SkuHourlyPrice -SKUName $targetSku.Name -SKUPriceSheet $pricesheetEntries
        }

        $targetSkuSavingsMonthly = $result.Last30DaysCost - ($result.Last30DaysCost / $savingCoefficient)

        if ($targetSku -and $skuPricesFound[$targetSku.Name] -lt [double]::MaxValue)
        {
            $targetSkuPrice = $skuPricesFound[$targetSku.Name]    

            if ($null -eq $skuPricesFound[$currentSku.Name])
            {
                $skuPricesFound[$currentSku.Name] = Find-SkuHourlyPrice -SKUName $currentSku.Name -SKUPriceSheet $pricesheetEntries
            }

            if ($skuPricesFound[$currentSku.Name] -lt [double]::MaxValue)
            {
                $currentSkuPrice = $skuPricesFound[$currentSku.Name]    
                $targetSkuSavingsMonthly = ($currentSkuPrice * [double] $result.Last30DaysQuantity) - ($targetSkuPrice * [double] $result.Last30DaysQuantity)    
            }
            else
            {
                $targetSkuSavingsMonthly = $result.Last30DaysCost - ($targetSkuPrice * [double] $result.Last30DaysQuantity)    
            }
        }

        $tags = @{}

        if (-not([string]::IsNullOrEmpty($result.Tags_s)))
        {
            $tagPairs = $result.Tags_s.Substring(2, $result.Tags_s.Length - 3).Split(';')
            foreach ($tagPairString in $tagPairs)
            {
                $tagPair = $tagPairString.Split('=')
                if (-not([string]::IsNullOrEmpty($tagPair[0])) -and -not([string]::IsNullOrEmpty($tagPair[1])))
                {
                    $tagName = $tagPair[0].Trim()
                    $tagValue = $tagPair[1].Trim()
                    $tags[$tagName] = $tagValue    
                }
            }
        }            
    
        if ($targetSkuSavingsMonthly -eq [double]::PositiveInfinity)
        {
            $targetSkuSavingsMonthly = [double] $result.Last30DaysCost / 2
        }

        $additionalInfoDictionary["savingsAmount"] = [double] $targetSkuSavingsMonthly     
        $additionalInfoDictionary["CostsAmount"] = [double] $result.Last30DaysCost 
    
        $recommendation = New-Object PSObject -Property @{
            Timestamp                   = $timestamp
            Cloud                       = $result.Cloud_s
            Category                    = "Cost"
            ImpactedArea                = "Microsoft.Compute/virtualMachineScaleSets"
            Impact                      = "High"
            RecommendationType          = "Saving"
            RecommendationSubType       = "UnderusedVMSS"
            RecommendationSubTypeId     = "a4955cc9-533d-46a2-8625-5c4ebd1c30d5"
            RecommendationDescription   = "VM Scale Set has been underutilized"
            RecommendationAction        = "Resize VM Scale Set to lower SKU or scale it in"
            InstanceId                  = $result.InstanceId_s
            InstanceName                = $result.VMSSName
            AdditionalInfo              = $additionalInfoDictionary
            ResourceGroup               = $result.ResourceGroup
            SubscriptionGuid            = $result.SubscriptionId
            SubscriptionName            = $result.SubscriptionName
            TenantGuid                  = $result.TenantGuid_g
            FitScore                    = $fitScore
            Tags                        = $tags
            DetailsURL                  = $detailsURL
        }
    
        $recommendations += $recommendation        
    }
}

# Export the recommendations as JSON to blob storage

$fileDate = $datetime.ToString("yyyy-MM-dd")
$jsonExportPath = "vmss-underutilized-$fileDate.json"
$recommendations | ConvertTo-Json | Out-File $jsonExportPath

$jsonBlobName = $jsonExportPath
$jsonProperties = @{"ContentType" = "application/json"};
Set-AzStorageBlobContent -File $jsonExportPath -Container $storageAccountSinkContainer -Properties $jsonProperties -Blob $jsonBlobName -Context $sa.Context -Force

Write-Output "Looking for performance constrained Scale Sets, with more than $cpuDegradedMaxPercentageThreshold% Max. CPU, $cpuDegradedAvgPercentageThreshold% Avg. CPU and $memoryDegradedPercentageThreshold% RAM usage..."

$baseQuery = @"
    let perfInterval = $($perfDaysBackwards)d; 
    let cpuPercentileValue = $cpuPercentile;

    let MemoryPerf = $metricsTableName 
    | where TimeGenerated > ago(perfInterval) 
    | where MetricNames_s == "Available Memory Bytes" and AggregationType_s == "Minimum"
    | extend MemoryAvailableMBs = todouble(MetricValue_s)/1024/1024
    | project TimeGenerated, MemoryAvailableMBs, InstanceId_s=ResourceId
    | join kind=inner (
        $vmssTableName 
        | where TimeGenerated > ago(1d)
        | distinct InstanceId_s, MemoryMB_s
    ) on InstanceId_s
    | extend MemoryPercentage = todouble(toint(MemoryMB_s) - toint(MemoryAvailableMBs)) / todouble(MemoryMB_s) * 100 
    | summarize PMemoryPercentage = avg(MemoryPercentage) by InstanceId_s;

    let ProcessorMaxPerf = $metricsTableName 
    | where TimeGenerated > ago(perfInterval) 
    | where MetricNames_s == "Percentage CPU" and AggregationType_s == 'Maximum'
    | extend InstanceId_s = ResourceId
    | summarize PCPUMaxPercentage = percentile(todouble(MetricValue_s), cpuPercentileValue) by InstanceId_s;

    let ProcessorAvgPerf = $metricsTableName 
    | where TimeGenerated > ago(perfInterval) 
    | where MetricNames_s == "Percentage CPU" and AggregationType_s == 'Average'
    | extend InstanceId_s = ResourceId
    | summarize PCPUAvgPercentage = percentile(todouble(MetricValue_s), cpuPercentileValue) by InstanceId_s;

    $vmssTableName 
    | where TimeGenerated > ago(1d)
    | distinct InstanceId_s, VMSSName_s, ResourceGroupName_s, SubscriptionGuid_g, Cloud_s, TenantGuid_g, VMSSSize_s, NicCount_s, DataDiskCount_s, Tags_s
    | join kind=leftouter ( MemoryPerf ) on InstanceId_s
    | join kind=leftouter ( ProcessorMaxPerf ) on InstanceId_s
    | join kind=leftouter ( ProcessorAvgPerf ) on InstanceId_s
    | project InstanceId_s, VMSSName = VMSSName_s, ResourceGroup = ResourceGroupName_s, SubscriptionId = SubscriptionGuid_g, Cloud_s, TenantGuid_g, VMSSSize_s, NicCount_s, DataDiskCount_s, PMemoryPercentage, PCPUMaxPercentage, PCPUAvgPercentage, Tags_s
    | join kind=leftouter ( 
        $subscriptionsTableName
        | where TimeGenerated > ago(1d)
        | where ContainerType_s =~ 'microsoft.resources/subscriptions' 
        | project SubscriptionId = SubscriptionGuid_g, SubscriptionName = ContainerName_s 
    ) on SubscriptionId
    | where isnotempty(PMemoryPercentage) and isnotempty(PCPUAvgPercentage) and isnotempty(PCPUMaxPercentage) and (PMemoryPercentage > $memoryDegradedPercentageThreshold or (PCPUMaxPercentage > $cpuDegradedMaxPercentageThreshold and PCPUAvgPercentage > $cpuDegradedAvgPercentageThreshold))
"@

try
{
    $queryResults = Invoke-AzOperationalInsightsQuery -WorkspaceId $workspaceId -Query $baseQuery -Timespan (New-TimeSpan -Days $recommendationSearchTimeSpan) -Wait 600 -IncludeStatistics
    if ($queryResults)
    {
        $results = [System.Linq.Enumerable]::ToArray($queryResults.Results)        
    }
}
catch
{
    Write-Warning -Message "Query failed. Debug the following query in the AOE Log Analytics workspace: $baseQuery"    
}

Write-Output "Query finished with $($results.Count) results."

Write-Output "Query statistics: $($queryResults.Statistics.query)"

# Build the recommendations objects

$recommendations = @()
$datetime = (get-date).ToUniversalTime()
$timestamp = $datetime.ToString("yyyy-MM-ddTHH:mm:00.000Z")

foreach ($result in $results)
{
    $queryInstanceId = $result.InstanceId_s
    $queryText = @"
    let perfInterval = 7d; 
    let armId = `'$queryInstanceId`';
    let gInt = $perfTimeGrain;
    let MemoryPerf = $metricsTableName 
    | where TimeGenerated > ago(perfInterval)
    | extend CollectedDate = todatetime(strcat(format_datetime(TimeGenerated, 'yyyy-MM-dd'),'T',format_datetime(TimeGenerated, 'HH'),':00:00Z'))
    | where ResourceId == armId
    | where MetricNames_s == 'Available Memory Bytes' and AggregationType_s == 'Minimum'
    | extend MemoryAvailableMBs = todouble(MetricValue_s)/1024/1024
    | project CollectedDate, MemoryAvailableMBs, InstanceId_s=ResourceId
    | join kind=inner (
        $vmssTableName 
        | where TimeGenerated > ago(1d)
        | distinct InstanceId_s, MemoryMB_s
    ) on InstanceId_s
    | extend MemoryPercentage = todouble(toint(MemoryMB_s) - toint(MemoryAvailableMBs)) / todouble(MemoryMB_s) * 100 
    | summarize avg(MemoryPercentage) by bin(CollectedDate, gInt);
    let ProcessorMaxPerf = $metricsTableName 
    | where TimeGenerated > ago(perfInterval) 
    | extend CollectedDate = todatetime(strcat(format_datetime(TimeGenerated, 'yyyy-MM-dd'),'T',format_datetime(TimeGenerated, 'HH'),':00:00Z'))
    | where ResourceId == armId
    | where MetricNames_s == 'Percentage CPU' and AggregationType_s == 'Maximum'
    | extend ProcessorMaxPercentage = todouble(MetricValue_s)
    | summarize percentile(ProcessorMaxPercentage, $cpuPercentile) by bin(CollectedDate, gInt);
    let ProcessorAvgPerf = $metricsTableName 
    | where TimeGenerated > ago(perfInterval) 
    | extend CollectedDate = todatetime(strcat(format_datetime(TimeGenerated, 'yyyy-MM-dd'),'T',format_datetime(TimeGenerated, 'HH'),':00:00Z'))
    | where ResourceId == armId
    | where MetricNames_s == 'Percentage CPU' and AggregationType_s == 'Average'
    | extend ProcessorAvgPercentage = todouble(MetricValue_s)
    | summarize percentile(ProcessorAvgPercentage, $cpuPercentile) by bin(CollectedDate, gInt);
    MemoryPerf
    | join kind=inner (ProcessorMaxPerf) on CollectedDate
    | join kind=inner (ProcessorAvgPerf) on CollectedDate
    | render timechart
"@

    switch ($cloudEnvironment)
    {
        "AzureCloud" { $azureTld = "com" }
        "AzureChinaCloud" { $azureTld = "cn" }
        "AzureUSGovernment" { $azureTld = "us" }
        default { $azureTld = "com" }
    }

    $encodedQuery = [System.Uri]::EscapeDataString($queryText)
    $detailsQueryStart = $datetime.AddDays(-30).ToString("yyyy-MM-dd")
    $detailsQueryEnd = $datetime.AddDays(8).ToString("yyyy-MM-dd")
    $detailsURL = "https://portal.azure.$azureTld#@$workspaceTenantId/blade/Microsoft_Azure_Monitoring_Logs/LogsBlade/resourceId/%2Fsubscriptions%2F$workspaceSubscriptionId%2Fresourcegroups%2F$workspaceRG%2Fproviders%2Fmicrosoft.operationalinsights%2Fworkspaces%2F$workspaceName/source/LogsBlade.AnalyticsShareLinkToQuery/query/$encodedQuery/timespan/$($detailsQueryStart)T00%3A00%3A00.000Z%2F$($detailsQueryEnd)T00%3A00%3A00.000Z"

    $additionalInfoDictionary = @{}

    $additionalInfoDictionary["MetricCPUAvgPercentage"] = "$($result.PCPUAvgPercentage)"
    $additionalInfoDictionary["MetricCPUMaxPercentage"] = "$($result.PCPUMaxPercentage)"
    $additionalInfoDictionary["MetricMemoryPercentage"] = "$($result.PMemoryPercentage)"

    $fitScore = 5 # needs disk IOPS and throughput analysis to improve score
    
    $fitScore = [Math]::max(0.0, $fitScore)

    $tags = @{}

    if (-not([string]::IsNullOrEmpty($result.Tags_s)))
    {
        $tagPairs = $result.Tags_s.Substring(2, $result.Tags_s.Length - 3).Split(';')
        foreach ($tagPairString in $tagPairs)
        {
            $tagPair = $tagPairString.Split('=')
            if (-not([string]::IsNullOrEmpty($tagPair[0])) -and -not([string]::IsNullOrEmpty($tagPair[1])))
            {
                $tagName = $tagPair[0].Trim()
                $tagValue = $tagPair[1].Trim()
                $tags[$tagName] = $tagValue    
            }
        }
    }            

    $recommendation = New-Object PSObject -Property @{
        Timestamp                   = $timestamp
        Cloud                       = $result.Cloud_s
        Category                    = "Performance"
        ImpactedArea                = "Microsoft.Compute/virtualMachineScaleSets"
        Impact                      = "Medium"
        RecommendationType          = "BestPractices"
        RecommendationSubType       = "PerfConstrainedVMSS"
        RecommendationSubTypeId     = "20a40c62-e5c8-4cc3-9fc2-f4ac75013182"
        RecommendationDescription   = "VM Scale Set performance has been constrained by lack of resources"
        RecommendationAction        = "Resize VM Scale Set to higher SKU or scale it out"
        InstanceId                  = $result.InstanceId_s
        InstanceName                = $result.VMSSName
        AdditionalInfo              = $additionalInfoDictionary
        ResourceGroup               = $result.ResourceGroup
        SubscriptionGuid            = $result.SubscriptionId
        SubscriptionName            = $result.SubscriptionName
        TenantGuid                  = $result.TenantGuid_g
        FitScore                    = $fitScore
        Tags                        = $tags
        DetailsURL                  = $detailsURL
    }

    $recommendations += $recommendation        
}

# Export the recommendations as JSON to blob storage

$fileDate = $datetime.ToString("yyyy-MM-dd")
$jsonExportPath = "vmss-perfconstrained-$fileDate.json"
$recommendations | ConvertTo-Json | Out-File $jsonExportPath

$jsonBlobName = $jsonExportPath
$jsonProperties = @{"ContentType" = "application/json"};
Set-AzStorageBlobContent -File $jsonExportPath -Container $storageAccountSinkContainer -Properties $jsonProperties -Blob $jsonBlobName -Context $sa.Context -Force

