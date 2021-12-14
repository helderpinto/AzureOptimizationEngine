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
        [object] $appObject
    )
    
    $credObjects = @()

    foreach ($obj in $appObject.KeyCredentials)
    {
        $credObject = New-Object PSObject -Property @{
            DisplayName = $obj.DisplayName
            KeyId = $obj.KeyId
            KeyType = $obj.Type
            StartDate = (Get-Date($obj.StartDateTime)).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:00.000Z")
            EndDate = (Get-Date($obj.EndDateTime)).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:00.000Z")
        }
        $credObjects += $credObject        
    }

    foreach ($obj in $appObject.PasswordCredentials)
    {
        $credObject = New-Object PSObject -Property @{
            DisplayName = $obj.DisplayName
            KeyId = $obj.KeyId
            KeyType = "Password"
            StartDate = (Get-Date($obj.StartDateTime)).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:00.000Z")
            EndDate = (Get-Date($obj.EndDateTime)).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:00.000Z")
        }
        $credObjects += $credObject        
    }

    return $credObjects
}

function Build-PrincipalNames {
    param (
        [object] $appObject
    )
    
    $principalNames = @()

    if ($appObject.Web.HomePageUrl)
    {
        $principalNames += $appObject.Web.HomePageUrl
    }

    foreach ($obj in $appObject.IdentifierUris)
    {
        $principalNames += $obj
    }

    foreach ($obj in $appObject.ServicePrincipalNames)
    {
        $principalNames += $obj
    }

    foreach ($obj in $appObject.AlternativeNames)
    {
        $principalNames += $obj
    }

    return $principalNames
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

#workaround for https://github.com/microsoftgraph/msgraph-sdk-powershell/issues/888
$localPath = [System.Environment]::GetFolderPath([System.Environment+SpecialFolder]::UserProfile)
if (-not(get-item "$localPath\.graph\" -ErrorAction SilentlyContinue))
{
    New-Item -Type Directory "$localPath\.graph"
}

Import-Module Microsoft.Graph.Authentication
Import-Module Microsoft.Graph.Users
Import-Module Microsoft.Graph.Applications
Import-Module Microsoft.Graph.Groups

$graphEnvironment = "Global"
$graphEndpointUri = "https://graph.microsoft.com"  
if ($cloudEnvironment -eq "AzureUSGovernment")
{
    $graphEnvironment = "USGov"
    $graphEndpointUri = "https://graph.microsoft.us"
}
if ($cloudEnvironment -eq "AzureChinaCloud")
{
    $graphEnvironment = "China"
    $graphEndpointUri = "https://microsoftgraph.chinacloudapi.cn"
}
if ($cloudEnvironment -eq "AzureGermanCloud")
{
    $graphEnvironment = "Germany"
    $graphEndpointUri = "https://graph.microsoft.de"
}

$token = Get-AzAccessToken -ResourceUrl $graphEndpointUri
Connect-MgGraph -AccessToken $token.Token -Environment $graphEnvironment
    
$datetime = (get-date).ToUniversalTime()
$timestamp = $datetime.ToString("yyyy-MM-ddTHH:mm:00.000Z")

$aadObjectsTypes = $aadObjectsFilter.Split(",")

$fileDate = $datetime.ToString("yyyyMMdd")

if ("Application" -in $aadObjectsTypes)
{
    $aadObjects = @()

    Write-Output "Getting AAD applications..."
    $apps = Get-MgApplication -All -ExpandProperty Owners -Property Id,AppId,CreatedDateTime,DeletedDateTime,DisplayName,KeyCredentials,PasswordCredentials,Owners,PublisherDomain,Web,IdentifierUris
    Write-Output "Found $($apps.Count) AAD applications"

    foreach ($app in $apps)
    {
        $owners = $null
        if ($app.Owners.Count -gt 0)
        {
            $owners = ($app.Owners | Where-Object { [string]::IsNullOrEmpty($_.DeletedDateTime) }).Id | ConvertTo-Json
        }
        $createdDate = $null
        if ($app.CreatedDateTime)
        {
            $createdDate = (Get-Date($app.CreatedDateTime)).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:00.000Z")
        }
        $deletedDate = $null
        if ($app.DeletedDateTime)
        {
            $deletedDate = (Get-Date($app.DeletedDateTime)).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:00.000Z")
        }
        $aadObject = New-Object PSObject -Property @{
            Timestamp = $timestamp
            TenantGuid = $tenantId
            Cloud = $cloudEnvironment
            ObjectId = $app.Id
            ObjectType = "Application"
            ObjectSubType = "N/A"
            DisplayName = $app.DisplayName
            SecurityEnabled = "N/A"
            ApplicationId = $app.AppId
            Keys = (Build-CredObjectWithDates -appObject $app) | ConvertTo-Json
            PrincipalNames = (Build-PrincipalNames -appObject $app) | ConvertTo-Json
            Owners = $owners
            CreatedDate = $createdDate
            DeletedDate = $deletedDate
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
    $spns = Get-MgServicePrincipal -All -ExpandProperty Owners -Property Id,AppId,DeletedDateTime,DisplayName,KeyCredentials,PasswordCredentials,Owners,ServicePrincipalNames,ServicePrincipalType,AccountEnabled,AlternativeNames
    Write-Output "Found $($spns.Count) AAD service principals"
    
    foreach ($spn in $spns)
    {
        $owners = $null
        if ($spn.Owners.Count -gt 0)
        {
            $owners = ($spn.Owners | Where-Object { [string]::IsNullOrEmpty($_.DeletedDateTime) }).Id | ConvertTo-Json
        }
        $deletedDate = $null
        if ($spn.DeletedDateTime)
        {
            $deletedDate = (Get-Date($spn.DeletedDateTime)).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:00.000Z")
        }
        $aadObject = New-Object PSObject -Property @{
            Timestamp = $timestamp
            TenantGuid = $tenantId
            Cloud = $cloudEnvironment
            ObjectId = $spn.Id
            ObjectType = "ServicePrincipal"
            ObjectSubType = $spn.ServicePrincipalType
            DisplayName = $spn.DisplayName
            SecurityEnabled = $spn.AccountEnabled
            ApplicationId = $spn.AppId
            Keys = (Build-CredObjectWithDates -appObject $spn) | ConvertTo-Json
            PrincipalNames = (Build-PrincipalNames -appObject $spn) | ConvertTo-Json
            Owners = $owners
            DeletedDate = $deletedDate
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
    $users = Get-MgUser -All -Property Id,AccountEnabled,DisplayName,UserPrincipalName,UserType,CreatedDateTime,DeletedDateTime
    Write-Output "Found $($users.Count) AAD users"
    
    foreach ($user in $users)
    {
        $createdDate = $null
        if ($user.CreatedDateTime)
        {
            $createdDate = (Get-Date($user.CreatedDateTime)).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:00.000Z")
        }
        $deletedDate = $null
        if ($user.DeletedDateTime)
        {
            $deletedDate = (Get-Date($user.DeletedDateTime)).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:00.000Z")
        }
        $aadObject = New-Object PSObject -Property @{
            Timestamp = $timestamp
            TenantGuid = $tenantId
            Cloud = $cloudEnvironment
            ObjectId = $user.Id
            ObjectType = "User"
            ObjectSubType = $user.UserType
            DisplayName = $user.DisplayName
            SecurityEnabled = $user.AccountEnabled
            PrincipalNames = $user.UserPrincipalName
            CreatedDate = $createdDate
            DeletedDate = $deletedDate
        }
        $aadObjects += $aadObject    
    }

    $jsonExportPath = "$fileDate-$tenantId-aadobjects-users.json"
    $csvExportPath = "$fileDate-$tenantId-aadobjects-users.csv"
    
    $aadObjects | Export-Csv -NoTypeInformation -Path $csvExportPath
    Write-Output "Export to $csvExportPath"
    
    $csvBlobName = $csvExportPath
    $csvProperties = @{"ContentType" = "text/csv"};
    
    Set-AzStorageBlobContent -File $csvExportPath -Container $storageAccountSinkContainer -Properties $csvProperties -Blob $csvBlobName -Context $sa.Context -Force        
}

if ("Group" -in $aadObjectsTypes)
{
    $aadObjects = @()

    Write-Output "Getting AAD groups..."
    $groups = Get-MgGroup -All -ExpandProperty Members -Property Id,SecurityEnabled,DisplayName,Members,CreatedDateTime,DeletedDateTime,GroupTypes
    Write-Output "Found $($groups.Count) AAD groups"
    
    foreach ($group in $groups)
    {
        $groupMembers = $null
        if ($group.Members.Count -gt 0)
        {
            $groupMembers = $group.Members.Id | ConvertTo-Json
        }
        $createdDate = $null
        if ($group.CreatedDateTime)
        {
            $createdDate = (Get-Date($group.CreatedDateTime)).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:00.000Z")
        }
        $deletedDate = $null
        if ($group.DeletedDateTime)
        {
            $deletedDate = (Get-Date($group.DeletedDateTime)).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:00.000Z")
        }
        $aadObject = New-Object PSObject -Property @{
            Timestamp = $timestamp
            TenantGuid = $tenantId
            Cloud = $cloudEnvironment
            ObjectId = $group.Id
            ObjectType = "Group"
            ObjectSubType = $group.GroupTypes | ConvertTo-Json
            DisplayName = $group.DisplayName
            SecurityEnabled = $group.SecurityEnabled
            PrincipalNames = $groupMembers
            CreatedDate = $createdDate
            DeletedDate = $deletedDate
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