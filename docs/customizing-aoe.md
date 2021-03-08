# Customizing the Azure Optimization Engine

There are many customization options available in AOE, in the form of Azure Automation variables. The list below is a highlight of the most relevant configuration variables. To access them, go to the Automation Account _Shared Resources - Variables_ menu option.

* `AzureOptimization_AdvisorFilter` - If you are not interested in getting recommendations for all the non-Cost Advisor pillars, you can specify a pillar-level filter (comma-separated list with at least one of the following: `HighAvailability,Security,Performance,OperationalExcellence`). Defaults to all pillars.
* `AzureOptimization_AuthenticationOption` - The default authentication method for Automation Runbooks is `RunAsAccount`. But you can change to `ManagedIdentity` if you're using a Hybrid Worker in an Azure VM.
* `AzureOptimization_ConsumptionOffsetDays` - The Azure Consumption data collection runbook queries each day for billing events that occurred 7 days ago (default). You can change to a closer offset, but bear in mind that some subscription types (e.g., MSDN) to not support a lower value.
* `AzureOptimization_PerfPercentileCpu` - The default percentile for CPU metrics aggregations is 99. The lower the percentile, the less conservative will be VM right-size fit score algorithm.
* `AzureOptimization_PerfPercentileDisk` - The default percentile for disk IO/throughput metrics aggregations is 99. The lower the percentile, the less conservative will be VM right-size fit score algorithm.
* `AzureOptimization_PerfPercentileMemory` - The default percentile for memory metrics aggregations is 99. The lower the percentile, the less conservative will be VM right-size fit score algorithm.
* `AzureOptimization_PerfPercentileNetwork` - The default percentile for network metrics aggregations is 99. The lower the percentile, the less conservative will be VM right-size fit score algorithm.
* `AzureOptimization_PerfThresholdCpuPercentage` - The CPU threshold (in % Processor Time) above which the VM right-size fit score will decrease.
* `AzureOptimization_PerfThresholdCpuShutdownPercentage` - The CPU threshold (in % Processor Time) above which the VM right-size fit score will decrease (_shutdown recommendations only_).
* `AzureOptimization_PerfThresholdMemoryPercentage` - The memory threshold (in % Used Memory) above which the VM right-size fit score will decrease.
* `AzureOptimization_PerfThresholdMemoryShutdownPercentage` - The memory threshold (in % Used Memory) above which the VM right-size fit score will decrease (_shutdown recommendations only_).
* `AzureOptimization_PerfThresholdNetworkMbps` - The network threshold (in Total Mbps) above which the VM right-size fit score will decrease.
* `AzureOptimization_PerfThresholdNetworkShutdownMbps` - The network threshold (in Total Mbps) above which the VM right-size fit score will decrease (_shutdown recommendations only_).
* `AzureOptimization_RecommendAdvisorPeriodInDays` - The interval in days to look for Advisor recommendations in the Log Analytics repository - the default is 7, as Advisor recommendations are collected once a week.
* `AzureOptimization_RecommendationAADMaxCredValidityYears` - The maximum number of years for a Service Principal credential/certificate validity - any validity above this interval will generate a Security recommendation. Defaults to 2.
* `AzureOptimization_RecommendationAADMinCredValidityDays` - The minimum number of days for a Service Principal credential/certificate before it expires - any validity below this interval will generate an Operational Excellence recommendation. Defaults to 30.
* `AzureOptimization_RecommendationLongDeallocatedVmsIntervalDays` - The number of consecutive days a VM has been deallocated before being recommended for deletion (_Virtual Machine has been deallocated for long with disks still incurring costs_). Defaults to 30.
* `AzureOptimization_ReferenceRegion` - The Azure region used as a reference for getting the list of available SKUs (defaults to `westeurope`).
* `AzureOptimization_RemediateRightSizeMinFitScore` - The minimum fit score a VM right-size recommendation must have for the remediation to occur.
* `AzureOptimization_RemediateRightSizeMinWeeksInARow` - The minimum number of weeks in a row a VM right-size recommendation must have been done for the remediation to occur.
* `AzureOptimization_RightSizeAdditionalPerfWorkspaces` - A comma-separated list of additional Log Analytics workspace IDs where to look for VM metrics (see [Configuring Log Analytics workspaces](./docs/configuring-workspaces.md)).

