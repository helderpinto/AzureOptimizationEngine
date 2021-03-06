For the VMs that have been deallocated for a long time, the default deallocated interval is 30 days, but you can change this in the `AzureOptimization_RecommendationLongDeallocatedVmsIntervalDays` variable.

If you are not interested in getting recommendations for all the non-Cost Advisor pillars, you can specify a pillar-level filter in the `AzureOptimization_AdvisorFilter` variable (comma-separated list with at least one of the following: `HighAvailability,Security,Performance,OperationalExcellence`).

