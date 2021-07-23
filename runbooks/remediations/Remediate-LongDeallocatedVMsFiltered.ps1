param(
    [Parameter(Mandatory = $false)]
    [bool] $Simulate = $true
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

$minFitScore = 5.0

$minWeeksInARow = [int] (Get-AutomationVariable -Name  "AzureOptimization_RemediateLongDeallocatedVMsMinWeeksInARow" -ErrorAction SilentlyContinue)
if (-not($minWeeksInARow -gt 0)) {
    $minWeeksInARow = 4
}

$tagsFilter = Get-AutomationVariable -Name  "AzureOptimization_RemediateLongDeallocatedVMsTagsFilter" -ErrorAction SilentlyContinue
# example: '[ { "tagName": "a", "tagValue": "b" }, { "tagName": "c", "tagValue": "d" } ]'
if (-not($tagsFilter)) {
    $tagsFilter = '{}'
}
$tagsFilter = $tagsFilter | ConvertFrom-Json

$recommendationId = Get-AutomationVariable -Name  "AzureOptimization_RecommendationLongDeallocatedVMsId" -ErrorAction SilentlyContinue
if (-not($recommendationId)) {
    $recommendationId = 'c320b790-2e58-452a-aa63-7b62c383ad8a'
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

        <#

        SELECT InstanceId, COUNT(InstanceId) as RecCount
FROM [dbo].[Recommendations]
WHERE RecommendationSubTypeId = 'c320b790-2e58-452a-aa63-7b62c383ad8a' AND FitScore >= 4 AND GeneratedDate >= GETDATE()-(5*7)-- AND SubscriptionGuid IN ('6cb52f26-4370-4d50-afa5-b47282f84704','e054c9f5-d781-4a83-a835-2296004b9fe6','e1c0fd01-ecae-4ae5-ae72-3f70db6ec72f')
GROUP BY InstanceId
HAVING COUNT(InstanceId) >= 5
ORDER BY RecCount DESC

        #>

        $Cmd.CommandText = @"
        SELECT InstanceId, Cloud, TenantGuid, COUNT(InstanceId)
        FROM [dbo].[$recommendationsTable] 
        WHERE RecommendationSubTypeId = '$recommendationId' AND FitScore >= $minFitScore AND GeneratedDate >= GETDATE()-(7*$minWeeksInARow)
        GROUP BY InstanceId, Cloud, TenantGuid
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

$Conn.Close()    
$Conn.Dispose()            

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
        $vmTags = Get-AzTag -ResourceId $vm.InstanceId -ErrorAction SilentlyContinue
        if ($vmTags)
        {
            foreach ($tagFilter in $tagsFilter)
            {
                if ($vmTags.Properties.TagsProperty.($tagFilter.tagName) -eq $tagFilter.tagValue)
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

    $subscriptionId = $vm.InstanceId.Split("/")[2]
    $resourceGroup = $vm.InstanceId.Split("/")[4]
    $instanceName = $vm.InstanceId.Split("/")[8]
    
    if ($isVmEligible)
    {
        Write-Output "Downsizing (SIMULATE=$Simulate) $($vm.InstanceId) disks Standard_LRS..."
        if (-not($Simulate) -and $ctx.Environment.Name -eq $vm.Cloud -and $ctx.Tenant.Id -eq $vm.TenantGuid)
        {
            if ($ctx.Subscription.Id -ne $subscriptionId)
            {
                Select-AzSubscription -SubscriptionId $subscriptionId | Out-Null
                $ctx = Get-AzContext
            }
            $vmObj = Get-AzVM -ResourceGroupName $resourceGroup -VMName $instanceName -Status
            if ($vmObj.PowerState -eq 'VM deallocated')
            {
                $osDiskId = $vmObj.StorageProfile.OsDisk.ManagedDisk.Id
                $dataDiskIds = $vmObj.StorageProfile.DataDisks.ManagedDisk.Id
                if ($osDiskId)
                {
                    $disk = Get-AzDisk -ResourceGroupName $osDiskId.Split("/")[4] -DiskName $osDiskId.Split("/")[8]
                    if ($disk.Sku.Name -ne 'Standard_LRS')
                    {
                        $disk.Sku = [Microsoft.Azure.Management.Compute.Models.DiskSku]::new('Standard_LRS')
                        $disk | Update-AzDisk | Out-Null
                    }
                    else
                    {
                        Write-Output "Skipping as OS disk is already HDD."                        
                    }
                    foreach ($dataDiskId in $dataDiskIds)
                    {
                        $disk = Get-AzDisk -ResourceGroupName $dataDiskId.Split("/")[4] -DiskName $dataDiskId.Split("/")[8]
                        if ($disk.Sku.Name -ne 'Standard_LRS')
                        {
                            $disk.Sku = [Microsoft.Azure.Management.Compute.Models.DiskSku]::new('Standard_LRS')
                            $disk | Update-AzDisk | Out-Null
                        }
                        else
                        {
                            Write-Output "Skipping as Data disk is already HDD."                        
                        }                            
                    }
                }
                else
                {
                    Write-Output "Skipping as OS disk is not managed."    
                }
            }
            else
            {
                Write-Output "Skipping as VM is not deallocated."    
            }
        }
    }

    $logDetails = @{
        IsVmEligible = $isVmEligible
    }

    $logentry = New-Object PSObject -Property @{
        Timestamp = $timestamp
        Cloud = $vm.Cloud
        TenantGuid = $vm.TenantGuid
        SubscriptionGuid = $subscriptionId
        ResourceGroupName = $resourceGroup.ToLower()
        InstanceName = $instanceName.ToLower()
        InstanceId = $vm.InstanceId.ToLower()
        Simulate = $Simulate
        LogDetails = $logDetails | ConvertTo-Json
        RecommendationSubTypeId = $recommendationId
    }
    
    $logEntries += $logentry
}
    
$today = $datetime.ToString("yyyyMMdd")
$csvExportPath = "$today-longdeallocatedvmsfiltered.csv"

$logEntries | Export-Csv -Path $csvExportPath -NoTypeInformation

$csvBlobName = $csvExportPath

$csvProperties = @{"ContentType" = "text/csv"};

Set-AzStorageBlobContent -File $csvExportPath -Container $storageAccountSinkContainer -Properties $csvProperties -Blob $csvBlobName -Context $sa.Context -Force
