param (
    [Parameter(Mandatory = $true)]
    [string] $TemplateUri
)

$ErrorActionPreference = "Stop"

$deploymentNameTemplate = "{0}" + (Get-Date).ToString("yyMMddHHmmss")
$resourceGroupNameTemplate = "{0}-rg"
$storageAccountNameTemplate = "{0}sa"
$laWorkspaceNameTemplate = "{0}-la"
$automationAccountNameTemplate = "{0}-auto"
$sqlServerNameTemplate = "{0}-sql"

$ctx = Get-AzContext
if (-not($ctx))
{
    Connect-AzAccount
    $ctx = Get-AzContext
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
    while ($selectedSubscription -lt 0 -or $selectedSubscription -gt $lastSubscriptionIndex)
    {
        Write-Output "---"
        $selectedSubscription = Read-Host "Please, select the target subscription for this deployment [0..$lastSubscriptionIndex]"
    }
}
else
{
    $selectedSubscription = 0
}

$subscriptionId = $subscriptions[$selectedSubscription].Id

$workspaceReuse = $null

do
{
    $nameAvailable = $true
    $namePrefix = Read-Host "Please, enter a unique name prefix for the resource group and all resources created by this deployment (up to 21 characters)"
    if ($namePrefix.Length -gt 21)
    {
        throw "Name prefix length is larger than the 21 characters limit ($namePrefix)"
    }

    if ($null -eq $workspaceReuse)
    {
        $workspaceReuse = Read-Host "Are you going to reuse an existing Log Analytics workspace (Y/N)?"
    }

    $deploymentName = $deploymentNameTemplate -f $namePrefix
    $resourceGroupName = $resourceGroupNameTemplate -f $namePrefix
    $storageAccountName = $storageAccountNameTemplate -f $namePrefix
    $automationAccountName = $automationAccountNameTemplate -f $namePrefix
    $sqlServerName = $sqlServerNameTemplate -f $namePrefix
        
    Write-Output "Checking name prefix availability..."

    $saNameResult = Get-AzStorageAccountNameAvailability -Name $storageAccountName
    if (-not($saNameResult.NameAvailable))
    {
        $nameAvailable = $false
        Write-Output "$($saNameResult.Message)"
    }

    if ("N","n" -contains $workspaceReuse)
    {
        $logAnalyticsReuse = $false
        $laWorkspaceName = $laWorkspaceNameTemplate -f $namePrefix
        $laWorkspaceResourceGroup = $resourceGroupName
        
        $laNameResult = Invoke-WebRequest -Uri "https://portal.loganalytics.io/api/workspaces/IsWorkspaceExists?name=$laWorkspaceName"
        if ($laNameResult.Content -eq "true")
        {
            $nameAvailable = $false
            Write-Output "The Log Analytics workspace $laWorkspaceName is already taken."
        }
    }
    else
    {
        $logAnalyticsReuse = $true
    }

    $azureRmProfile = [Microsoft.Azure.Commands.Common.Authentication.Abstractions.AzureRmProfileProvider]::Instance.Profile;
    $profileClient = New-Object Microsoft.Azure.Commands.ResourceManager.Common.RMProfileClient($azureRmProfile);
    $accessToken = $profileClient.AcquireAccessToken($ctx.Subscription.TenantId).AccessToken

    $SqlServerNameAvailabilityUri = "https://management.azure.com/subscriptions/$subscriptionId/providers/Microsoft.Sql/checkNameAvailability?api-version=2014-04-01"
    $Headers = @{}
    $Headers.Add("Authorization","Bearer $accessToken")
    $body = "{`"name`": `"$sqlServerName`", `"type`": `"Microsoft.Sql/servers`"}"
    $sqlNameResult = (Invoke-WebRequest -Uri $SqlServerNameAvailabilityUri -Method Post -Body $body -ContentType "application/json" -Headers $Headers).content | ConvertFrom-Json
    
    if (-not($sqlNameResult.available))
    {
        $nameAvailable = $false
        Write-Output "$($sqlNameResult.message) ($sqlServerName)"
    }
}
while (-not($nameAvailable))

Write-Output "Name prefix $namePrefix is available."
$continueInput = Read-Host "Deploying Azure Optimization Engine to subscription $($subscriptions[$selectedSubscription].Name). Continue (Y/N)?"
if ("Y","y" -contains $continueInput)
{
    if ($ctx.Subscription.Id -ne $subscriptionId)
    {
        Select-AzSubscription -SubscriptionId $subscriptionId
    }

    if ("Y","y" -contains $workspaceReuse)
    {
        $laWorkspaceName = Read-Host "Please, enter the Log Analytics workspace name"
        $laWorkspaceResourceGroup = Read-Host "Please, enter the name of the resource group containing Log Analytics $laWorkspaceName"
        $la = Get-AzOperationalInsightsWorkspace -ResourceGroupName $laWorkspaceResourceGroup -Name $laWorkspaceName -ErrorAction SilentlyContinue
        if (-not($la))
        {
            throw "Could not find $laWorkspaceName in resource group $laWorkspaceResourceGroup for the chosen subscription. Aborting."
        }        
    }

    $locations = Get-AzLocation | Sort-Object -Property location

    for ($i = 0; $i -lt $locations.Count; $i++)
    {
        Write-Output "[$i] $($locations[$i].location)"    
    }
    $selectedLocation = -1
    $lastLocationIndex = $locations.Count - 1
    while ($selectedLocation -lt 0 -or $selectedLocation -gt $lastLocationIndex)
    {
        Write-Output "---"
        $selectedLocation = Read-Host "Please, select the target location for this deployment [0..$lastLocationIndex]"
    }

    $targetLocation = $locations[$selectedLocation].location
    
    $rg = Get-AzResourceGroup -Name $resourceGroupName -ErrorAction SilentlyContinue 
    
    if ($null -eq $rg)
    {
        Write-Output "Resource group $resourceGroupName does not exist."
        Write-Output "Creating resource group $resourceGroupName..."
        New-AzResourceGroup -Name $resourceGroupName -Location $targetLocation
    }

    $sqlAdmin = Read-Host "Please, input the SQL Admin username"
    $sqlPass = Read-Host "Please, input the SQL Admin password" -AsSecureString
    
    New-AzResourceGroupDeployment -TemplateUri $TemplateUri -ResourceGroupName $resourceGroupName -Name $deploymentName `
        -projectName $namePrefix -projectLocation $targetlocation -logAnalyticsReuse $logAnalyticsReuse
        -sqlAdminLogin $sqlAdmin -sqlAdminPassword $sqlPass
    
    $myPublicIp = (Invoke-WebRequest -uri "http://ifconfig.me/ip").Content

    $tempFirewallRuleName = "InitialDeployment"            
    New-AzSqlServerFirewallRule -ResourceGroupName $resourceGroupName -ServerName $sqlServerName -FirewallRuleName $tempFirewallRuleName -StartIpAddress $myPublicIp -EndIpAddress $myPublicIp
    
    $laIdVariableName = "AzureOptimization_LogAnalyticsWorkspaceId"    
    $laIdVariable = Get-AzAutomationVariable -ResourceGroupName $resourceGroupName -AutomationAccountName $automationAccountName -Name $laIdVariableName -ErrorAction SilentlyContinue
    
    if ($null -eq $laIdVariable)
    {
        $la = Get-AzOperationalInsightsWorkspace -ResourceGroupName $laWorkspaceResourceGroup -Name $laWorkspaceName
        New-AzAutomationVariable -Name $laIdVariableName -Description "The Log Analytics Workspace ID where optimization data will be ingested." `
            -ResourceGroupName $resourceGroupName -AutomationAccountName $automationAccountName -Value $la.CustomerId.Guid -Encrypted $false
    }
    
    $laKeyVariableName = "AzureOptimization_LogAnalyticsWorkspaceKey"    
    $laKeyVariable = Get-AzAutomationVariable -ResourceGroupName $resourceGroupName -AutomationAccountName $automationAccountName -Name $laKeyVariableName -ErrorAction SilentlyContinue
    
    if ($null -eq $laKeyVariable)
    {
        $keys = Get-AzOperationalInsightsWorkspaceSharedKey -ResourceGroupName $laWorkspaceResourceGroup -Name $laWorkspaceName
        New-AzAutomationVariable -Name $laKeyVariableName -Description "The shared key for the Log Analytics Workspace where optimization data will be ingested." `
            -ResourceGroupName $resourceGroupName -AutomationAccountName $automationAccountName -Value $keys.PrimarySharedKey -Encrypted $true
    }
    
    $runAsConnection = Get-AzAutomationConnection -ResourceGroupName $resourceGroupName -AutomationAccountName $automationAccountName -Name "AzureRunAsConnection"
    
    if ($null -eq $runAsConnection)
    {

        $runasAppName = "$automactionAccountName-runasaccount"
        $certPass = Read-Host "Please, input the Run As certificate password" -AsSecureString   
        .\New-RunAsAccount.ps1 -ResourceGroup $resourceGroupName -AutomationAccountName $automationAccountName -SubscriptionId $subscriptionId `
            -ApplicationDisplayName $runasAppName -SelfSignedCertPlainPassword $certPass -CreateClassicRunAsAccount $false
    }
    
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