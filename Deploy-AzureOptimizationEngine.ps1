$templateUri = "https://hppfedevopssa.blob.core.windows.net/azureoptimizationengine/azuredeploy.json"
$deploymentName = "aoe01"
$resourceGroupName = "azure-optimization-engine-rg"
$projectName = "optimizationengine"
$location = "westeurope"
$workspace = "helderpintopfe"
$workspaceResourceGroup = "pfe-governance-rg"
$sqlAdmin = "hppfeadmin"
$automationAccountName = "$projectName-auto"
$runasAppName = "$automactionAccountName-runasaccount"

$ErrorActionPreference = "Stop"
$ctx = Get-AzContext
if (-not($ctx))
{
    Connect-AzAccount
    $ctx = Get-AzContext
}

$subscriptionId = $ctx.Subscription.Id

New-AzResourceGroupDeployment -TemplateUri $templateUri -ResourceGroupName $resourceGroupName -Name $deploymentName `
    -projectName $projectName -projectLocation $location -logAnalyticsReuse $true -logAnalyticsWorkspaceName $workspace -sqlAdminLogin $sqlAdmin

$laIdVariableName = "AzureOptimization_LogAnalyticsWorkspaceId"    
$laIdVariable = Get-AzAutomationVariable -ResourceGroupName $resourceGroupName -AutomationAccountName $automationAccountName -Name $laIdVariableName -ErrorAction SilentlyContinue

if ($null -eq $laIdVariable)
{
    $la = Get-AzOperationalInsightsWorkspace -ResourceGroupName $workspaceResourceGroup -Name $workspace
    New-AzAutomationVariable -Name $laIdVariableName -Description "The Log Analytics Workspace ID where optimization data will be ingested." `
        -ResourceGroupName $resourceGroupName -AutomationAccountName $automationAccountName -Value $la.CustomerId.Guid -Encrypted $false
}

$laKeyVariableName = "AzureOptimization_LogAnalyticsWorkspaceKey"    
$laKeyVariable = Get-AzAutomationVariable -ResourceGroupName $resourceGroupName -AutomationAccountName $automationAccountName -Name $laKeyVariableName -ErrorAction SilentlyContinue

if ($null -eq $laKeyVariable)
{
    $keys = Get-AzOperationalInsightsWorkspaceSharedKey -ResourceGroupName $workspaceResourceGroup -Name $workspace
    New-AzAutomationVariable -Name $laKeyVariableName -Description "The shared key for the Log Analytics Workspace where optimization data will be ingested." `
        -ResourceGroupName $resourceGroupName -AutomationAccountName $automationAccountName -Value $keys.PrimarySharedKey -Encrypted $true
}

$runAsConnection = Get-AzAutomationConnection -ResourceGroupName $resourceGroupName -AutomationAccountName $automationAccountName -Name "AzureRunAsConnection"

if ($null -eq $runAsConnection)
{
    $certPass = Read-Host "Please, input the Run As cert password" -AsSecureString

    .\New-RunAsAccount.ps1 -ResourceGroup $resourceGroupName -AutomationAccountName $automationAccountName -SubscriptionId $subscriptionId `
        -ApplicationDisplayName $runasAppName -SelfSignedCertPlainPassword $certPass -CreateClassicRunAsAccount $false
}