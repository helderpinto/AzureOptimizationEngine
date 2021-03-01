param(
    [Parameter(Mandatory = $false)] 
    [String] $AzureEnvironment = "AzureCloud",

    [Parameter(Mandatory = $false)] 
    [String[]] $WorkspaceIds,

    [Parameter(Mandatory = $false)]
    [switch] $AutoFix,

    [Parameter(Mandatory = $false)] 
    [int] $IntervalSeconds = 60
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

$wsIds = foreach ($workspaceId in $WorkspaceIds)
{
    "'$workspaceId'"
}
if ($wsIds)
{
    $wsIds = $wsIds -join ","
    $whereWsIds = " and properties.customerId in ($wsIds)"
}

$perfCounters = Get-Content -Path ".\perfcounters.json" | ConvertFrom-Json 

$ARGPageSize = 1000

$subscriptions = Get-AzSubscription | Where-Object { $_.State -eq "Enabled" } | ForEach-Object { "$($_.Id)"}

$argQuery = "resources | where type =~ 'microsoft.operationalinsights/workspaces'$whereWsIds | order by id"

$workspaces = Search-AzGraph -Query $argQuery -First $ARGPageSize -Subscription $subscriptions

Write-Output "Found $($workspaces.Count) workspaces."

$laQuery = "Heartbeat | where TimeGenerated > ago(1d) and ComputerEnvironment == 'Azure' | distinct Computer | summarize AzureComputersCount = count()"

foreach ($workspace in $workspaces) {
    $laQueryResults = Invoke-AzOperationalInsightsQuery -WorkspaceId $workspace.properties.customerId -Query $laQuery -Timespan (New-TimeSpan -Days 1)
    $results = [System.Linq.Enumerable]::ToArray($laQueryResults.Results)
    Write-Output "$($workspace.name): $($results.AzureComputersCount) Azure computers connected."
    if ($results.AzureComputersCount -gt 0)
    {
        if ($ctx.Subscription.SubscriptionId -ne $workspace.subscriptionId)
        {
            $ctx = Set-AzContext -SubscriptionId $workspace.subscriptionId
        }
        $dsWindows = Get-AzOperationalInsightsDataSource -ResourceGroupName $workspace.resourceGroup -WorkspaceName $workspace.name -Kind WindowsPerformanceCounter
        foreach ($perfCounter in ($perfCounters | Where-Object {$_.osType -eq "Windows"})) {
            if (-not($dsWindows | Where-Object { $_.Properties.ObjectName -eq $perfCounter.objectName -and $_.Properties.InstanceName -eq $perfCounter.instance `
                -and $_.Properties.CounterName -eq $perfCounter.counterName}))
            {
                Write-Output "Missing $($perfCounter.objectName)($($perfCounter.instance))\$($perfCounter.counterName)"
                if ($AutoFix)
                {
                    Write-Output "Fixing..."
                    $dsName = "DataSource_WindowsPerformanceCounter_$(New-Guid)"
                    New-AzOperationalInsightsWindowsPerformanceCounterDataSource -ResourceGroupName $workspace.resourceGroup -WorkspaceName $workspace.name `
                        -Name $dsName -ObjectName $perfCounter.objectName -CounterName $perfCounter.counterName -InstanceName $perfCounter.instance `
                        -IntervalSeconds $IntervalSeconds -Force | Out-Null
                }
            }
        }

        $missingLinuxCounters = @()
        $dsLinux = Get-AzOperationalInsightsDataSource -ResourceGroupName $workspace.resourceGroup -WorkspaceName $workspace.name -Kind LinuxPerformanceObject
        foreach ($perfCounter in ($perfCounters | Where-Object {$_.osType -eq "Linux"})) {
            if (-not($dsLinux | Where-Object { $_.Properties.ObjectName -eq $perfCounter.objectName -and $_.Properties.InstanceName -eq $perfCounter.instance `
                -and ($_.Properties.PerformanceCounters | Where-Object { $_.CounterName -eq $perfCounter.counterName }) }))
            {
                Write-Output "Missing $($perfCounter.objectName)($($perfCounter.instance))\$($perfCounter.counterName)"
                if ($AutoFix)
                {
                    $missingLinuxCounters += $perfCounter
                }
            }
        }

        if ($AutoFix)
        {
            $fixedLinuxCounters = @()
            $existingLinuxObjects = ($dsLinux | Select-Object -ExpandProperty Properties | Select-Object -Property ObjectName).ObjectName
            foreach ($linuxObject in $existingLinuxObjects) {
                $missingObjectCounters = $missingLinuxCounters | Where-Object { $_.objectName -eq $linuxObject }
                $originalDataSource = $dsLinux | Where-Object { $_.Properties.ObjectName -eq $linuxObject }
                foreach ($perfCounter in $missingObjectCounters) {
                    $fixedLinuxCounters += $perfCounter
                    $newCounterName = New-Object -TypeName Microsoft.Azure.Commands.OperationalInsights.Models.PerformanceCounterIdentifier -Property @{CounterName = $perfCounter.counterName}
                    $originalDataSource.Properties.PerformanceCounters.Add($newCounterName)
                }
                if ($missingObjectCounters)
                {
                    Write-Output "Fixing $linuxObject object..."
                    Set-AzOperationalInsightsDataSource -DataSource $originalDataSource | Out-Null
                }
            }
            $missingObjects = ($missingLinuxCounters | Select-Object -Property objectName -Unique).objectName
            $fixedObjects = ($fixedLinuxCounters | Select-Object -Property objectName -Unique).objectName
            $missingObjects = $missingObjects | Where-Object { -not($_ -in $fixedObjects) }
            foreach ($linuxObject in $missingObjects) {
                $missingObjectCounters = $missingLinuxCounters | Where-Object { $_.objectName -eq $linuxObject }
                $missingInstance = ($missingObjectCounters | Select-Object -Property instance -Unique -First).instance
                $missingCounterNames = ($missingObjectCounters).counterName
    
                Write-Output "Adding $linuxObject object..."
                New-AzOperationalInsightsLinuxPerformanceObjectDataSource -ResourceGroupName $workspace.resourceGroup -WorkspaceName $workspace.name `
                    -Name "DataSource_LinuxPerformanceObject_$(New-Guid)" -ObjectName $linuxObject -InstanceName $missingInstance -IntervalSeconds $IntervalSeconds `
                    -CounterNames $missingCounterNames -Force | Out-Null
            }    
        }
    }
}