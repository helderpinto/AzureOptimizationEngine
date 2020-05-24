# Make template URI a parameter

$templateUri = "https://hppfedevopssa.blob.core.windows.net/azureoptimizationengine/azuredeploy.json"

$deploymentName = "aoe07"
$resourceGroupName = "azure-optimization-engine-rg"
$location = "westeurope"
$workspace = "helderpintopfe"
$workspaceResourceGroup = "pfe-governance-rg"
$sqlAdmin = "hppfeadmin"
$automationAccountName = "$projectName-auto"
$runasAppName = "$automactionAccountName-runasaccount"
$sqlServerName = "$projectName-sql"
$sqlServerEndpoint = "$projectName-sql.database.windows.net"
$databaseName = "azureoptimization"
$tempFirewallRuleName = "InitialDeployment"

$ErrorActionPreference = "Stop"
if (-not(Get-AzContext))
{
    Connect-AzAccount
}

$subscriptions = Get-AzSubscription

if ($subscriptions.Count -gt 1)
{
    for ($i = 0; $i -lt $subscriptions.Count; $i++)
    {
        Write-Output "[$i] $($subscriptions[$i].Name)"    
    }
    $selectedSubscription = -1
    $lastSubscriptionIndex = $subscriptions.Count - 1
    while ($selectedSubscription -le 0 -or $selectedSubscription -gt $lastSubscriptionIndex)
    {
        Write-Output "---"
        $selectedSubscription = Read-Host "Please, select the target subscription for this deployment [0..$lastSubscriptionIndex]"
    }
}
else
{
    $selectedSubscription = 0
}

$workspaceReuse = $null

do
{
    $nameAvailable = $true
    $namePrefix = Read-Host "Please, enter a unique name prefix for the resource group and all resources created by this deployment (up to 21 characters)"
    if ($null -eq $workspaceReuse)
    {
        $workspaceReuse = Read-Host "Are you going to reuse an existing Log Analytics workspace (Y/N)?"
    }
    
    Write-Output "Checking name prefix availability..."

    $saNameResult = Get-AzStorageAccountNameAvailability -Name ($namePrefix + "sa")
    if (-not($saNameResult.NameAvailable))
    {
        $nameAvailable = $false
        Write-Output "$($saNameResult.Message)"
    }

    if ("N","n" -contains $workspaceReuse)
    {
        $logAnalyticsReuse = $false
        
        $laNameResult = Invoke-WebRequest -Uri "https://portal.loganalytics.io/api/workspaces/IsWorkspaceExists?name=$namePrefix-la"
        if ($laNameResult.Content -eq "true")
        {
            $nameAvailable = $false
            Write-Output "The Log Analytics workspace named $namePrefix-la is already taken."
        }
    }
    else
    {
        $logAnalyticsReuse = $true
    }

    ## SQL Server name availability
    # https://docs.microsoft.com/en-us/rest/api/sql/servers%20-%20name%20availability/checknameavailability
    # https://secureinfra.blog/2019/11/07/test-azure-resource-name-availability/
}
while (-not($nameAvailable))

$continueInput = Read-Host "Deploying Azure Optimization Engine to subscription $($subscriptions[$selectedSubscription].Name). Continue (Y/N)?"
if ("Y","y" -contains $continueInput)
{
    $subscriptionId = $subscriptions[$selectedSubscription].Id

    ## Create Resource Group

    $sqlPass = Read-Host "Please, input the SQL Admin password" -AsSecureString
    
    New-AzResourceGroupDeployment -TemplateUri $templateUri -ResourceGroupName $resourceGroupName -Name $deploymentName `
        -projectName $namePrefix -projectLocation $location -logAnalyticsReuse $logAnalyticsReuse -logAnalyticsWorkspaceName $workspace `
        -sqlAdminLogin $sqlAdmin -sqlAdminPassword $sqlPass
    
    $myPublicIp = (Invoke-WebRequest -uri "http://ifconfig.me/ip").Content
    
    New-AzSqlServerFirewallRule -ResourceGroupName $resourceGroupName -ServerName $sqlServerName -FirewallRuleName $tempFirewallRuleName -StartIpAddress $myPublicIp -EndIpAddress $myPublicIp
    
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
    
    
            $Conn = New-Object System.Data.SqlClient.SqlConnection("Server=tcp:$sqlServerEndpoint,1433;Database=$databaseName;User ID=$sqlAdmin;Password=$sqlPassPlain;Trusted_Connection=False;Encrypt=True;Connection Timeout=$SqlTimeout;") 
            $Conn.Open() 
    
            $createTableQuery = Get-Content -Path ".\model\loganalyticsingestcontrol-table.sql"
            $Cmd=new-object system.Data.SqlClient.SqlCommand
            $Cmd.Connection = $Conn
            $Cmd.CommandTimeout = $SqlTimeout
            $Cmd.CommandText = $createTableQuery
            $Cmd.ExecuteReader()
            $Conn.Close()
    
            $Conn = New-Object System.Data.SqlClient.SqlConnection("Server=tcp:$sqlServerEndpoint,1433;Database=$databaseName;User ID=$sqlAdmin;Password=$sqlPassPlain;Trusted_Connection=False;Encrypt=True;Connection Timeout=$SqlTimeout;") 
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
    
    Remove-AzSqlServerFirewallRule -FirewallRuleName $tempFirewallRuleName -ResourceGroupName $resourceGroupName -ServerName $sqlServerName    
}
else
{
    Write-Output "Deployment cancelled."    
}