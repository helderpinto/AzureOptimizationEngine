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
$storageAccountSinkContainer = Get-AutomationVariable -Name  "AzureOptimization_AADObjectsContainer" -ErrorAction SilentlyContinue
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

    Select-AzSubscription -SubscriptionId $subscription.Id | Out-Null

    $assignments = Get-AzRoleAssignment -IncludeClassicAdministrators
    Write-Output "Found $($assignments.Count) assignments for $($subscription.Name) subscription..."

    foreach ($assignment in $assignments) {
        if ($null -eq $assignment.ObjectId -and $assignment.Scope.Contains($subscription.Id))
        {
            $assignmentEntry = New-Object PSObject -Property @{
                Timestamp         = $timestamp
                AADTenantId       = $tenantId
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
                    AADTenantId       = $tenantId
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

Write-Output "DONE!"