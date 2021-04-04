param(
    [Parameter(Mandatory = $false)]
    [string] $externalCloudEnvironment = "",

    [Parameter(Mandatory = $false)]
    [string] $externalTenantId = "",

    [Parameter(Mandatory = $false)]
    [string] $externalCredentialName = ""
)

$ErrorActionPreference = "Stop"

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
$storageAccountSinkContainer = Get-AutomationVariable -Name  "AzureOptimization_RBACAssignmentsContainer" -ErrorAction SilentlyContinue
if ([string]::IsNullOrEmpty($storageAccountSinkContainer))
{
    $storageAccountSinkContainer = "rbacexports"
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

$subscriptions = Get-AzSubscription -TenantId $tenantId | Where-Object { $_.State -eq "Enabled" }

$roleAssignments = @()

Write-Output "Iterating through all reachable subscriptions..."

foreach ($subscription in $subscriptions) {

    Select-AzSubscription -SubscriptionId $subscription.Id -TenantId $tenantId | Out-Null

    $assignments = Get-AzRoleAssignment -IncludeClassicAdministrators
    Write-Output "Found $($assignments.Count) assignments for $($subscription.Name) subscription..."

    foreach ($assignment in $assignments) {
        if ($null -eq $assignment.ObjectId -and $assignment.Scope.Contains($subscription.Id))
        {
            $assignmentEntry = New-Object PSObject -Property @{
                Timestamp         = $timestamp
                TenantGuid        = $tenantId
                Cloud             = $cloudEnvironment
                Model             = "AzureClassic"
                PrincipalId       = $assignment.SignInName
                Scope             = $assignment.Scope
                RoleDefinition    = $assignment.RoleDefinitionName
            }
            $roleAssignments += $assignmentEntry            
        }
        else
        {
            $duplicateRoleAssignment = $roleAssignments | Where-Object { $_.PrincipalId -eq $assignment.ObjectId -and $_.Scope -eq $assignment.Scope -and $_.RoleDefinition -eq $assignment.RoleDefinitionName}
            if (-not($duplicateRoleAssignment))
            {
                $assignmentEntry = New-Object PSObject -Property @{
                    Timestamp         = $timestamp
                    TenantGuid        = $tenantId
                    Cloud             = $cloudEnvironment
                    Model             = "AzureRM"
                    PrincipalId       = $assignment.ObjectId
                    Scope             = $assignment.Scope
                    RoleDefinition    = $assignment.RoleDefinitionName
                }
                $roleAssignments += $assignmentEntry                            
            }
        }
    }       
}

$fileDate = $datetime.ToString("yyyyMMdd")
$jsonExportPath = "$fileDate-$tenantId-rbacassignments.json"
$csvExportPath = "$fileDate-$tenantId-rbacassignments.csv"

$roleAssignments | ConvertTo-Json -Depth 3 | Out-File $jsonExportPath
Write-Output "Exported to JSON: $($roleAssignments.Count) lines"
$rbacObjectsJson = Get-Content -Path $jsonExportPath | ConvertFrom-Json
Write-Output "JSON Import: $($rbacObjectsJson.Count) lines"
$rbacObjectsJson | Export-Csv -NoTypeInformation -Path $csvExportPath
Write-Output "Export to $csvExportPath"

$csvBlobName = $csvExportPath
$csvProperties = @{"ContentType" = "text/csv"};

Set-AzStorageBlobContent -File $csvExportPath -Container $storageAccountSinkContainer -Properties $csvProperties -Blob $csvBlobName -Context $sa.Context -Force

$roleAssignments = @()

Write-Output "Getting Azure AD roles..."

Import-Module AzureADPreview

try
{
    if (-not([string]::IsNullOrEmpty($externalCredentialName)))
    {
        $apiEndpointUri = "https://graph.windows.net/"  
        if ($cloudEnvironment -eq "AzureChinaCloud")
        {
            $apiEndpointUri = "https://graph.chinacloudapi.cn/"
        }
        if ($cloudEnvironment -eq "AzureGermanCloud")
        {
            $apiEndpointUri = "https://graph.cloudapi.de/"
        }
        $applicationId = $externalCredential.GetNetworkCredential().UserName
        $secret = $externalCredential.GetNetworkCredential().Password
        $encodedSecret = [System.Web.HttpUtility]::UrlEncode($secret)
        $RequestAccessTokenUri = "https://login.microsoftonline.com/$externalTenantId/oauth2/token"  
        if ($cloudEnvironment -eq "AzureChinaCloud")
        {
            $RequestAccessTokenUri = "https://login.partner.microsoftonline.cn/$externalTenantId/oauth2/token"
        }
        if ($cloudEnvironment -eq "AzureUSGovernment")
        {
            $RequestAccessTokenUri = "https://login.microsoftonline.us/$externalTenantId/oauth2/token"
        }
        if ($cloudEnvironment -eq "AzureGermanCloud")
        {
            $RequestAccessTokenUri = "https://login.microsoftonline.de/$externalTenantId/oauth2/token"
        }
        $body = "grant_type=client_credentials&client_id=$applicationId&client_secret=$encodedSecret&resource=$apiEndpointUri"  
        $contentType = 'application/x-www-form-urlencoded'  
        $Token = Invoke-RestMethod -Method Post -Uri $RequestAccessTokenUri -Body $body -ContentType $contentType      
        $ctx = Get-AzContext
        Connect-AzureAD -AzureEnvironmentName $cloudEnvironment -AadAccessToken $token.access_token -AccountId $ctx.Account.Id -TenantId $externalTenantId
    }
    else
    {
        Connect-AzureAD -AzureEnvironmentName $cloudEnvironment -TenantId $tenantId -ApplicationId $ArmConn.ApplicationID -CertificateThumbprint $ArmConn.CertificateThumbprint
    }
    
    $tenantDetails = Get-AzureADTenantDetail                
}
catch
{
    Write-Output "Failed Azure AD authentication."
}

if ($tenantDetails)
{
    $roles = Get-AzureADDirectoryRole    
    foreach ($role in $roles)
    {
        $roleMembers = (Get-AzureADDirectoryRoleMember -ObjectId $role.ObjectId).ObjectId
        foreach ($roleMember in $roleMembers)
        {
            $assignmentEntry = New-Object PSObject -Property @{
                Timestamp         = $timestamp
                TenantGuid        = $tenantId
                Cloud             = $cloudEnvironment
                Model             = "AzureAD"
                PrincipalId       = $roleMember
                Scope             = $tenantDetails.VerifiedDomains[0].Name
                RoleDefinition    = $role.DisplayName
            }
            $roleAssignments += $assignmentEntry                            
        }
    }
    
    $fileDate = $datetime.ToString("yyyyMMdd")
    $jsonExportPath = "$fileDate-$tenantId-aadrbacassignments.json"
    $csvExportPath = "$fileDate-$tenantId-aadrbacassignments.csv"
    
    $roleAssignments | ConvertTo-Json -Depth 3 | Out-File $jsonExportPath
    Write-Output "Exported to JSON: $($roleAssignments.Count) lines"
    $rbacObjectsJson = Get-Content -Path $jsonExportPath | ConvertFrom-Json
    Write-Output "JSON Import: $($rbacObjectsJson.Count) lines"
    $rbacObjectsJson | Export-Csv -NoTypeInformation -Path $csvExportPath
    Write-Output "Export to $csvExportPath"
    
    $csvBlobName = $csvExportPath
    $csvProperties = @{"ContentType" = "text/csv"};
    
    Set-AzStorageBlobContent -File $csvExportPath -Container $storageAccountSinkContainer -Properties $csvProperties -Blob $csvBlobName -Context $sa.Context -Force    
}

Write-Output "DONE!"