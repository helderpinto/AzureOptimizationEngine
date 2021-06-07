param projectLocation string

@description('The base URI where artifacts required by this template are located')
param artifactsLocation string = deployment().properties.templateLink.uri

@description('The sasToken required to access _artifactsLocation. When the template is deployed using the accompanying scripts, a sasToken will be grabbed from parameters.')
@secure()
param artifactsLocationSasToken string = ''
param storageAccountName string
param automationAccountName string
param sqlServerName string
param sqlDatabaseName string = 'azureoptimization'
param logAnalyticsReuse bool
param logAnalyticsWorkspaceName string
param logAnalyticsWorkspaceRG string
param logAnalyticsRetentionDays int = 120
param sqlBackupRetentionDays int = 7
param sqlAdminLogin string

@secure()
param sqlAdminPassword string
param cloudEnvironment string = 'AzureCloud'
param authenticationOption string = 'RunAsAccount'

@description('Base time for all automation runbook schedules.')
param baseTime string = utcNow('u')

@description('GUID for the ARG Disk Export job schedule creation - create a unique before deploy')
param argDiskExportJobId string = newGuid()

@description('GUID for the ARG VHD Export job schedule creation - create a unique before deploy')
param argVhdExportJobId string = newGuid()

@description('GUID for the ARG VM Export job schedule creation - create a unique before deploy')
param argVmExportJobId string = newGuid()

@description('GUID for the ARG Availability Set Export job schedule creation - create a unique before deploy')
param argAvailSetExportJobId string = newGuid()

@description('GUID for the Advisor Export job schedule creation - create a unique before deploy')
param advisorExportJobId string = newGuid()

@description('GUID for the Consumption Export job schedule creation - create a unique before deploy')
param consumptionExportJobId string = newGuid()

@description('GUID for the Azure AD Objects Export job schedule creation - create a unique before deploy')
param aadObjectsExportJobId string = newGuid()

@description('GUID for the Load Balancers Export job schedule creation - create a unique before deploy')
param argLoadBalancersExportJobId string = newGuid()

@description('GUID for the Application Gateways Export job schedule creation - create a unique before deploy')
param argAppGWsExportJobId string = newGuid()

@description('GUID for the RBAC Export job schedule creation - create a unique before deploy')
param rbacExportJobId string = newGuid()

@description('GUID for the Resource Containers Export job schedule creation - create a unique before deploy')
param argResContainersExportJobId string = newGuid()

@description('GUID for the ARG Disk Ingest job schedule creation - create a unique before deploy')
param argDiskIngestJobId string = newGuid()

@description('GUID for the ARG VHD Ingest job schedule creation - create a unique before deploy')
param argVhdIngestJobId string = newGuid()

@description('GUID for the ARG VM Ingest job schedule creation - create a unique before deploy')
param argVmIngestJobId string = newGuid()

@description('GUID for the ARG Availability Set Ingest job schedule creation - create a unique before deploy')
param argAvailSetIngestJobId string = newGuid()

@description('GUID for the Advisor Ingest job schedule creation - create a unique before deploy')
param advisorIngestJobId string = newGuid()

@description('GUID for the Remediation Logs Ingest job schedule creation - create a unique before deploy')
param remediationLogsIngestJobId string = newGuid()

@description('GUID for the Consumption Ingest job schedule creation - create a unique before deploy')
param consumptionIngestJobId string = newGuid()

@description('GUID for the AAD Objects Ingest job schedule creation - create a unique before deploy')
param aadObjectsIngestJobId string = newGuid()

@description('GUID for the Load Balancers Ingest job schedule creation - create a unique before deploy')
param argLoadBalancersIngestJobId string = newGuid()

@description('GUID for the Application Gateways Ingest job schedule creation - create a unique before deploy')
param argAppGWsIngestJobId string = newGuid()

@description('GUID for the Resource Containers Ingest job schedule creation - create a unique before deploy')
param argResContainersIngestJobId string = newGuid()

@description('GUID for the RBAC Ingest job schedule creation - create a unique before deploy')
param rbacIngestJobId string = newGuid()

@description('GUID for the Unattached Disks Recommendation Generation job schedule creation - create a unique before deploy')
param unattachedDisksRecommendationJobId string = newGuid()

@description('GUID for the Augmented Advisor Cost Recommendation Generation job schedule creation - create a unique before deploy')
param advisorCostAugmentedRecommendationJobId string = newGuid()

@description('GUID for the Advisor General Recommendations Generation job schedule creation - create a unique before deploy')
param advisorAsIsRecommendationJobId string = newGuid()

@description('GUID for the Unmanaged Disks Recommendation Generation job schedule creation - create a unique before deploy')
param unmanagedDisksRecommendationJobId string = newGuid()

@description('GUID for the Availability Sets with Low Fault Domains Recommendation Generation job schedule creation - create a unique before deploy')
param availSetsLowFaultDomainRecommendationJobId string = newGuid()

@description('GUID for the Availability Sets with Low Update Domains Recommendation Generation job schedule creation - create a unique before deploy')
param availSetsLowUpdateDomainRecommendationJobId string = newGuid()

@description('GUID for the Availability Sets with VMs Sharing Storage Recommendation Generation job schedule creation - create a unique before deploy')
param availSetsSharingStorageRecommendationJobId string = newGuid()

@description('GUID for the Long Deallocated VMs Recommendation Generation job schedule creation - create a unique before deploy')
param longDeallocatedVmsRecommendationJobId string = newGuid()

@description('GUID for the Storage Accounts with Multiple VMs Recommendation Generation job schedule creation - create a unique before deploy')
param storageAccountsMultipleVmsRecommendationJobId string = newGuid()

@description('GUID for the VMs without Availability Set Recommendation Generation job schedule creation - create a unique before deploy')
param vmsNoAvailSetRecommendationJobId string = newGuid()

@description('GUID for the VMs single in Availability Set Recommendation Generation job schedule creation - create a unique before deploy')
param vmsSingleInAvailSetRecommendationJobId string = newGuid()

@description('GUID for the VMs with Disks in Multiple Storage Accounts Recommendation Generation job schedule creation - create a unique before deploy')
param vmsDisksMultipleStorageRecommendationJobId string = newGuid()

@description('GUID for the AAD Objects with Expiring Credentials Recommendation Generation job schedule creation - create a unique before deploy')
param aadExpiringCredsRecommendationJobId string = newGuid()

@description('GUID for the Unused Load Balancers Recommendation Generation job schedule creation - create a unique before deploy')
param unusedLoadBalancersRecommendationJobId string = newGuid()

@description('GUID for the Unused Application Gateways Recommendation Generation job schedule creation - create a unique before deploy')
param unusedAppGWsRecommendationJobId string = newGuid()

@description('GUID for the Recommendations Ingest job schedule creation - create a unique before deploy')
param recommendationsIngestJobId string = newGuid()

var advisorContainerName = 'advisorexports'
var argVmContainerName = 'argvmexports'
var argDiskContainerName = 'argdiskexports'
var argVhdContainerName = 'argvhdexports'
var argAvailSetContainerName = 'argavailsetexports'
var consumptionContainerName = 'consumptionexports'
var recommendationsContainerName = 'recommendationsexports'
var aadObjectsContainerName = 'aadobjectsexports'
var argLBsContainerName = 'arglbexports'
var argAppGWsContainerName = 'argappgwexports'
var argResContainersContainerName = 'argrescontainersexports'
var rbacContainerName = 'rbacexports'
var remediationLogsContainerName = 'remediationlogs'
var advisorExportsRunbookName = 'Export-AdvisorRecommendationsToBlobStorage'
var argVmExportsRunbookName = 'Export-ARGVirtualMachinesPropertiesToBlobStorage'
var argDisksExportsRunbookName = 'Export-ARGManagedDisksPropertiesToBlobStorage'
var argVhdExportsRunbookName = 'Export-ARGUnmanagedDisksPropertiesToBlobStorage'
var argAvailSetExportsRunbookName = 'Export-ARGAvailabilitySetPropertiesToBlobStorage'
var consumptionExportsRunbookName = 'Export-ConsumptionToBlobStorage'
var aadObjectsExportsRunbookName = 'Export-AADObjectsToBlobStorage'
var argLoadBalancersExportsRunbookName = 'Export-ARGLoadBalancerPropertiesToBlobStorage'
var argAppGWsExportsRunbookName = 'Export-ARGAppGatewayPropertiesToBlobStorage'
var argResContainersExportsRunbookName = 'Export-ARGResourceContainersPropertiesToBlobStorage'
var rbacExportsRunbookName = 'Export-RBACAssignmentsToBlobStorage'
var csvIngestRunbookName = 'Ingest-OptimizationCSVExportsToLogAnalytics'
var unattachedDisksRecommendationsRunbookName = 'Recommend-UnattachedDisksToBlobStorage'
var advisorCostAugmentedRecommendationsRunbookName = 'Recommend-AdvisorCostAugmentedToBlobStorage'
var advisorAsIsRecommendationsRunbookName = 'Recommend-AdvisorAsIsToBlobStorage'
var unmanagedDisksRecommendationsRunbookName = 'Recommend-VMsWithUnmanagedDisksToBlobStorage'
var availSetsLowFaultDomainRecommendationsRunbookName = 'Recommend-AvailSetsWithLowFaultDomainCountToBlobStorage'
var availSetsLowUpdateDomainRecommendationsRunbookName = 'Recommend-AvailSetsWithLowUpdateDomainCountToBlobStorage'
var availSetsSharingStorageRecommendationsRunbookName = 'Recommend-AvailSetsWithVMsSharingStorageAccountsToBlobStorage'
var longDeallocatedVmsRecommendationsRunbookName = 'Recommend-LongDeallocatedVmsToBlobStorage'
var storageAccountsMultipleVmsRecommendationsRunbookName = 'Recommend-StorageAccountsWithMultipleVMsToBlobStorage'
var vmsNoAvailSetRecommendationsRunbookName = 'Recommend-VMsNoAvailSetToBlobStorage'
var vmsSingleInAvailSetRecommendationsRunbookName = 'Recommend-VMsSingleInAvailSetToBlobStorage'
var vmsDisksMultipleStorageRecommendationsRunbookName = 'Recommend-VMsWithDisksMultipleStorageAccountsToBlobStorage'
var aadExpiringCredsRecommendationsRunbookName = 'Recommend-AADExpiringCredentialsToBlobStorage'
var unusedLBsRecommendationsRunbookName = 'Recommend-UnusedLoadBalancersToBlobStorage'
var unusedAppGWsRecommendationsRunbookName = 'Recommend-UnusedAppGWsToBlobStorage'
var recommendationsIngestRunbookName = 'Ingest-RecommendationsToSQLServer'
var advisorRightSizeFilteredRemediationRunbookName = 'Remediate-AdvisorRightSizeFiltered'
var advisorExportsScheduleName = 'AzureOptimization_ExportAdvisorWeekly'
var argExportsScheduleName = 'AzureOptimization_ExportARGDaily'
var consumptionExportsScheduleName = 'AzureOptimization_ExportConsumptionDaily'
var aadObjectsExportsScheduleName = 'AzureOptimization_ExportAADObjectsDaily'
var argDiskIngestScheduleName = 'AzureOptimization_IngestARGDisksDaily'
var argVhdIngestScheduleName = 'AzureOptimization_IngestARGVHDsDaily'
var argVmIngestScheduleName = 'AzureOptimization_IngestARGVMsDaily'
var argAvailSetIngestScheduleName = 'AzureOptimization_IngestARGAvailSetsDaily'
var remediationLogsIngestScheduleName = 'AzureOptimization_IngestRemediationLogsDaily'
var consumptionIngestScheduleName = 'AzureOptimization_IngestConsumptionDaily'
var aadObjectsIngestScheduleName = 'AzureOptimization_IngestAADObjectsDaily'
var argLBsIngestScheduleName = 'AzureOptimization_IngestARGLoadBalancersDaily'
var argAppGWsIngestScheduleName = 'AzureOptimization_IngestARGAppGWsDaily'
var argResContainersIngestScheduleName = 'AzureOptimization_IngestARGResourceContainersDaily'
var rbacIngestScheduleName = 'AzureOptimization_IngestRBACAssignmentsDaily'
var advisorIngestScheduleName = 'AzureOptimization_IngestAdvisorWeekly'
var recommendationsScheduleName = 'AzureOptimization_RecommendationsWeekly'
var recommendationsIngestScheduleName = 'AzureOptimization_IngestRecommendationsWeekly'
var apiVersions = {
  operationalInsights: '2020-08-01'
  automation: '2018-06-30'
  storage: '2019-06-01'
  sql: '2019-06-01-preview'
}
var Az_Accounts = {
  name: 'Az.Accounts'
  url: 'https://www.powershellgallery.com/api/v2/package/Az.Accounts/2.2.4'
}
var psModules = [
  {
    name: 'Az.Advisor'
    url: 'https://www.powershellgallery.com/api/v2/package/Az.Advisor/1.1.1'
  }
  {
    name: 'Az.Billing'
    url: 'https://www.powershellgallery.com/api/v2/package/Az.Billing/2.0.0'
  }
  {
    name: 'Az.Compute'
    url: 'https://www.powershellgallery.com/api/v2/package/Az.Compute/4.8.0'
  }
  {
    name: 'Az.OperationalInsights'
    url: 'https://www.powershellgallery.com/api/v2/package/Az.OperationalInsights/2.3.0'
  }
  {
    name: 'Az.ResourceGraph'
    url: 'https://www.powershellgallery.com/api/v2/package/Az.ResourceGraph/0.8.0'
  }
  {
    name: 'Az.Storage'
    url: 'https://www.powershellgallery.com/api/v2/package/Az.Storage/3.2.1'
  }
  {
    name: 'Az.Resources'
    url: 'https://www.powershellgallery.com/api/v2/package/Az.Resources/3.2.0'
  }
  {
    name: 'Az.Monitor'
    url: 'https://www.powershellgallery.com/api/v2/package/Az.Monitor/2.4.0'
  }
  {
    name: 'AzureADPreview'
    url: 'https://www.powershellgallery.com/api/v2/package/AzureADPreview/2.0.2.129'
  }
]
var runbooks = [
  {
    name: advisorExportsRunbookName
    version: '1.3.0.0'
    description: 'Exports Azure Advisor recommendations to Blob Storage using the Advisor API'
    type: 'PowerShell'
    scriptUri: uri(artifactsLocation, 'runbooks/data-collection/${advisorExportsRunbookName}.ps1${artifactsLocationSasToken}')
  }
  {
    name: argDisksExportsRunbookName
    version: '1.3.0.0'
    description: 'Exports Managed Disks properties to Blob Storage using Azure Resource Graph'
    type: 'PowerShell'
    scriptUri: uri(artifactsLocation, 'runbooks/data-collection/${argDisksExportsRunbookName}.ps1${artifactsLocationSasToken}')
  }
  {
    name: argVhdExportsRunbookName
    version: '1.1.0.0'
    description: 'Exports Unmanaged Disks (owned by a VM) properties to Blob Storage using Azure Resource Graph'
    type: 'PowerShell'
    scriptUri: uri(artifactsLocation, 'runbooks/data-collection/${argVhdExportsRunbookName}.ps1${artifactsLocationSasToken}')
  }
  {
    name: argVmExportsRunbookName
    version: '1.4.0.0'
    description: 'Exports Virtual Machine properties to Blob Storage using Azure Resource Graph'
    type: 'PowerShell'
    scriptUri: uri(artifactsLocation, 'runbooks/data-collection/${argVmExportsRunbookName}.ps1${artifactsLocationSasToken}')
  }
  {
    name: argAvailSetExportsRunbookName
    version: '1.1.0.0'
    description: 'Exports Availability Set properties to Blob Storage using Azure Resource Graph'
    type: 'PowerShell'
    scriptUri: uri(artifactsLocation, 'runbooks/data-collection/${argAvailSetExportsRunbookName}.ps1${artifactsLocationSasToken}')
  }
  {
    name: consumptionExportsRunbookName
    version: '1.1.0.0'
    description: 'Exports Azure Consumption events to Blob Storage using Azure Consumption API'
    type: 'PowerShell'
    scriptUri: uri(artifactsLocation, 'runbooks/data-collection/${consumptionExportsRunbookName}.ps1${artifactsLocationSasToken}')
  }
  {
    name: aadObjectsExportsRunbookName
    version: '1.1.1.0'
    description: 'Exports Azure AAD Objects to Blob Storage using Azure ARM API'
    type: 'PowerShell'
    scriptUri: uri(artifactsLocation, 'runbooks/data-collection/${aadObjectsExportsRunbookName}.ps1${artifactsLocationSasToken}')
  }
  {
    name: argLoadBalancersExportsRunbookName
    version: '1.1.0.0'
    description: 'Exports Load Balancer properties to Blob Storage using Azure Resource Graph'
    type: 'PowerShell'
    scriptUri: uri(artifactsLocation, 'runbooks/data-collection/${argLoadBalancersExportsRunbookName}.ps1${artifactsLocationSasToken}')
  }
  {
    name: argAppGWsExportsRunbookName
    version: '1.1.0.0'
    description: 'Exports Application Gateway properties to Blob Storage using Azure Resource Graph'
    type: 'PowerShell'
    scriptUri: uri(artifactsLocation, 'runbooks/data-collection/${argAppGWsExportsRunbookName}.ps1${artifactsLocationSasToken}')
  }
  {
    name: argResContainersExportsRunbookName
    version: '1.0.0.0'
    description: 'Exports Resource Containers properties to Blob Storage using Azure Resource Graph'
    type: 'PowerShell'
    scriptUri: uri(artifactsLocation, 'runbooks/data-collection/${argResContainersExportsRunbookName}.ps1${artifactsLocationSasToken}')
  }
  {
    name: rbacExportsRunbookName
    version: '1.0.0.0'
    description: 'Exports RBAC assignments to Blob Storage using ARM and Azure AD'
    type: 'PowerShell'
    scriptUri: uri(artifactsLocation, 'runbooks/data-collection/${rbacExportsRunbookName}.ps1${artifactsLocationSasToken}')
  }
  {
    name: csvIngestRunbookName
    version: '1.4.3.0'
    description: 'Ingests CSV blobs as custom logs to Log Analytics'
    type: 'PowerShell'
    scriptUri: uri(artifactsLocation, 'runbooks/data-collection/${csvIngestRunbookName}.ps1${artifactsLocationSasToken}')
  }
  {
    name: unattachedDisksRecommendationsRunbookName
    version: '2.4.1.0'
    description: 'Generates unattached disks recommendations'
    type: 'PowerShell'
    scriptUri: uri(artifactsLocation, 'runbooks/recommendations/${unattachedDisksRecommendationsRunbookName}.ps1${artifactsLocationSasToken}')
  }
  {
    name: advisorCostAugmentedRecommendationsRunbookName
    version: '2.8.1.0'
    description: 'Generates augmented Advisor Cost recommendations'
    type: 'PowerShell'
    scriptUri: uri(artifactsLocation, 'runbooks/recommendations/${advisorCostAugmentedRecommendationsRunbookName}.ps1${artifactsLocationSasToken}')
  }
  {
    name: advisorAsIsRecommendationsRunbookName
    version: '1.5.1.0'
    description: 'Generates all types of Advisor recommendations'
    type: 'PowerShell'
    scriptUri: uri(artifactsLocation, 'runbooks/recommendations/${advisorAsIsRecommendationsRunbookName}.ps1${artifactsLocationSasToken}')
  }
  {
    name: unmanagedDisksRecommendationsRunbookName
    version: '1.5.1.0'
    description: 'Generates unmanaged disks recommendations'
    type: 'PowerShell'
    scriptUri: uri(artifactsLocation, 'runbooks/recommendations/${unmanagedDisksRecommendationsRunbookName}.ps1${artifactsLocationSasToken}')
  }
  {
    name: availSetsLowFaultDomainRecommendationsRunbookName
    version: '1.2.1.0'
    description: 'Generates low fault domain Availability Set recommendations'
    type: 'PowerShell'
    scriptUri: uri(artifactsLocation, 'runbooks/recommendations/${availSetsLowFaultDomainRecommendationsRunbookName}.ps1${artifactsLocationSasToken}')
  }
  {
    name: availSetsLowUpdateDomainRecommendationsRunbookName
    version: '1.2.1.0'
    description: 'Generates low update domain Availability Set recommendations'
    type: 'PowerShell'
    scriptUri: uri(artifactsLocation, 'runbooks/recommendations/${availSetsLowUpdateDomainRecommendationsRunbookName}.ps1${artifactsLocationSasToken}')
  }
  {
    name: availSetsSharingStorageRecommendationsRunbookName
    version: '1.2.1.0'
    description: 'Generates Availability Set VMs sharing storage recommendations'
    type: 'PowerShell'
    scriptUri: uri(artifactsLocation, 'runbooks/recommendations/${availSetsSharingStorageRecommendationsRunbookName}.ps1${artifactsLocationSasToken}')
  }
  {
    name: longDeallocatedVmsRecommendationsRunbookName
    version: '1.2.1.0'
    description: 'Generates long deallocated VMs recommendations'
    type: 'PowerShell'
    scriptUri: uri(artifactsLocation, 'runbooks/recommendations/${longDeallocatedVmsRecommendationsRunbookName}.ps1${artifactsLocationSasToken}')
  }
  {
    name: storageAccountsMultipleVmsRecommendationsRunbookName
    version: '1.2.1.0'
    description: 'Generates storage accounts with multiple VMs recommendations'
    type: 'PowerShell'
    scriptUri: uri(artifactsLocation, 'runbooks/recommendations/${storageAccountsMultipleVmsRecommendationsRunbookName}.ps1${artifactsLocationSasToken}')
  }
  {
    name: vmsNoAvailSetRecommendationsRunbookName
    version: '1.2.1.0'
    description: 'Generates VMs without Availability Set recommendations'
    type: 'PowerShell'
    scriptUri: uri(artifactsLocation, 'runbooks/recommendations/${vmsNoAvailSetRecommendationsRunbookName}.ps1${artifactsLocationSasToken}')
  }
  {
    name: vmsSingleInAvailSetRecommendationsRunbookName
    version: '1.2.1.0'
    description: 'Generates VMs single in Availability Set recommendations'
    type: 'PowerShell'
    scriptUri: uri(artifactsLocation, 'runbooks/recommendations/${vmsSingleInAvailSetRecommendationsRunbookName}.ps1${artifactsLocationSasToken}')
  }
  {
    name: vmsDisksMultipleStorageRecommendationsRunbookName
    version: '1.2.1.0'
    description: 'Generates VMs with disks in multiple storage accounts recommendations'
    type: 'PowerShell'
    scriptUri: uri(artifactsLocation, 'runbooks/recommendations/${vmsDisksMultipleStorageRecommendationsRunbookName}.ps1${artifactsLocationSasToken}')
  }
  {
    name: aadExpiringCredsRecommendationsRunbookName
    version: '1.1.6.0'
    description: 'Generates AAD Objects with expiring credentials recommendations'
    type: 'PowerShell'
    scriptUri: uri(artifactsLocation, 'runbooks/recommendations/${aadExpiringCredsRecommendationsRunbookName}.ps1${artifactsLocationSasToken}')
  }
  {
    name: unusedLBsRecommendationsRunbookName
    version: '1.2.2.0'
    description: 'Generates unused Load Balancers recommendations'
    type: 'PowerShell'
    scriptUri: uri(artifactsLocation, 'runbooks/recommendations/${unusedLBsRecommendationsRunbookName}.ps1${artifactsLocationSasToken}')
  }
  {
    name: unusedAppGWsRecommendationsRunbookName
    version: '1.2.1.0'
    description: 'Generates unused Application Gateways recommendations'
    type: 'PowerShell'
    scriptUri: uri(artifactsLocation, 'runbooks/recommendations/${unusedAppGWsRecommendationsRunbookName}.ps1${artifactsLocationSasToken}')
  }
  {
    name: recommendationsIngestRunbookName
    version: '1.6.1.0'
    description: 'Ingests JSON-based recommendations into an Azure SQL Database'
    type: 'PowerShell'
    scriptUri: uri(artifactsLocation, 'runbooks/recommendations/${recommendationsIngestRunbookName}.ps1${artifactsLocationSasToken}')
  }
  {
    name: advisorRightSizeFilteredRemediationRunbookName
    version: '1.2.0.0'
    description: 'Remediates Azure Advisor right-size recommendations given fit and tag filters'
    type: 'PowerShell'
    scriptUri: uri(artifactsLocation, 'runbooks/remediations/${advisorRightSizeFilteredRemediationRunbookName}.ps1${artifactsLocationSasToken}')
  }
]
var automationVariables = [
  {
    name: 'AzureOptimization_CloudEnvironment'
    description: 'Azure Cloud environment (e.g., AzureCloud, AzureChinaCloud, etc.)'
    value: '"${cloudEnvironment}"'
  }
  {
    name: 'AzureOptimization_AuthenticationOption'
    description: 'Runbook authentication type (Run As Account or Managed Identity)'
    value: '"${authenticationOption}"'
  }
  {
    name: 'AzureOptimization_StorageSink'
    description: 'The Azure Storage Account where data source exports are dumped to'
    value: '"${storageAccountName}"'
  }
  {
    name: 'AzureOptimization_StorageSinkRG'
    description: 'The resource group for the Azure Storage Account sink'
    value: '"${resourceGroup().name}"'
  }
  {
    name: 'AzureOptimization_StorageSinkSubId'
    description: 'The subscription Id for the Azure Storage Account sink'
    value: '"${subscription().subscriptionId}"'
  }
  {
    name: 'AzureOptimization_AdvisorContainer'
    description: 'The Storage Account container where Azure Advisor exports are dumped to'
    value: '"${advisorContainerName}"'
  }
  {
    name: 'AzureOptimization_ARGDiskContainer'
    description: 'The Storage Account container where Azure Resource Graph Managed Disks exports are dumped to'
    value: '"${argDiskContainerName}"'
  }
  {
    name: 'AzureOptimization_ARGVhdContainer'
    description: 'The Storage Account container where Azure Resource Graph Unmanaged Disks exports are dumped to'
    value: '"${argVhdContainerName}"'
  }
  {
    name: 'AzureOptimization_ARGVMContainer'
    description: 'The Storage Account container where Azure Resource Graph Virtual Machine exports are dumped to'
    value: '"${argVmContainerName}"'
  }
  {
    name: 'AzureOptimization_ARGAvailabilitySetContainer'
    description: 'The Storage Account container where Azure Resource Graph Availability Set exports are dumped to'
    value: '"${argAvailSetContainerName}"'
  }
  {
    name: 'AzureOptimization_ConsumptionContainer'
    description: 'The Storage Account container where Azure Consumption exports are dumped to'
    value: '"${consumptionContainerName}"'
  }
  {
    name: 'AzureOptimization_AADObjectsContainer'
    description: 'The Storage Account container where Azure AD Objects exports are dumped to'
    value: '"${aadObjectsContainerName}"'
  }
  {
    name: 'AzureOptimization_ARGLoadBalancerContainer'
    description: 'The Storage Account container where Azure Resource Graph Load Balancer exports are dumped to'
    value: '"${argLBsContainerName}"'
  }
  {
    name: 'AzureOptimization_ARGAppGatewayContainer'
    description: 'The Storage Account container where Azure Resource Graph Application Gateway exports are dumped to'
    value: '"${argAppGWsContainerName}"'
  }
  {
    name: 'AzureOptimization_ARGResourceContainersContainer'
    description: 'The Storage Account container where Azure Resource Graph Resource Containers exports are dumped to'
    value: '"${argResContainersContainerName}"'
  }
  {
    name: 'AzureOptimization_RBACAssignmentsContainer'
    description: 'The Storage Account container where RBAC Assignments exports are dumped to'
    value: '"${rbacContainerName}"'
  }
  {
    name: 'AzureOptimization_ConsumptionOffsetDays'
    description: 'The offset (in days) for querying for consumption data'
    value: 7
  }
  {
    name: 'AzureOptimization_RecommendationsContainer'
    description: 'The Storage Account container where recommendations are dumped to'
    value: '"${recommendationsContainerName}"'
  }
  {
    name: 'AzureOptimization_RemediationLogsContainer'
    description: 'The Storage Account container where remediation logs are dumped to'
    value: '"${remediationLogsContainerName}"'
  }
  {
    name: 'AzureOptimization_AdvisorFilter'
    description: 'The category filter to use for Azure Advisor (non-Cost) recommendations exports'
    value: '"HighAvailability,Security,Performance,OperationalExcellence"'
  }
  {
    name: 'AzureOptimization_ReferenceRegion'
    description: 'The Azure region used as a reference for getting details about Azure VM sizes available'
    value: '"${projectLocation}"'
  }
  {
    name: 'AzureOptimization_SQLServerDatabase'
    description: 'The Azure SQL Database name for the ingestion control and recommendations tables'
    value: '"${sqlDatabaseName}"'
  }
  {
    name: 'AzureOptimization_LogAnalyticsChunkSize'
    description: 'The size (in rows) for each chunk of Log Analytics ingestion request'
    value: 10000
  }
  {
    name: 'AzureOptimization_StorageBlobsPageSize'
    description: 'The size (in blobs count) for each page of Storage Account container blob listing'
    value: 1000
  }
  {
    name: 'AzureOptimization_SQLServerInsertSize'
    description: 'The size (in inserted lines) for each page of recommendations ingestion into the SQL Database'
    value: 900
  }
  {
    name: 'AzureOptimization_LogAnalyticsLogPrefix'
    description: 'The prefix for all Azure Optimization custom log tables in Log Analytics'
    value: '"AzureOptimization"'
  }
  {
    name: 'AzureOptimization_LogAnalyticsWorkspaceName'
    description: 'The Log Analytics Workspace Name where optimization data will be ingested'
    value: '"${logAnalyticsWorkspaceName}"'
  }
  {
    name: 'AzureOptimization_LogAnalyticsWorkspaceRG'
    description: 'The resource group for the Log Analytics Workspace where optimization data will be ingested'
    value: '"${((!logAnalyticsReuse) ? resourceGroup().name : logAnalyticsWorkspaceRG)}"'
  }
  {
    name: 'AzureOptimization_LogAnalyticsWorkspaceSubId'
    description: 'The Azure subscription for the Log Analytics Workspace where optimization data will be ingested'
    value: '"${subscription().subscriptionId}"'
  }
  {
    name: 'AzureOptimization_LogAnalyticsWorkspaceTenantId'
    description: 'The Azure AD tenant for the Log Analytics Workspace where optimization data will be ingested'
    value: '"${subscription().tenantId}"'
  }
  {
    name: 'AzureOptimization_RecommendAdvisorPeriodInDays'
    description: 'The period (in days) to look back for Advisor exported recommendations'
    value: 7
  }
  {
    name: 'AzureOptimization_RecommendationLongDeallocatedVmsIntervalDays'
    description: 'The period (in days) for considering a VM long deallocated'
    value: 30
  }
  {
    name: 'AzureOptimization_PerfPercentileCpu'
    description: 'The percentile to be used for processor metrics'
    value: 99
  }
  {
    name: 'AzureOptimization_PerfPercentileMemory'
    description: 'The percentile to be used for memory metrics'
    value: 99
  }
  {
    name: 'AzureOptimization_PerfPercentileNetwork'
    description: 'The percentile to be used for network metrics'
    value: 99
  }
  {
    name: 'AzureOptimization_PerfPercentileDisk'
    description: 'The percentile to be used for disk metrics'
    value: 99
  }
  {
    name: 'AzureOptimization_PerfThresholdCpuPercentage'
    description: 'The processor usage percentage threshold above which the fit score is decreased'
    value: 30
  }
  {
    name: 'AzureOptimization_PerfThresholdMemoryPercentage'
    description: 'The memory usage percentage threshold above which the fit score is decreased'
    value: 50
  }
  {
    name: 'AzureOptimization_PerfThresholdNetworkMbps'
    description: 'The network usage threshold (in Mbps) above which the fit score is decreased'
    value: 750
  }
  {
    name: 'AzureOptimization_PerfThresholdCpuShutdownPercentage'
    description: 'The processor usage percentage threshold above which the fit score is decreased (shutdown scenarios)'
    value: 5
  }
  {
    name: 'AzureOptimization_PerfThresholdMemoryShutdownPercentage'
    description: 'The memory usage percentage threshold above which the fit score is decreased (shutdown scenarios)'
    value: 100
  }
  {
    name: 'AzureOptimization_PerfThresholdNetworkShutdownMbps'
    description: 'The network usage threshold (in Mbps) above which the fit score is decreased (shutdown scenarios)'
    value: 10
  }
  {
    name: 'AzureOptimization_RemediateRightSizeMinFitScore'
    description: 'The minimum fit score for right-size remediation'
    value: '"5.0"'
  }
  {
    name: 'AzureOptimization_RemediateRightSizeMinWeeksInARow'
    description: 'The minimum number of weeks in a row required for a right-size recommendation to be remediated'
    value: 4
  }
  {
    name: 'AzureOptimization_RecommendationAdvisorCostRightSizeId'
    description: 'The Azure Advisor VM right-size recommendation ID'
    value: '"e10b1381-5f0a-47ff-8c7b-37bd13d7c974"'
  }
  {
    name: 'AzureOptimization_RecommendationAADMinCredValidityDays'
    description: 'The minimum validity of an AAD Object credential in days'
    value: 30
  }
  {
    name: 'AzureOptimization_RecommendationAADMaxCredValidityYears'
    description: 'The maximum validity of an AAD Object credential in years'
    value: 2
  }
  {
    name: 'AzureOptimization_AADObjectsFilter'
    description: 'The Azure AD object types to export'
    value: '"Application,ServicePrincipal,User,Group"'
  }
]

resource logAnalyticsWorkspaceName_resource 'microsoft.operationalinsights/workspaces@2020-08-01' = if (!logAnalyticsReuse) {
  name: logAnalyticsWorkspaceName
  location: projectLocation
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: logAnalyticsRetentionDays
  }
}

resource storageAccountName_resource 'Microsoft.Storage/storageAccounts@2019-06-01' = {
  name: storageAccountName
  location: projectLocation
  sku: {
    name: 'Standard_LRS'
    tier: 'Standard'
  }
  kind: 'StorageV2'
  properties: {
    networkAcls: {
      bypass: 'AzureServices'
      virtualNetworkRules: []
      ipRules: []
      defaultAction: 'Allow'
    }
    supportsHttpsTrafficOnly: true
    encryption: {
      services: {
        file: {
          enabled: true
        }
        blob: {
          enabled: true
        }
      }
      keySource: 'Microsoft.Storage'
    }
    accessTier: 'Cool'
  }
}

resource storageAccountName_default 'Microsoft.Storage/storageAccounts/blobServices@2019-06-01' = {
  name: '${storageAccountName}/default'
  sku: {
    name: 'Standard_LRS'
  }
  properties: {
    cors: {
      corsRules: []
    }
    deleteRetentionPolicy: {
      enabled: false
    }
  }
  dependsOn: [
    storageAccountName_resource
  ]
}

resource storageAccountName_default_argDiskContainerName 'Microsoft.Storage/storageAccounts/blobServices/containers@2019-06-01' = {
  name: '${storageAccountName}/default/${argDiskContainerName}'
  properties: {
    publicAccess: 'None'
  }
  dependsOn: [
    storageAccountName_default
    storageAccountName_resource
  ]
}

resource storageAccountName_default_argVhdContainerName 'Microsoft.Storage/storageAccounts/blobServices/containers@2019-06-01' = {
  name: '${storageAccountName}/default/${argVhdContainerName}'
  properties: {
    publicAccess: 'None'
  }
  dependsOn: [
    storageAccountName_default
    storageAccountName_resource
  ]
}

resource storageAccountName_default_argVmContainerName 'Microsoft.Storage/storageAccounts/blobServices/containers@2019-06-01' = {
  name: '${storageAccountName}/default/${argVmContainerName}'
  properties: {
    publicAccess: 'None'
  }
  dependsOn: [
    storageAccountName_default
    storageAccountName_resource
  ]
}

resource storageAccountName_default_argAvailSetContainerName 'Microsoft.Storage/storageAccounts/blobServices/containers@2019-06-01' = {
  name: '${storageAccountName}/default/${argAvailSetContainerName}'
  properties: {
    publicAccess: 'None'
  }
  dependsOn: [
    storageAccountName_default
    storageAccountName_resource
  ]
}

resource storageAccountName_default_advisorContainerName 'Microsoft.Storage/storageAccounts/blobServices/containers@2019-06-01' = {
  name: '${storageAccountName}/default/${advisorContainerName}'
  properties: {
    publicAccess: 'None'
  }
  dependsOn: [
    storageAccountName_default
    storageAccountName_resource
  ]
}

resource storageAccountName_default_consumptionContainerName 'Microsoft.Storage/storageAccounts/blobServices/containers@2019-06-01' = {
  name: '${storageAccountName}/default/${consumptionContainerName}'
  properties: {
    publicAccess: 'None'
  }
  dependsOn: [
    storageAccountName_default
    storageAccountName_resource
  ]
}

resource storageAccountName_default_aadObjectsContainerName 'Microsoft.Storage/storageAccounts/blobServices/containers@2019-06-01' = {
  name: '${storageAccountName}/default/${aadObjectsContainerName}'
  properties: {
    publicAccess: 'None'
  }
  dependsOn: [
    storageAccountName_default
    storageAccountName_resource
  ]
}

resource storageAccountName_default_argLBsContainerName 'Microsoft.Storage/storageAccounts/blobServices/containers@2019-06-01' = {
  name: '${storageAccountName}/default/${argLBsContainerName}'
  properties: {
    publicAccess: 'None'
  }
  dependsOn: [
    storageAccountName_default
    storageAccountName_resource
  ]
}

resource storageAccountName_default_argAppGWsContainerName 'Microsoft.Storage/storageAccounts/blobServices/containers@2019-06-01' = {
  name: '${storageAccountName}/default/${argAppGWsContainerName}'
  properties: {
    publicAccess: 'None'
  }
  dependsOn: [
    storageAccountName_default
    storageAccountName_resource
  ]
}

resource storageAccountName_default_argResContainersContainerName 'Microsoft.Storage/storageAccounts/blobServices/containers@2019-06-01' = {
  name: '${storageAccountName}/default/${argResContainersContainerName}'
  properties: {
    publicAccess: 'None'
  }
  dependsOn: [
    storageAccountName_default
    storageAccountName_resource
  ]
}

resource storageAccountName_default_rbacContainerName 'Microsoft.Storage/storageAccounts/blobServices/containers@2019-06-01' = {
  name: '${storageAccountName}/default/${rbacContainerName}'
  properties: {
    publicAccess: 'None'
  }
  dependsOn: [
    storageAccountName_default
    storageAccountName_resource
  ]
}

resource storageAccountName_default_recommendationsContainerName 'Microsoft.Storage/storageAccounts/blobServices/containers@2019-06-01' = {
  name: '${storageAccountName}/default/${recommendationsContainerName}'
  properties: {
    publicAccess: 'None'
  }
  dependsOn: [
    storageAccountName_default
    storageAccountName_resource
  ]
}

resource storageAccountName_default_remediationLogsContainerName 'Microsoft.Storage/storageAccounts/blobServices/containers@2019-06-01' = {
  name: '${storageAccountName}/default/${remediationLogsContainerName}'
  properties: {
    publicAccess: 'None'
  }
  dependsOn: [
    storageAccountName_default
    storageAccountName_resource
  ]
}

resource sqlServerName_resource 'Microsoft.Sql/servers@2019-06-01-preview' = {
  name: sqlServerName
  location: projectLocation
  kind: 'v12.0'
  properties: {
    administratorLogin: sqlAdminLogin
    administratorLoginPassword: sqlAdminPassword
    version: '12.0'
    publicNetworkAccess: 'Enabled'
  }
}

resource sqlServerName_AllowAllWindowsAzureIps 'Microsoft.Sql/servers/firewallRules@2019-06-01-preview' = {
  name: '${sqlServerName}/AllowAllWindowsAzureIps'
  location: projectLocation
  properties: {
    endIpAddress: '0.0.0.0'
    startIpAddress: '0.0.0.0'
  }
  dependsOn: [
    sqlServerName_resource
  ]
}

resource sqlServerName_sqlDatabaseName 'Microsoft.Sql/servers/databases@2019-06-01-preview' = {
  name: '${sqlServerName}/${sqlDatabaseName}'
  location: projectLocation
  sku: {
    name: 'Basic'
    tier: 'Basic'
    capacity: 5
  }
  kind: 'v12.0,user'
  properties: {
    collation: 'SQL_Latin1_General_CP1_CI_AS'
    maxSizeBytes: 2147483648
    catalogCollation: 'SQL_Latin1_General_CP1_CI_AS'
    zoneRedundant: false
    readScale: 'Disabled'
    readReplicaCount: 0
    autoPauseDelay: 60
    storageAccountType: 'GRS'
  }
  dependsOn: [
    sqlServerName_resource
  ]
}

resource sqlServerName_sqlDatabaseName_default 'Microsoft.Sql/servers/databases/backupShortTermRetentionPolicies@2019-06-01-preview' = {
  name: '${sqlServerName}/${sqlDatabaseName}/default'
  properties: {
    retentionDays: sqlBackupRetentionDays
  }
  dependsOn: [
    sqlServerName_sqlDatabaseName
    sqlServerName_resource
  ]
}

resource automationAccountName_resource 'Microsoft.Automation/automationAccounts@2018-06-30' = {
  name: automationAccountName
  location: projectLocation
  properties: {
    sku: {
      name: 'Basic'
    }
  }
}

resource automationAccountName_Az_Accounts_name 'Microsoft.Automation/automationAccounts/modules@2018-06-30' = {
  name: '${automationAccountName}/${Az_Accounts.name}'
  properties: {
    contentLink: {
      uri: Az_Accounts.url
    }
  }
  dependsOn: [
    automationAccountName_resource
  ]
}

resource automationAccountName_psModules_name 'Microsoft.Automation/automationAccounts/modules@2018-06-30' = [for item in psModules: {
  name: '${automationAccountName}/${item.name}'
  properties: {
    contentLink: {
      uri: item.url
    }
  }
  dependsOn: [
    automationAccountName_resource
    automationAccountName_Az_Accounts_name
  ]
}]

resource automationAccountName_runbooks_name 'Microsoft.Automation/automationAccounts/runbooks@2018-06-30' = [for item in runbooks: {
  name: '${automationAccountName}/${item.name}'
  location: projectLocation
  properties: {
    runbookType: item.type
    logProgress: false
    logVerbose: false
    description: item.description
    publishContentLink: {
      uri: item.scriptUri
      version: item.version
    }
  }
  dependsOn: [
    automationAccountName_resource
    automationAccountName_Az_Accounts_name
    automationAccountName_psModules_name
  ]
}]

resource automationAccountName_automationVariables_name 'Microsoft.Automation/automationAccounts/variables@2018-06-30' = [for item in automationVariables: {
  name: '${automationAccountName}/${item.name}'
  properties: {
    description: item.description
    value: item.value
  }
  dependsOn: [
    automationAccountName_resource
  ]
}]

resource automationAccountName_AzureOptimization_SQLServerHostname 'Microsoft.Automation/automationAccounts/variables@2018-06-30' = {
  name: '${automationAccountName}/AzureOptimization_SQLServerHostname'
  properties: {
    description: 'The Azure SQL Server hostname for the ingestion control and recommendations tables'
    value: '"${reference(sqlServerName_resource.id, providers('Microsoft.Sql', 'servers').apiVersions[0]).fullyQualifiedDomainName}"'
  }
  dependsOn: [
    automationAccountName_resource
  ]
}

resource automationAccountName_AzureOptimization_LogAnalyticsWorkspaceId 'Microsoft.Automation/automationAccounts/variables@2018-06-30' = {
  name: '${automationAccountName}/AzureOptimization_LogAnalyticsWorkspaceId'
  properties: {
    description: 'The Log Analytics Workspace ID where optimization data will be ingested'
    value: '"${reference(((!logAnalyticsReuse) ? logAnalyticsWorkspaceName_resource.id : resourceId(logAnalyticsWorkspaceRG, 'microsoft.operationalinsights/workspaces', logAnalyticsWorkspaceName)), providers('microsoft.operationalinsights', 'workspaces').apiVersions[0]).customerId}"'
  }
  dependsOn: [
    automationAccountName_resource
    ((!logAnalyticsReuse) ? logAnalyticsWorkspaceName_resource.id : 'variableLoop')
  ]
}

resource automationAccountName_AzureOptimization_LogAnalyticsWorkspaceKey 'Microsoft.Automation/automationAccounts/variables@2018-06-30' = {
  name: '${automationAccountName}/AzureOptimization_LogAnalyticsWorkspaceKey'
  properties: {
    description: 'The shared key for the Log Analytics Workspace where optimization data will be ingested'
    value: '"${listKeys(((!logAnalyticsReuse) ? logAnalyticsWorkspaceName_resource.id : resourceId(logAnalyticsWorkspaceRG, 'microsoft.operationalinsights/workspaces', logAnalyticsWorkspaceName)), apiVersions.operationalInsights).primarySharedKey}"'
    isEncrypted: true
  }
  dependsOn: [
    automationAccountName_resource
    ((!logAnalyticsReuse) ? logAnalyticsWorkspaceName_resource.id : 'variableLoop')
  ]
}

resource automationAccountName_AzureOptimization_SQLServerCredential 'Microsoft.Automation/automationAccounts/credentials@2018-06-30' = {
  name: '${automationAccountName}/AzureOptimization_SQLServerCredential'
  properties: {
    description: 'Azure Optimization SQL Database Credentials'
    password: sqlAdminPassword
    userName: sqlAdminLogin
  }
  dependsOn: [
    automationAccountName_resource
  ]
}

resource automationAccountName_argExportsScheduleName 'Microsoft.Automation/automationAccounts/schedules@2018-06-30' = {
  name: '${automationAccountName}/${argExportsScheduleName}'
  properties: {
    description: 'Starts the daily Azure Resource Graph exports'
    expiryTime: '31/12/9999 23:59:00'
    isEnabled: true
    startTime: dateTimeAdd(baseTime, 'PT1H')
    interval: 1
    frequency: 'Day'
  }
  dependsOn: [
    automationAccountName_resource
  ]
}

resource automationAccountName_advisorExportsScheduleName 'Microsoft.Automation/automationAccounts/schedules@2018-06-30' = {
  name: '${automationAccountName}/${advisorExportsScheduleName}'
  properties: {
    description: 'Starts the weekly Azure Advisor exports'
    expiryTime: '31/12/9999 23:59:00'
    isEnabled: true
    startTime: dateTimeAdd(baseTime, 'PT1H15M')
    interval: 1
    frequency: 'Week'
  }
  dependsOn: [
    automationAccountName_resource
  ]
}

resource automationAccountName_consumptionExportsScheduleName 'Microsoft.Automation/automationAccounts/schedules@2018-06-30' = {
  name: '${automationAccountName}/${consumptionExportsScheduleName}'
  properties: {
    description: 'Starts the daily Azure Consumption exports'
    expiryTime: '31/12/9999 23:59:00'
    isEnabled: true
    startTime: dateTimeAdd(baseTime, 'PT1H')
    interval: 1
    frequency: 'Day'
  }
  dependsOn: [
    automationAccountName_resource
  ]
}

resource automationAccountName_aadObjectsExportsScheduleName 'Microsoft.Automation/automationAccounts/schedules@2018-06-30' = {
  name: '${automationAccountName}/${aadObjectsExportsScheduleName}'
  properties: {
    description: 'Starts the daily Azure AD Objects exports'
    expiryTime: '31/12/9999 23:59:00'
    isEnabled: true
    startTime: dateTimeAdd(baseTime, 'PT1H')
    interval: 1
    frequency: 'Day'
  }
  dependsOn: [
    automationAccountName_resource
  ]
}

resource automationAccountName_argDiskIngestScheduleName 'Microsoft.Automation/automationAccounts/schedules@2018-06-30' = {
  name: '${automationAccountName}/${argDiskIngestScheduleName}'
  properties: {
    description: 'Starts the daily Azure Resource Graph Managed Disks ingests'
    expiryTime: '31/12/9999 23:59:00'
    isEnabled: true
    startTime: dateTimeAdd(baseTime, 'PT1H30M')
    interval: 1
    frequency: 'Day'
  }
  dependsOn: [
    automationAccountName_resource
  ]
}

resource automationAccountName_argVhdIngestScheduleName 'Microsoft.Automation/automationAccounts/schedules@2018-06-30' = {
  name: '${automationAccountName}/${argVhdIngestScheduleName}'
  properties: {
    description: 'Starts the daily Azure Resource Graph Unmanaged Disks ingests'
    expiryTime: '31/12/9999 23:59:00'
    isEnabled: true
    startTime: dateTimeAdd(baseTime, 'PT1H30M')
    interval: 1
    frequency: 'Day'
  }
  dependsOn: [
    automationAccountName_resource
  ]
}

resource automationAccountName_argVmIngestScheduleName 'Microsoft.Automation/automationAccounts/schedules@2018-06-30' = {
  name: '${automationAccountName}/${argVmIngestScheduleName}'
  properties: {
    description: 'Starts the daily Azure Resource Graph Virtual Machine ingests'
    expiryTime: '31/12/9999 23:59:00'
    isEnabled: true
    startTime: dateTimeAdd(baseTime, 'PT1H30M')
    interval: 1
    frequency: 'Day'
  }
  dependsOn: [
    automationAccountName_resource
  ]
}

resource automationAccountName_argAvailSetIngestScheduleName 'Microsoft.Automation/automationAccounts/schedules@2018-06-30' = {
  name: '${automationAccountName}/${argAvailSetIngestScheduleName}'
  properties: {
    description: 'Starts the daily Azure Resource Graph Availability Set ingests'
    expiryTime: '31/12/9999 23:59:00'
    isEnabled: true
    startTime: dateTimeAdd(baseTime, 'PT1H30M')
    interval: 1
    frequency: 'Day'
  }
  dependsOn: [
    automationAccountName_resource
  ]
}

resource automationAccountName_remediationLogsIngestScheduleName 'Microsoft.Automation/automationAccounts/schedules@2018-06-30' = {
  name: '${automationAccountName}/${remediationLogsIngestScheduleName}'
  properties: {
    description: 'Starts the daily Remediation Logs ingests'
    expiryTime: '31/12/9999 23:59:00'
    isEnabled: true
    startTime: dateTimeAdd(baseTime, 'PT1H30M')
    interval: 1
    frequency: 'Day'
  }
  dependsOn: [
    automationAccountName_resource
  ]
}

resource automationAccountName_consumptionIngestScheduleName 'Microsoft.Automation/automationAccounts/schedules@2018-06-30' = {
  name: '${automationAccountName}/${consumptionIngestScheduleName}'
  properties: {
    description: 'Starts the daily Consumption ingests'
    expiryTime: '31/12/9999 23:59:00'
    isEnabled: true
    startTime: dateTimeAdd(baseTime, 'PT2H')
    interval: 1
    frequency: 'Day'
  }
  dependsOn: [
    automationAccountName_resource
  ]
}

resource automationAccountName_aadObjectsIngestScheduleName 'Microsoft.Automation/automationAccounts/schedules@2018-06-30' = {
  name: '${automationAccountName}/${aadObjectsIngestScheduleName}'
  properties: {
    description: 'Starts the daily AAD Objects ingests'
    expiryTime: '31/12/9999 23:59:00'
    isEnabled: true
    startTime: dateTimeAdd(baseTime, 'PT2H')
    interval: 1
    frequency: 'Day'
  }
  dependsOn: [
    automationAccountName_resource
  ]
}

resource automationAccountName_argLBsIngestScheduleName 'Microsoft.Automation/automationAccounts/schedules@2018-06-30' = {
  name: '${automationAccountName}/${argLBsIngestScheduleName}'
  properties: {
    description: 'Starts the daily Load Balancer ingests'
    expiryTime: '31/12/9999 23:59:00'
    isEnabled: true
    startTime: dateTimeAdd(baseTime, 'PT1H30M')
    interval: 1
    frequency: 'Day'
  }
  dependsOn: [
    automationAccountName_resource
  ]
}

resource automationAccountName_argAppGWsIngestScheduleName 'Microsoft.Automation/automationAccounts/schedules@2018-06-30' = {
  name: '${automationAccountName}/${argAppGWsIngestScheduleName}'
  properties: {
    description: 'Starts the daily App Gateways ingests'
    expiryTime: '31/12/9999 23:59:00'
    isEnabled: true
    startTime: dateTimeAdd(baseTime, 'PT1H30M')
    interval: 1
    frequency: 'Day'
  }
  dependsOn: [
    automationAccountName_resource
  ]
}

resource automationAccountName_argResContainersIngestScheduleName 'Microsoft.Automation/automationAccounts/schedules@2018-06-30' = {
  name: '${automationAccountName}/${argResContainersIngestScheduleName}'
  properties: {
    description: 'Starts the daily Resource Containers ingests'
    expiryTime: '31/12/9999 23:59:00'
    isEnabled: true
    startTime: dateTimeAdd(baseTime, 'PT1H30M')
    interval: 1
    frequency: 'Day'
  }
  dependsOn: [
    automationAccountName_resource
  ]
}

resource automationAccountName_rbacIngestScheduleName 'Microsoft.Automation/automationAccounts/schedules@2018-06-30' = {
  name: '${automationAccountName}/${rbacIngestScheduleName}'
  properties: {
    description: 'Starts the daily RBAC ingests'
    expiryTime: '31/12/9999 23:59:00'
    isEnabled: true
    startTime: dateTimeAdd(baseTime, 'PT1H30M')
    interval: 1
    frequency: 'Day'
  }
  dependsOn: [
    automationAccountName_resource
  ]
}

resource automationAccountName_advisorIngestScheduleName 'Microsoft.Automation/automationAccounts/schedules@2018-06-30' = {
  name: '${automationAccountName}/${advisorIngestScheduleName}'
  properties: {
    description: 'Starts the weekly Azure Advisor ingests'
    expiryTime: '31/12/9999 23:59:00'
    isEnabled: true
    startTime: dateTimeAdd(baseTime, 'PT1H45M')
    interval: 1
    frequency: 'Week'
  }
  dependsOn: [
    automationAccountName_resource
  ]
}

resource automationAccountName_recommendationsScheduleName 'Microsoft.Automation/automationAccounts/schedules@2018-06-30' = {
  name: '${automationAccountName}/${recommendationsScheduleName}'
  properties: {
    description: 'Starts the weekly Recommendations generation'
    expiryTime: '31/12/9999 23:59:00'
    isEnabled: true
    startTime: dateTimeAdd(baseTime, 'PT2H30M')
    interval: 1
    frequency: 'Week'
  }
  dependsOn: [
    automationAccountName_resource
  ]
}

resource automationAccountName_recommendationsIngestScheduleName 'Microsoft.Automation/automationAccounts/schedules@2018-06-30' = {
  name: '${automationAccountName}/${recommendationsIngestScheduleName}'
  properties: {
    description: 'Starts the weekly Recommendations ingests'
    expiryTime: '31/12/9999 23:59:00'
    isEnabled: true
    startTime: dateTimeAdd(baseTime, 'PT3H30M')
    interval: 1
    frequency: 'Week'
  }
  dependsOn: [
    automationAccountName_resource
  ]
}

resource automationAccountName_argDiskExportJobId 'Microsoft.Automation/automationAccounts/jobSchedules@2018-06-30' = {
  name: '${automationAccountName}/${argDiskExportJobId}'
  location: projectLocation
  properties: {
    schedule: {
      name: argExportsScheduleName
    }
    runbook: {
      name: argDisksExportsRunbookName
    }
  }
  dependsOn: [
    automationAccountName_resource
    automationAccountName_argExportsScheduleName
    automationAccountName_psModules_name
    argDisksExportsRunbookName
  ]
}

resource automationAccountName_argVhdExportJobId 'Microsoft.Automation/automationAccounts/jobSchedules@2018-06-30' = {
  name: '${automationAccountName}/${argVhdExportJobId}'
  location: projectLocation
  properties: {
    schedule: {
      name: argExportsScheduleName
    }
    runbook: {
      name: argVhdExportsRunbookName
    }
  }
  dependsOn: [
    automationAccountName_resource
    automationAccountName_argExportsScheduleName
    automationAccountName_psModules_name
    argVhdExportsRunbookName
  ]
}

resource automationAccountName_argVmExportJobId 'Microsoft.Automation/automationAccounts/jobSchedules@2018-06-30' = {
  name: '${automationAccountName}/${argVmExportJobId}'
  location: projectLocation
  properties: {
    schedule: {
      name: argExportsScheduleName
    }
    runbook: {
      name: argVmExportsRunbookName
    }
  }
  dependsOn: [
    automationAccountName_resource
    automationAccountName_argExportsScheduleName
    automationAccountName_psModules_name
    argVmExportsRunbookName
  ]
}

resource automationAccountName_argAvailSetExportJobId 'Microsoft.Automation/automationAccounts/jobSchedules@2018-06-30' = {
  name: '${automationAccountName}/${argAvailSetExportJobId}'
  location: projectLocation
  properties: {
    schedule: {
      name: argExportsScheduleName
    }
    runbook: {
      name: argAvailSetExportsRunbookName
    }
  }
  dependsOn: [
    automationAccountName_resource
    automationAccountName_argExportsScheduleName
    automationAccountName_psModules_name
    argAvailSetExportsRunbookName
  ]
}

resource automationAccountName_advisorExportJobId 'Microsoft.Automation/automationAccounts/jobSchedules@2018-06-30' = {
  name: '${automationAccountName}/${advisorExportJobId}'
  location: projectLocation
  properties: {
    schedule: {
      name: advisorExportsScheduleName
    }
    runbook: {
      name: advisorExportsRunbookName
    }
  }
  dependsOn: [
    automationAccountName_resource
    automationAccountName_advisorExportsScheduleName
    automationAccountName_psModules_name
    advisorExportsRunbookName
  ]
}

resource automationAccountName_consumptionExportJobId 'Microsoft.Automation/automationAccounts/jobSchedules@2018-06-30' = {
  name: '${automationAccountName}/${consumptionExportJobId}'
  location: projectLocation
  properties: {
    schedule: {
      name: consumptionExportsScheduleName
    }
    runbook: {
      name: consumptionExportsRunbookName
    }
  }
  dependsOn: [
    automationAccountName_resource
    automationAccountName_consumptionExportsScheduleName
    automationAccountName_psModules_name
    consumptionExportsRunbookName
  ]
}

resource automationAccountName_aadObjectsExportJobId 'Microsoft.Automation/automationAccounts/jobSchedules@2018-06-30' = {
  name: '${automationAccountName}/${aadObjectsExportJobId}'
  location: projectLocation
  properties: {
    schedule: {
      name: aadObjectsExportsScheduleName
    }
    runbook: {
      name: aadObjectsExportsRunbookName
    }
  }
  dependsOn: [
    automationAccountName_resource
    automationAccountName_aadObjectsExportsScheduleName
    automationAccountName_psModules_name
    aadObjectsExportsRunbookName
  ]
}

resource automationAccountName_argLoadBalancersExportJobId 'Microsoft.Automation/automationAccounts/jobSchedules@2018-06-30' = {
  name: '${automationAccountName}/${argLoadBalancersExportJobId}'
  location: projectLocation
  properties: {
    schedule: {
      name: argExportsScheduleName
    }
    runbook: {
      name: argLoadBalancersExportsRunbookName
    }
  }
  dependsOn: [
    automationAccountName_resource
    automationAccountName_argExportsScheduleName
    automationAccountName_psModules_name
    argLoadBalancersExportsRunbookName
  ]
}

resource automationAccountName_argAppGWsExportJobId 'Microsoft.Automation/automationAccounts/jobSchedules@2018-06-30' = {
  name: '${automationAccountName}/${argAppGWsExportJobId}'
  location: projectLocation
  properties: {
    schedule: {
      name: argExportsScheduleName
    }
    runbook: {
      name: argAppGWsExportsRunbookName
    }
  }
  dependsOn: [
    automationAccountName_resource
    automationAccountName_argExportsScheduleName
    automationAccountName_psModules_name
    argAppGWsExportsRunbookName
  ]
}

resource automationAccountName_argResContainersExportJobId 'Microsoft.Automation/automationAccounts/jobSchedules@2018-06-30' = {
  name: '${automationAccountName}/${argResContainersExportJobId}'
  location: projectLocation
  properties: {
    schedule: {
      name: argExportsScheduleName
    }
    runbook: {
      name: argResContainersExportsRunbookName
    }
  }
  dependsOn: [
    automationAccountName_resource
    automationAccountName_argExportsScheduleName
    automationAccountName_psModules_name
    argResContainersExportsRunbookName
  ]
}

resource automationAccountName_rbacExportJobId 'Microsoft.Automation/automationAccounts/jobSchedules@2018-06-30' = {
  name: '${automationAccountName}/${rbacExportJobId}'
  location: projectLocation
  properties: {
    schedule: {
      name: aadObjectsExportsScheduleName
    }
    runbook: {
      name: rbacExportsRunbookName
    }
  }
  dependsOn: [
    automationAccountName_resource
    automationAccountName_aadObjectsExportsScheduleName
    automationAccountName_psModules_name
    rbacExportsRunbookName
  ]
}

resource automationAccountName_argDiskIngestJobId 'Microsoft.Automation/automationAccounts/jobSchedules@2018-06-30' = {
  name: '${automationAccountName}/${argDiskIngestJobId}'
  location: projectLocation
  properties: {
    schedule: {
      name: argDiskIngestScheduleName
    }
    runbook: {
      name: csvIngestRunbookName
    }
    parameters: {
      StorageSinkContainer: argDiskContainerName
    }
  }
  dependsOn: [
    automationAccountName_resource
    automationAccountName_argDiskIngestScheduleName
    automationAccountName_psModules_name
    csvIngestRunbookName
  ]
}

resource automationAccountName_argVhdIngestJobId 'Microsoft.Automation/automationAccounts/jobSchedules@2018-06-30' = {
  name: '${automationAccountName}/${argVhdIngestJobId}'
  location: projectLocation
  properties: {
    schedule: {
      name: argVhdIngestScheduleName
    }
    runbook: {
      name: csvIngestRunbookName
    }
    parameters: {
      StorageSinkContainer: argVhdContainerName
    }
  }
  dependsOn: [
    automationAccountName_resource
    automationAccountName_argVhdIngestScheduleName
    automationAccountName_psModules_name
    csvIngestRunbookName
  ]
}

resource automationAccountName_argVmIngestJobId 'Microsoft.Automation/automationAccounts/jobSchedules@2018-06-30' = {
  name: '${automationAccountName}/${argVmIngestJobId}'
  location: projectLocation
  properties: {
    schedule: {
      name: argVmIngestScheduleName
    }
    runbook: {
      name: csvIngestRunbookName
    }
    parameters: {
      StorageSinkContainer: argVmContainerName
    }
  }
  dependsOn: [
    automationAccountName_resource
    automationAccountName_argVmIngestScheduleName
    automationAccountName_psModules_name
    csvIngestRunbookName
  ]
}

resource automationAccountName_argAvailSetIngestJobId 'Microsoft.Automation/automationAccounts/jobSchedules@2018-06-30' = {
  name: '${automationAccountName}/${argAvailSetIngestJobId}'
  location: projectLocation
  properties: {
    schedule: {
      name: argAvailSetIngestScheduleName
    }
    runbook: {
      name: csvIngestRunbookName
    }
    parameters: {
      StorageSinkContainer: argAvailSetContainerName
    }
  }
  dependsOn: [
    automationAccountName_resource
    automationAccountName_argAvailSetIngestScheduleName
    automationAccountName_psModules_name
    csvIngestRunbookName
  ]
}

resource automationAccountName_remediationLogsIngestJobId 'Microsoft.Automation/automationAccounts/jobSchedules@2018-06-30' = {
  name: '${automationAccountName}/${remediationLogsIngestJobId}'
  location: projectLocation
  properties: {
    schedule: {
      name: remediationLogsIngestScheduleName
    }
    runbook: {
      name: csvIngestRunbookName
    }
    parameters: {
      StorageSinkContainer: remediationLogsContainerName
    }
  }
  dependsOn: [
    automationAccountName_resource
    automationAccountName_remediationLogsIngestScheduleName
    automationAccountName_psModules_name
    csvIngestRunbookName
  ]
}

resource automationAccountName_consumptionIngestJobId 'Microsoft.Automation/automationAccounts/jobSchedules@2018-06-30' = {
  name: '${automationAccountName}/${consumptionIngestJobId}'
  location: projectLocation
  properties: {
    schedule: {
      name: consumptionIngestScheduleName
    }
    runbook: {
      name: csvIngestRunbookName
    }
    parameters: {
      StorageSinkContainer: consumptionContainerName
    }
  }
  dependsOn: [
    automationAccountName_resource
    automationAccountName_consumptionIngestScheduleName
    automationAccountName_psModules_name
    csvIngestRunbookName
  ]
}

resource automationAccountName_aadObjectsIngestJobId 'Microsoft.Automation/automationAccounts/jobSchedules@2018-06-30' = {
  name: '${automationAccountName}/${aadObjectsIngestJobId}'
  location: projectLocation
  properties: {
    schedule: {
      name: aadObjectsIngestScheduleName
    }
    runbook: {
      name: csvIngestRunbookName
    }
    parameters: {
      StorageSinkContainer: aadObjectsContainerName
    }
  }
  dependsOn: [
    automationAccountName_resource
    automationAccountName_aadObjectsIngestScheduleName
    automationAccountName_psModules_name
    csvIngestRunbookName
  ]
}

resource automationAccountName_argLoadBalancersIngestJobId 'Microsoft.Automation/automationAccounts/jobSchedules@2018-06-30' = {
  name: '${automationAccountName}/${argLoadBalancersIngestJobId}'
  location: projectLocation
  properties: {
    schedule: {
      name: argLBsIngestScheduleName
    }
    runbook: {
      name: csvIngestRunbookName
    }
    parameters: {
      StorageSinkContainer: argLBsContainerName
    }
  }
  dependsOn: [
    automationAccountName_resource
    automationAccountName_argLBsIngestScheduleName
    automationAccountName_psModules_name
    csvIngestRunbookName
  ]
}

resource automationAccountName_argAppGWsIngestJobId 'Microsoft.Automation/automationAccounts/jobSchedules@2018-06-30' = {
  name: '${automationAccountName}/${argAppGWsIngestJobId}'
  location: projectLocation
  properties: {
    schedule: {
      name: argAppGWsIngestScheduleName
    }
    runbook: {
      name: csvIngestRunbookName
    }
    parameters: {
      StorageSinkContainer: argAppGWsContainerName
    }
  }
  dependsOn: [
    automationAccountName_resource
    automationAccountName_argAppGWsIngestScheduleName
    automationAccountName_psModules_name
    csvIngestRunbookName
  ]
}

resource automationAccountName_argResContainersIngestJobId 'Microsoft.Automation/automationAccounts/jobSchedules@2018-06-30' = {
  name: '${automationAccountName}/${argResContainersIngestJobId}'
  location: projectLocation
  properties: {
    schedule: {
      name: argResContainersIngestScheduleName
    }
    runbook: {
      name: csvIngestRunbookName
    }
    parameters: {
      StorageSinkContainer: argResContainersContainerName
    }
  }
  dependsOn: [
    automationAccountName_resource
    automationAccountName_argResContainersIngestScheduleName
    automationAccountName_psModules_name
    csvIngestRunbookName
  ]
}

resource automationAccountName_rbacIngestJobId 'Microsoft.Automation/automationAccounts/jobSchedules@2018-06-30' = {
  name: '${automationAccountName}/${rbacIngestJobId}'
  location: projectLocation
  properties: {
    schedule: {
      name: rbacIngestScheduleName
    }
    runbook: {
      name: csvIngestRunbookName
    }
    parameters: {
      StorageSinkContainer: rbacContainerName
    }
  }
  dependsOn: [
    automationAccountName_resource
    automationAccountName_rbacIngestScheduleName
    automationAccountName_psModules_name
    csvIngestRunbookName
  ]
}

resource automationAccountName_advisorIngestJobId 'Microsoft.Automation/automationAccounts/jobSchedules@2018-06-30' = {
  name: '${automationAccountName}/${advisorIngestJobId}'
  location: projectLocation
  properties: {
    schedule: {
      name: advisorIngestScheduleName
    }
    runbook: {
      name: csvIngestRunbookName
    }
    parameters: {
      StorageSinkContainer: advisorContainerName
    }
  }
  dependsOn: [
    automationAccountName_resource
    automationAccountName_advisorIngestScheduleName
    automationAccountName_psModules_name
    csvIngestRunbookName
  ]
}

resource automationAccountName_unattachedDisksRecommendationJobId 'Microsoft.Automation/automationAccounts/jobSchedules@2018-06-30' = {
  name: '${automationAccountName}/${unattachedDisksRecommendationJobId}'
  location: projectLocation
  properties: {
    schedule: {
      name: recommendationsScheduleName
    }
    runbook: {
      name: unattachedDisksRecommendationsRunbookName
    }
  }
  dependsOn: [
    automationAccountName_resource
    automationAccountName_recommendationsScheduleName
    automationAccountName_psModules_name
    unattachedDisksRecommendationsRunbookName
  ]
}

resource automationAccountName_advisorCostAugmentedRecommendationJobId 'Microsoft.Automation/automationAccounts/jobSchedules@2018-06-30' = {
  name: '${automationAccountName}/${advisorCostAugmentedRecommendationJobId}'
  location: projectLocation
  properties: {
    schedule: {
      name: recommendationsScheduleName
    }
    runbook: {
      name: advisorCostAugmentedRecommendationsRunbookName
    }
  }
  dependsOn: [
    automationAccountName_resource
    automationAccountName_recommendationsScheduleName
    automationAccountName_psModules_name
    advisorCostAugmentedRecommendationsRunbookName
  ]
}

resource automationAccountName_advisorAsIsRecommendationJobId 'Microsoft.Automation/automationAccounts/jobSchedules@2018-06-30' = {
  name: '${automationAccountName}/${advisorAsIsRecommendationJobId}'
  location: projectLocation
  properties: {
    schedule: {
      name: recommendationsScheduleName
    }
    runbook: {
      name: advisorAsIsRecommendationsRunbookName
    }
  }
  dependsOn: [
    automationAccountName_resource
    automationAccountName_recommendationsScheduleName
    automationAccountName_psModules_name
    advisorAsIsRecommendationsRunbookName
  ]
}

resource automationAccountName_unmanagedDisksRecommendationJobId 'Microsoft.Automation/automationAccounts/jobSchedules@2018-06-30' = {
  name: '${automationAccountName}/${unmanagedDisksRecommendationJobId}'
  location: projectLocation
  properties: {
    schedule: {
      name: recommendationsScheduleName
    }
    runbook: {
      name: unmanagedDisksRecommendationsRunbookName
    }
  }
  dependsOn: [
    automationAccountName_resource
    automationAccountName_recommendationsScheduleName
    automationAccountName_psModules_name
    unmanagedDisksRecommendationsRunbookName
  ]
}

resource automationAccountName_availSetsLowFaultDomainRecommendationJobId 'Microsoft.Automation/automationAccounts/jobSchedules@2018-06-30' = {
  name: '${automationAccountName}/${availSetsLowFaultDomainRecommendationJobId}'
  location: projectLocation
  properties: {
    schedule: {
      name: recommendationsScheduleName
    }
    runbook: {
      name: availSetsLowFaultDomainRecommendationsRunbookName
    }
  }
  dependsOn: [
    automationAccountName_resource
    automationAccountName_recommendationsScheduleName
    automationAccountName_psModules_name
    availSetsLowFaultDomainRecommendationsRunbookName
  ]
}

resource automationAccountName_availSetsLowUpdateDomainRecommendationJobId 'Microsoft.Automation/automationAccounts/jobSchedules@2018-06-30' = {
  name: '${automationAccountName}/${availSetsLowUpdateDomainRecommendationJobId}'
  location: projectLocation
  properties: {
    schedule: {
      name: recommendationsScheduleName
    }
    runbook: {
      name: availSetsLowUpdateDomainRecommendationsRunbookName
    }
  }
  dependsOn: [
    automationAccountName_resource
    automationAccountName_recommendationsScheduleName
    automationAccountName_psModules_name
    availSetsLowUpdateDomainRecommendationsRunbookName
  ]
}

resource automationAccountName_availSetsSharingStorageRecommendationJobId 'Microsoft.Automation/automationAccounts/jobSchedules@2018-06-30' = {
  name: '${automationAccountName}/${availSetsSharingStorageRecommendationJobId}'
  location: projectLocation
  properties: {
    schedule: {
      name: recommendationsScheduleName
    }
    runbook: {
      name: availSetsSharingStorageRecommendationsRunbookName
    }
  }
  dependsOn: [
    automationAccountName_resource
    automationAccountName_recommendationsScheduleName
    automationAccountName_psModules_name
    availSetsSharingStorageRecommendationsRunbookName
  ]
}

resource automationAccountName_longDeallocatedVmsRecommendationJobId 'Microsoft.Automation/automationAccounts/jobSchedules@2018-06-30' = {
  name: '${automationAccountName}/${longDeallocatedVmsRecommendationJobId}'
  location: projectLocation
  properties: {
    schedule: {
      name: recommendationsScheduleName
    }
    runbook: {
      name: longDeallocatedVmsRecommendationsRunbookName
    }
  }
  dependsOn: [
    automationAccountName_resource
    automationAccountName_recommendationsScheduleName
    automationAccountName_psModules_name
    longDeallocatedVmsRecommendationsRunbookName
  ]
}

resource automationAccountName_storageAccountsMultipleVmsRecommendationJobId 'Microsoft.Automation/automationAccounts/jobSchedules@2018-06-30' = {
  name: '${automationAccountName}/${storageAccountsMultipleVmsRecommendationJobId}'
  location: projectLocation
  properties: {
    schedule: {
      name: recommendationsScheduleName
    }
    runbook: {
      name: storageAccountsMultipleVmsRecommendationsRunbookName
    }
  }
  dependsOn: [
    automationAccountName_resource
    automationAccountName_recommendationsScheduleName
    automationAccountName_psModules_name
    storageAccountsMultipleVmsRecommendationsRunbookName
  ]
}

resource automationAccountName_vmsNoAvailSetRecommendationJobId 'Microsoft.Automation/automationAccounts/jobSchedules@2018-06-30' = {
  name: '${automationAccountName}/${vmsNoAvailSetRecommendationJobId}'
  location: projectLocation
  properties: {
    schedule: {
      name: recommendationsScheduleName
    }
    runbook: {
      name: vmsNoAvailSetRecommendationsRunbookName
    }
  }
  dependsOn: [
    automationAccountName_resource
    automationAccountName_recommendationsScheduleName
    automationAccountName_psModules_name
    vmsNoAvailSetRecommendationsRunbookName
  ]
}

resource automationAccountName_vmsSingleInAvailSetRecommendationJobId 'Microsoft.Automation/automationAccounts/jobSchedules@2018-06-30' = {
  name: '${automationAccountName}/${vmsSingleInAvailSetRecommendationJobId}'
  location: projectLocation
  properties: {
    schedule: {
      name: recommendationsScheduleName
    }
    runbook: {
      name: vmsSingleInAvailSetRecommendationsRunbookName
    }
  }
  dependsOn: [
    automationAccountName_resource
    automationAccountName_recommendationsScheduleName
    automationAccountName_psModules_name
    vmsSingleInAvailSetRecommendationsRunbookName
  ]
}

resource automationAccountName_vmsDisksMultipleStorageRecommendationJobId 'Microsoft.Automation/automationAccounts/jobSchedules@2018-06-30' = {
  name: '${automationAccountName}/${vmsDisksMultipleStorageRecommendationJobId}'
  location: projectLocation
  properties: {
    schedule: {
      name: recommendationsScheduleName
    }
    runbook: {
      name: vmsDisksMultipleStorageRecommendationsRunbookName
    }
  }
  dependsOn: [
    automationAccountName_resource
    automationAccountName_recommendationsScheduleName
    automationAccountName_psModules_name
    vmsDisksMultipleStorageRecommendationsRunbookName
  ]
}

resource automationAccountName_aadExpiringCredsRecommendationJobId 'Microsoft.Automation/automationAccounts/jobSchedules@2018-06-30' = {
  name: '${automationAccountName}/${aadExpiringCredsRecommendationJobId}'
  location: projectLocation
  properties: {
    schedule: {
      name: recommendationsScheduleName
    }
    runbook: {
      name: aadExpiringCredsRecommendationsRunbookName
    }
  }
  dependsOn: [
    automationAccountName_resource
    automationAccountName_recommendationsScheduleName
    automationAccountName_psModules_name
    aadExpiringCredsRecommendationsRunbookName
  ]
}

resource automationAccountName_unusedLoadBalancersRecommendationJobId 'Microsoft.Automation/automationAccounts/jobSchedules@2018-06-30' = {
  name: '${automationAccountName}/${unusedLoadBalancersRecommendationJobId}'
  location: projectLocation
  properties: {
    schedule: {
      name: recommendationsScheduleName
    }
    runbook: {
      name: unusedLBsRecommendationsRunbookName
    }
  }
  dependsOn: [
    automationAccountName_resource
    automationAccountName_recommendationsScheduleName
    automationAccountName_psModules_name
    unusedLBsRecommendationsRunbookName
  ]
}

resource automationAccountName_unusedAppGWsRecommendationJobId 'Microsoft.Automation/automationAccounts/jobSchedules@2018-06-30' = {
  name: '${automationAccountName}/${unusedAppGWsRecommendationJobId}'
  location: projectLocation
  properties: {
    schedule: {
      name: recommendationsScheduleName
    }
    runbook: {
      name: unusedAppGWsRecommendationsRunbookName
    }
  }
  dependsOn: [
    automationAccountName_resource
    automationAccountName_recommendationsScheduleName
    automationAccountName_psModules_name
    unusedAppGWsRecommendationsRunbookName
  ]
}

resource automationAccountName_recommendationsIngestJobId 'Microsoft.Automation/automationAccounts/jobSchedules@2018-06-30' = {
  name: '${automationAccountName}/${recommendationsIngestJobId}'
  location: projectLocation
  properties: {
    schedule: {
      name: recommendationsIngestScheduleName
    }
    runbook: {
      name: recommendationsIngestRunbookName
    }
  }
  dependsOn: [
    automationAccountName_resource
    automationAccountName_recommendationsIngestScheduleName
    automationAccountName_psModules_name
    recommendationsIngestRunbookName
  ]
}
