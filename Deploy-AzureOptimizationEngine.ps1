$templateUri = "https://hppfedevopssa.blob.core.windows.net/azureoptimizationengine/azuredeploy.json"
$deploymentName = "aoe04"
$resourceGroupName = "azure-optimization-engine-rg"
$projectName = "optimizationengine"
$location = "westeurope"
$workspace = "helderpintopfe"
$workspaceResourceGroup = "pfe-governance-rg"
$sqlAdmin = "hppfeadmin"
$automationAccountName = "$projectName-auto"
$runasAppName = "$automactionAccountName-runasaccount"
$sqlServerName = "$projectName-sql.database.windows.net"
$databaseName = "azureoptimization"

$ErrorActionPreference = "Stop"
$ctx = Get-AzContext
if (-not($ctx))
{
    Connect-AzAccount
    $ctx = Get-AzContext
}

$subscriptionId = $ctx.Subscription.Id

$sqlPass = Read-Host "Please, input the SQL Admin password" -AsSecureString

$myPublicIp = (Invoke-WebRequest -uri "http://ifconfig.me/ip").Content

New-AzResourceGroupDeployment -TemplateUri $templateUri -ResourceGroupName $resourceGroupName -Name $deploymentName `
    -projectName $projectName -projectLocation $location -logAnalyticsReuse $true -logAnalyticsWorkspaceName $workspace `
    -sqlAdminLogin $sqlAdmin -sqlAdminPassword $sqlPass -outboundPublicIp $myPublicIp

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

$bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($sqlPass)
$sqlPassPlain = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr)

$SqlTimeout = 60
$tries = 0
$connectionSuccess = $false
do {
    $tries++
    try {


        $Conn = New-Object System.Data.SqlClient.SqlConnection("Server=tcp:$sqlServerName,1433;Database=$databaseName;User ID=$sqlAdmin;Password=$sqlPassPlain;Trusted_Connection=False;Encrypt=True;Connection Timeout=$SqlTimeout;") 
        $Conn.Open() 

        $createTableQuery = Get-Content -Path ".\model\loganalyticsingestcontrol-table.sql"
        $Cmd=new-object system.Data.SqlClient.SqlCommand
        $Cmd.Connection = $Conn
        $Cmd.CommandTimeout = $SqlTimeout
        $Cmd.CommandText = $createTableQuery
        $Cmd.ExecuteReader()
        $Conn.Close()

        $Conn = New-Object System.Data.SqlClient.SqlConnection("Server=tcp:$sqlServerName,1433;Database=$databaseName;User ID=$sqlAdmin;Password=$sqlPassPlain;Trusted_Connection=False;Encrypt=True;Connection Timeout=$SqlTimeout;") 
        $Conn.Open() 

        $initTableQuery = Get-Content -Path ".\model\loganalyticsingestcontrol-initialize.sql"
        $Cmd=new-object system.Data.SqlClient.SqlCommand
        $Cmd.Connection = $Conn
        $Cmd.CommandTimeout = $SqlTimeout
        $Cmd.CommandText = $initTableQuery
        $Cmd.ExecuteReader()
        $Conn.Close()

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
