param (
    [Parameter(Mandatory = $false)]
    [string] $TemplateUri,

    [Parameter(Mandatory = $false)]
    [string] $AzureEnvironment = "AzureCloud",

    [Parameter(Mandatory = $false)]
    [string] $ArtifactsSasToken,

    [Parameter(Mandatory = $false)]
    [switch] $DoPartialUpgrade # updates only storage account containers, Automation assets and SQL Database model
)

function ConvertTo-Hashtable {
    [CmdletBinding()]
    [OutputType('hashtable')]
    param (
        [Parameter(ValueFromPipeline)]
        $InputObject
    )
 
    process {
        if ($null -eq $InputObject) {
            return $null
        }
 
        if ($InputObject -is [System.Collections.IEnumerable] -and $InputObject -isnot [string]) {
            $collection = @(
                foreach ($object in $InputObject) {
                    ConvertTo-Hashtable -InputObject $object
                }
            ) 
            Write-Output -NoEnumerate $collection
        } elseif ($InputObject -is [psobject]) { 
            $hash = @{}
            foreach ($property in $InputObject.PSObject.Properties) {
                $hash[$property.Name] = ConvertTo-Hashtable -InputObject $property.Value
            }
            $hash
        } else {
            $InputObject
        }
    }
}

$ErrorActionPreference = "Stop"

$lastDeploymentStatePath = ".\last-deployment-state.json"
$deploymentOptions = @{}

if (Test-Path -Path $lastDeploymentStatePath)
{
    $depOptions = Get-Content -Path $lastDeploymentStatePath | ConvertFrom-Json
    Write-Host $depOptions -ForegroundColor Green
    $depOptionsReuse = Read-Host "Found last deployment options above. Do you want to repeat/upgrade last deployment (Y/N)?"
    if ("Y", "y" -contains $depOptionsReuse)
    {
        foreach ($property in $depOptions.PSObject.Properties)
        {
            $deploymentOptions[$property.Name] = $property.Value
        }    
    }
}

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

$cloudDetails = Get-AzEnvironment -Name $AzureEnvironment

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

Write-Host "Getting Azure subscriptions (filtering out unsupported ones)..." -ForegroundColor Green

$subscriptions = Get-AzSubscription | Where-Object { $_.State -eq "Enabled" -and $_.SubscriptionPolicies.QuotaId -notlike "Internal*" -and $_.SubscriptionPolicies.QuotaId -notlike "AAD*" }

if ($subscriptions.Count -gt 1) {

    $selectedSubscription = -1
    for ($i = 0; $i -lt $subscriptions.Count; $i++)
    {
        if (-not($deploymentOptions["SubscriptionId"]))
        {
            Write-Output "[$i] $($subscriptions[$i].Name)"    
        }
        else
        {
            if ($subscriptions[$i].Id -eq $deploymentOptions["SubscriptionId"])
            {
                $selectedSubscription = $i
                break
            }
        }
    }
    if (-not($deploymentOptions["SubscriptionId"]))
    {
        $lastSubscriptionIndex = $subscriptions.Count - 1
        while ($selectedSubscription -lt 0 -or $selectedSubscription -gt $lastSubscriptionIndex) {
            Write-Output "---"
            $selectedSubscription = [int] (Read-Host "Please, select the target subscription for this deployment [0..$lastSubscriptionIndex]")
        }    
    }
    if ($selectedSubscription -eq -1)
    {
        throw "The selected subscription does not exist. Check if you are logged in with the right Azure AD account."        
    }
}
else
{
    if ($subscriptions.Count -ne 0)
    {
        $selectedSubscription = 0
    }
    else
    {
        throw "No valid subscriptions found. Azure AD or Internal subscriptions are currently not supported."
    }
}

if ($subscriptions.Count -eq 0) {
    throw "No subscriptions found. Check if you are logged in with the right Azure AD account."
}

$subscriptionId = $subscriptions[$selectedSubscription].Id

if (-not($deploymentOptions["SubscriptionId"]))
{
    $deploymentOptions["SubscriptionId"] = $subscriptionId
}

if ($ctx.Subscription.Id -ne $subscriptionId) {
    $ctx = Select-AzSubscription -SubscriptionId $subscriptionId
}

$workspaceReuse = $null

$deploymentNameTemplate = "{0}" + (Get-Date).ToString("yyMMddHHmmss")
$resourceGroupNameTemplate = "{0}-rg"
$storageAccountNameTemplate = "{0}sa"
$laWorkspaceNameTemplate = "{0}-la"
$automationAccountNameTemplate = "{0}-auto"
$sqlServerNameTemplate = "{0}-sql"

$nameAvailable = $true
if (-not($deploymentOptions["NamePrefix"]))
{
    $namePrefix = Read-Host "Please, enter a unique name prefix for the deployment or existing prefix if updating deployment (if you want instead to individually name all resources, just press ENTER)"
    if (-not($namePrefix))
    {
        $namePrefix = "EmptyNamePrefix"
    }
    $deploymentOptions["NamePrefix"] = $namePrefix
}
else {
    if ($deploymentOptions["NamePrefix"] -eq "EmptyNamePrefix")
    {
        $namePrefix = $null
    }
    else
    {
        $namePrefix = $deploymentOptions["NamePrefix"]            
    }
}

if (-not($deploymentOptions["WorkspaceReuse"]))
{
    if ($null -eq $workspaceReuse) {
        $workspaceReuse = Read-Host "Are you going to reuse an existing Log Analytics workspace (Y/N)?"
    }
    $deploymentOptions["WorkspaceReuse"] = $workspaceReuse
}
else
{
    $workspaceReuse = $deploymentOptions["WorkspaceReuse"]
}

if (-not($deploymentOptions["ResourceGroupName"]))
{
    if ([string]::IsNullOrEmpty($namePrefix) -or $namePrefix -eq "EmptyNamePrefix") {
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

    $deploymentOptions["ResourceGroupName"] = $resourceGroupName
    $deploymentOptions["StorageAccountName"] = $storageAccountName
    $deploymentOptions["AutomationAccountName"] = $automationAccountName
    $deploymentOptions["SqlServerName"] = $sqlServerName
    $deploymentOptions["SqlDatabaseName"] = $sqlDatabaseName
    $deploymentOptions["WorkspaceName"] = $laWorkspaceName
}
else
{
    $resourceGroupName = $deploymentOptions["ResourceGroupName"]
    $storageAccountName = $deploymentOptions["StorageAccountName"]
    $automationAccountName = $deploymentOptions["AutomationAccountName"]
    $sqlServerName = $deploymentOptions["SqlServerName"]
    $sqlDatabaseName = $deploymentOptions["SqlDatabaseName"]        
    $laWorkspaceName = $deploymentOptions["WorkspaceName"]        
    $deploymentName = $deploymentNameTemplate -f $resourceGroupName
}

Write-Host "Checking name prefix availability..." -ForegroundColor Green

Write-Host "...for the Storage Account..." -ForegroundColor Green
$sa = Get-AzStorageAccount -ResourceGroupName $resourceGroupName -Name $storageAccountName -ErrorAction SilentlyContinue
if ($null -eq $sa) {
    $saNameResult = Get-AzStorageAccountNameAvailability -Name $storageAccountName
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

if (-not($nameAvailable))
{
    throw "Please, fix naming issues. Terminating execution."
}

Write-Host "Chosen resource names are available for all services" -ForegroundColor Green

if (-not($deploymentOptions["WorkspaceResourceGroupName"]))
{
    if ("Y", "y" -contains $workspaceReuse) {
        $laWorkspaceName = Read-Host "Please, enter the name of the Log Analytics workspace to be reused"
        $laWorkspaceResourceGroup = Read-Host "Please, enter the name of the resource group containing Log Analytics $laWorkspaceName"
        $la = Get-AzOperationalInsightsWorkspace -ResourceGroupName $laWorkspaceResourceGroup -Name $laWorkspaceName -ErrorAction SilentlyContinue
        if (-not($la)) {
            throw "Could not find $laWorkspaceName in resource group $laWorkspaceResourceGroup for the chosen subscription. Aborting."
        }        
        $deploymentOptions["WorkspaceName"] = $laWorkspaceName
        $deploymentOptions["WorkspaceResourceGroupName"] = $laWorkspaceResourceGroup
    }    
}
else
{
    $laWorkspaceResourceGroup = $deploymentOptions["WorkspaceResourceGroupName"]
}

$rg = Get-AzResourceGroup -Name $resourceGroupName -ErrorAction SilentlyContinue 

if (-not($deploymentOptions["TargetLocation"]))
{
    if (-not($rg.Location)) {
        Write-Host "Getting Azure locations..." -ForegroundColor Green
        $locations = Get-AzLocation | Where-Object { $_.Providers -contains "Microsoft.Automation" -and $_.Providers -contains "Microsoft.Sql" `
                                                        -and $_.Providers -contains "Microsoft.OperationalInsights" `
                                                        -and $_.Providers -contains "Microsoft.Storage"} | Sort-Object -Property Location
        
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
    
    $deploymentOptions["TargetLocation"] = $targetLocation
}
else
{
    $targetLocation = $deploymentOptions["TargetLocation"]    
}

if (-not($deploymentOptions["SqlAdmin"]))
{
    $sqlAdmin = Read-Host "Please, input the SQL Admin username"
    $deploymentOptions["SqlAdmin"] = $sqlAdmin
}
else
{
    $sqlAdmin = $deploymentOptions["SqlAdmin"]    
}
$sqlPass = Read-Host "Please, input the SQL Admin ($sqlAdmin) password" -AsSecureString

if (-not($DoPartialUpgrade))
{
    $upgrading = $false
}
else
{
    $upgrading = $true

    if ($null -ne $rg)
    {
        if ($upgrading -and $null -ne $sa) 
        {
            $containers = Get-AzStorageContainer -Context $sa.Context
        }
        else
        {
            $upgrading = $false    
            Write-Host "Did not find the $storageAccountName Storage Account." -ForegroundColor Yellow
        }
    
        if ($upgrading -and $null -ne $sql)
        {
            $databases = Get-AzSqlDatabase -ServerName $sql.ServerName -ResourceGroupName $resourceGroupName
            if (-not($databases | Where-Object { $_.DatabaseName -eq $sqlDatabaseName}))
            {
                $upgrading = $false
                Write-Host "Did not find the $sqlDatabaseName database." -ForegroundColor Yellow
            }
        }
        else
        {
            $upgrading = $false    
            Write-Host "Did not find the $sqlServerName SQL Server." -ForegroundColor Yellow
        }
    
        $auto = Get-AzAutomationAccount -ResourceGroupName $resourceGroupName -Name $automationAccountName -ErrorAction SilentlyContinue
        if ($null -ne $auto)
        {
            $runbooks = Get-AzAutomationRunbook -ResourceGroupName $resourceGroupName `
                -AutomationAccountName $auto.AutomationAccountName | Where-Object { $_.Name.StartsWith('Export') }
            if ($runbooks.Count -lt 3)
            {
                $upgrading = $false    
                Write-Host "Did not find existing runbooks in the $automationAccountName Automation Account." -ForegroundColor Yellow
            }
        }
        else
        {
            $upgrading = $false    
            Write-Host "Did not find the $automationAccountName Automation Account." -ForegroundColor Yellow
        }
    }
    else
    {
        $upgrading = $false    
    }        
}

$deploymentMessage = "Deploying Azure Optimization Engine to subscription"
if ($upgrading)
{
    Write-Host "Looks like this deployment was already done in the past. We will only upgrade runbooks, modules, schedules, variables, storage and the database." -ForegroundColor Yellow
    $deploymentMessage = "Upgrading Azure Optimization Engine in subscription"
}

$continueInput = Read-Host "$deploymentMessage $($subscriptions[$selectedSubscription].Name). Continue (Y/N)?"
if ("Y", "y" -contains $continueInput) {

    $deploymentOptions | ConvertTo-Json | Out-File -FilePath $lastDeploymentStatePath -Force
    
    $baseTime = (Get-Date).ToUniversalTime().ToString("u")
    $upgradingSchedules = $false
    $schedules = Get-AzAutomationSchedule -ResourceGroupName $resourceGroupName -AutomationAccountName $automationAccountName -ErrorAction SilentlyContinue
    if ($schedules.Count -gt 0) {
        $upgradingSchedules = $true
        $originalBaseTime = ($schedules | Where-Object { $_.Name.EndsWith("Weekly") } | Sort-Object -Property StartTime | Select-Object -First 1).StartTime.AddHours(-1.25).DateTime
        $now = (Get-Date).ToUniversalTime()
        $diff = $now.AddHours(-1.25) - $originalBaseTime
        $nextWeekDays = [Math]::Ceiling($diff.TotalDays / 7) * 7
        $baseTime = $now.AddHours(-1.25).AddDays($nextWeekDays - $diff.TotalDays).ToString("u")
        Write-Host "Existing schedules found. Keeping original base time: $baseTime." -ForegroundColor Green
    }
    else {
        Write-Host "Automation schedules base time automatically set to $baseTime." -ForegroundColor Green
    }

    if (-not($upgrading))
    {
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
            $deployment = New-AzDeployment -TemplateUri $TemplateUri -Location $targetLocation -rgName $resourceGroupName -Name $deploymentName `
                -projectLocation $targetlocation -logAnalyticsReuse $logAnalyticsReuse -baseTime $baseTime `
                -logAnalyticsWorkspaceName $laWorkspaceName -logAnalyticsWorkspaceRG $laWorkspaceResourceGroup `
                -storageAccountName $storageAccountName -automationAccountName $automationAccountName `
                -sqlServerName $sqlServerName -sqlDatabaseName $sqlDatabaseName -cloudEnvironment $AzureEnvironment `
                -sqlAdminLogin $sqlAdmin -sqlAdminPassword $sqlPass
        }
        else {
            $deployment = New-AzDeployment -TemplateUri $TemplateUri -Location $targetLocation -rgName $resourceGroupName -Name $deploymentName `
                -projectLocation $targetlocation -logAnalyticsReuse $logAnalyticsReuse -baseTime $baseTime `
                -logAnalyticsWorkspaceName $laWorkspaceName -logAnalyticsWorkspaceRG $laWorkspaceResourceGroup `
                -storageAccountName $storageAccountName -automationAccountName $automationAccountName `
                -sqlServerName $sqlServerName -sqlDatabaseName $sqlDatabaseName -cloudEnvironment $AzureEnvironment `
                -sqlAdminLogin $sqlAdmin -sqlAdminPassword $sqlPass -artifactsLocationSasToken (ConvertTo-SecureString $ArtifactsSasToken -AsPlainText -Force)        
        }
        $spnId = $deployment.Outputs['automationPrincipalId'].Value 
    }
    else
    {
        $upgradeManifest = Get-Content -Path "./upgrade-manifest.json" | ConvertFrom-Json
        Write-Host "Creating missing storage account containers..." -ForegroundColor Green
        $upgradeContainers = $upgradeManifest.dataCollection.container
        foreach ($container in $upgradeContainers)
        {
            if (-not($container -in $containers.Name))
            {
                New-AzStorageContainer -Name $container -Context $sa.Context -Permission Off | Out-Null
                Write-Host "$container container created."
            }
        }

        Write-Host "Importing runbooks..." -ForegroundColor Green
        $allRunbooks = $upgradeManifest.baseIngest.runbook + $upgradeManifest.dataCollection.runbook + $upgradeManifest.recommendations.runbook + $upgradeManifest.remediations.runbook
        $runbookBaseUri = $TemplateUri.Replace("azuredeploy.json", "")
        $topTemplateJson = "{ `"`$schema`": `"https://schema.management.azure.com/schemas/2019-04-01/deploymentTemplate.json#`", " + `
            "`"contentVersion`": `"1.0.0.0`", `"resources`": ["
        $bottomTemplateJson = "] }"
        $runbookDeploymentTemplateJson = $topTemplateJson
        for ($i = 0; $i -lt $allRunbooks.Count; $i++)
        {
            try {
                Invoke-WebRequest -Uri ($runbookBaseUri + $allRunbooks[$i]) | Out-Null
                $runbookName = [System.IO.Path]::GetFilenameWithoutExtension($allRunbooks[$i])
                $runbookJson = "{ `"name`": `"$automationAccountName/$runbookName`", `"type`": `"Microsoft.Automation/automationAccounts/runbooks`", " + `
                "`"apiVersion`": `"2018-06-30`", `"location`": `"$targetLocation`", `"properties`": { " + `
                "`"runbookType`": `"PowerShell`", `"logProgress`": false, `"logVerbose`": false, " + `
                "`"publishContentLink`": { `"uri`": `"$runbookBaseUri$($allRunbooks[$i])`" } } }"
                $runbookDeploymentTemplateJson += $runbookJson
                if ($i -lt $allRunbooks.Count - 1)
                {
                    $runbookDeploymentTemplateJson += ", "
                }
                Write-Host "$($allRunbooks[$i]) imported."
            }
            catch {
                Write-Host "$($allRunbooks[$i]) not imported (not found)." -ForegroundColor Yellow
            }
        }
        $runbookDeploymentTemplateJson += $bottomTemplateJson
        $templateObject = ConvertFrom-Json $runbookDeploymentTemplateJson | ConvertTo-Hashtable
        Write-Host "Executing runbooks deployment..." -ForegroundColor Green
        New-AzResourceGroupDeployment -TemplateObject $templateObject -ResourceGroupName $resourceGroupName -Name ($deploymentNameTemplate -f "runbooks") | Out-Null
        Write-Host "Runbooks update deployed."

        Write-Host "Importing modules..." -ForegroundColor Green
        $allModules = $upgradeManifest.modules
        $modulesDeploymentTemplateJson = $topTemplateJson
        for ($i = 0; $i -lt $allModules.Count; $i++)
        {
            $moduleJson = "{ `"name`": `"$automationAccountName/$($allModules[$i].name)`", `"type`": `"Microsoft.Automation/automationAccounts/modules`", " + `
                "`"apiVersion`": `"2018-06-30`", `"location`": `"$targetLocation`", `"properties`": { " + `
                "`"contentLink`": { `"uri`": `"$($allModules[$i].url)`" } } "
            if ($allModules[$i].name -ne "Az.Accounts" -and $allModules[$i].name -ne "Microsoft.Graph.Authentication")
            {
                $moduleJson += ", `"dependsOn`": [ `"Az.Accounts`", `"Microsoft.Graph.Authentication`" ]"
            }
            $moduleJson += "}"
            $modulesDeploymentTemplateJson += $moduleJson
            if ($i -lt $allModules.Count - 1)
            {
                $modulesDeploymentTemplateJson += ", "
            }
            Write-Host "$($allModules[$i].name) imported."
        }
        $modulesDeploymentTemplateJson += $bottomTemplateJson
        $templateObject = ConvertFrom-Json $modulesDeploymentTemplateJson | ConvertTo-Hashtable
        Write-Host "Executing modules deployment..." -ForegroundColor Green
        New-AzResourceGroupDeployment -TemplateObject $templateObject -ResourceGroupName $resourceGroupName -Name ($deploymentNameTemplate -f "modules") | Out-Null
        Write-Host "Modules update deployed."

        Write-Host "Updating schedules..." -ForegroundColor Green
        $allSchedules = $upgradeManifest.schedules

        $allScheduledRunbooks = Get-AzAutomationScheduledRunbook -AutomationAccountName $AutomationAccountName -ResourceGroupName $ResourceGroupName
        $exportHybridWorkerOption = ($allScheduledRunbooks | Where-Object { $_.RunbookName.StartsWith("Export") })[0].HybridWorker
        $ingestHybridWorkerOption = ($allScheduledRunbooks | Where-Object { $_.RunbookName.StartsWith("Ingest") })[0].HybridWorker
        $recommendHybridWorkerOption = ($allScheduledRunbooks | Where-Object { $_.RunbookName.StartsWith("Recommend") })[0].HybridWorker
        if ($allScheduledRunbooks | Where-Object { $_.RunbookName.StartsWith("Remediate") })
        {
            $remediateHybridWorkerOption = ($allScheduledRunbooks | Where-Object { $_.RunbookName.StartsWith("Remediate") })[0].HybridWorker
        }
        
        $hybridWorkerOption = "None"
        if ($exportHybridWorkerOption -or $ingestHybridWorkerOption -or $recommendHybridWorkerOption -or $remediateHybridWorkerOption) {
            $hybridWorkerOption = "Export: $exportHybridWorkerOption; Ingest: $ingestHybridWorkerOption; Recommend: $recommendHybridWorkerOption; Remediate: $remediateHybridWorkerOption"
        }      
        Write-Host "Current Hybrid Worker option: $hybridWorkerOption" -ForegroundColor Green            

        foreach ($schedule in $allSchedules)
        {
            if (-not($schedules | Where-Object { $_.Name -eq $schedule.name }))
            {
                $scheduleStartTime = (Get-Date $baseTime).Add([System.Xml.XmlConvert]::ToTimeSpan($schedule.offset))
                $scheduleNow = (Get-Date).ToUniversalTime()

                if ($schedule.frequency -eq "Hour")
                {
                    if ($scheduleNow.AddMinutes(5) -gt $scheduleStartTime)
                    {
                        $hoursDiff = ($scheduleNow - $scheduleStartTime).Hours + 1
                        $scheduleStartTime = $scheduleStartTime.AddHours($hoursDiff)
                    }

                    New-AzAutomationSchedule -Name $schedule.name -AutomationAccountName $automationAccountName -ResourceGroupName $resourceGroupName `
                        -StartTime $scheduleStartTime -HourInterval 1 | Out-Null
                }
                if ($schedule.frequency -eq "Day")
                {
                    if ($scheduleNow.AddMinutes(5) -gt $scheduleStartTime)
                    {
                        $scheduleStartTime = $scheduleStartTime.AddDays(1)
                    }

                    New-AzAutomationSchedule -Name $schedule.name -AutomationAccountName $automationAccountName -ResourceGroupName $resourceGroupName `
                        -StartTime $scheduleStartTime -DayInterval 1 | Out-Null
                }
                if ($schedule.frequency -eq "Week")
                {
                    if ($scheduleNow.AddMinutes(5) -gt $scheduleStartTime)
                    {
                        $scheduleStartTime = $scheduleStartTime.AddDays(7)
                    }

                    New-AzAutomationSchedule -Name $schedule.name -AutomationAccountName $automationAccountName -ResourceGroupName $resourceGroupName `
                        -StartTime $scheduleStartTime -WeekInterval 1 | Out-Null
                }
                Write-Host "$($schedule.name) schedule created."
            }

            $scheduledRunbooks = Get-AzAutomationScheduledRunbook -ResourceGroupName $resourceGroupName -AutomationAccountName $automationAccountName `
                -ScheduleName $schedule.name

            $dataExportsToSchedule = ($upgradeManifest.dataCollection + $upgradeManifest.recommendations) | Where-Object { $_.exportSchedule -eq $schedule.name }
            foreach ($dataExport in $dataExportsToSchedule)
            {
                $runbookName = [System.IO.Path]::GetFileNameWithoutExtension($dataExport.runbook)
                $runbookType = $runbookName.Split("-")[0]
                switch ($runbookType)
                {
                    "Export" {
                        $hybridWorkerName = $exportHybridWorkerOption
                    }
                    "Recommmend" {
                        $hybridWorkerName = $recommendHybridWorkerOption
                    }
                    "Ingest" {
                        $hybridWorkerName = $ingestHybridWorkerOption
                    }
                    "Remediate" {
                        $hybridWorkerName = $remediateHybridWorkerOption
                    }
                    Default {
                        $hybridWorkerName = $null
                    }
                }

                if (-not($scheduledRunbooks | Where-Object { $_.RunbookName -eq $runbookName}))
                {
                    if ($hybridWorkerName)
                    {
                        Register-AzAutomationScheduledRunbook -ResourceGroupName $resourceGroupName -AutomationAccountName $automationAccountName `
                            -RunbookName $runbookName -ScheduleName $schedule.name -RunOn $hybridWorkerName | Out-Null
                    }
                    else
                    {
                        Register-AzAutomationScheduledRunbook -ResourceGroupName $resourceGroupName -AutomationAccountName $automationAccountName `
                            -RunbookName $runbookName -ScheduleName $schedule.name | Out-Null                        
                    }
                    Write-Host "Added $($schedule.name) schedule to $hybridWorkerName $runbookName runbook"
                }
            }

            $dataExportsToMultiSchedule = $upgradeManifest.dataCollection | Where-Object { $_.exportSchedules.Count -gt 0 }

            foreach ($dataExport in $dataExportsToMultiSchedule)
            {
                $exportSchedule = $dataExport.exportSchedules | Where-Object { $_.schedule -eq $schedule.name }
                if ($exportSchedule)
                {
                    $runbookName = [System.IO.Path]::GetFileNameWithoutExtension($dataExport.runbook)
                    $runbookType = $runbookName.Split("-")[0]
                    switch ($runbookType)
                    {
                        "Export" {
                            $hybridWorkerName = $exportHybridWorkerOption
                        }
                        "Recommmend" {
                            $hybridWorkerName = $recommendHybridWorkerOption
                        }
                        "Ingest" {
                            $hybridWorkerName = $ingestHybridWorkerOption
                        }
                        "Remediate" {
                            $hybridWorkerName = $remediateHybridWorkerOption
                        }
                        Default {
                            $hybridWorkerName = $null
                        }
                    }
                    
                    if (-not($scheduledRunbooks | Where-Object { $_.RunbookName -eq $runbookName -and $_.ScheduleName -eq $schedule.name}))
                    {   
                        $params = @{}
                        $exportSchedule.parameters.PSObject.Properties | ForEach-Object {
                            $params[$_.Name] = $_.Value
                        }                                
    
                        if ($hybridWorkerName)
                        {
                            Register-AzAutomationScheduledRunbook -ResourceGroupName $resourceGroupName -AutomationAccountName $automationAccountName `
                                -RunbookName $runbookName -ScheduleName $schedule.name -RunOn $hybridWorkerName -Parameters $params | Out-Null
                        }
                        else
                        {
                            Register-AzAutomationScheduledRunbook -ResourceGroupName $resourceGroupName -AutomationAccountName $automationAccountName `
                                -RunbookName $runbookName -ScheduleName $schedule.name -Parameters $params | Out-Null                        
                        }
                        Write-Host "Added $($schedule.name) schedule to $hybridWorkerName $runbookName runbook."
                    }    
                }
            }

            $dataIngestToSchedule = $upgradeManifest.dataCollection | Where-Object { $_.ingestSchedule -eq $schedule.name }
            foreach ($dataIngest in $dataIngestToSchedule)
            {
                $runbookName = [System.IO.Path]::GetFileNameWithoutExtension(($upgradeManifest.baseIngest | Where-Object { $_.source -eq "dataCollection"}).runbook)
                $runbookType = $runbookName.Split("-")[0]
                switch ($runbookType)
                {
                    "Export" {
                        $hybridWorkerName = $exportHybridWorkerOption
                    }
                    "Recommmend" {
                        $hybridWorkerName = $recommendHybridWorkerOption
                    }
                    "Ingest" {
                        $hybridWorkerName = $ingestHybridWorkerOption
                    }
                    "Remediate" {
                        $hybridWorkerName = $remediateHybridWorkerOption
                    }
                    Default {
                        $hybridWorkerName = $null
                    }
                }
    
                if (-not($scheduledRunbooks | Where-Object { $_.RunbookName -eq $runbookName}))
                {
                    $params = @{"StorageSinkContainer"=$dataIngest.container}

                    if ($hybridWorkerName)
                    {
                        Register-AzAutomationScheduledRunbook -ResourceGroupName $resourceGroupName -AutomationAccountName $automationAccountName `
                            -RunbookName $runbookName -ScheduleName $schedule.name -RunOn $hybridWorkerName -Parameters $params | Out-Null
                    }
                    else
                    {
                        Register-AzAutomationScheduledRunbook -ResourceGroupName $resourceGroupName -AutomationAccountName $automationAccountName `
                            -RunbookName $runbookName -ScheduleName $schedule.name -Parameters $params | Out-Null                        
                    }
                    Write-Host "Added $($schedule.name) schedule to $hybridWorkerName $runbookName runbook."
                }
            }
        }

        Write-Host "Updating variables..." -ForegroundColor Green
        $allVariables = $upgradeManifest.dataCollection.requiredVariables + $upgradeManifest.recommendations.requiredVariables + $upgradeManifest.remediations.requiredVariables
        foreach ($variable in $allVariables)
        {
            $existingVariables = Get-AzAutomationVariable -ResourceGroupName $resourceGroupName -AutomationAccountName $automationAccountName
            if (-not($existingVariables | Where-Object { $_.Name -eq $variable.name }))
            {
                New-AzAutomationVariable -Name $variable.name -AutomationAccountName $automationAccountName -ResourceGroupName $resourceGroupName `
                    -Value $variable.defaultValue -Encrypted $false | Out-Null
                Write-Host "$($variable.name) variable created."
            }
        }

        Write-Host "Removing deprecated runbooks..." -ForegroundColor Green
        $deprecatedRunbooks = $upgradeManifest.deprecatedRunbooks
        foreach ($deprecatedRunbook in $deprecatedRunbooks)
        {
            Remove-AzAutomationRunbook -AutomationAccountName $automationAccountName -Name $deprecatedRunbook -ResourceGroupName $resourceGroupName -Force -ErrorAction SilentlyContinue
        }
    }

    if ($upgradingSchedules) {
        $schedules = Get-AzAutomationSchedule -ResourceGroupName $resourceGroupName -AutomationAccountName $automationAccountName
        $dailySchedules = $schedules | Where-Object { $_.Frequency -eq "Day" -or $_.Frequency -eq "Hour" }
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
                  `"frequency`": `"$($schedule.Frequency.ToString())`",
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

    Write-Host "Deploying SQL Database model..." -ForegroundColor Green
    
    $sqlPassPlain = (New-Object PSCredential "user", $sqlPass).GetNetworkCredential().Password        
    $sqlServerEndpoint = "$sqlServerName$($cloudDetails.SqlDatabaseDnsSuffix)"
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

            $Conn = New-Object System.Data.SqlClient.SqlConnection("Server=tcp:$sqlServerEndpoint,1433;Database=$databaseName;User ID=$sqlAdmin;Password=$sqlPassPlain;Trusted_Connection=False;Encrypt=True;Connection Timeout=$SqlTimeout;") 
            $Conn.Open() 
    
            $createTableQuery = Get-Content -Path "./model/recommendations-sp.sql"
            $Cmd = new-object system.Data.SqlClient.SqlCommand
            $Cmd.Connection = $Conn
            $Cmd.CommandTimeout = $SqlTimeout
            $Cmd.CommandText = $createTableQuery
            $Cmd.ExecuteReader()
            $Conn.Close()

            $Conn = New-Object System.Data.SqlClient.SqlConnection("Server=tcp:$sqlServerEndpoint,1433;Database=$databaseName;User ID=$sqlAdmin;Password=$sqlPassPlain;Trusted_Connection=False;Encrypt=True;Connection Timeout=$SqlTimeout;") 
            $Conn.Open() 
    
            $createTableQuery = Get-Content -Path "./model/filters-table.sql"
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

    Write-Host "Publishing workbooks..." -ForegroundColor Green
    $workbooks = Get-ChildItem -Path "./views/workbooks/" | Where-Object { $_.Name.EndsWith("-arm.json") }
    $la = Get-AzOperationalInsightsWorkspace -ResourceGroupName $laWorkspaceResourceGroup -Name $laWorkspaceName
    foreach ($workbook in $workbooks)
    {
        $armTemplate = Get-Content -Path $workbook.FullName | ConvertFrom-Json
        Write-Host "Deploying $($armTemplate.parameters.workbookDisplayName.defaultValue) workbook..."
        try {
            New-AzResourceGroupDeployment -TemplateFile $workbook.FullName -ResourceGroupName $resourceGroupName -Name ($deploymentNameTemplate -f $workbook.Name) `
                -workbookSourceId $la.ResourceId | Out-Null        
        }
        catch {
            Write-Host "Failed to deploy the workbook. If you are upgrading AOE, please remove first the $($armTemplate.parameters.workbookDisplayName.defaultValue) workbook from the $laWorkspaceName Log Analytics workspace and then re-deploy." -ForegroundColor Yellow            
        }
    }
    
    if ($null -eq $spnId)
    {
        $auto = Get-AzAutomationAccount -Name $automationAccountName -ResourceGroupName $resourceGroupName
        $spnId = $auto.Identity.PrincipalId
        if ($null -eq $spnId)
        {
            $runAsConnection = Get-AzAutomationConnection -ResourceGroupName $resourceGroupName -AutomationAccountName $automationAccountName -Name AzureRunAsConnection -ErrorAction SilentlyContinue
            $runAsAppId = $runAsConnection.FieldDefinitionValues.ApplicationId
            if ($runAsAppId)
            {
                $runAsServicePrincipal = Get-AzADServicePrincipal -ApplicationId $runAsAppId
                $spnId = $runAsServicePrincipal.Id
            }
        }
    }

    try
    {
        Import-Module Microsoft.Graph.Authentication
        Import-Module Microsoft.Graph.Identity.DirectoryManagement

        Write-Host "Granting Azure AD Global Reader role to the Automation Account..." -ForegroundColor Green

        #workaround for https://github.com/microsoftgraph/msgraph-sdk-powershell/issues/888
        $localPath = [System.Environment]::GetFolderPath([System.Environment+SpecialFolder]::UserProfile)
        if (-not(get-item "$localPath\.graph\" -ErrorAction SilentlyContinue))
        {
            New-Item -Type Directory "$localPath\.graph"
        }
        
        $graphEnvironment = "Global"
        $graphEndpointUri = "https://graph.microsoft.com"  
        if ($AzureEnvironment -eq "AzureUSGovernment")
        {
            $graphEnvironment = "USGov"
            $graphEndpointUri = "https://graph.microsoft.us"
        }
        if ($AzureEnvironment -eq "AzureChinaCloud")
        {
            $graphEnvironment = "China"
            $graphEndpointUri = "https://microsoftgraph.chinacloudapi.cn"
        }
        if ($AzureEnvironment -eq "AzureGermanCloud")
        {
            $graphEnvironment = "Germany"
            $graphEndpointUri = "https://graph.microsoft.de"
        }
        
        $token = Get-AzAccessToken -ResourceUrl $graphEndpointUri
        Connect-MgGraph -AccessToken $token.Token -Environment $graphEnvironment

        $globalReaderRole = Get-MgDirectoryRole -ExpandProperty Members -Property Id,Members,DisplayName,RoleTemplateId `
            | Where-Object { $_.RoleTemplateId -eq "f2ef992c-3afb-46b9-b7cf-a126ee74c451" }
        $globalReaders = $globalReaderRole.Members.Id
        if (-not($globalReaders -contains $spnId))
        {
            New-MgDirectoryRoleMemberByRef -DirectoryRoleId $globalReaderRole.Id -BodyParameter @{"@odata.id" = "https://graph.microsoft.com/v1.0/directoryObjects/$spnId"}
            Write-Host "Role granted." -ForegroundColor Green
        }
        else
        {
            Write-Host "Role was already granted." -ForegroundColor Green            
        }        
    }
    catch
    {
        Write-Host $Error[0] -ForegroundColor Yellow
        Write-Host "Could not grant role. If you want Azure AD-based recommendations, please grant the Global Reader role manually to the $automationAccountName managed identity or, for previous versions of AOE, to the Run As Account principal." -ForegroundColor Red
    }

    Write-Host "Deployment completed!" -ForegroundColor Green
}
else {
    Write-Host "Deployment cancelled." -ForegroundColor Red
}
