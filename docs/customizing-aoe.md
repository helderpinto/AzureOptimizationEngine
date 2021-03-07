# Customizing the Azure Optimization Engine

There are many customization options available in AOE, in the form of Azure Automation variables. The list below is a highlight of the most relevant configuration variables. To access them, go to the Automation Account _Shared Resources - Variables_ menu option.

* `AzureOptimization_AdvisorFilter` - If you are not interested in getting recommendations for all the non-Cost Advisor pillars, you can specify a pillar-level filter (comma-separated list with at least one of the following: `HighAvailability,Security,Performance,OperationalExcellence`). Defaults to all pillars.
* AzureOptimization_AuthenticationOption
* AzureOptimization_CloudEnvironment
* AzureOptimization_ConsumptionOffsetDays
* AzureOptimization_LogAnalyticsChunkSize
* AzureOptimization_LogAnalyticsLogPrefix
* AzureOptimization_PerfPercentileCpu
* AzureOptimization_PerfPercentileDisk
* AzureOptimization_PerfPercentileMemory
* AzureOptimization_PerfPercentileNetwork
* AzureOptimization_PerfThresholdCpuPercentage
* AzureOptimization_PerfThresholdCpuShutdownPercentage
* AzureOptimization_PerfThresholdMemoryPercentage
* AzureOptimization_PerfThresholdMemoryShutdownPercentage
* AzureOptimization_PerfThresholdNetworkMbps
* AzureOptimization_PerfThresholdNetworkShutdownMbps
* AzureOptimization_RecommendAdvisorPeriodInDays
* AzureOptimization_RecommendationAADMaxCredValidityYears
* AzureOptimization_RecommendationAADMinCredValidityDays
* AzureOptimization_RecommendationAdvisorCostRightSizeId
* `AzureOptimization_RecommendationLongDeallocatedVmsIntervalDays` - The number of consecutive days a VM has been deallocated before being recommended for deletion (_Virtual Machine has been deallocated for long with disks still incurring costs_). Defaults to 30.
* AzureOptimization_ReferenceRegion
* AzureOptimization_RemediateRightSizeMinFitScore
* AzureOptimization_RemediateRightSizeMinWeeksInARow
* AzureOptimization_RightSizeAdditionalPerfWorkspaces
* AzureOptimization_SQLServerInsertSize
* AzureOptimization_StorageBlobsPageSize

