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

@description('GUID for the NIC Export job schedule creation - create a unique before deploy')
param argNICExportJobId string = newGuid()

@description('GUID for the NSG Export job schedule creation - create a unique before deploy')
param argNSGExportJobId string = newGuid()

@description('GUID for the Public IP Export job schedule creation - create a unique before deploy')
param argPublicIPExportJobId string = newGuid()

@description('GUID for the VNet Export job schedule creation - create a unique before deploy')
param argVNetExportJobId string = newGuid()

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

@description('GUID for the NIC Ingest job schedule creation - create a unique before deploy')
param argNICIngestJobId string = newGuid()

@description('GUID for the NSG Ingest job schedule creation - create a unique before deploy')
param argNSGIngestJobId string = newGuid()

@description('GUID for the Public IP Ingest job schedule creation - create a unique before deploy')
param argPublicIPIngestJobId string = newGuid()

@description('GUID for the VNet Ingest job schedule creation - create a unique before deploy')
param argVNetIngestJobId string = newGuid()

@description('GUID for the Unattached Disks Recommendation Generation job schedule creation - create a unique before deploy')
param unattachedDisksRecommendationJobId string = newGuid()

@description('GUID for the Augmented Advisor Cost Recommendation Generation job schedule creation - create a unique before deploy')
param advisorCostAugmentedRecommendationJobId string = newGuid()

@description('GUID for the Advisor General Recommendations Generation job schedule creation - create a unique before deploy')
param advisorAsIsRecommendationJobId string = newGuid()

@description('GUID for the VMs High Availability Recommendation Generation job schedule creation - create a unique before deploy')
param vmsHaRecommendationJobId string = newGuid()

@description('GUID for the Long Deallocated VMs Recommendation Generation job schedule creation - create a unique before deploy')
param longDeallocatedVmsRecommendationJobId string = newGuid()

@description('GUID for the AAD Objects with Expiring Credentials Recommendation Generation job schedule creation - create a unique before deploy')
param aadExpiringCredsRecommendationJobId string = newGuid()

@description('GUID for the Unused Load Balancers Recommendation Generation job schedule creation - create a unique before deploy')
param unusedLoadBalancersRecommendationJobId string = newGuid()

@description('GUID for the Unused Application Gateways Recommendation Generation job schedule creation - create a unique before deploy')
param unusedAppGWsRecommendationJobId string = newGuid()

@description('GUID for the ARM Optimizations Recommendation Generation job schedule creation - create a unique before deploy')
param armOptimizationsRecommendationJobId string = newGuid()

@description('GUID for the VNet Optimizations Recommendation Generation job schedule creation - create a unique before deploy')
param vnetOptimizationsRecommendationJobId string = newGuid()

@description('GUID for the Recommendations Ingest job schedule creation - create a unique before deploy')
param recommendationsIngestJobId string = newGuid()

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
var argNICExportsRunbookName = 'Export-ARGNICPropertiesToBlobStorage'
var argNSGExportsRunbookName = 'Export-ARGNSGPropertiesToBlobStorage'
var argVNetExportsRunbookName = 'Export-ARGVNetPropertiesToBlobStorage'
var argPublicIpExportsRunbookName = 'Export-ARGPublicIpPropertiesToBlobStorage'
var advisorExportsScheduleName = 'AzureOptimization_ExportAdvisorWeekly'
var argExportsScheduleName = 'AzureOptimization_ExportARGDaily'
var consumptionExportsScheduleName = 'AzureOptimization_ExportConsumptionDaily'
var aadObjectsExportsScheduleName = 'AzureOptimization_ExportAADObjectsDaily'
var rbacExportsScheduleName = 'AzureOptimization_ExportRBACDaily'
var csvExportsSchedules = [
  {
    exportSchedule: argExportsScheduleName
    exportDescription: 'Daily Azure Resource Graph exports'
    exportTimeOffset: 'PT1H'
    exportFrequency: 'Day'
  }
  {
    exportSchedule: advisorExportsScheduleName
    exportDescription: 'Weekly Azure Advisor exports'
    exportTimeOffset: 'PT1H15M'
    exportFrequency: 'Week'
  }
  {
    exportSchedule: consumptionExportsScheduleName
    exportDescription: 'Daily Azure Consumption exports'
    exportTimeOffset: 'PT1H'
    exportFrequency: 'Day'
  }
  {
    exportSchedule: aadObjectsExportsScheduleName
    exportDescription: 'Daily Azure AD Objects exports'
    exportTimeOffset: 'PT1H'
    exportFrequency: 'Day'
  }
  {
    exportSchedule: rbacExportsScheduleName
    exportDescription: 'Daily Azure RBAC exports'
    exportTimeOffset: 'PT1H'
    exportFrequency: 'Day'
  }
]
var csvExports = [
  {
    runbookName: advisorExportsRunbookName
    containerName: 'advisorexports'
    variableName: 'AzureOptimization_AdvisorContainer'
    variableDescription: 'The Storage Account container where Azure Advisor exports are dumped to'
    ingestSchedule: 'AzureOptimization_IngestAdvisorWeekly'
    ingestDescription: 'Weekly Azure Advisor recommendations ingests'
    ingestTimeOffset: 'PT1H45M'
    ingestFrequency: 'Week'
    ingestJobId: advisorIngestJobId
    exportSchedule: advisorExportsScheduleName
    exportJobId: advisorExportJobId
  }
  {
    runbookName: argVmExportsRunbookName
    containerName: 'argvmexports'
    variableName: 'AzureOptimization_ARGVMContainer'
    variableDescription: 'The Storage Account container where Azure Resource Graph Virtual Machine exports are dumped to'
    ingestSchedule: 'AzureOptimization_IngestARGVMsDaily'
    ingestDescription: 'Daily Azure Resource Graph Virtual Machines ingests'
    ingestTimeOffset: 'PT1H30M'
    ingestFrequency: 'Day'
    ingestJobId: argVmIngestJobId
    exportSchedule: argExportsScheduleName
    exportJobId: argVmExportJobId
  }
  {
    runbookName: argDisksExportsRunbookName
    containerName: 'argdiskexports'
    variableName: 'AzureOptimization_ARGDiskContainer'
    variableDescription: 'The Storage Account container where Azure Resource Graph Managed Disks exports are dumped to'
    ingestSchedule: 'AzureOptimization_IngestARGDisksDaily'
    ingestDescription: 'Daily Azure Resource Graph Managed Disks ingests'
    ingestTimeOffset: 'PT1H30M'
    ingestFrequency: 'Day'
    ingestJobId: argDiskIngestJobId
    exportSchedule: argExportsScheduleName
    exportJobId: argDiskExportJobId
  }
  {
    runbookName: argVhdExportsRunbookName
    containerName: 'argvhdexports'
    variableName: 'AzureOptimization_ARGVhdContainer'
    variableDescription: 'The Storage Account container where Azure Resource Graph Unmanaged Disks exports are dumped to'
    ingestSchedule: 'AzureOptimization_IngestARGVHDsDaily'
    ingestDescription: 'Daily Azure Resource Graph Unmanaged Disks ingests'
    ingestTimeOffset: 'PT1H30M'
    ingestFrequency: 'Day'
    ingestJobId: argVhdIngestJobId
    exportSchedule: argExportsScheduleName
    exportJobId: argVhdExportJobId
  }
  {
    runbookName: argAvailSetExportsRunbookName
    containerName: 'argavailsetexports'
    variableName: 'AzureOptimization_ARGAvailabilitySetContainer'
    variableDescription: 'The Storage Account container where Azure Resource Graph Availability Set exports are dumped to'
    ingestSchedule: 'AzureOptimization_IngestARGAvailSetsDaily'
    ingestDescription: 'Daily Azure Resource Graph Availability Sets ingests'
    ingestTimeOffset: 'PT1H30M'
    ingestFrequency: 'Day'
    ingestJobId: argAvailSetIngestJobId
    exportSchedule: argExportsScheduleName
    exportJobId: argAvailSetExportJobId
  }
  {
    runbookName: consumptionExportsRunbookName
    containerName: 'consumptionexports'
    variableName: 'AzureOptimization_ConsumptionContainer'
    variableDescription: 'The Storage Account container where Azure Consumption exports are dumped to'
    ingestSchedule: 'AzureOptimization_IngestConsumptionDaily'
    ingestDescription: 'Daily Azure Consumption ingests'
    ingestTimeOffset: 'PT2H'
    ingestFrequency: 'Day'
    ingestJobId: consumptionIngestJobId
    exportSchedule: consumptionExportsScheduleName
    exportJobId: consumptionExportJobId
  }
  {
    runbookName: aadObjectsExportsRunbookName
    containerName: 'aadobjectsexports'
    variableName: 'AzureOptimization_AADObjectsContainer'
    variableDescription: 'The Storage Account container where Azure AD Objects exports are dumped to'
    ingestSchedule: 'AzureOptimization_IngestAADObjectsDaily'
    ingestDescription: 'Daily Azure AD Objects ingests'
    ingestTimeOffset: 'PT2H'
    ingestFrequency: 'Day'
    ingestJobId: aadObjectsIngestJobId
    exportSchedule: aadObjectsExportsScheduleName
    exportJobId: aadObjectsExportJobId
  }
  {
    runbookName: argLoadBalancersExportsRunbookName
    containerName: 'arglbexports'
    variableName: 'AzureOptimization_ARGLoadBalancerContainer'
    variableDescription: 'The Storage Account container where Azure Resource Graph Load Balancer exports are dumped to'
    ingestSchedule: 'AzureOptimization_IngestARGLoadBalancersDaily'
    ingestDescription: 'Daily Azure Resource Graph Load Balancers ingests'
    ingestTimeOffset: 'PT1H30M'
    ingestFrequency: 'Day'
    ingestJobId: argLoadBalancersIngestJobId
    exportSchedule: argExportsScheduleName
    exportJobId: argLoadBalancersExportJobId
  }
  {
    runbookName: argAppGWsExportsRunbookName
    containerName: 'argappgwexports'
    variableName: 'AzureOptimization_ARGAppGatewayContainer'
    variableDescription: 'The Storage Account container where Azure Resource Graph Application Gateway exports are dumped to'
    ingestSchedule: 'AzureOptimization_IngestARGAppGWsDaily'
    ingestDescription: 'Daily Azure Resource Graph Application Gateways ingests'
    ingestTimeOffset: 'PT1H30M'
    ingestFrequency: 'Day'
    ingestJobId: argAppGWsIngestJobId
    exportSchedule: argExportsScheduleName
    exportJobId: argAppGWsExportJobId
  }
  {
    runbookName: argResContainersExportsRunbookName
    containerName: 'argrescontainersexports'
    variableName: 'AzureOptimization_ARGResourceContainersContainer'
    variableDescription: 'The Storage Account container where Azure Resource Graph Resource Containers exports are dumped to'
    ingestSchedule: 'AzureOptimization_IngestARGResourceContainersDaily'
    ingestDescription: 'Daily Azure Resource Graph Resource Containers ingests'
    ingestTimeOffset: 'PT1H30M'
    ingestFrequency: 'Day'
    ingestJobId: argResContainersIngestJobId
    exportSchedule: argExportsScheduleName
    exportJobId: argResContainersExportJobId
  }
  {
    runbookName: rbacExportsRunbookName
    containerName: 'rbacexports'
    variableName: 'AzureOptimization_RBACAssignmentsContainer'
    variableDescription: 'The Storage Account container where RBAC Assignments exports are dumped to'
    ingestSchedule: 'AzureOptimization_IngestRBACDaily'
    ingestDescription: 'Daily Azure RBAC ingests'
    ingestTimeOffset: 'PT1H30M'
    ingestFrequency: 'Day'
    ingestJobId: rbacIngestJobId
    exportSchedule: rbacExportsScheduleName
    exportJobId: rbacExportJobId
  }
  {
    runbookName: argNICExportsRunbookName
    containerName: 'argnicexports'
    variableName: 'AzureOptimization_ARGNICContainer'
    variableDescription: 'The Storage Account container where Azure Resource Graph NIC exports are dumped to'
    ingestSchedule: 'AzureOptimization_IngestARGNICsDaily'
    ingestDescription: 'Daily Azure Resource Graph NIC ingests'
    ingestTimeOffset: 'PT1H30M'
    ingestFrequency: 'Day'
    ingestJobId: argNICIngestJobId
    exportSchedule: argExportsScheduleName
    exportJobId: argNICExportJobId
  }
  {
    runbookName: argNSGExportsRunbookName
    containerName: 'argnsgexports'
    variableName: 'AzureOptimization_ARGNSGContainer'
    variableDescription: 'The Storage Account container where Azure Resource Graph NSG exports are dumped to'
    ingestSchedule: 'AzureOptimization_IngestARGNSGsDaily'
    ingestDescription: 'Daily Azure Resource Graph NSG ingests'
    ingestTimeOffset: 'PT1H30M'
    ingestFrequency: 'Day'
    ingestJobId: argNSGIngestJobId
    exportSchedule: argExportsScheduleName
    exportJobId: argNSGExportJobId
  }
  {
    runbookName: argVNetExportsRunbookName
    containerName: 'argvnetexports'
    variableName: 'AzureOptimization_ARGVNetContainer'
    variableDescription: 'The Storage Account container where Azure Resource Graph VNet exports are dumped to'
    ingestSchedule: 'AzureOptimization_IngestARGVNetsDaily'
    ingestDescription: 'Daily Azure Resource Graph Virtual Network ingests'
    ingestTimeOffset: 'PT1H30M'
    ingestFrequency: 'Day'
    ingestJobId: argVNetIngestJobId
    exportSchedule: argExportsScheduleName
    exportJobId: argVNetExportJobId
  }
  {
    runbookName: argPublicIpExportsRunbookName
    containerName: 'argpublicipexports'
    variableName: 'AzureOptimization_ARGPublicIpContainer'
    variableDescription: 'The Storage Account container where Azure Resource Graph Public IP exports are dumped to'
    ingestSchedule: 'AzureOptimization_IngestARGPublicIPsDaily'
    ingestDescription: 'Daily Azure Resource Graph Public IP ingests'
    ingestTimeOffset: 'PT1H30M'
    ingestFrequency: 'Day'
    ingestJobId: argPublicIPIngestJobId
    exportSchedule: argExportsScheduleName
    exportJobId: argPublicIPExportJobId
  }
]
var unattachedDisksRecommendationsRunbookName = 'Recommend-UnattachedDisksToBlobStorage'
var advisorCostAugmentedRecommendationsRunbookName = 'Recommend-AdvisorCostAugmentedToBlobStorage'
var advisorAsIsRecommendationsRunbookName = 'Recommend-AdvisorAsIsToBlobStorage'
var vmsHARecommendationsRunbookName = 'Recommend-VMsHighAvailabilityToBlobStorage'
var longDeallocatedVmsRecommendationsRunbookName = 'Recommend-LongDeallocatedVmsToBlobStorage'
var aadExpiringCredsRecommendationsRunbookName = 'Recommend-AADExpiringCredentialsToBlobStorage'
var unusedLBsRecommendationsRunbookName = 'Recommend-UnusedLoadBalancersToBlobStorage'
var unusedAppGWsRecommendationsRunbookName = 'Recommend-UnusedAppGWsToBlobStorage'
var armOptimizationsRecommendationsRunbookName = 'Recommend-ARMOptimizationsToBlobStorage'
var vnetOptimizationsRecommendationsRunbookName = 'Recommend-VNetOptimizationsToBlobStorage'
var recommendations = [
  {
    recommendationJobId: unattachedDisksRecommendationJobId
    runbookName: unattachedDisksRecommendationsRunbookName
  }
  {
    recommendationJobId: advisorCostAugmentedRecommendationJobId
    runbookName: advisorCostAugmentedRecommendationsRunbookName
  }
  {
    recommendationJobId: advisorAsIsRecommendationJobId
    runbookName: advisorAsIsRecommendationsRunbookName
  }
  {
    recommendationJobId: vmsHaRecommendationJobId
    runbookName: vmsHARecommendationsRunbookName
  }
  {
    recommendationJobId: longDeallocatedVmsRecommendationJobId
    runbookName: longDeallocatedVmsRecommendationsRunbookName
  }
  {
    recommendationJobId: aadExpiringCredsRecommendationJobId
    runbookName: aadExpiringCredsRecommendationsRunbookName
  }
  {
    recommendationJobId: unusedLoadBalancersRecommendationJobId
    runbookName: unusedLBsRecommendationsRunbookName
  }
  {
    recommendationJobId: unusedAppGWsRecommendationJobId
    runbookName: unusedAppGWsRecommendationsRunbookName
  }
  {
    recommendationJobId: armOptimizationsRecommendationJobId
    runbookName: armOptimizationsRecommendationsRunbookName
  }
  {
    recommendationJobId: vnetOptimizationsRecommendationJobId
    runbookName: vnetOptimizationsRecommendationsRunbookName
  }
]
var remediationLogsContainerName = 'remediationlogs'
var recommendationsContainerName = 'recommendationsexports'
var csvIngestRunbookName = 'Ingest-OptimizationCSVExportsToLogAnalytics'
var recommendationsIngestRunbookName = 'Ingest-RecommendationsToSQLServer'
var advisorRightSizeFilteredRemediationRunbookName = 'Remediate-AdvisorRightSizeFiltered'
var longDeallocatedVMsFilteredRemediationRunbookName = 'Remediate-LongDeallocatedVMsFiltered'
var unattachedDisksFilteredRemediationRunbookName = 'Remediate-UnattachedDisksFiltered'
var remediationLogsIngestScheduleName = 'AzureOptimization_IngestRemediationLogsDaily'
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
  url: 'https://www.powershellgallery.com/api/v2/package/Az.Accounts/2.5.2'
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
    url: 'https://www.powershellgallery.com/api/v2/package/Az.Compute/4.16.0'
  }
  {
    name: 'Az.OperationalInsights'
    url: 'https://www.powershellgallery.com/api/v2/package/Az.OperationalInsights/2.3.0'
  }
  {
    name: 'Az.ResourceGraph'
    url: 'https://www.powershellgallery.com/api/v2/package/Az.ResourceGraph/0.11.0'
  }
  {
    name: 'Az.Storage'
    url: 'https://www.powershellgallery.com/api/v2/package/Az.Storage/3.10.0'
  }
  {
    name: 'Az.Resources'
    url: 'https://www.powershellgallery.com/api/v2/package/Az.Resources/4.3.0'
  }
  {
    name: 'Az.Monitor'
    url: 'https://www.powershellgallery.com/api/v2/package/Az.Monitor/2.7.0'
  }
  {
    name: 'AzureADPreview'
    url: 'https://www.powershellgallery.com/api/v2/package/AzureADPreview/2.0.2.138'
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
    version: '1.3.2.0'
    description: 'Exports Managed Disks properties to Blob Storage using Azure Resource Graph'
    type: 'PowerShell'
    scriptUri: uri(artifactsLocation, 'runbooks/data-collection/${argDisksExportsRunbookName}.ps1${artifactsLocationSasToken}')
  }
  {
    name: argVhdExportsRunbookName
    version: '1.1.2.0'
    description: 'Exports Unmanaged Disks (owned by a VM) properties to Blob Storage using Azure Resource Graph'
    type: 'PowerShell'
    scriptUri: uri(artifactsLocation, 'runbooks/data-collection/${argVhdExportsRunbookName}.ps1${artifactsLocationSasToken}')
  }
  {
    name: argVmExportsRunbookName
    version: '1.4.2.0'
    description: 'Exports Virtual Machine properties to Blob Storage using Azure Resource Graph'
    type: 'PowerShell'
    scriptUri: uri(artifactsLocation, 'runbooks/data-collection/${argVmExportsRunbookName}.ps1${artifactsLocationSasToken}')
  }
  {
    name: argAvailSetExportsRunbookName
    version: '1.1.2.0'
    description: 'Exports Availability Set properties to Blob Storage using Azure Resource Graph'
    type: 'PowerShell'
    scriptUri: uri(artifactsLocation, 'runbooks/data-collection/${argAvailSetExportsRunbookName}.ps1${artifactsLocationSasToken}')
  }
  {
    name: consumptionExportsRunbookName
    version: '1.1.1.0'
    description: 'Exports Azure Consumption events to Blob Storage using Azure Consumption API'
    type: 'PowerShell'
    scriptUri: uri(artifactsLocation, 'runbooks/data-collection/${consumptionExportsRunbookName}.ps1${artifactsLocationSasToken}')
  }
  {
    name: aadObjectsExportsRunbookName
    version: '1.1.2.0'
    description: 'Exports Azure AAD Objects to Blob Storage using Azure ARM API'
    type: 'PowerShell'
    scriptUri: uri(artifactsLocation, 'runbooks/data-collection/${aadObjectsExportsRunbookName}.ps1${artifactsLocationSasToken}')
  }
  {
    name: argLoadBalancersExportsRunbookName
    version: '1.1.2.0'
    description: 'Exports Load Balancer properties to Blob Storage using Azure Resource Graph'
    type: 'PowerShell'
    scriptUri: uri(artifactsLocation, 'runbooks/data-collection/${argLoadBalancersExportsRunbookName}.ps1${artifactsLocationSasToken}')
  }
  {
    name: argAppGWsExportsRunbookName
    version: '1.1.2.0'
    description: 'Exports Application Gateway properties to Blob Storage using Azure Resource Graph'
    type: 'PowerShell'
    scriptUri: uri(artifactsLocation, 'runbooks/data-collection/${argAppGWsExportsRunbookName}.ps1${artifactsLocationSasToken}')
  }
  {
    name: argResContainersExportsRunbookName
    version: '1.0.2.0'
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
    name: argNICExportsRunbookName
    version: '1.0.0.0'
    description: 'Exports NIC properties to Blob Storage using Azure Resource Graph'
    type: 'PowerShell'
    scriptUri: uri(artifactsLocation, 'runbooks/data-collection/${argNICExportsRunbookName}.ps1${artifactsLocationSasToken}')
  }
  {
    name: argNSGExportsRunbookName
    version: '1.0.0.0'
    description: 'Exports NSG properties to Blob Storage using Azure Resource Graph'
    type: 'PowerShell'
    scriptUri: uri(artifactsLocation, 'runbooks/data-collection/${argNSGExportsRunbookName}.ps1${artifactsLocationSasToken}')
  }
  {
    name: argPublicIpExportsRunbookName
    version: '1.0.0.0'
    description: 'Exports Public IP properties to Blob Storage using Azure Resource Graph'
    type: 'PowerShell'
    scriptUri: uri(artifactsLocation, 'runbooks/data-collection/${argPublicIpExportsRunbookName}.ps1${artifactsLocationSasToken}')
  }
  {
    name: argVNetExportsRunbookName
    version: '1.0.0.0'
    description: 'Exports VNet properties to Blob Storage using Azure Resource Graph'
    type: 'PowerShell'
    scriptUri: uri(artifactsLocation, 'runbooks/data-collection/${argVNetExportsRunbookName}.ps1${artifactsLocationSasToken}')
  }
  {
    name: csvIngestRunbookName
    version: '1.4.4.0'
    description: 'Ingests CSV blobs as custom logs to Log Analytics'
    type: 'PowerShell'
    scriptUri: uri(artifactsLocation, 'runbooks/data-collection/${csvIngestRunbookName}.ps1${artifactsLocationSasToken}')
  }
  {
    name: unattachedDisksRecommendationsRunbookName
    version: '2.4.4.0'
    description: 'Generates unattached disks recommendations'
    type: 'PowerShell'
    scriptUri: uri(artifactsLocation, 'runbooks/recommendations/${unattachedDisksRecommendationsRunbookName}.ps1${artifactsLocationSasToken}')
  }
  {
    name: advisorCostAugmentedRecommendationsRunbookName
    version: '2.8.3.0'
    description: 'Generates augmented Advisor Cost recommendations'
    type: 'PowerShell'
    scriptUri: uri(artifactsLocation, 'runbooks/recommendations/${advisorCostAugmentedRecommendationsRunbookName}.ps1${artifactsLocationSasToken}')
  }
  {
    name: advisorAsIsRecommendationsRunbookName
    version: '1.5.3.0'
    description: 'Generates all types of Advisor recommendations'
    type: 'PowerShell'
    scriptUri: uri(artifactsLocation, 'runbooks/recommendations/${advisorAsIsRecommendationsRunbookName}.ps1${artifactsLocationSasToken}')
  }
  {
    name: vmsHARecommendationsRunbookName
    version: '1.0.0.0'
    description: 'Generates VMs High Availability recommendations'
    type: 'PowerShell'
    scriptUri: uri(artifactsLocation, 'runbooks/recommendations/${vmsHARecommendationsRunbookName}.ps1${artifactsLocationSasToken}')
  }
  {
    name: longDeallocatedVmsRecommendationsRunbookName
    version: '1.2.3.0'
    description: 'Generates long deallocated VMs recommendations'
    type: 'PowerShell'
    scriptUri: uri(artifactsLocation, 'runbooks/recommendations/${longDeallocatedVmsRecommendationsRunbookName}.ps1${artifactsLocationSasToken}')
  }
  {
    name: aadExpiringCredsRecommendationsRunbookName
    version: '1.1.8.0'
    description: 'Generates AAD Objects with expiring credentials recommendations'
    type: 'PowerShell'
    scriptUri: uri(artifactsLocation, 'runbooks/recommendations/${aadExpiringCredsRecommendationsRunbookName}.ps1${artifactsLocationSasToken}')
  }
  {
    name: unusedLBsRecommendationsRunbookName
    version: '1.2.5.0'
    description: 'Generates unused Load Balancers recommendations'
    type: 'PowerShell'
    scriptUri: uri(artifactsLocation, 'runbooks/recommendations/${unusedLBsRecommendationsRunbookName}.ps1${artifactsLocationSasToken}')
  }
  {
    name: unusedAppGWsRecommendationsRunbookName
    version: '1.2.4.0'
    description: 'Generates unused Application Gateways recommendations'
    type: 'PowerShell'
    scriptUri: uri(artifactsLocation, 'runbooks/recommendations/${unusedAppGWsRecommendationsRunbookName}.ps1${artifactsLocationSasToken}')
  }
  {
    name: armOptimizationsRecommendationsRunbookName
    version: '1.0.1.0'
    description: 'Generates ARM optimizations recommendations'
    type: 'PowerShell'
    scriptUri: uri(artifactsLocation, 'runbooks/recommendations/${armOptimizationsRecommendationsRunbookName}.ps1${artifactsLocationSasToken}')
  }
  {
    name: vnetOptimizationsRecommendationsRunbookName
    version: '1.0.0.0'
    description: 'Generates Virtual Network optimizations recommendations'
    type: 'PowerShell'
    scriptUri: uri(artifactsLocation, 'runbooks/recommendations/${vnetOptimizationsRecommendationsRunbookName}.ps1${artifactsLocationSasToken}')
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
    version: '1.2.1.0'
    description: 'Remediates Azure Advisor right-size recommendations given fit and tag filters'
    type: 'PowerShell'
    scriptUri: uri(artifactsLocation, 'runbooks/remediations/${advisorRightSizeFilteredRemediationRunbookName}.ps1${artifactsLocationSasToken}')
  }
  {
    name: longDeallocatedVMsFilteredRemediationRunbookName
    version: '1.0.0.0'
    description: 'Remediates long-deallocated VMs recommendations given fit and tag filters'
    type: 'PowerShell'
    scriptUri: uri(artifactsLocation, 'runbooks/remediations/${longDeallocatedVMsFilteredRemediationRunbookName}.ps1${artifactsLocationSasToken}')
  }
  {
    name: unattachedDisksFilteredRemediationRunbookName
    version: '1.0.0.0'
    description: 'Remediates unattached disks recommendations given fit and tag filters'
    type: 'PowerShell'
    scriptUri: uri(artifactsLocation, 'runbooks/remediations/${unattachedDisksFilteredRemediationRunbookName}.ps1${artifactsLocationSasToken}')
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
    name: 'AzureOptimization_ConsumptionOffsetDays'
    description: 'The offset (in days) for querying for consumption data'
    value: 3
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
    value: 9000
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
    name: 'AzureOptimization_RemediateLongDeallocatedVMsMinFitScore'
    description: 'The minimum fit score for long-deallocated VM remediation'
    value: '"5.0"'
  }
  {
    name: 'AzureOptimization_RemediateLongDeallocatedVMsMinWeeksInARow'
    description: 'The minimum number of weeks in a row required for a long-deallocated VM recommendation to be remediated'
    value: 4
  }
  {
    name: 'AzureOptimization_RecommendationLongDeallocatedVMsId'
    description: 'The long deallocated VM recommendation ID'
    value: '"c320b790-2e58-452a-aa63-7b62c383ad8a"'
  }
  {
    name: 'AzureOptimization_RemediateUnattachedDisksMinFitScore'
    description: 'The minimum fit score for unattached disk remediation'
    value: '"5.0"'
  }
  {
    name: 'AzureOptimization_RemediateUnattachedDisksMinWeeksInARow'
    description: 'The minimum number of weeks in a row required for a unattached disk recommendation to be remediated'
    value: 4
  }
  {
    name: 'AzureOptimization_RemediateUnattachedDisksAction'
    description: 'The action for the unattached disk recommendation to be remediated (Delete or Downsize)'
    value: '"Delete"'
  }
  {
    name: 'AzureOptimization_RecommendationUnattachedDisksId'
    description: 'The unattached disk recommendation ID'
    value: '"c84d5e86-e2d6-4d62-be7c-cecfbd73b0db"'
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
  {
    name: 'AzureOptimization_RecommendationRBACAssignmentsPercentageThreshold'
    description: 'The percentage threshold (used to trigger recommendations) for total RBAC assignments limits'
    value: 80
  }
  {
    name: 'AzureOptimization_RecommendationResourceGroupsPerSubPercentageThreshold'
    description: 'The percentage threshold (used to trigger recommendations) for resource group count limits'
    value: 80
  }
  {
    name: 'AzureOptimization_RecommendationVNetSubnetMaxUsedPercentageThreshold'
    description: 'The percentage threshold (used to trigger recommendations) for maximum subnet address space usage'
    value: 80
  }
  {
    name: 'AzureOptimization_RecommendationVNetSubnetMinUsedPercentageThreshold'
    description: 'The percentage threshold (used to trigger recommendations) for minimum subnet address space usage'
    value: 5
  }
  {
    name: 'AzureOptimization_RecommendationVNetSubnetEmptyMinAgeInDays'
    description: 'The minimum age (in days) for an empty subnet to trigger an NSG rule recommendation'
    value: 30
  }
]

resource logAnalyticsWorkspaceName_resource 'microsoft.operationalinsights/workspaces@2020-08-01' = if (!logAnalyticsReuse) {
  name: logAnalyticsWorkspaceName
  location: projectLocation
  properties: {
    sku: {
      name: 'pergb2018'
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

resource storageAccountName_default_csvExports_containerName 'Microsoft.Storage/storageAccounts/blobServices/containers@2019-06-01' = [for item in csvExports: {
  name: '${storageAccountName}/default/${item.containerName}'
  properties: {
    publicAccess: 'None'
  }
  dependsOn: [
    storageAccountName_default
    storageAccountName_resource
  ]
}]

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

resource automationAccountName_csvExports_variableName 'Microsoft.Automation/automationAccounts/variables@2018-06-30' = [for item in csvExports: {
  name: '${automationAccountName}/${item.variableName}'
  properties: {
    description: item.variableDescription
    value: '"${item.containerName}"'
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

resource automationAccountName_csvExportsSchedules_exportSchedule 'Microsoft.Automation/automationAccounts/schedules@2018-06-30' = [for item in csvExportsSchedules: {
  name: '${automationAccountName}/${item.exportSchedule}'
  properties: {
    description: item.exportDescription
    expiryTime: '31/12/9999 23:59:00'
    isEnabled: true
    startTime: dateTimeAdd(baseTime, item.exportTimeOffset)
    interval: 1
    frequency: item.exportFrequency
  }
  dependsOn: [
    automationAccountName_resource
  ]
}]

resource automationAccountName_csvExports_ingestSchedule 'Microsoft.Automation/automationAccounts/schedules@2018-06-30' = [for item in csvExports: {
  name: '${automationAccountName}/${item.ingestSchedule}'
  properties: {
    description: item.ingestDescription
    expiryTime: '31/12/9999 23:59:00'
    isEnabled: true
    startTime: dateTimeAdd(baseTime, item.ingestTimeOffset)
    interval: 1
    frequency: item.ingestFrequency
  }
  dependsOn: [
    automationAccountName_resource
  ]
}]

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

resource automationAccountName_csvExports_exportJobId 'Microsoft.Automation/automationAccounts/jobSchedules@2018-06-30' = [for item in csvExports: {
  name: '${automationAccountName}/${item.exportJobId}'
  location: projectLocation
  properties: {
    schedule: {
      name: item.exportSchedule
    }
    runbook: {
      name: item.runbookName
    }
  }
  dependsOn: [
    automationAccountName_resource
    automationAccountName_csvExportsSchedules_exportSchedule
    automationAccountName_psModules_name
    automationAccountName_runbooks_name
  ]
}]

resource automationAccountName_csvExports_ingestJobId 'Microsoft.Automation/automationAccounts/jobSchedules@2018-06-30' = [for item in csvExports: {
  name: '${automationAccountName}/${item.ingestJobId}'
  location: projectLocation
  properties: {
    schedule: {
      name: item.ingestSchedule
    }
    runbook: {
      name: csvIngestRunbookName
    }
    parameters: {
      StorageSinkContainer: item.containerName
    }
  }
  dependsOn: [
    automationAccountName_resource
    automationAccountName_csvExports_ingestSchedule
    automationAccountName_psModules_name
    csvIngestRunbookName
  ]
}]

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
    csvIngestRunbookName
  ]
}

resource automationAccountName_recommendations_recommendationJobId 'Microsoft.Automation/automationAccounts/jobSchedules@2018-06-30' = [for item in recommendations: {
  name: '${automationAccountName}/${item.recommendationJobId}'
  location: projectLocation
  properties: {
    schedule: {
      name: recommendationsScheduleName
    }
    runbook: {
      name: item.runbookName
    }
  }
  dependsOn: [
    automationAccountName_resource
    automationAccountName_recommendationsScheduleName
    automationAccountName_psModules_name
    automationAccountName_runbooks_name
  ]
}]

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
