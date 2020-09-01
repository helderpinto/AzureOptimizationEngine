$ErrorActionPreference = "Stop"


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

$lognamePrefix = Get-AutomationVariable -Name  "AzureOptimization_LogAnalyticsLogPrefix" -ErrorAction SilentlyContinue
if ([string]::IsNullOrEmpty($lognamePrefix))
{
    $lognamePrefix = "AzureOptimization"
}

$vmsTableSuffix = "VMsV1_CL"
$vmsTableName = $lognamePrefix + $vmsTableSuffix

$advisorTableSuffix = "AdvisorV1_CL"
$advisorTableName = $lognamePrefix + $advisorTableSuffix

$referenceRegion = Get-AutomationVariable -Name "AzureOptimization_ReferenceRegion"

# must be less than or equal to the advisor exports frequency
$daysBackwards = [int] (Get-AutomationVariable -Name  "AzureOptimization_RecommendAdvisorPeriodInDays" -ErrorAction SilentlyContinue)
if (-not($daysBackwards -gt 0)) {
    $daysBackwards = 7
}

$perfDaysBackwards = [int] (Get-AutomationVariable -Name  "AzureOptimization_RecommendPerfPeriodInDays" -ErrorAction SilentlyContinue)
if (-not($perfDaysBackwards -gt 0)) {
    $perfDaysBackwards = 7
}

$perfTimeGrain = Get-AutomationVariable -Name  "AzureOptimization_RecommendPerfTimeGrain" -ErrorAction SilentlyContinue
if (-not($perfTimeGrain)) {
    $perfTimeGrain = "1h"
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
$networkPercentile = [int] (Get-AutomationVariable -Name  "AzureOptimization_PerfPercentileNetwork" -ErrorAction SilentlyContinue)
if (-not($networkPercentile -gt 0)) {
    $networkPercentile = 99
}
$diskPercentile = [int] (Get-AutomationVariable -Name  "AzureOptimization_PerfPercentileDisk" -ErrorAction SilentlyContinue)
if (-not($diskPercentile -gt 0)) {
    $diskPercentile = 99
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
$networkMpbsThreshold = [int] (Get-AutomationVariable -Name  "AzureOptimization_PerfThresholdNetworkMbps" -ErrorAction SilentlyContinue)
if (-not($networkMpbsThreshold -gt 0)) {
    $networkMpbsThreshold = 750
}

# perf thresholds variables (shutdown)
$cpuPercentageShutdownThreshold = [int] (Get-AutomationVariable -Name  "AzureOptimization_PerfThresholdCpuShutdownPercentage" -ErrorAction SilentlyContinue)
if (-not($cpuPercentageShutdownThreshold -gt 0)) {
    $cpuPercentageShutdownThreshold = 5
}
$memoryPercentageShutdownThreshold = [int] (Get-AutomationVariable -Name  "AzureOptimization_PerfThresholdMemoryShutdownPercentage" -ErrorAction SilentlyContinue)
if (-not($memoryPercentageShutdownThreshold -gt 0)) {
    $memoryPercentageShutdownThreshold = 100
}
$networkMpbsShutdownThreshold = [int] (Get-AutomationVariable -Name  "AzureOptimization_PerfThresholdNetworkShutdownMbps" -ErrorAction SilentlyContinue )
if (-not($networkMpbsShutdownThreshold -gt 0)) {
    $networkMpbsShutdownThreshold = 10
}

$rightSizeRecommendationId = Get-AutomationVariable -Name  "AzureOptimization_RecommendationAdvisorCostRightSizeId" -ErrorAction SilentlyContinue
if (-not($rightSizeRecommendationId)) {
    $rightSizeRecommendationId = 'e10b1381-5f0a-47ff-8c7b-37bd13d7c974'
}

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


# Get the reference to the exports Storage Account
Select-AzSubscription -SubscriptionId $storageAccountSinkSubscriptionId
$sa = Get-AzStorageAccount -ResourceGroupName $storageAccountSinkRG -Name $storageAccountSink

if ($workspaceSubscriptionId -ne $storageAccountSinkSubscriptionId)
{
    Select-AzSubscription -SubscriptionId $workspaceSubscriptionId
}

Write-Output "Getting Virtual Machine SKUs for the $referenceRegion region..."
# Get all the VM SKUs information for the reference Azure region
$skus = Get-AzComputeResourceSku | Where-Object { $_.ResourceType -eq "virtualMachines" -and $_.LocationInfo.Location -eq $referenceRegion }

$baseQuery = @"
let advisorInterval = $($daysBackwards)d;
let perfInterval = $($perfDaysBackwards)d;
let perfTimeGrain = $perfTimeGrain;
let cpuPercentileValue = $cpuPercentile;
let memoryPercentileValue = $memoryPercentile;
let networkPercentileValue = $networkPercentile;
let diskPercentileValue = $diskPercentile;
let rightSizeRecommendationId = '$rightSizeRecommendationId';

let LinuxMemoryPerf = Perf 
| where TimeGenerated > ago(perfInterval) 
| where CounterName == '% Used Memory' 
| summarize hint.strategy=shuffle PMemoryPercentage = percentile(CounterValue, memoryPercentileValue) by _ResourceId;

let WindowsMemoryPerf = Perf 
| where TimeGenerated > ago(perfInterval) 
| where CounterName == 'Available MBytes' 
| project TimeGenerated, MemoryAvailableMBs = CounterValue, _ResourceId;

let MemoryPerf = $vmsTableName 
| where TimeGenerated > ago(1d)
| distinct InstanceId_s, MemoryMB_s
| join kind=inner hint.strategy=broadcast (
	WindowsMemoryPerf
) on `$left.InstanceId_s == `$right._ResourceId
| extend MemoryPercentage = todouble(toint(MemoryMB_s) - toint(MemoryAvailableMBs)) / todouble(MemoryMB_s) * 100 
| summarize hint.strategy=shuffle PMemoryPercentage = percentile(MemoryPercentage, memoryPercentileValue) by _ResourceId
| union LinuxMemoryPerf;

let ProcessorPerf = Perf 
| where TimeGenerated > ago(perfInterval) 
| where CounterName == '% Processor Time' and InstanceName == '_Total' 
| summarize hint.strategy=shuffle PCPUPercentage = percentile(CounterValue, cpuPercentileValue) by _ResourceId;

let WindowsNetworkPerf = Perf 
| where TimeGenerated > ago(perfInterval) 
| where CounterName == 'Bytes Total/sec' 
| summarize hint.strategy=shuffle PCounter = percentile(CounterValue, networkPercentileValue) by InstanceName, _ResourceId
| summarize PNetwork = sum(PCounter) by _ResourceId;

let DiskPerf = Perf
| where TimeGenerated > ago(perfInterval) 
| where CounterName in ('Disk Reads/sec', 'Disk Writes/sec', 'Disk Read Bytes/sec', 'Disk Write Bytes/sec') and InstanceName !in ("_Total", "D:", "/mnt/resource", "/mnt")
| summarize hint.strategy=shuffle PCounter = percentile(CounterValue, diskPercentileValue) by bin(TimeGenerated, perfTimeGrain), CounterName, InstanceName, _ResourceId
| summarize SumPCounter = sum(PCounter) by CounterName, TimeGenerated, _ResourceId
| summarize MaxPReadIOPS = maxif(SumPCounter, CounterName == 'Disk Reads/sec'), 
            MaxPWriteIOPS = maxif(SumPCounter, CounterName == 'Disk Writes/sec'), 
            MaxPReadMiBps = (maxif(SumPCounter, CounterName == 'Disk Read Bytes/sec') / 1024 / 1024), 
            MaxPWriteMiBps = (maxif(SumPCounter, CounterName == 'Disk Write Bytes/sec') / 1024 / 1024) by _ResourceId;

$advisorTableName 
| where Category == 'Cost' and todatetime(TimeGenerated) > ago(advisorInterval) 
| join kind=leftouter (
    $vmsTableName 
    | where TimeGenerated > ago(1d) 
    | project InstanceId_s, NicCount_s, DataDiskCount_s, Tags_s
) on InstanceId_s 
| where RecommendationTypeId_g != rightSizeRecommendationId or (RecommendationTypeId_g == rightSizeRecommendationId and toint(NicCount_s) >= 0 and toint(DataDiskCount_s) >= 0)
| join kind=leftouter hint.strategy=broadcast ( MemoryPerf ) on `$left.InstanceId_s == `$right._ResourceId
| join kind=leftouter hint.strategy=broadcast ( ProcessorPerf ) on `$left.InstanceId_s == `$right._ResourceId
| join kind=leftouter hint.strategy=broadcast ( WindowsNetworkPerf ) on `$left.InstanceId_s == `$right._ResourceId
| join kind=leftouter hint.strategy=broadcast ( DiskPerf ) on `$left.InstanceId_s == `$right._ResourceId
| extend MaxPIOPS = MaxPReadIOPS + MaxPWriteIOPS, MaxPMiBps = MaxPReadMiBps + MaxPWriteMiBps
| extend PNetworkMbps = PNetwork * 8 / 1000 / 1000
| summarize by InstanceId_s, InstanceName_s, Description_s, SubscriptionGuid_g, ResourceGroup, Cloud_s, AdditionalInfo_s, RecommendationText_s, ImpactedArea_s, Impact_s, RecommendationTypeId_g, NicCount_s, DataDiskCount_s, PMemoryPercentage, PCPUPercentage, PNetworkMbps, MaxPIOPS, MaxPMiBps, Tags_s            
"@

Write-Output "Getting cost recommendations for $($daysBackwards)d Advisor and $($perfDaysBackwards)d Perf history and a $perfTimeGrain time grain..."

$queryResults = Invoke-AzOperationalInsightsQuery -WorkspaceId $workspaceId -Query $baseQuery -Timespan (New-TimeSpan -Days ([Math]::max($daysBackwards,$perfDaysBackwards))) -Wait 600
$results = [System.Linq.Enumerable]::ToArray($queryResults.Results)

Write-Output "Query finished with $($results.Count) results."

$recommendations = @()
$datetime = (get-date).ToUniversalTime()
$hour = $datetime.Hour
if ($hour -lt 10) {
    $hour = "0" + $hour
}
$min = $datetime.Minute
if ($min -lt 10) {
    $min = "0" + $min
}
$timestamp = $datetime.ToString("yyyy-MM-ddT$($hour):$($min):00.000Z")

Write-Output "Generating confidence score..."

foreach ($result in $results) {  
    $queryInstanceId = $result.InstanceId_s

    $tags = @{}

    if (-not([string]::IsNullOrEmpty($result.Tags_s)))
    {
        $tagPairs = $result.Tags_s.Substring(2, $result.Tags_s.Length - 3).Split(';')
        foreach ($tagPairString in $tagPairs)
        {
            $tagPair = $tagPairString.Split('=')
            $tagName = $tagPair[0].Trim()
            $tagValue = $tagPair[1].Trim()
            $tags[$tagName] = $tagValue
        }
    }
    
    $additionalInfoDictionary = @{ }
    if ($result.AdditionalInfo_s.Length -gt 0) {
        $result.AdditionalInfo_s.Split('{')[1].Split('}')[0].Split(';') | ForEach-Object {
            $key, $value = $_.Trim().Split('=')
            $additionalInfoDictionary[$key] = $value
        }
    }

    $confidenceScore = -1
    $hasCpuRamPerfMetrics = $false

    if ($additionalInfoDictionary.targetSku) {
        $confidenceScore = 5
        $additionalInfoDictionary["SupportsDataDisksCount"] = "true"
        $additionalInfoDictionary["DataDiskCount"] = "$($result.DataDiskCount_s)"
        $additionalInfoDictionary["SupportsNICCount"] = "true"
        $additionalInfoDictionary["NicCount"] = "$($result.NicCount_s)"
        $additionalInfoDictionary["SupportsIOPS"] = "true"
        $additionalInfoDictionary["MetricIOPS"] = "$($result.MaxPIOPS)"
        $additionalInfoDictionary["SupportsMiBps"] = "true"
        $additionalInfoDictionary["MetricMiBps"] = "$($result.MaxPMiBps)"
        $additionalInfoDictionary["BelowCPUThreshold"] = "true"
        $additionalInfoDictionary["MetricCPUPercentage"] = "$($result.PCPUPercentage)"
        $additionalInfoDictionary["BelowMemoryThreshold"] = "true"
        $additionalInfoDictionary["MetricMemoryPercentage"] = "$($result.PMemoryPercentage)"
        $additionalInfoDictionary["BelowNetworkThreshold"] = "true"
        $additionalInfoDictionary["MetricNetworkMbps"] = "$($result.PNetworkMbps)"

        $targetSku = $null
        if ($additionalInfoDictionary.targetSku -ne "Shutdown") {

            $targetSku = $skus | Where-Object { $_.Name -eq $additionalInfoDictionary.targetSku }
            $targetMaxDataDiskCount = [int]($targetSku.Capabilities | Where-Object { $_.Name -eq 'MaxDataDiskCount' }).Value
            if ($targetMaxDataDiskCount -gt 0) {
                if (-not([string]::isNullOrEmpty($result.DataDiskCount_s))) {
                    if ([int]$result.DataDiskCount_s -gt $targetMaxDataDiskCount) {
                        $confidenceScore = 1
                        $additionalInfoDictionary["SupportsDataDisksCount"] = "false:needs$($result.DataDiskCount_s)-max$targetMaxDataDiskCount"
                    }
                }
                else {
                    $confidenceScore -= 1
                    $additionalInfoDictionary["SupportsDataDisksCount"] = "unknown:max$targetMaxDataDiskCount"
                }
            }
            else {
                $confidenceScore -= 1
                $additionalInfoDictionary["SupportsDataDisksCount"] = "unknown:needs$($result.DataDiskCount_s)"
            }
            $targetMaxNICCount = [int]($targetSku.Capabilities | Where-Object { $_.Name -eq 'MaxNetworkInterfaces' }).Value
            if ($targetMaxNICCount -gt 0) {
                if (-not([string]::isNullOrEmpty($result.NicCount_s))) {
                    if ([int]$result.NicCount_s -gt $targetMaxNICCount) {
                        $confidenceScore = 1
                        $additionalInfoDictionary["SupportsNICCount"] = "false:needs$($result.NicCount_s)-max$targetMaxNICCount"
                    }
                }
                else {
                    $confidenceScore -= 1
                    $additionalInfoDictionary["SupportsNICCount"] = "unknown:max$targetMaxNICCount"
                }
            }
            else {
                $confidenceScore -= 1
                $additionalInfoDictionary["SupportsNICCount"] = "unknown:needs$($result.NicCount_s)"
            }
            $targetUncachedDiskIOPS = [int]($targetSku.Capabilities | Where-Object { $_.Name -eq 'UncachedDiskIOPS' }).Value
            if ($targetUncachedDiskIOPS -gt 0) {
                if (-not([string]::isNullOrEmpty($result.MaxPIOPS))) {
                    if ([double]$result.MaxPIOPS -ge $targetUncachedDiskIOPS) {
                        $confidenceScore -= 1
                        $additionalInfoDictionary["SupportsIOPS"] = "false:needs$($result.MaxPIOPS)-max$targetUncachedDiskIOPS"            
                    }
                }
                else {
                    $confidenceScore -= 0.5
                    $additionalInfoDictionary["SupportsIOPS"] = "unknown:max$targetUncachedDiskIOPS"
                }
            }
            else {
                $confidenceScore -= 1
                $additionalInfoDictionary["SupportsIOPS"] = "unknown:needs$($result.MaxPIOPS)" 
            }
            $targetUncachedDiskMiBps = [int]($targetSku.Capabilities | Where-Object { $_.Name -eq 'UncachedDiskBytesPerSecond' }).Value / 1024 / 1024
            if ($targetUncachedDiskMiBps -gt 0) { 
                if (-not([string]::isNullOrEmpty($result.MaxPMiBps))) {
                    if ([double]$result.MaxPMiBps -ge $targetUncachedDiskMiBps) {
                        $confidenceScore -= 1    
                        $additionalInfoDictionary["SupportsMiBps"] = "false:needs$($result.MaxPMiBps)-max$targetUncachedDiskMiBps"                    
                    }
                }
                else {
                    $confidenceScore -= 0.5
                    $additionalInfoDictionary["SupportsMiBps"] = "unknown:max$targetUncachedDiskMiBps"
                }
            }
            else {
                $additionalInfoDictionary["SupportsMiBps"] = "unknown:needs$($result.MaxPMiBps)"
            }
        }

        $cpuThreshold = $cpuPercentageThreshold
        $memoryThreshold = $memoryPercentageThreshold
        $networkThreshold = $networkMpbsThreshold
        if ($additionalInfoDictionary.targetSku -eq "Shutdown") {
            $cpuThreshold = $cpuPercentageShutdownThreshold
            $memoryThreshold = $memoryPercentageShutdownThreshold
            $networkThreshold = $networkMpbsShutdownThreshold
        }

        if (-not([string]::isNullOrEmpty($result.PCPUPercentage))) {
            if ([double]$result.PCPUPercentage -ge [double]$cpuThreshold) {
                $confidenceScore -= 0.5    
                $additionalInfoDictionary["BelowCPUThreshold"] = "false:needs$($result.PCPUPercentage)-max$cpuThreshold"                    
            }
            $hasCpuRamPerfMetrics = $true
        }
        else {
            $confidenceScore -= 0.5
            $additionalInfoDictionary["BelowCPUThreshold"] = "unknown:max$cpuThreshold"
        }
        if (-not([string]::isNullOrEmpty($result.PMemoryPercentage))) {
            if ([double]$result.PMemoryPercentage -ge [double]$memoryThreshold) {
                $confidenceScore -= 0.5    
                $additionalInfoDictionary["BelowMemoryThreshold"] = "false:needs$($result.PMemoryPercentage)-max$memoryThreshold"                    
            }
            $hasCpuRamPerfMetrics = $true
        }
        else {
            $confidenceScore -= 0.5
            $additionalInfoDictionary["BelowMemoryThreshold"] = "unknown:max$memoryThreshold"
        }
        if (-not([string]::isNullOrEmpty($result.PNetworkMbps))) {
            if ([double]$result.PNetworkMbps -ge [double]$networkThreshold) {
                $confidenceScore -= 0.1    
                $additionalInfoDictionary["BelowNetworkThreshold"] = "false:needs$($result.PNetworkMbps)-max$networkThreshold"                    
            }
        }
        else {
            $confidenceScore -= 0.1
            $additionalInfoDictionary["BelowNetworkThreshold"] = "unknown:max$networkThreshold"
        }

        $confidenceScore = [Math]::max(0.0, $confidenceScore)
    }

    $queryInstanceId = $result.InstanceId_s
    if (-not($hasCpuRamPerfMetrics))
    {
        $detailsURL = "https://portal.azure.com/#@$workspaceTenantId/resource/$queryInstanceId/overview"
    }
    else
    {
        $queryText = @"
        let perfInterval = $($perfDaysBackwards)d;
        let armId = tolower(`'$queryInstanceId`');
        let gInt = $perfTimeGrain;
        let LinuxMemoryPerf = Perf 
        | where TimeGenerated > ago(perfInterval) 
        | where CounterName == '% Used Memory' and _ResourceId =~ armId
        | project TimeGenerated, MemoryPercentage = CounterValue; 
        let WindowsMemoryPerf = Perf 
        | where TimeGenerated > ago(perfInterval) 
        | where CounterName == 'Available MBytes' and _ResourceId =~ armId
        | extend MemoryAvailableMBs = CounterValue, InstanceId = tolower(_ResourceId) 
        | project TimeGenerated, MemoryAvailableMBs, InstanceId;
        let MemoryPerf = WindowsMemoryPerf
        | join kind=inner (
            $vmsTableName 
            | where TimeGenerated > ago(1d)
            | extend InstanceId = tolower(InstanceId_s)
            | distinct InstanceId, MemoryMB_s
        ) on InstanceId
        | extend MemoryPercentage = todouble(toint(MemoryMB_s) - toint(MemoryAvailableMBs)) / todouble(MemoryMB_s) * 100 
        | project TimeGenerated, MemoryPercentage
        | union LinuxMemoryPerf
        | summarize P$($memoryPercentile)MemoryPercentage = percentile(MemoryPercentage, $memoryPercentile) by bin(TimeGenerated, gInt);
        let ProcessorPerf = Perf 
        | where TimeGenerated > ago(perfInterval) 
        | where CounterName == '% Processor Time' and InstanceName == '_Total' and _ResourceId =~ armId
        | summarize P$($cpuPercentile)CPUPercentage = percentile(CounterValue, $cpuPercentile) by bin(TimeGenerated, gInt);
        MemoryPerf
        | union ProcessorPerf
        | render timechart
"@
    
        $encodedQuery = [System.Uri]::EscapeDataString($queryText)
        $detailsQueryStart = $datetime.AddDays(-30).ToString("yyyy-MM-dd")
        $detailsQueryEnd = $datetime.AddDays(1).ToString("yyyy-MM-dd")
        $detailsURL = "https://portal.azure.com#@$workspaceTenantId/blade/Microsoft_Azure_Monitoring_Logs/LogsBlade/resourceId/%2Fsubscriptions%2F$workspaceSubscriptionId%2Fresourcegroups%2F$workspaceRG%2Fproviders%2Fmicrosoft.operationalinsights%2Fworkspaces%2F$workspaceName/source/LogsBlade.AnalyticsShareLinkToQuery/query/$encodedQuery/timespan/$($detailsQueryStart)T00%3A00%3A00.000Z%2F$($detailsQueryEnd)T00%3A00%3A00.000Z"            
    }

    $recommendation = New-Object PSObject -Property @{
        Timestamp                   = $timestamp
        Cloud                       = $result.Cloud_s
        Category                    = "Cost"
        ImpactedArea                = $result.ImpactedArea_s
        Impact                      = $result.Impact_s
        RecommendationType          = "Saving"
        RecommendationSubType       = "AdvisorCost"
        RecommendationSubTypeId     = $result.RecommendationTypeId_g
        RecommendationDescription   = $result.Description_s
        RecommendationAction        = $result.RecommendationText_s
        InstanceId                  = $result.InstanceId_s
        InstanceName                = $result.InstanceName_s
        AdditionalInfo              = $additionalInfoDictionary
        ResourceGroup               = $result.ResourceGroup
        SubscriptionGuid            = $result.SubscriptionGuid_g
        ConfidenceScore             = $confidenceScore
        Tags                        = $tags
        DetailsURL                  = $detailsURL
    }

    $recommendations += $recommendation
}

Write-Output "Exporting final results as a JSON file..."

$fileDate = $datetime.ToString("yyyyMMdd")
$jsonExportPath = "advisor-cost-augmented-$fileDate.json"
$recommendations | ConvertTo-Json | Out-File $jsonExportPath

Write-Output "Uploading $jsonExportPath to blob storage..."

$jsonBlobName = $jsonExportPath
$jsonProperties = @{"ContentType" = "application/json" };
Set-AzStorageBlobContent -File $jsonExportPath -Container $storageAccountSinkContainer -Properties $jsonProperties -Blob $jsonBlobName -Context $sa.Context -Force

Write-Output "DONE"