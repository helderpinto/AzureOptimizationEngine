param(
    [Parameter(Mandatory = $false)]
    [string] $externalCloudEnvironment = "",

    [Parameter(Mandatory = $false)]
    [string] $externalTenantId = "",

    [Parameter(Mandatory = $false)]
    [string] $externalCredentialName = ""
)

$ErrorActionPreference = "Stop"

function Build-CredObjectWithDates {
    param (
        [object[]] $credObjectWithStrings
    )
    
    $credObjects = @()

    foreach ($obj in $credObjectWithStrings)
    {
        $credObject = New-Object PSObject -Property @{
            KeyId = $obj.KeyId
            KeyType = $obj.Type
            StartDate = (Get-Date($obj.StartDate)).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:00.000Z")
            EndDate = (Get-Date($obj.EndDate)).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:00.000Z")
        }
        $credObjects += $credObject        
    }

    return $credObjects
}

$cloudEnvironment = Get-AutomationVariable -Name "AzureOptimization_CloudEnvironment" -ErrorAction SilentlyContinue # AzureCloud|AzureChinaCloud
if ([string]::IsNullOrEmpty($cloudEnvironment))
{
    $cloudEnvironment = "AzureCloud"
}
$authenticationOption = Get-AutomationVariable -Name  "AzureOptimization_AuthenticationOption" -ErrorAction SilentlyContinue # RunAsAccount|ManagedIdentity
if ([string]::IsNullOrEmpty($authenticationOption))
{
    $authenticationOption = "RunAsAccount"
}

# get Advisor exports sink (storage account) details
$storageAccountSink = Get-AutomationVariable -Name  "AzureOptimization_StorageSink"
$storageAccountSinkRG = Get-AutomationVariable -Name  "AzureOptimization_StorageSinkRG"
$storageAccountSinkSubscriptionId = Get-AutomationVariable -Name  "AzureOptimization_StorageSinkSubId"
$storageAccountSinkContainer = Get-AutomationVariable -Name  "AzureOptimization_AADObjectsContainer" -ErrorAction SilentlyContinue
if ([string]::IsNullOrEmpty($storageAccountSinkContainer))
{
    $storageAccountSinkContainer = "aadobjectsexports"
}

if (-not([string]::IsNullOrEmpty($externalCredentialName)))
{
    $externalCredential = Get-AutomationPSCredential -Name $externalCredentialName
}

Write-Output "Logging in to Azure with $authenticationOption..."

switch ($authenticationOption) {
    "RunAsAccount" { 
        $ArmConn = Get-AutomationConnection -Name AzureRunAsConnection
        Connect-AzAccount -ServicePrincipal -EnvironmentName $cloudEnvironment -Tenant $ArmConn.TenantID -ApplicationId $ArmConn.ApplicationID -CertificateThumbprint $ArmConn.CertificateThumbprint
        break
    }
    "ManagedIdentity" { 
        Connect-AzAccount -Identity -EnvironmentName $cloudEnvironment 
        break
    }
    Default {
        $ArmConn = Get-AutomationConnection -Name AzureRunAsConnection
        Connect-AzAccount -ServicePrincipal -EnvironmentName $cloudEnvironment -Tenant $ArmConn.TenantID -ApplicationId $ArmConn.ApplicationID -CertificateThumbprint $ArmConn.CertificateThumbprint
        break
    }
}

Select-AzSubscription -SubscriptionId $storageAccountSinkSubscriptionId
$sa = Get-AzStorageAccount -ResourceGroupName $storageAccountSinkRG -Name $storageAccountSink

if (-not([string]::IsNullOrEmpty($externalCredentialName)))
{
    Connect-AzAccount -ServicePrincipal -EnvironmentName $externalCloudEnvironment -Tenant $externalTenantId -Credential $externalCredential 
    $cloudEnvironment = $externalCloudEnvironment   
}

$tenantId = (Get-AzContext).Tenant.Id
$datetime = (get-date).ToUniversalTime()
$timestamp = $datetime.ToString("yyyy-MM-ddTHH:mm:00.000Z")

$aadObjects = @()

$apps = Get-AzADApplication
Write-Output "Found $($apps.Count) AAD applications"
$spns = Get-AzADServicePrincipal
Write-Output "Found $($spns.Count) AAD service principals"

foreach ($app in $apps)
{
    $appCred = Get-AzADAppCredential -ApplicationId $app.ApplicationId
    $aadObject = New-Object PSObject -Property @{
        Timestamp = $timestamp
        TenantId = $tenantId
        Cloud = $cloudEnvironment
        ObjectId = $app.ObjectId
        ObjectType = $app.ObjectType
        DisplayName = $app.DisplayName
        ApplicationId = $app.ApplicationId
        Keys = (Build-CredObjectWithDates -credObjectWithStrings $appCred) | ConvertTo-Json
        PrincipalNames = $app.HomePage
    }
    $aadObjects += $aadObject    
}

foreach ($spn in $spns)
{
    $spnCred = Get-AzADSpCredential -ObjectId $spn.Id
    if ($spn.ServicePrincipalNames)
    {
        $principalNames = $spn.ServicePrincipalNames | ConvertTo-Json
    }
    else
    {
        $principalNames = $spn.PrincipalNames | ConvertTo-Json        
    }
    $aadObject = New-Object PSObject -Property @{
        Timestamp = $timestamp
        TenantId = $tenantId
        Cloud = $cloudEnvironment
        ObjectId = $spn.ObjectId
        ObjectType = $spn.ObjectType
        DisplayName = $spn.DisplayName
        ApplicationId = $spn.ApplicationId
        Keys = (Build-CredObjectWithDates -credObjectWithStrings $spnCred) | ConvertTo-Json
        PrincipalNames = $principalNames
    }
    $aadObjects += $aadObject    
}

$fileDate = $datetime.ToString("yyyyMMdd")
$jsonExportPath = "$fileDate-$tenantId-aadobjects.json"
$csvExportPath = "$fileDate-$tenantId-aadobjects.csv"

$aadObjects | ConvertTo-Json -Depth 3 | Out-File $jsonExportPath
Write-Output "Exported to JSON: $($aadObjects.Count) lines"
$aadObjectsJson = Get-Content -Path $jsonExportPath | ConvertFrom-Json
Write-Output "JSON Import: $($aadObjectsJson.Count) lines"
$aadObjectsJson | Export-Csv -NoTypeInformation -Path $csvExportPath
Write-Output "Export to $csvExportPath"

$csvBlobName = $csvExportPath
$csvProperties = @{"ContentType" = "text/csv"};

Set-AzStorageBlobContent -File $csvExportPath -Container $storageAccountSinkContainer -Properties $csvProperties -Blob $csvBlobName -Context $sa.Context -Force

Write-Output "DONE!"