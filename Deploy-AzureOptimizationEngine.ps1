param (
    [Parameter(Mandatory = $false)]
    [string] $TemplateUri = "https://raw.githubusercontent.com/helderpinto/AzureOptimizationEngine/master/azuredeploy.json"
)

$ErrorActionPreference = "Stop"

$deploymentNameTemplate = "{0}" + (Get-Date).ToString("yyMMddHHmmss")
$resourceGroupNameTemplate = "{0}-rg"
$storageAccountNameTemplate = "{0}sa"
$laWorkspaceNameTemplate = "{0}-la"
$automationAccountNameTemplate = "{0}-auto"
$sqlServerNameTemplate = "{0}-sql"

$ctx = Get-AzContext
if (-not($ctx)) {
    Connect-AzAccount
    $ctx = Get-AzContext
}

Write-Host "Getting Azure subscriptions..." -ForegroundColor Green

$subscriptions = Get-AzSubscription

if ($subscriptions.Count -gt 1) {
    for ($i = 0; $i -lt $subscriptions.Count; $i++) {
        Write-Output "[$i] $($subscriptions[$i].Name)"    
    }
    $selectedSubscription = -1
    $lastSubscriptionIndex = $subscriptions.Count - 1
    while ($selectedSubscription -lt 0 -or $selectedSubscription -gt $lastSubscriptionIndex) {
        Write-Output "---"
        $selectedSubscription = Read-Host "Please, select the target subscription for this deployment [0..$lastSubscriptionIndex]"
    }
}
else {
    $selectedSubscription = 0
}

$subscriptionId = $subscriptions[$selectedSubscription].Id

if ($ctx.Subscription.Id -ne $subscriptionId) {
    Select-AzSubscription -SubscriptionId $subscriptionId
}

$workspaceReuse = $null

do {
    $nameAvailable = $true
    $namePrefix = Read-Host "Please, enter a unique name prefix for this deployment or enter existing prefix if updating deployment"
    if ($namePrefix.Length -gt 21) {
        throw "Name prefix length is larger than the 21 characters limit ($namePrefix)"
    }

    if ($null -eq $workspaceReuse) {
        $workspaceReuse = Read-Host "Are you going to reuse an existing Log Analytics workspace (Y/N)?"
    }

    $deploymentName = $deploymentNameTemplate -f $namePrefix
    $resourceGroupName = $resourceGroupNameTemplate -f $namePrefix
    $storageAccountName = $storageAccountNameTemplate -f $namePrefix
    $automationAccountName = $automationAccountNameTemplate -f $namePrefix
    $sqlServerName = $sqlServerNameTemplate -f $namePrefix
        
    Write-Host "Checking name prefix availability..." -ForegroundColor Green

    Write-Host "...for the Storage Account..." -ForegroundColor Green
    $sa = Get-AzStorageAccount -ResourceGroupName $resourceGroupName -Name $storageAccountName.Replace("-", "") -ErrorAction SilentlyContinue
    if ($null -eq $sa) {
        $saNameResult = Get-AzStorageAccountNameAvailability -Name $storageAccountName.Replace("-", "")
        if (-not($saNameResult.NameAvailable)) {
            $nameAvailable = $false
            Write-Host "$($saNameResult.Message)" -ForegroundColor Red
        }    
    }
    else {
        Write-Host "(The Storage Account was already deployed)" -ForegroundColor Green
    }

    if ("N", "n" -contains $workspaceReuse) {
        Write-Host "...for the Log Analytics workspace..." -ForegroundColor Green

        $logAnalyticsReuse = $false
        $laWorkspaceName = $laWorkspaceNameTemplate -f $namePrefix
        $laWorkspaceResourceGroup = $resourceGroupName

        $la = Get-AzOperationalInsightsWorkspace -ResourceGroupName $resourceGroupName -Name $laWorkspaceName -ErrorAction SilentlyContinue
        if ($null -eq $la) {
            $laNameResult = Invoke-WebRequest -Uri "https://portal.loganalytics.io/api/workspaces/IsWorkspaceExists?name=$laWorkspaceName"
            if ($laNameResult.Content -eq "true") {
                $nameAvailable = $false
                Write-Host "The Log Analytics workspace $laWorkspaceName is already taken." -ForegroundColor Red
            }
        }
        else {
            Write-Host "(The Log Analytics Workspace was already deployed)" -ForegroundColor Green
        }
    }
    else {
        $logAnalyticsReuse = $true
    }

    Write-Host "...for the Azure SQL Server..." -ForegroundColor Green
    $sql = Get-AzSqlServer -ResourceGroupName $resourceGroupName -Name $sqlServerName -ErrorAction SilentlyContinue
    if ($null -eq $sql) {

        $azureRmProfile = [Microsoft.Azure.Commands.Common.Authentication.Abstractions.AzureRmProfileProvider]::Instance.Profile;
        $profileClient = New-Object Microsoft.Azure.Commands.ResourceManager.Common.RMProfileClient($azureRmProfile);
        $accessToken = $profileClient.AcquireAccessToken($ctx.Subscription.TenantId).AccessToken

        $SqlServerNameAvailabilityUri = "https://management.azure.com/subscriptions/$subscriptionId/providers/Microsoft.Sql/checkNameAvailability?api-version=2014-04-01"
        $Headers = @{ }
        $Headers.Add("Authorization", "Bearer $accessToken")
        $body = "{`"name`": `"$sqlServerName`", `"type`": `"Microsoft.Sql/servers`"}"
        $sqlNameResult = (Invoke-WebRequest -Uri $SqlServerNameAvailabilityUri -Method Post -Body $body -ContentType "application/json" -Headers $Headers).content | ConvertFrom-Json
        
        if (-not($sqlNameResult.available)) {
            $nameAvailable = $false
            Write-Host "$($sqlNameResult.message) ($sqlServerName)" -ForegroundColor Red
        }
    }
    else {
        Write-Host "(The SQL Server was already deployed)" -ForegroundColor Green
    }
}
while (-not($nameAvailable))

Write-Host "Name prefix $namePrefix is available for all services" -ForegroundColor Green

if ("Y", "y" -contains $workspaceReuse) {
    $laWorkspaceName = Read-Host "Please, enter the Log Analytics workspace name"
    $laWorkspaceResourceGroup = Read-Host "Please, enter the name of the resource group containing Log Analytics $laWorkspaceName"
    $la = Get-AzOperationalInsightsWorkspace -ResourceGroupName $laWorkspaceResourceGroup -Name $laWorkspaceName -ErrorAction SilentlyContinue
    if (-not($la)) {
        throw "Could not find $laWorkspaceName in resource group $laWorkspaceResourceGroup for the chosen subscription. Aborting."
    }        
}

Write-Host "Getting Azure locations..." -ForegroundColor Green
$locations = Get-AzLocation | Where-Object {$_.Providers -contains "Microsoft.Automation"} | Sort-Object -Property Location

for ($i = 0; $i -lt $locations.Count; $i++) {
    Write-Output "[$i] $($locations[$i].location)"    
}
$selectedLocation = -1
$lastLocationIndex = $locations.Count - 1
while ($selectedLocation -lt 0 -or $selectedLocation -gt $lastLocationIndex) {
    Write-Output "---"
    $selectedLocation = Read-Host "Please, select the target location for this deployment [0..$lastLocationIndex]"
}

$targetLocation = $locations[$selectedLocation].location

$sqlAdmin = Read-Host "Please, input the SQL Admin username"
$sqlPass = Read-Host "Please, input the SQL Admin password" -AsSecureString

$continueInput = Read-Host "Deploying Azure Optimization Engine to subscription $($subscriptions[$selectedSubscription].Name). Continue (Y/N)?"
if ("Y", "y" -contains $continueInput) {
    
    $rg = Get-AzResourceGroup -Name $resourceGroupName -ErrorAction SilentlyContinue 
    
    if ($null -eq $rg) {
        Write-Host "Resource group $resourceGroupName does not exist." -ForegroundColor Yellow
        Write-Host "Creating resource group $resourceGroupName..." -ForegroundColor Green
        New-AzResourceGroup -Name $resourceGroupName -Location $targetLocation
    }

    $jobSchedules = Get-AzAutomationScheduledRunbook -ResourceGroupName $resourceGroupName -AutomationAccountName $automationAccountName -ErrorAction SilentlyContinue
    if ($jobSchedules.Count -gt 0)
    {
        Write-Host "Unregistering previous runbook schedules associations from $automationAccountName..." -ForegroundColor Green
        foreach ($jobSchedule in $jobSchedules)
        {
            Unregister-AzAutomationScheduledRunbook -ResourceGroupName $resourceGroupName -AutomationAccountName $automationAccountName `
                -JobScheduleId $jobSchedule.JobScheduleId -Force
        }    
    }

    Write-Host "Deploying Azure Optimization Engine resources..." -ForegroundColor Green
    New-AzResourceGroupDeployment -TemplateUri $TemplateUri -ResourceGroupName $resourceGroupName -Name $deploymentName `
        -projectName $namePrefix -projectLocation $targetlocation -logAnalyticsReuse $logAnalyticsReuse `
        -logAnalyticsWorkspaceName $laWorkspaceName -logAnalyticsWorkspaceRG $laWorkspaceResourceGroup -sqlAdminLogin $sqlAdmin -sqlAdminPassword $sqlPass
    
    $myPublicIp = (Invoke-WebRequest -uri "http://ifconfig.me/ip").Content

    Write-Host "Opening SQL Server firewall temporarily to your public IP ($myPublicIp)..." -ForegroundColor Green
    $tempFirewallRuleName = "InitialDeployment"            
    New-AzSqlServerFirewallRule -ResourceGroupName $resourceGroupName -ServerName $sqlServerName -FirewallRuleName $tempFirewallRuleName -StartIpAddress $myPublicIp -EndIpAddress $myPublicIp -ErrorAction SilentlyContinue
    
    Write-Host "Checking Azure Automation variable referring to the initial Azure Optimization Engine deployment date..." -ForegroundColor Green
    $deploymentDateVariableName = "AzureOptimization_DeploymentDate"    
    $deploymentDateVariable = Get-AzAutomationVariable -ResourceGroupName $resourceGroupName -AutomationAccountName $automationAccountName -Name $deploymentDateVariableName -ErrorAction SilentlyContinue
    
    if ($null -eq $deploymentDateVariable) {
        $deploymentDate = (get-date).ToUniversalTime().ToString("yyyy-MM-dd")
        Write-Host "Setting initial deployment date ($deploymentDate)..." -ForegroundColor Green
        New-AzAutomationVariable -Name $deploymentDateVariableName -Description "The date of the initial engine deployment" `
            -ResourceGroupName $resourceGroupName -AutomationAccountName $automationAccountName -Value $deploymentDate -Encrypted $false
    }

    Write-Host "Checking Azure Automation Run As account..." -ForegroundColor Green

    $runAsConnection = Get-AzAutomationConnection -ResourceGroupName $resourceGroupName -AutomationAccountName $automationAccountName -Name "AzureRunAsConnection" -ErrorAction SilentlyContinue
    
    if ($null -eq $runAsConnection) {

        $runasAppName = "$automationAccountName-runasaccount"
        $certPass = Read-Host "Please, input the Run As certificate password" -AsSecureString   
        .\New-RunAsAccount.ps1 -ResourceGroup $resourceGroupName -AutomationAccountName $automationAccountName -SubscriptionId $subscriptionId `
            -ApplicationDisplayName $runasAppName -SelfSignedCertPlainPassword $certPass -CreateClassicRunAsAccount $false
    }
    else {
        Write-Host "(The Automation Run As account was already deployed)" -ForegroundColor Green
    }

    Write-Host "Deploying SQL Database model..." -ForegroundColor Green
    
    $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($sqlPass)
    $sqlPassPlain = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr)
    
    $sqlServerEndpoint = "$sqlServerName.database.windows.net"
    $databaseName = "azureoptimization" 
    $SqlTimeout = 60
    $tries = 0
    $connectionSuccess = $false
    do {
        $tries++
        try {
    
    
            $Conn = New-Object System.Data.SqlClient.SqlConnection("Server=tcp:$sqlServerEndpoint,1433;Database=$databaseName;User ID=$sqlAdmin;Password=$sqlPassPlain;Trusted_Connection=False;Encrypt=True;Connection Timeout=$SqlTimeout;") 
            $Conn.Open() 
    
            $createTableQuery = Get-Content -Path ".\model\loganalyticsingestcontrol-table.sql"
            $Cmd = new-object system.Data.SqlClient.SqlCommand
            $Cmd.Connection = $Conn
            $Cmd.CommandTimeout = $SqlTimeout
            $Cmd.CommandText = $createTableQuery
            $Cmd.ExecuteReader()
            $Conn.Close()
    
            $Conn = New-Object System.Data.SqlClient.SqlConnection("Server=tcp:$sqlServerEndpoint,1433;Database=$databaseName;User ID=$sqlAdmin;Password=$sqlPassPlain;Trusted_Connection=False;Encrypt=True;Connection Timeout=$SqlTimeout;") 
            $Conn.Open() 
    
            $initTableQuery = Get-Content -Path ".\model\loganalyticsingestcontrol-initialize.sql"
            $Cmd = new-object system.Data.SqlClient.SqlCommand
            $Cmd.Connection = $Conn
            $Cmd.CommandTimeout = $SqlTimeout
            $Cmd.CommandText = $initTableQuery
            $Cmd.ExecuteReader()
            $Conn.Close()
    
            $Conn = New-Object System.Data.SqlClient.SqlConnection("Server=tcp:$sqlServerEndpoint,1433;Database=$databaseName;User ID=$sqlAdmin;Password=$sqlPassPlain;Trusted_Connection=False;Encrypt=True;Connection Timeout=$SqlTimeout;") 
            $Conn.Open() 
    
            $createTableQuery = Get-Content -Path ".\model\recommendationsingestcontrol-table.sql"
            $Cmd = new-object system.Data.SqlClient.SqlCommand
            $Cmd.Connection = $Conn
            $Cmd.CommandTimeout = $SqlTimeout
            $Cmd.CommandText = $createTableQuery
            $Cmd.ExecuteReader()
            $Conn.Close()

            $Conn = New-Object System.Data.SqlClient.SqlConnection("Server=tcp:$sqlServerEndpoint,1433;Database=$databaseName;User ID=$sqlAdmin;Password=$sqlPassPlain;Trusted_Connection=False;Encrypt=True;Connection Timeout=$SqlTimeout;") 
            $Conn.Open() 
    
            $initTableQuery = Get-Content -Path ".\model\recommendationsingestcontrol-initialize.sql"
            $Cmd = new-object system.Data.SqlClient.SqlCommand
            $Cmd.Connection = $Conn
            $Cmd.CommandTimeout = $SqlTimeout
            $Cmd.CommandText = $initTableQuery
            $Cmd.ExecuteReader()
            $Conn.Close()

            $Conn = New-Object System.Data.SqlClient.SqlConnection("Server=tcp:$sqlServerEndpoint,1433;Database=$databaseName;User ID=$sqlAdmin;Password=$sqlPassPlain;Trusted_Connection=False;Encrypt=True;Connection Timeout=$SqlTimeout;") 
            $Conn.Open() 
    
            $createTableQuery = Get-Content -Path ".\model\recommendations-table.sql"
            $Cmd = new-object system.Data.SqlClient.SqlCommand
            $Cmd.Connection = $Conn
            $Cmd.CommandTimeout = $SqlTimeout
            $Cmd.CommandText = $createTableQuery
            $Cmd.ExecuteReader()
            $Conn.Close()

            $connectionSuccess = $true
        }
        catch {
            Write-Host "Failed to contact SQL at try $tries." -ForegroundColor Yellow
            Write-Host $Error[0] -ForegroundColor Yellow
            Start-Sleep -Seconds ($tries * 20)
        }    
    } while (-not($connectionSuccess) -and $tries -lt 3)
    
    if (-not($connectionSuccess)) {
        throw "Could not establish connection to SQL."
    }
    
    Write-Host "Deleting temporary SQL Server firewall rule..." -ForegroundColor Green
    Remove-AzSqlServerFirewallRule -FirewallRuleName $tempFirewallRuleName -ResourceGroupName $resourceGroupName -ServerName $sqlServerName    

    Write-Host "Deployment completed!" -ForegroundColor Green
}
else {
    Write-Host "Deployment cancelled." -ForegroundColor Red
}