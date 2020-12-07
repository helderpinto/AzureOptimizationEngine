param(
    [Parameter(Mandatory = $true)]
    [string] $StorageSinkContainer
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
$workspaceId = Get-AutomationVariable -Name  "AzureOptimization_LogAnalyticsWorkspaceId"
$sharedKey = Get-AutomationVariable -Name  "AzureOptimization_LogAnalyticsWorkspaceKey"
$LogAnalyticsChunkSize = [int] (Get-AutomationVariable -Name  "AzureOptimization_LogAnalyticsChunkSize" -ErrorAction SilentlyContinue)
if (-not($LogAnalyticsChunkSize -gt 0))
{
    $LogAnalyticsChunkSize = 10000
}
$lognamePrefix = Get-AutomationVariable -Name  "AzureOptimization_LogAnalyticsLogPrefix" -ErrorAction SilentlyContinue
if ([string]::IsNullOrEmpty($lognamePrefix))
{
    $lognamePrefix = "AzureOptimization"
}
$storageAccountSink = Get-AutomationVariable -Name  "AzureOptimization_StorageSink"
$storageAccountSinkRG = Get-AutomationVariable -Name  "AzureOptimization_StorageSinkRG"
$storageAccountSinkSubscriptionId = Get-AutomationVariable -Name  "AzureOptimization_StorageSinkSubId"
$storageAccountSinkContainer = $StorageSinkContainer
$StorageBlobsPageSize = [int] (Get-AutomationVariable -Name  "AzureOptimization_StorageBlobsPageSize" -ErrorAction SilentlyContinue)
if (-not($StorageBlobsPageSize -gt 0))
{
    $StorageBlobsPageSize = 1000
}

$SqlTimeout = 120
$LogAnalyticsIngestControlTable = "LogAnalyticsIngestControl"

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

#region Functions

# Function to create the authorization signature
Function Build-OMSSignature ($workspaceId, $sharedKey, $date, $contentLength, $method, $contentType, $resource) {
    $xHeaders = "x-ms-date:" + $date
    $stringToHash = $method + "`n" + $contentLength + "`n" + $contentType + "`n" + $xHeaders + "`n" + $resource
    $bytesToHash = [Text.Encoding]::UTF8.GetBytes($stringToHash)
    $keyBytes = [Convert]::FromBase64String($sharedKey)
    $sha256 = New-Object System.Security.Cryptography.HMACSHA256
    $sha256.Key = $keyBytes
    $calculatedHash = $sha256.ComputeHash($bytesToHash)
    $encodedHash = [Convert]::ToBase64String($calculatedHash)
    $authorization = 'SharedKey {0}:{1}' -f $workspaceId, $encodedHash
    return $authorization
}

# Function to create and post the request
Function Post-OMSData($workspaceId, $sharedKey, $body, $logType, $TimeStampField) {
    $method = "POST"
    $contentType = "application/json"
    $resource = "/api/logs"
    $rfc1123date = [DateTime]::UtcNow.ToString("r")
    $contentLength = $body.Length
    $signature = Build-OMSSignature `
        -workspaceId $workspaceId `
        -sharedKey $sharedKey `
        -date $rfc1123date `
        -contentLength $contentLength `
        -method $method `
        -contentType $contentType `
        -resource $resource
    $uri = "https://" + $workspaceId + ".ods.opinsights.azure.com" + $resource + "?api-version=2016-04-01"

    $OMSheaders = @{
        "Authorization"        = $signature;
        "Log-Type"             = $logType;
        "x-ms-date"            = $rfc1123date;
        "time-generated-field" = $TimeStampField;
    }

    Try {

        $response = Invoke-WebRequest -Uri $uri -Method POST  -ContentType $contentType -Headers $OMSheaders -Body $body -UseBasicParsing -TimeoutSec 1000
    }
    catch {
        $_.Message
        if ($_.Exception.Response.StatusCode.Value__ -eq 401) {            
            "REAUTHENTICATING"

            $response = Invoke-WebRequest -Uri $uri -Method POST  -ContentType $contentType -Headers $OMSheaders -Body $body -UseBasicParsing -TimeoutSec 1000
        }
    }

    write-output $response.StatusCode
    return $response.StatusCode
    
}
#endregion Functions



# get reference to storage sink
Write-Output "Getting blobs list from $storageAccountSink storage account ($storageAccountSinkContainer container)..."
Select-AzSubscription -SubscriptionId $storageAccountSinkSubscriptionId
$sa = Get-AzStorageAccount -ResourceGroupName $storageAccountSinkRG -Name $storageAccountSink

$allblobs = @()

$continuationToken = $null
do
{
    $blobs = Get-AzStorageBlob -Container $storageAccountSinkContainer -MaxCount $StorageBlobsPageSize -ContinuationToken $continuationToken -Context $sa.Context | Sort-Object -Property LastModified
    if ($blobs.Count -le 0) { break }
    $allblobs += $blobs
    $continuationToken = $blobs[$blobs.Count -1].ContinuationToken;
}
While ($null -ne $continuationToken)

$newProcessedTime = $null

foreach ($blob in $allblobs) {

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
            $Cmd.CommandText = "SELECT * FROM [dbo].[$LogAnalyticsIngestControlTable] WHERE StorageContainerName = '$storageAccountSinkContainer'"
        
            $sqlAdapter = New-Object System.Data.SqlClient.SqlDataAdapter
            $sqlAdapter.SelectCommand = $Cmd
            $controlRows = New-Object System.Data.DataTable
            $sqlAdapter.Fill($controlRows) | Out-Null
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

    $controlRow = $controlRows[0]

    $Conn.Close()    
    $Conn.Dispose()            

    $lastProcessedLine = $controlRow.LastProcessedLine
    $lastProcessedDateTime = $controlRow.LastProcessedDateTime.ToUniversalTime().ToString("yyyy'-'MM'-'dd'T'HH':'mm':'ss'.'fff'Z'")
    $newProcessedTime = $blob.LastModified.ToUniversalTime().ToString("yyyy'-'MM'-'dd'T'HH':'mm':'ss'.'fff'Z'")
    if ($lastProcessedDateTime -lt $newProcessedTime) {
        Write-Output "About to process $($blob.Name)..."
        Get-AzStorageBlobContent -CloudBlob $blob.ICloudBlob -Context $sa.Context -Force
        $csvObject = Import-Csv $blob.Name

        $logname = $lognamePrefix + $controlRow.LogAnalyticsSuffix
        $linesProcessed = 0
        $csvObjectSplitted = @()

        if ($null -eq $csvObject)
        {
            $recCount = 0
        }
        elseif ($null -eq $csvObject.Count)
        {
            $recCount = 1
        }
        else
        {
            $recCount = $csvObject.Count    
        }

        if ($recCount -gt 1)
        {
            for ($i = 0; $i -lt $recCount; $i += $LogAnalyticsChunkSize) {
                $csvObjectSplitted += , @($csvObject[$i..($i + ($LogAnalyticsChunkSize - 1))]);
            }
        }
        else
        {
            $csvObjectArray = @()
            $csvObjectArray += $csvObject
            $csvObjectSplitted += , $csvObjectArray   
        }        
        
        for ($i = 0; $i -lt $csvObjectSplitted.Count; $i++) {
            $currentObjectLines = $csvObjectSplitted[$i].Count
            if ($lastProcessedLine -lt $linesProcessed) {				
			    $jsonObject = ConvertTo-Json -InputObject $csvObjectSplitted[$i]                
                $res = Post-OMSData -workspaceId $workspaceId -sharedKey $sharedKey -body ([System.Text.Encoding]::UTF8.GetBytes($jsonObject)) -logType $logname -TimeStampField "Timestamp"
                If ($res -ge 200 -and $res -lt 300) {
                    Write-Output "Succesfully uploaded $currentObjectLines $($controlTable.LogAnalyticsSuffix) rows to Log Analytics"    
                    $linesProcessed += $currentObjectLines
                    if ($i -eq ($csvObjectSplitted.Count - 1)) {
                        $lastProcessedLine = -1    
                    }
                    else {
                        $lastProcessedLine = $linesProcessed - 1   
                    }
                    
                    $updatedLastProcessedLine = $lastProcessedLine
                    $updatedLastProcessedDateTime = $lastProcessedDateTime
                    if ($i -eq ($csvObjectSplitted.Count - 1)) {
                        $updatedLastProcessedDateTime = $newProcessedTime
                    }
                    Write-Output "Updating last processed time / line to $($updatedLastProcessedDateTime) / $updatedLastProcessedLine"
                    $sqlStatement = "UPDATE [$LogAnalyticsIngestControlTable] SET LastProcessedLine = $updatedLastProcessedLine, LastProcessedDateTime = '$updatedLastProcessedDateTime' WHERE StorageContainerName = '$storageAccountSinkContainer'"
                    $Conn = New-Object System.Data.SqlClient.SqlConnection("Server=tcp:$sqlserver,1433;Database=$sqldatabase;User ID=$SqlUsername;Password=$SqlPass;Trusted_Connection=False;Encrypt=True;Connection Timeout=$SqlTimeout;") 
                    $Conn.Open() 
                    $Cmd=new-object system.Data.SqlClient.SqlCommand
                    $Cmd.Connection = $Conn
                    $Cmd.CommandText = $sqlStatement
                    $Cmd.CommandTimeout=120 
                    $Cmd.ExecuteReader()
                    $Conn.Close()    
                    $Conn.Dispose()            
                }
                Else {
                    $linesProcessed += $currentObjectLines
                    Write-Warning "Failed to upload $currentObjectLines $($controlTable.LogAnalyticsSuffix) rows"
                    throw
                }
            }
            else {
                $linesProcessed += $currentObjectLines  
            }            
        }
    }
}