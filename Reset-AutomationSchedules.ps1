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

$subscriptionId = (Get-AzContext).Subscription.Id

$schedules = Get-AzAutomationSchedule -ResourceGroupName $ResourceGroupName -AutomationAccountName $AutomationAccountName
$weeklySchedules = $schedules | Where-Object { $_.Name.StartsWith("AzureOptimization") -and $_.Name.EndsWith("Weekly") }
if ($weeklySchedules.Count -gt 0) {
    $originalBaseTime = ($weeklySchedules | Sort-Object -Property StartTime | Select-Object -First 1).StartTime.AddHours(-1.25).DateTime
    $now = (Get-Date).ToUniversalTime()
    $diff = $now.AddHours(-1.25) - $originalBaseTime
    $nextWeekDays = [Math]::Ceiling($diff.TotalDays / 7) * 7
    $baseDateTime = $now.AddHours(-1.25).AddDays($nextWeekDays - $diff.TotalDays)
    $baseTimeStr = $baseDateTime.ToString("u")
    Write-Host "Existing schedules found. Weekly base time is $($baseDateTime.DayOfWeek) at $($baseDateTime.ToString('T')) (UTC)." -ForegroundColor Green
}
else {
    throw "The $AutomationAccountName Automation Account does not contain Azure Optimization Engine schedules."
}

$newBaseTimeStr = Read-Host "Please, enter a new base time for the *weekly* schedules in UTC (YYYY-MM-dd HH:mm:ss). If you want to keep the current one, just press ENTER"
if (-not($newBaseTimeStr)) {
    $newBaseTimeStr = $baseTimeStr
}
else {
    try {
        $newBaseTimeStr += "Z"
        $newBaseTime = [DateTime]::Parse($newBaseTimeStr)
    }
    catch {
        throw "$newBaseTimeStr is an invalid base time. Use the following format: YYYY-MM-dd HH:mm:ss. For example: 1977-09-08 06:14:15"
    }
    if ($newBaseTime -lt (Get-Date).ToUniversalTime().AddHours(-1)) {
        throw "$newBaseTimeStr is an invalid base time. It can't be sooner than $((Get-Date).ToUniversalTime().AddHours(-1).ToString('u'))"
    }
}

$baseTimeUtc = [DateTime]::Parse($newBaseTimeStr).ToUniversalTime()

if ($newBaseTimeStr -ne $baseTimeStr) {
    Write-Host "Updating current base schedule to every $($baseTimeUtc.DayOfWeek) at $($baseTimeUtc.TimeOfDay.ToString()) UTC..." -ForegroundColor Green
    $continueInput = Read-Host "Continue (Y/N)?"

    if ("Y", "y" -contains $continueInput) {
        $upgradeManifest = Get-Content -Path "./upgrade-manifest.json" | ConvertFrom-Json
        $manifestSchedules = $upgradeManifest.schedules

        foreach ($schedule in $schedules) {
            $manifestSchedule = $manifestSchedules | Where-Object { $_.name -eq $schedule.Name }
            if ($manifestSchedule) {
                if ($schedule.Frequency -eq "Week") {
                    $newStartTime = $baseTimeUtc.Add([System.Xml.XmlConvert]::ToTimeSpan($manifestSchedule.offset))
                }
                else {
                    $now = (Get-Date).ToUniversalTime()
                    $newStartTime = [System.DateTimeOffset]::Parse($now.ToString("yyyy-MM-ddT00:00:00Z"))
                    $newStartTime = $newStartTime.AddHours($baseTimeUtc.Hour).AddMinutes($baseTimeUtc.Minute).AddSeconds($baseTimeUtc.Second)
                    $newStartTime = $newStartTime.Add([System.Xml.XmlConvert]::ToTimeSpan($manifestSchedule.offset))                
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
                  `"interval`": $($schedule.Interval),
                  `"frequency`": `"$($schedule.Frequency)`",
                  `"advancedSchedule`": {}
                }
              }"
                Invoke-AzRestMethod -Path $automationPath -Method PUT -Payload $body | Out-Null    
            }
            else {
                Write-Host "$($schedule.Name) not found in schedules manifest." -ForegroundColor Yellow
            }
        }
    }
    else
    {
        throw "Interrupting schedules reset due to user input."   
    }
}
else {
    Write-Host "Kept current base schedule (every $($baseTimeUtc.DayOfWeek) at $($baseTimeUtc.TimeOfDay.ToString()) UTC)." -ForegroundColor Green
}

$exportHybridWorkerOption = ($scheduledRunbooks | Where-Object { $_.RunbookName.StartsWith("Export") })[0].HybridWorker
$ingestHybridWorkerOption = ($scheduledRunbooks | Where-Object { $_.RunbookName.StartsWith("Ingest") })[0].HybridWorker
$recommendHybridWorkerOption = ($scheduledRunbooks | Where-Object { $_.RunbookName.StartsWith("Recommend") })[0].HybridWorker
if ($scheduledRunbooks | Where-Object { $_.RunbookName.StartsWith("Remediate") })
{
    $remediateHybridWorkerOption = ($scheduledRunbooks | Where-Object { $_.RunbookName.StartsWith("Remediate") })[0].HybridWorker
}

$hybridWorkerOption = "None"
if ($exportHybridWorkerOption -or $ingestHybridWorkerOption -or $recommendHybridWorkerOption -or $remediateHybridWorkerOption) {
    $hybridWorkerOption = "Export: $exportHybridWorkerOption; Ingest: $ingestHybridWorkerOption; Recommend: $recommendHybridWorkerOption; Remediate: $remediateHybridWorkerOption"
}

Write-Host "Current Hybrid Worker option: $hybridWorkerOption" -ForegroundColor Green

$newHybridWorker = Read-Host "If you want all schedules to use the same Hybrid Worker, please enter the Hybrid Worker Group name (if you want to keep the current option, just press ENTER)"

if ($newHybridWorker)
{
    Write-Host "Updating Hybrid Worker Group in every runbook schedule to every $newHybridWorker..."    
    $continueInput = Read-Host "Continue (Y/N)?"

    if ("Y", "y" -contains $continueInput)
    {
        Write-Host "Unregistering previous runbook schedules associations from $automationAccountName..." -ForegroundColor Green
        foreach ($jobSchedule in $scheduledRunbooks) {
            if ($jobSchedule.ScheduleName.StartsWith("AzureOptimization")) {
                $jobSchedule = Get-AzAutomationScheduledRunbook -JobScheduleId $jobSchedule.JobScheduleId -ResourceGroupName $resourceGroupName `
                    -AutomationAccountName $automationAccountName
                Unregister-AzAutomationScheduledRunbook -ResourceGroupName $resourceGroupName -AutomationAccountName $automationAccountName `
                    -JobScheduleId $jobSchedule.JobScheduleId -Force
                Register-AzAutomationScheduledRunbook -ResourceGroupName $resourceGroupName -AutomationAccountName $automationAccountName `
                    -RunbookName $jobSchedule.RunbookName -ScheduleName $jobSchedule.ScheduleName -RunOn $newHybridWorker -Parameters $jobSchedule.Parameters | Out-Null
            }
        }        
    }
    else
    {
        throw "Interrupting schedules reset due to user input."   
    }
}
else
{
    Write-Host "Kept current Hybrid Worker option: $hybridWorkerOption" -ForegroundColor Green
}

Write-Host "DONE" -ForegroundColor Green