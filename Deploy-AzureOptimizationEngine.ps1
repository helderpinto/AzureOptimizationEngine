#Requires -RunAsAdministrator
param (
    [Parameter(Mandatory = $false)]
    [string] $TemplateUri,

    [Parameter(Mandatory = $false)]
    [string] $AzureEnvironment = "AzureCloud",

    [Parameter(Mandatory = $false)]
    [string] $ArtifactsSasToken
)

function CreateSelfSignedCertificate([string] $certificateName, [string] $selfSignedCertPlainPassword,
    [string] $certPath, [string] $certPathCer, [int] $selfSignedCertNoOfMonthsUntilExpired ) {

    if ($IsWindows -or $env:OS -like "Win*" -or [System.Environment]::OSVersion.Platform -like "Win*") {
        $Cert = New-SelfSignedCertificate -DnsName $certificateName -CertStoreLocation cert:\LocalMachine\My `
            -KeyExportPolicy Exportable -Provider "Microsoft Enhanced RSA and AES Cryptographic Provider" `
            -NotAfter (Get-Date).AddMonths($selfSignedCertNoOfMonthsUntilExpired) -HashAlgorithm SHA256

        $CertPassword = ConvertTo-SecureString $selfSignedCertPlainPassword -AsPlainText -Force
        Export-PfxCertificate -Cert ("Cert:\localmachine\my\" + $Cert.Thumbprint) -FilePath $certPath -Password $CertPassword -Force | Write-Verbose
        Export-Certificate -Cert ("Cert:\localmachine\my\" + $Cert.Thumbprint) -FilePath $certPathCer -Type CERT | Write-Verbose
    }
    elseif ($IsLinux -or $IsMacOs -or [System.Environment]::OSVersion.Platform -eq "Unix") {
        $ValidityDays = $selfSignedCertNoOfMonthsUntilExpired * 30
        openssl req -x509 -sha256 -nodes -days $ValidityDays -newkey rsa:2048 -subj "/CN=$certificateName" -keyout "$certPathCer.key" -out $certPathCer
        openssl pkcs12 -export -out $certPath -password pass:$selfSignedCertPlainPassword -inkey "$certPathCer.key" -in $certPathCer
    }
    else {
        throw "Unsupported OS type"
    }
}

function CreateServicePrincipal([System.Security.Cryptography.X509Certificates.X509Certificate2] $PfxCert, [string] $applicationDisplayName) {
    $keyValue = [System.Convert]::ToBase64String($PfxCert.GetRawCertData())
    $keyId = (New-Guid).Guid

    # Create an Azure AD application, AD App Credential, AD ServicePrincipal

    # Requires Application Developer Role, but works with Application administrator or GLOBAL ADMIN
    $Application = New-AzADApplication -DisplayName $ApplicationDisplayName -HomePage ("http://" + $applicationDisplayName) -IdentifierUris ("http://" + $keyId)
    # Requires Application administrator or GLOBAL ADMIN
    $ApplicationCredential = New-AzADAppCredential -ApplicationId $Application.ApplicationId -CertValue $keyValue -StartDate $PfxCert.NotBefore -EndDate $PfxCert.NotAfter
    # Requires Application administrator or GLOBAL ADMIN
    $ServicePrincipal = New-AzADServicePrincipal -ApplicationId $Application.ApplicationId
    $GetServicePrincipal = Get-AzADServicePrincipal -ObjectId $ServicePrincipal.Id

    # Sleep here for a few seconds to allow the service principal application to become active (ordinarily takes a few seconds)
    Start-Sleep -Seconds 15
    # Requires User Access Administrator or Owner.
    $NewRole = New-AzRoleAssignment -RoleDefinitionName Contributor -ServicePrincipalName $Application.ApplicationId -ErrorAction SilentlyContinue
    $Retries = 0;
    While ($null -eq $NewRole -and $Retries -le 6) {
        Start-Sleep -Seconds 10
        New-AzRoleAssignment -RoleDefinitionName Contributor -ServicePrincipalName $Application.ApplicationId -ErrorAction SilentlyContinue
        $NewRole = Get-AzRoleAssignment -ServicePrincipalName $Application.ApplicationId -ErrorAction SilentlyContinue
        $Retries++;
    }
    return $Application.ApplicationId.ToString();
}

function CreateAutomationCertificateAsset ([string] $resourceGroup, [string] $automationAccountName, [string] $certifcateAssetName, [string] $certPath, [string] $certPlainPassword, [Boolean] $Exportable) {
    $CertPassword = ConvertTo-SecureString $certPlainPassword -AsPlainText -Force
    Remove-AzAutomationCertificate -ResourceGroupName $resourceGroup -AutomationAccountName $automationAccountName -Name $certifcateAssetName -ErrorAction SilentlyContinue
    New-AzAutomationCertificate -ResourceGroupName $resourceGroup -AutomationAccountName $automationAccountName -Path $certPath -Name $certifcateAssetName -Password $CertPassword -Exportable:$Exportable  | write-verbose
}

function CreateAutomationConnectionAsset ([string] $resourceGroup, [string] $automationAccountName, [string] $connectionAssetName, [string] $connectionTypeName, [System.Collections.Hashtable] $connectionFieldValues ) {
    Remove-AzAutomationConnection -ResourceGroupName $resourceGroup -AutomationAccountName $automationAccountName -Name $connectionAssetName -Force -ErrorAction SilentlyContinue
    New-AzAutomationConnection -ResourceGroupName $ResourceGroup -AutomationAccountName $automationAccountName -Name $connectionAssetName -ConnectionTypeName $connectionTypeName -ConnectionFieldValues $connectionFieldValues
}


$ErrorActionPreference = "Stop"

$GitHubOriginalUri = "https://raw.githubusercontent.com/helderpinto/AzureOptimizationEngine/master/azuredeploy.json"

if ([string]::IsNullOrEmpty($TemplateUri)) {
    $TemplateUri = $GitHubOriginalUri
}

$isTemplateAvailable = $false

try {
    Invoke-WebRequest -Uri $TemplateUri | Out-Null
    $isTemplateAvailable = $true
}
catch {
    $saNameEnd = $TemplateUri.IndexOf(".blob.core.")
    if ($saNameEnd -gt 0) {
        $FullTemplateUri = $TemplateUri + $ArtifactsSasToken
        try {
            Invoke-WebRequest -Uri $FullTemplateUri | Out-Null
            $isTemplateAvailable = $true
            $TemplateUri = $FullTemplateUri
        }
        catch {
            Write-Host "The template URL ($TemplateUri) is not available. Please, provide a valid SAS Token in the ArtifactsSasToken parameter (Read permission and Object level access are sufficient)." -ForegroundColor Red
        }
    }
    else {
        Write-Host "The template URL ($TemplateUri) is not available. Please, put it in a publicly accessible HTTPS location." -ForegroundColor Red
    }
}

if (!$isTemplateAvailable) {
    throw "Terminating due to template unavailability."
}

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

Write-Host "Getting Azure subscriptions..." -ForegroundColor Green

$subscriptions = Get-AzSubscription | Where-Object { $_.State -eq "Enabled" }

if ($subscriptions.Count -gt 1) {
    for ($i = 0; $i -lt $subscriptions.Count; $i++) {
        Write-Output "[$i] $($subscriptions[$i].Name)"    
    }
    $selectedSubscription = -1
    $lastSubscriptionIndex = $subscriptions.Count - 1
    while ($selectedSubscription -lt 0 -or $selectedSubscription -gt $lastSubscriptionIndex) {
        Write-Output "---"
        $selectedSubscription = [int] (Read-Host "Please, select the target subscription for this deployment [0..$lastSubscriptionIndex]")
    }
}
else {
    $selectedSubscription = 0
}

if ($subscriptions.Count -eq 0) {
    throw "No subscriptions found. Check if you are logged in with the right Azure AD account."
}

$subscriptionId = $subscriptions[$selectedSubscription].Id

if ($ctx.Subscription.Id -ne $subscriptionId) {
    Select-AzSubscription -SubscriptionId $subscriptionId
}

$workspaceReuse = $null

$deploymentNameTemplate = "{0}" + (Get-Date).ToString("yyMMddHHmmss")
$resourceGroupNameTemplate = "{0}-rg"
$storageAccountNameTemplate = "{0}sa"
$laWorkspaceNameTemplate = "{0}-la"
$automationAccountNameTemplate = "{0}-auto"
$sqlServerNameTemplate = "{0}-sql"

do {
    $nameAvailable = $true
    $namePrefix = Read-Host "Please, enter a unique name prefix for the deployment or existing prefix if updating deployment (if you want instead to individually name all resources, just press ENTER)"

    if ($null -eq $workspaceReuse) {
        $workspaceReuse = Read-Host "Are you going to reuse an existing Log Analytics workspace (Y/N)?"
    }

    if ([string]::IsNullOrEmpty($namePrefix)) {
        $resourceGroupName = Read-Host "Please, enter the new or existing Resource Group for this deployment"
        $deploymentName = $deploymentNameTemplate -f $resourceGroupName
        $storageAccountName = Read-Host "Enter the Storage Account name"
        $automationAccountName = Read-Host "Automation Account name"
        $sqlServerName = Read-Host "Azure SQL Server name"
        $sqlDatabaseName = Read-Host "Azure SQL Database name"
        if ("N", "n" -contains $workspaceReuse) {
            $laWorkspaceName = Read-Host "Log Analytics Workspace"
        }
    }
    else {
        if ($namePrefix.Length -gt 21) {
            throw "Name prefix length is larger than the 21 characters limit ($namePrefix)"
        }
    
        $deploymentName = $deploymentNameTemplate -f $namePrefix
        $resourceGroupName = $resourceGroupNameTemplate -f $namePrefix
        $storageAccountName = $storageAccountNameTemplate -f $namePrefix
        $automationAccountName = $automationAccountNameTemplate -f $namePrefix
        $sqlServerName = $sqlServerNameTemplate -f $namePrefix            
        $laWorkspaceName = $laWorkspaceNameTemplate -f $namePrefix
        $sqlDatabaseName = "azureoptimization"
    }

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

        $SqlServerNameAvailabilityUriPath = "/subscriptions/$subscriptionId/providers/Microsoft.Sql/checkNameAvailability?api-version=2014-04-01"
        $body = "{`"name`": `"$sqlServerName`", `"type`": `"Microsoft.Sql/servers`"}"
        $sqlNameResult = (Invoke-AzRestMethod -Path $SqlServerNameAvailabilityUriPath -Method POST -Payload $body).Content | ConvertFrom-Json
        
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

Write-Host "Chosen resource names are available for all services" -ForegroundColor Green

if ("Y", "y" -contains $workspaceReuse) {
    $laWorkspaceName = Read-Host "Please, enter the name of the Log Analytics workspace to be reused"
    $laWorkspaceResourceGroup = Read-Host "Please, enter the name of the resource group containing Log Analytics $laWorkspaceName"
    $la = Get-AzOperationalInsightsWorkspace -ResourceGroupName $laWorkspaceResourceGroup -Name $laWorkspaceName -ErrorAction SilentlyContinue
    if (-not($la)) {
        throw "Could not find $laWorkspaceName in resource group $laWorkspaceResourceGroup for the chosen subscription. Aborting."
    }        
}

$rg = Get-AzResourceGroup -Name $resourceGroupName -ErrorAction SilentlyContinue 

if (-not($rg.Location)) {
    Write-Host "Getting Azure locations..." -ForegroundColor Green
    $locations = Get-AzLocation | Where-Object { $_.Providers -contains "Microsoft.Automation" } | Sort-Object -Property Location
    
    for ($i = 0; $i -lt $locations.Count; $i++) {
        Write-Output "[$i] $($locations[$i].location)"    
    }
    $selectedLocation = -1
    $lastLocationIndex = $locations.Count - 1
    while ($selectedLocation -lt 0 -or $selectedLocation -gt $lastLocationIndex) {
        Write-Output "---"
        $selectedLocation = [int] (Read-Host "Please, select the target location for this deployment [0..$lastLocationIndex]")
    }
    
    $targetLocation = $locations[$selectedLocation].location    
}
else {
    $targetLocation = $rg.Location    
}

$sqlAdmin = Read-Host "Please, input the SQL Admin username"
$sqlPass = Read-Host "Please, input the SQL Admin password" -AsSecureString

$continueInput = Read-Host "Deploying Azure Optimization Engine to subscription $($subscriptions[$selectedSubscription].Name). Continue (Y/N)?"
if ("Y", "y" -contains $continueInput) {
    
    if ($null -eq $rg) {
        Write-Host "Resource group $resourceGroupName does not exist." -ForegroundColor Yellow
        Write-Host "Creating resource group $resourceGroupName..." -ForegroundColor Green
        New-AzResourceGroup -Name $resourceGroupName -Location $targetLocation
    }

    $baseTime = (Get-Date).ToUniversalTime().ToString("u")
    $upgradingSchedules = $false
    $schedules = Get-AzAutomationSchedule -ResourceGroupName $resourceGroupName -AutomationAccountName $automationAccountName -ErrorAction SilentlyContinue
    if ($schedules.Count -gt 0) {
        $upgradingSchedules = $true
        $originalBaseTime = ($schedules | Sort-Object -Property StartTime | Select-Object -First 1).StartTime.AddHours(-1).DateTime
        $now = (Get-Date).ToUniversalTime()
        $diff = $now - $originalBaseTime
        $nextWeekDays = [Math]::Ceiling($diff.TotalDays / 7) * 7
        $baseTime = $now.AddDays($nextWeekDays - $diff.TotalDays).ToString("u")
        Write-Host "Existing schedules found. Keeping original base time: $baseTime." -ForegroundColor Green
    }
    else {
        Write-Host "Automation schedules base time automatically set to $baseTime." -ForegroundColor Green
    }
    $jobSchedules = Get-AzAutomationScheduledRunbook -ResourceGroupName $resourceGroupName -AutomationAccountName $automationAccountName -ErrorAction SilentlyContinue
    if ($jobSchedules.Count -gt 0) {
        Write-Host "Unregistering previous runbook schedules associations from $automationAccountName..." -ForegroundColor Green
        foreach ($jobSchedule in $jobSchedules) {
            if ($jobSchedule.ScheduleName.StartsWith("AzureOptimization")) {
                Unregister-AzAutomationScheduledRunbook -ResourceGroupName $resourceGroupName -AutomationAccountName $automationAccountName `
                    -JobScheduleId $jobSchedule.JobScheduleId -Force
            }
        }    
    }

    Write-Host "Deploying Azure Optimization Engine resources..." -ForegroundColor Green
    if ([string]::IsNullOrEmpty($ArtifactsSasToken)) {
        New-AzResourceGroupDeployment -TemplateUri $TemplateUri -ResourceGroupName $resourceGroupName -Name $deploymentName `
            -projectLocation $targetlocation -logAnalyticsReuse $logAnalyticsReuse -baseTime $baseTime `
            -logAnalyticsWorkspaceName $laWorkspaceName -logAnalyticsWorkspaceRG $laWorkspaceResourceGroup `
            -storageAccountName $storageAccountName -automationAccountName $automationAccountName `
            -sqlServerName $sqlServerName -sqlDatabaseName $sqlDatabaseName `
            -sqlAdminLogin $sqlAdmin -sqlAdminPassword $sqlPass
    }
    else {
        New-AzResourceGroupDeployment -TemplateUri $TemplateUri -ResourceGroupName $resourceGroupName -Name $deploymentName `
            -projectLocation $targetlocation -logAnalyticsReuse $logAnalyticsReuse -baseTime $baseTime `
            -logAnalyticsWorkspaceName $laWorkspaceName -logAnalyticsWorkspaceRG $laWorkspaceResourceGroup `
            -storageAccountName $storageAccountName -automationAccountName $automationAccountName `
            -sqlServerName $sqlServerName -sqlDatabaseName $sqlDatabaseName `
            -sqlAdminLogin $sqlAdmin -sqlAdminPassword $sqlPass -artifactsLocationSasToken (ConvertTo-SecureString $ArtifactsSasToken -AsPlainText -Force)        
    }

    if ($upgradingSchedules) {
        $schedules = Get-AzAutomationSchedule -ResourceGroupName $resourceGroupName -AutomationAccountName $automationAccountName
        $dailySchedules = $schedules | Where-Object { $_.Frequency -eq "Day" }
        Write-Host "Fixing daily schedules after upgrade..." -ForegroundColor Green
        foreach ($schedule in $dailySchedules) {
            $now = (Get-Date).ToUniversalTime()
            $newStartTime = [System.DateTimeOffset]::Parse($now.ToString("yyyy-MM-ddT00:00:00Z"))
            $newStartTime = $newStartTime.AddHours($schedule.StartTime.Hour).AddMinutes($schedule.StartTime.Minute)
            if ($newStartTime.AddMinutes(-5) -lt $now) {
                $newStartTime = $newStartTime.AddDays(1)
            }
            $expiryTime = $schedule.ExpiryTime.ToString("yyyy-MM-ddTHH:mm:ssZ")
            $startTime = $newStartTime.ToString("yyyy-MM-ddTHH:mm:ssZ")
            $automationPath = "/subscriptions/$subscriptionId/resourceGroups/$resourceGroupName/providers/Microsoft.Automation/automationAccounts/$automationAccountName/schedules/$($schedule.Name)?api-version=2015-10-31"
            $body = "{
                `"name`": `"$($schedule.Name)`",
                `"properties`": {
                  `"description`": `"$($schedule.Description)`",
                  `"startTime`": `"$startTime`",
                  `"expiryTime`": `"$expiryTime`",
                  `"interval`": 1,
                  `"frequency`": `"Day`",
                  `"advancedSchedule`": {}
                }
              }"
            Invoke-AzRestMethod -Path $automationPath -Method PUT -Payload $body | Out-Null
        }
    }
        
    $myPublicIp = (Invoke-WebRequest -uri "http://ifconfig.me/ip").Content

    Write-Host "Opening SQL Server firewall temporarily to your public IP ($myPublicIp)..." -ForegroundColor Green
    $tempFirewallRuleName = "InitialDeployment"            
    New-AzSqlServerFirewallRule -ResourceGroupName $resourceGroupName -ServerName $sqlServerName -FirewallRuleName $tempFirewallRuleName -StartIpAddress $myPublicIp -EndIpAddress $myPublicIp -ErrorAction SilentlyContinue
    
    Write-Host "Checking Azure Automation variable referring to the initial Azure Optimization Engine deployment date..." -ForegroundColor Green
    $deploymentDateVariableName = "AzureOptimization_DeploymentDate"    
    $deploymentDateVariable = Get-AzAutomationVariable -ResourceGroupName $resourceGroupName -AutomationAccountName $automationAccountName -Name $deploymentDateVariableName -ErrorAction SilentlyContinue
    
    if ($null -eq $deploymentDateVariable) {
        $deploymentDate = (Get-Date).ToUniversalTime().ToString("yyyy-MM-dd")
        Write-Host "Setting initial deployment date ($deploymentDate)..." -ForegroundColor Green
        New-AzAutomationVariable -Name $deploymentDateVariableName -Description "The date of the initial engine deployment" `
            -ResourceGroupName $resourceGroupName -AutomationAccountName $automationAccountName -Value $deploymentDate -Encrypted $false
    }

    Write-Host "Checking Azure Automation Run As account..." -ForegroundColor Green

    $CertificateAssetName = "AzureRunAsCertificate"
    $ConnectionAssetName = "AzureRunAsConnection"
    $ConnectionTypeName = "AzureServicePrincipal"
    $SelfSignedCertNoOfMonthsUntilExpired = 12

    $runAsConnection = Get-AzAutomationConnection -ResourceGroupName $resourceGroupName -AutomationAccountName $automationAccountName -Name $ConnectionAssetName -ErrorAction SilentlyContinue
    
    if ($null -eq $runAsConnection) {

        $runasAppName = "$automationAccountName-runasaccount"

        $CertificateName = $automationAccountName + $CertificateAssetName
        $TempDir = [System.IO.Path]::GetTempPath()
        $PfxCertPathForRunAsAccount = Join-Path $TempDir ($CertificateName + ".pfx")
        $PfxCertPlainPasswordForRunAsAccount = -join ((65..90) + (97..122) | Get-Random -Count 20 | % { [char]$_ })
        $CerCertPathForRunAsAccount = Join-Path $TempDir ($CertificateName + ".cer")

        try {
            CreateSelfSignedCertificate $CertificateName $PfxCertPlainPasswordForRunAsAccount $PfxCertPathForRunAsAccount $CerCertPathForRunAsAccount $SelfSignedCertNoOfMonthsUntilExpired   
        }
        catch {
            Write-Host "Message: [$($_.Exception.Message)"] -ForegroundColor Red
            Write-Host "Failed to create self-signed certificate. Please, run this script in an elevated prompt." -ForegroundColor Red
            throw "Terminating due to lack of administrative privileges."
        }

        $PfxCert = New-Object -TypeName System.Security.Cryptography.X509Certificates.X509Certificate2 -ArgumentList @($PfxCertPathForRunAsAccount, $PfxCertPlainPasswordForRunAsAccount)
        $ApplicationId = CreateServicePrincipal $PfxCert $runasAppName
        
        CreateAutomationCertificateAsset $resourceGroupName $automationAccountName $CertificateAssetName $PfxCertPathForRunAsAccount $PfxCertPlainPasswordForRunAsAccount $true
        
        $ConnectionFieldValues = @{"ApplicationId" = $ApplicationId; "TenantId" = $ctx.Subscription.TenantId; "CertificateThumbprint" = $PfxCert.Thumbprint; "SubscriptionId" = $ctx.Subscription.Id }

        CreateAutomationConnectionAsset $resourceGroupName $automationAccountName $ConnectionAssetName $ConnectionTypeName $ConnectionFieldValues
    }
    else {
        Write-Host "(The Automation Run As account was already deployed)" -ForegroundColor Green
    }

    Write-Host "Deploying SQL Database model..." -ForegroundColor Green
    
    $sqlPassPlain = (New-Object PSCredential "user", $sqlPass).GetNetworkCredential().Password    
    $sqlServerEndpoint = "$sqlServerName.database.windows.net"
    $databaseName = $sqlDatabaseName
    $SqlTimeout = 60
    $tries = 0
    $connectionSuccess = $false
    do {
        $tries++
        try {
    
    
            $Conn = New-Object System.Data.SqlClient.SqlConnection("Server=tcp:$sqlServerEndpoint,1433;Database=$databaseName;User ID=$sqlAdmin;Password=$sqlPassPlain;Trusted_Connection=False;Encrypt=True;Connection Timeout=$SqlTimeout;") 
            $Conn.Open() 
    
            $createTableQuery = Get-Content -Path "./model/loganalyticsingestcontrol-table.sql"
            $Cmd = new-object system.Data.SqlClient.SqlCommand
            $Cmd.Connection = $Conn
            $Cmd.CommandTimeout = $SqlTimeout
            $Cmd.CommandText = $createTableQuery
            $Cmd.ExecuteReader()
            $Conn.Close()
    
            $Conn = New-Object System.Data.SqlClient.SqlConnection("Server=tcp:$sqlServerEndpoint,1433;Database=$databaseName;User ID=$sqlAdmin;Password=$sqlPassPlain;Trusted_Connection=False;Encrypt=True;Connection Timeout=$SqlTimeout;") 
            $Conn.Open() 
    
            $initTableQuery = Get-Content -Path "./model/loganalyticsingestcontrol-initialize.sql"
            $Cmd = new-object system.Data.SqlClient.SqlCommand
            $Cmd.Connection = $Conn
            $Cmd.CommandTimeout = $SqlTimeout
            $Cmd.CommandText = $initTableQuery
            $Cmd.ExecuteReader()
            $Conn.Close()
    
            $Conn = New-Object System.Data.SqlClient.SqlConnection("Server=tcp:$sqlServerEndpoint,1433;Database=$databaseName;User ID=$sqlAdmin;Password=$sqlPassPlain;Trusted_Connection=False;Encrypt=True;Connection Timeout=$SqlTimeout;") 
            $Conn.Open() 
    
            $upgradeTableQuery = Get-Content -Path "./model/loganalyticsingestcontrol-upgrade.sql"
            $Cmd = new-object system.Data.SqlClient.SqlCommand
            $Cmd.Connection = $Conn
            $Cmd.CommandTimeout = $SqlTimeout
            $Cmd.CommandText = $upgradeTableQuery
            $Cmd.ExecuteReader()
            $Conn.Close()
    
            $Conn = New-Object System.Data.SqlClient.SqlConnection("Server=tcp:$sqlServerEndpoint,1433;Database=$databaseName;User ID=$sqlAdmin;Password=$sqlPassPlain;Trusted_Connection=False;Encrypt=True;Connection Timeout=$SqlTimeout;") 
            $Conn.Open() 
    
            $createTableQuery = Get-Content -Path "./model/sqlserveringestcontrol-table.sql"
            $Cmd = new-object system.Data.SqlClient.SqlCommand
            $Cmd.Connection = $Conn
            $Cmd.CommandTimeout = $SqlTimeout
            $Cmd.CommandText = $createTableQuery
            $Cmd.ExecuteReader()
            $Conn.Close()

            $Conn = New-Object System.Data.SqlClient.SqlConnection("Server=tcp:$sqlServerEndpoint,1433;Database=$databaseName;User ID=$sqlAdmin;Password=$sqlPassPlain;Trusted_Connection=False;Encrypt=True;Connection Timeout=$SqlTimeout;") 
            $Conn.Open() 
    
            $initTableQuery = Get-Content -Path "./model/sqlserveringestcontrol-initialize.sql"
            $Cmd = new-object system.Data.SqlClient.SqlCommand
            $Cmd.Connection = $Conn
            $Cmd.CommandTimeout = $SqlTimeout
            $Cmd.CommandText = $initTableQuery
            $Cmd.ExecuteReader()
            $Conn.Close()

            $Conn = New-Object System.Data.SqlClient.SqlConnection("Server=tcp:$sqlServerEndpoint,1433;Database=$databaseName;User ID=$sqlAdmin;Password=$sqlPassPlain;Trusted_Connection=False;Encrypt=True;Connection Timeout=$SqlTimeout;") 
            $Conn.Open() 
    
            $createTableQuery = Get-Content -Path "./model/recommendations-table.sql"
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