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

# Application,ServicePrincipal,User,Group
$aadObjectsFilter = Get-AutomationVariable -Name  "AzureOptimization_AADObjectsFilter" -ErrorAction SilentlyContinue
if ([string]::IsNullOrEmpty($aadObjectsFilter))
{
    $aadObjectsFilter = "Application,ServicePrincipal"
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

$aadObjectsTypes = $aadObjectsFilter.Split(",")

$fileDate = $datetime.ToString("yyyyMMdd")

if ("Application" -in $aadObjectsTypes)
{
    $aadObjects = @()

    Write-Output "Getting AAD applications..."
    $apps = Get-AzADApplication
    Write-Output "Found $($apps.Count) AAD applications"

    foreach ($app in $apps)
    {
        $appCred = Get-AzADAppCredential -ApplicationId $app.ApplicationId
        $aadObject = New-Object PSObject -Property @{
            Timestamp = $timestamp
            TenantGuid = $tenantId
            Cloud = $cloudEnvironment
            ObjectId = $app.ObjectId
            ObjectType = $app.ObjectType
            ObjectSubType = "N/A"
            DisplayName = $app.DisplayName
            SecurityEnabled = "N/A"
            ApplicationId = $app.ApplicationId
            Keys = (Build-CredObjectWithDates -credObjectWithStrings $appCred) | ConvertTo-Json
            PrincipalNames = $app.HomePage
        }
        $aadObjects += $aadObject    
    }   

    $jsonExportPath = "$fileDate-$tenantId-aadobjects-apps.json"
    $csvExportPath = "$fileDate-$tenantId-aadobjects-apps.csv"
    
    $aadObjects | ConvertTo-Json -Depth 3 | Out-File $jsonExportPath
    Write-Output "Exported to JSON: $($aadObjects.Count) lines"
    $aadObjectsJson = Get-Content -Path $jsonExportPath | ConvertFrom-Json
    Write-Output "JSON Import: $($aadObjectsJson.Count) lines"
    $aadObjectsJson | Export-Csv -NoTypeInformation -Path $csvExportPath
    Write-Output "Export to $csvExportPath"
    
    $csvBlobName = $csvExportPath
    $csvProperties = @{"ContentType" = "text/csv"};
    
    Set-AzStorageBlobContent -File $csvExportPath -Container $storageAccountSinkContainer -Properties $csvProperties -Blob $csvBlobName -Context $sa.Context -Force        
}

if ("ServicePrincipal" -in $aadObjectsTypes)
{
    $aadObjects = @()

    Write-Output "Getting AAD service principals..."
    $spns = Get-AzADServicePrincipal
    Write-Output "Found $($spns.Count) AAD service principals"
    
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
            TenantGuid = $tenantId
            Cloud = $cloudEnvironment
            ObjectId = $spn.Id
            ObjectType = $spn.ObjectType
            ObjectSubType = "N/A"
            DisplayName = $spn.DisplayName
            SecurityEnabled = "N/A"
            ApplicationId = $spn.ApplicationId
            Keys = (Build-CredObjectWithDates -credObjectWithStrings $spnCred) | ConvertTo-Json
            PrincipalNames = $principalNames
        }
        $aadObjects += $aadObject    
    }

    $jsonExportPath = "$fileDate-$tenantId-aadobjects-spns.json"
    $csvExportPath = "$fileDate-$tenantId-aadobjects-spns.csv"
    
    $aadObjects | ConvertTo-Json -Depth 3 | Out-File $jsonExportPath
    Write-Output "Exported to JSON: $($aadObjects.Count) lines"
    $aadObjectsJson = Get-Content -Path $jsonExportPath | ConvertFrom-Json
    Write-Output "JSON Import: $($aadObjectsJson.Count) lines"
    $aadObjectsJson | Export-Csv -NoTypeInformation -Path $csvExportPath
    Write-Output "Export to $csvExportPath"
    
    $csvBlobName = $csvExportPath
    $csvProperties = @{"ContentType" = "text/csv"};
    
    Set-AzStorageBlobContent -File $csvExportPath -Container $storageAccountSinkContainer -Properties $csvProperties -Blob $csvBlobName -Context $sa.Context -Force        
}

if ("User" -in $aadObjectsTypes)
{
    $aadObjects = @()

    Write-Output "Getting AAD users..."
    $users = Get-AzADUser
    Write-Output "Found $($users.Count) AAD users"
    
    foreach ($user in $users)
    {
        $aadObject = New-Object PSObject -Property @{
            Timestamp = $timestamp
            TenantGuid = $tenantId
            Cloud = $cloudEnvironment
            ObjectId = $user.Id
            ObjectType = "User"
            ObjectSubType = $user.Type
            DisplayName = $user.DisplayName
            SecurityEnabled = $user.AccountEnabled
            PrincipalNames = $user.UserPrincipalName
        }
        $aadObjects += $aadObject    
    }

    $jsonExportPath = "$fileDate-$tenantId-aadobjects-users.json"
    $csvExportPath = "$fileDate-$tenantId-aadobjects-users.csv"
    
    $aadObjects | ConvertTo-Json -Depth 3 | Out-File $jsonExportPath
    Write-Output "Exported to JSON: $($aadObjects.Count) lines"
    $aadObjectsJson = Get-Content -Path $jsonExportPath | ConvertFrom-Json
    Write-Output "JSON Import: $($aadObjectsJson.Count) lines"
    $aadObjectsJson | Export-Csv -NoTypeInformation -Path $csvExportPath
    Write-Output "Export to $csvExportPath"
    
    $csvBlobName = $csvExportPath
    $csvProperties = @{"ContentType" = "text/csv"};
    
    Set-AzStorageBlobContent -File $csvExportPath -Container $storageAccountSinkContainer -Properties $csvProperties -Blob $csvBlobName -Context $sa.Context -Force        
}

if ("Group" -in $aadObjectsTypes)
{
    $aadObjects = @()

    Write-Output "Getting AAD groups..."
    $groups = Get-AzADGroup
    Write-Output "Found $($groups.Count) AAD groups"
    
    foreach ($group in $groups)
    {
        $groupMembersObject = Get-AzADGroupMember -GroupObjectId $group.Id -ErrorAction Continue
        $groupMembers = $groupMembersObject.Id

        $aadObject = New-Object PSObject -Property @{
            Timestamp = $timestamp
            TenantGuid = $tenantId
            Cloud = $cloudEnvironment
            ObjectId = $group.Id
            ObjectType = "Group"
            ObjectSubType = $group.Type
            DisplayName = $group.DisplayName
            SecurityEnabled = $group.SecurityEnabled
            PrincipalNames = $groupMembers | ConvertTo-Json
        }
        $aadObjects += $aadObject    
    }

    $jsonExportPath = "$fileDate-$tenantId-aadobjects-groups.json"
    $csvExportPath = "$fileDate-$tenantId-aadobjects-groups.csv"
    
    $aadObjects | ConvertTo-Json -Depth 3 | Out-File $jsonExportPath
    Write-Output "Exported to JSON: $($aadObjects.Count) lines"
    $aadObjectsJson = Get-Content -Path $jsonExportPath | ConvertFrom-Json
    Write-Output "JSON Import: $($aadObjectsJson.Count) lines"
    $aadObjectsJson | Export-Csv -NoTypeInformation -Path $csvExportPath
    Write-Output "Export to $csvExportPath"
    
    $csvBlobName = $csvExportPath
    $csvProperties = @{"ContentType" = "text/csv"};
    
    Set-AzStorageBlobContent -File $csvExportPath -Container $storageAccountSinkContainer -Properties $csvProperties -Blob $csvBlobName -Context $sa.Context -Force        
}

Write-Output "DONE!"