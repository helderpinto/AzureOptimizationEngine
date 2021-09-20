param(
    [Parameter(Mandatory = $false)]
    [string] $TargetSubscription = $null,

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
$referenceRegion = Get-AutomationVariable -Name "AzureOptimization_ReferenceRegion" -ErrorAction SilentlyContinue # e.g., westeurope
if ([string]::IsNullOrEmpty($referenceRegion))
{
    $referenceRegion = "westeurope"
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
$storageAccountSinkContainer = Get-AutomationVariable -Name  "AzureOptimization_PolicyStatesContainer" -ErrorAction SilentlyContinue
if ([string]::IsNullOrEmpty($storageAccountSinkContainer))
{
    $storageAccountSinkContainer = "policystateexports"
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

$allpolicyStates = @()

Write-Output "Getting subscriptions target $TargetSubscription"
if (-not([string]::IsNullOrEmpty($TargetSubscription)))
{
    $subscriptions = $TargetSubscription
    $subscriptionSuffix = $TargetSubscription
}
else
{
    $subscriptions = Get-AzSubscription | Where-Object { $_.State -eq "Enabled" } | ForEach-Object { "$($_.Id)"}
    $subscriptionSuffix = $cloudSuffix + "all-" + $tenantId
}

Write-Output "Building Policy display names..."

$policyAssignments = @{}
$policyInitiatives = @{}
$policyDefinitions = @{}

foreach ($sub in $subscriptions)
{
    Select-AzSubscription -SubscriptionId $sub | Out-Null
    $assignments = Get-AzPolicyAssignment -IncludeDescendent
    foreach ($assignment in $assignments)
    {
        if (-not($policyAssignments[$assignment.PolicyAssignmentId]))
        {
            $policyAssignments.Add($assignment.PolicyAssignmentId, $assignment.Properties.DisplayName)
        }
    }

    $initiatives = Get-AzPolicySetDefinition
    foreach ($initiative in $initiatives)
    {
        if (-not($policyInitiatives[$initiative.PolicySetDefinitionId]))
        {
            $policyInitiatives.Add($initiative.PolicySetDefinitionId, $initiative.Properties.DisplayName)
        }
    }

    $definitions = Get-AzPolicyDefinition
    foreach ($definition in $definitions)
    {
        if (-not($policyDefinitions[$definition.PolicyDefinitionId]))
        {
            $policyDefinitions.Add($definition.PolicyDefinitionId, $definition.Properties.DisplayName)
        }
    }
}

$policyStatesTotal = @()

$resultsSoFar = 0

Write-Output "Querying for Policy states"

$argQuery = @"
policyresources
| extend effect = tostring(properties.policyDefinitionAction)
| extend assignmentId = tolower(properties.policyAssignmentId)
| extend definitionId = tolower(properties.policyDefinitionId)
| extend definitionReferenceId = tolower(properties.policyDefinitionReferenceId)
| extend initiativeId = tolower(properties.policySetDefinitionId)
| extend complianceState = tostring(properties.complianceState)
| extend complianceReason = tostring(properties.complianceReasonCode)
| extend resourceId = tolower(properties.resourceId)
| extend resourceType = tostring(properties.resourceType)
| extend evaluatedOn = tostring(properties.timestamp)
| where complianceState != 'Compliant' and complianceReason !contains 'ResourceNotFound'
| summarize StatesCount = count() by id, tenantId, subscriptionId, resourceGroup, resourceId, resourceType, complianceState, complianceReason, effect, assignmentId, definitionReferenceId, definitionId, initiativeId, evaluatedOn
| union ( policyresources
	| extend effect = tostring(properties.policyDefinitionAction)
	| extend assignmentId = tolower(properties.policyAssignmentId)
	| extend definitionId = tolower(properties.policyDefinitionId)
	| extend definitionReferenceId = tolower(properties.policyDefinitionReferenceId)
	| extend initiativeId = tolower(properties.policySetDefinitionId)
	| extend complianceState = tostring(properties.complianceState)
	| extend resourceType = tostring(properties.resourceType)
	| extend evaluatedOn = tostring(properties.timestamp)
	| where complianceState == 'Compliant'
	| summarize StatesCount = count() by tenantId, subscriptionId, complianceState, effect, assignmentId, definitionReferenceId, definitionId, initiativeId
)
| order by id asc
"@

do
{
    if ($resultsSoFar -eq 0)
    {
        $policyStates = Search-AzGraph -Query $argQuery -First $ARGPageSize -Subscription $subscriptions
    }
    else
    {
        $policyStates = Search-AzGraph -Query $argQuery -First $ARGPageSize -Skip $resultsSoFar -Subscription $subscriptions
    }
    if ($policyStates -and $policyStates.GetType().Name -eq "PSResourceGraphResponse")
    {
        $policyStates = $policyStates.Data
    }
    $resultsCount = $policyStates.Count
    $resultsSoFar += $resultsCount
    $policyStatesTotal += $policyStates

} while ($resultsCount -eq $ARGPageSize)

$datetime = (Get-Date).ToUniversalTime()
$timestamp = $datetime.ToString("yyyy-MM-ddTHH:mm:00.000Z")
$statusDate = $datetime.ToString("yyyy-MM-dd")

Write-Output "Building $($policyStatesTotal.Count) policyState entries"

foreach ($policyState in $policyStatesTotal)
{
    $resourceGroup = $null
    if ($policyState.resourceGroup)
    {
        $resourceGroup = $policyState.resourceGroup.ToLower()
    }

    $logentry = New-Object PSObject -Property @{
        Timestamp = $timestamp
        Cloud = $cloudEnvironment
        TenantGuid = $policyState.tenantId
        SubscriptionGuid = $policyState.subscriptionId
        ResourceGroupName = $resourceGroup
        ResourceId = $policyState.resourceId
        ResourceType = $policyState.resourceType
        ComplianceState = $policyState.complianceState
        ComplianceReason = $policyState.complianceReason
        Effect = $policyState.effect
        AssignmentId = $policyState.assignmentId
        AssignmentName = $policyAssignments[$policyState.assignmentId]
        InitiativeId = $policyState.initiativeId
        InitiativeName = $policyInitiatives[$policyState.initiativeId]
        DefinitionId = $policyState.definitionId
        DefinitionName = $policyDefinitions[$policyState.definitionId]
        DefinitionReferenceId = $policyState.definitionReferenceId
        EvaluatedOn = $policyState.evaluatedOn
        StatesCount = $policyState.StatesCount
        StatusDate = $statusDate
    }
    
    $allpolicyStates += $logentry
}

Write-Output "Uploading CSV to Storage"

$today = $datetime.ToString("yyyyMMdd")
$csvExportPath = "$today-policyStates-$subscriptionSuffix.csv"

$allpolicyStates | Export-Csv -Path $csvExportPath -NoTypeInformation

$csvBlobName = $csvExportPath

$csvProperties = @{"ContentType" = "text/csv"};

Set-AzStorageBlobContent -File $csvExportPath -Container $storageAccountSinkContainer -Properties $csvProperties -Blob $csvBlobName -Context $sa.Context -Force

Write-Output "DONE"