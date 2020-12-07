param(
    [Parameter(Mandatory = $true)]
    [bool] $Simulate = $false
)

$ErrorActionPreference = "Stop"

$cloudEnvironment = Get-AutomationVariable -Name "AzureOptimization_CloudEnvironment" -ErrorAction SilentlyContinue # AzureCloud|AzureChinaCloud
if ([string]::IsNullOrEmpty($cloudEnvironment))
{
    $cloudEnvironment = "AzureCloud"
}
$authenticationOption = Get-AutomationVariable -Name "AzureOptimization_AuthenticationOption" -ErrorAction SilentlyContinue # RunAsAccount|ManagedIdentity
if ([string]::IsNullOrEmpty($authenticationOption))
{
    $authenticationOption = "RunAsAccount"
}

$sqlserver = Get-AutomationVariable -Name  "AzureOptimization_SQLServerHostname"
$sqlserverCredential = Get-AutomationPSCredential -Name "AzureOptimization_SQLServerCredential"
$SqlUsername = $sqlserverCredential.UserName 
$SqlPass = $sqlserverCredential.GetNetworkCredential().Password 
$sqldatabase = Get-AutomationVariable -Name  "AzureOptimization_SQLServerDatabase" -ErrorAction SilentlyContinue
if ([string]::IsNullOrEmpty($sqldatabase))
{
    $sqldatabase = "azureoptimization"
}
$storageAccountSink = Get-AutomationVariable -Name  "AzureOptimization_StorageSink"
$storageAccountSinkRG = Get-AutomationVariable -Name  "AzureOptimization_StorageSinkRG"
$storageAccountSinkSubscriptionId = Get-AutomationVariable -Name  "AzureOptimization_StorageSinkSubId"
$storageAccountSinkContainer = Get-AutomationVariable -Name  "AzureOptimization_RemediationLogsContainer" -ErrorAction SilentlyContinue 
if ([string]::IsNullOrEmpty($storageAccountSinkContainer)) {
    $storageAccountSinkContainer = "remediationlogs"
}

$minFitScore = [double] (Get-AutomationVariable -Name  "AzureOptimization_RemediateRightSizeMinFitScore" -ErrorAction SilentlyContinue)
if (-not($minFitScore -gt 0.0)) {
    $minFitScore = 5.0
}

$minWeeksInARow = [int] (Get-AutomationVariable -Name  "AzureOptimization_RemediateRightSizeMinWeeksInARow" -ErrorAction SilentlyContinue)
if (-not($minWeeksInARow -gt 0)) {
    $minWeeksInARow = 4
}

$tagsFilter = Get-AutomationVariable -Name  "AzureOptimization_RemediateRightSizeTagsFilter" -ErrorAction SilentlyContinue
# example: '[ { "tagName": "a", "tagValue": "b" }, { "tagName": "c", "tagValue": "d" } ]'
if (-not($tagsFilter)) {
    $tagsFilter = '{}'
}
$tagsFilter = $tagsFilter | ConvertFrom-Json

$rightSizeRecommendationId = Get-AutomationVariable -Name  "AzureOptimization_RecommendationAdvisorCostRightSizeId" -ErrorAction SilentlyContinue
if (-not($rightSizeRecommendationId)) {
    $rightSizeRecommendationId = 'e10b1381-5f0a-47ff-8c7b-37bd13d7c974'
}

$SqlTimeout = 120
$recommendationsTable = "Recommendations"

Write-Output "Logging in to Azure with $authenticationOption..."

switch ($authenticationOption) {
    "RunAsAccount" { 
        $ArmConn = Get-AutomationConnection -Name AzureRunAsConnection
        Connect-AzAccount -ServicePrincipal -EnvironmentName $cloudEnvironment -Tenant $ArmConn.TenantID -ApplicationId $ArmConn.ApplicationID -CertificateThumbprint $ArmConn.CertificateThumbprint
        break
    }
    "ManagedIdentity" { 
        Connect-AzAccount -Identity
        break
    }
    Default {
        $ArmConn = Get-AutomationConnection -Name AzureRunAsConnection
        Connect-AzAccount -ServicePrincipal -EnvironmentName $cloudEnvironment -Tenant $ArmConn.TenantID -ApplicationId $ArmConn.ApplicationID -CertificateThumbprint $ArmConn.CertificateThumbprint
        break
    }
}

# get reference to storage sink
Select-AzSubscription -SubscriptionId $storageAccountSinkSubscriptionId
$sa = Get-AzStorageAccount -ResourceGroupName $storageAccountSinkRG -Name $storageAccountSink

Write-Output "Querying for right-size recommendations with fit score >= $minFitScore made consecutively for the last $minWeeksInARow weeks."

$tries = 0
$connectionSuccess = $false
do {
    $tries++
    try {
        $Conn = New-Object System.Data.SqlClient.SqlConnection("Server=tcp:$sqlserver,1433;Database=$sqldatabase;User ID=$SqlUsername;Password=$SqlPass;Trusted_Connection=False;Encrypt=True;Connection Timeout=$SqlTimeout;") 
        $Conn.Open() 
        $Cmd=new-object system.Data.SqlClient.SqlCommand
        $Cmd.Connection = $Conn
        $Cmd.CommandTimeout = $SqlTimeout
        $Cmd.CommandText = @"
        SELECT RecommendationId, InstanceId, InstanceName, AdditionalInfo, ResourceGroup, SubscriptionGuid, Tags, COUNT(InstanceId)
        FROM [dbo].[$recommendationsTable] 
        WHERE RecommendationSubTypeId = '$rightSizeRecommendationId' AND FitScore >= $minFitScore AND GeneratedDate >= GETDATE()-(7*$minWeeksInARow)
        GROUP BY InstanceId, InstanceName, AdditionalInfo, ResourceGroup, SubscriptionGuid, Tags
        HAVING COUNT(InstanceId) >= $minWeeksInARow
"@    
        $sqlAdapter = New-Object System.Data.SqlClient.SqlDataAdapter
        $sqlAdapter.SelectCommand = $Cmd
        $vmsToRightSize = New-Object System.Data.DataTable
        $sqlAdapter.Fill($vmsToRightSize) | Out-Null            
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

Write-Output "Found $($vmsToRightSize.Rows.Count) remediation opportunities."

$logEntries = @()

$datetime = (get-date).ToUniversalTime()
$hour = $datetime.Hour
$min = $datetime.Minute
$timestamp = $datetime.ToString("yyyy-MM-ddT$($hour):$($min):00.000Z")

$ctx = Get-AzContext

foreach ($vm in $vmsToRightSize.Rows)
{
    $isVmEligible = $false
    if ([string]::IsNullOrEmpty($tagsFilter))
    {
        $isVmEligible = $true
    }
    else
    {
        $vmTags = $null
        if (-not([string]::IsNullOrEmpty($vm.Tags)))
        {
            $vmTags = $vm.Tags | ConvertFrom-Json
        }
        if ($vmTags)
        {
            foreach ($tagFilter in $tagsFilter)
            {
                if ($vmTags.($tagFilter.tagName) -eq $tagFilter.tagValue)
                {
                    $isVmEligible = $true
                }
                else
                {
                    $isVmEligible = $false
                    break
                }
            }
        }
    }

    $additionalInfo = $vm.AdditionalInfo | ConvertFrom-Json

    if ($isVmEligible -and $additionalInfo.targetSku -ne "Shutdown")
    {
        Write-Output "Downsizing (SIMULATE=$Simulate) $($vm.InstanceId) to $($additionalInfo.targetSku)..."
        if (-not($Simulate))
        {
            if ($ctx.Subscription.Id -ne $vm.SubscriptionGuid)
            {
                Select-AzSubscription -SubscriptionId $vm.SubscriptionGuid | Out-Null
                $ctx = Get-AzContext
            }
            $vmObj = Get-AzVM -ResourceGroupName $vm.ResourceGroup -VMName $vm.InstanceName
            $vmObj.HardwareProfile.VmSize = $additionalInfo.targetSku
            Update-AzVM -VM $vmObj -ResourceGroupName $vm.ResourceGroup    
        }
    }

    $logDetails = @{
        IsVmEligible = $isVmEligible
        CurrentSku = $additionalInfo.currentSku
        TargetSku = $additionalInfo.targetSku
    }

    $logentry = New-Object PSObject -Property @{
        Timestamp = $timestamp
        Cloud = $cloudEnvironment
        SubscriptionGuid = $vm.SubscriptionGuid
        ResourceGroupName = $vm.ResourceGroup.ToLower()
        InstanceName = $vm.InstanceName.ToLower()
        InstanceId = $vm.InstanceId.ToLower()
        Simulate = $Simulate
        LogDetails = $logDetails
        RecommendationId = $vm.RecommendationId
        RecommendationSubTypeId = $rightSizeRecommendationId
    }
    
    $logEntries += $logentry
}
    
$Conn.Close()    
$Conn.Dispose()            


$today = $datetime.ToString("yyyyMMdd")
$csvExportPath = "$today-rightsizefiltered.csv"

$logEntries | Export-Csv -Path $csvExportPath -NoTypeInformation

$csvBlobName = $csvExportPath

$csvProperties = @{"ContentType" = "text/csv"};

Set-AzStorageBlobContent -File $csvExportPath -Container $storageAccountSinkContainer -Properties $csvProperties -Blob $csvBlobName -Context $sa.Context -Force
