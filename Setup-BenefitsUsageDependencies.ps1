param(
    [Parameter(Mandatory = $false)] 
    [String] $AzureEnvironment = "AzureCloud",

    [Parameter(Mandatory = $true)] 
    [String] $AutomationAccountName,

    [Parameter(Mandatory = $true)] 
    [String] $ResourceGroupName
)

$ErrorActionPreference = "Stop"

$ctx = Get-AzContext
if (-not($ctx)) {
    Connect-AzAccount -Environment $AzureEnvironment
    $ctx = Get-AzContext
}
else {
    if ($ctx.Environment.Name -ne $AzureEnvironment) {
        Disconnect-AzAccount -ContextName $ctx.Name
        Connect-AzAccount -Environment $AzureEnvironment
        $ctx = Get-AzContext
    }
}

try {
    $scheduledRunbooks = Get-AzAutomationScheduledRunbook -AutomationAccountName $AutomationAccountName -ResourceGroupName $ResourceGroupName
}
catch {
    throw "$AutomationAccountName Automation Account not found in Resource Group $ResourceGroupName in Subscription $($ctx.Subscription.Name). If we are not in the right subscription, use Set-AzContext to switch to the correct one."    
}

if (-not($scheduledRunbooks)) {
    throw "The $AutomationAccountName Automation Account does not contain any scheduled runbook. It might not be associated to the Azure Optimization Engine."
}

# TODO : Check if the runbooks are the ones from the Azure Optimization Engine

Write-Host "DONE" -ForegroundColor Green