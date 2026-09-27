#Requires -Version 5.1
#Requires -Modules Az.Accounts, Az.Resources, Az.Storage, Az.ManagedServiceIdentity
<#
.SYNOPSIS
    Bootstraps the Azure Storage remote state backend used by the Terraform
    deploy pipeline, for one environment.
.DESCRIPTION
    Manual, human-run script (see docs/specs/004-terraform). For the given
    environment it creates (or confirms) a dedicated state resource group, a
    storage account in it (TLS 1.2, no public blob access, blob versioning and
    soft delete), a private blob container for state, and a Storage Blob Data
    Contributor role assignment on the storage account for the environment's
    pipeline managed identity (created by New-IdentityResourceGroup.ps1), so
    Terraform can read/write state with Azure AD auth instead of account keys.
    Safe to re-run: every step checks for an existing resource before creating
    one.

    Requires an active `Connect-AzAccount` session, with rights to create role
    assignments (Owner or User Access Administrator), before running.
.PARAMETER Workload
    Workload/application token used in resource names (e.g. "fc"). Required.
.PARAMETER Environment
    Target environment: dev, test, or prod. Required.
.PARAMETER SubscriptionId
    Azure subscription to provision into. Required.
.PARAMETER Location
    Azure region; must be one of the regions in the naming convention
    (infra/terraform/modules/naming/locals.tf). Required.
.PARAMETER ResourceGroupInstance
    Reserved instance suffix for the state resource group. Must differ from
    the identity resource group's instance, since both use the `rg-` prefix.
    Required.
.PARAMETER StorageAccountInstance
    Reserved instance suffix for the state storage account. Storage account
    names are globally unique; if the generated name is taken, pick another
    value. Required.
.PARAMETER ContainerName
    Blob container that holds the Terraform state files (e.g. "tfstate").
    Required.
.PARAMETER IdentityResourceGroupName
    Resource group of the pipeline's user-assigned managed identity (output
    of New-IdentityResourceGroup.ps1). Required.
.PARAMETER IdentityName
    Name of the pipeline's user-assigned managed identity (output of
    New-IdentityResourceGroup.ps1). Required.
.PARAMETER OutputPath
    Path to also write the result as JSON, for feeding into
    `gh variable set` afterwards. Required.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Workload,

    [Parameter(Mandatory = $true)]
    [ValidateSet('dev', 'test', 'prod')]
    [string]$Environment,

    [Parameter(Mandatory = $true)]
    [string]$SubscriptionId,

    [Parameter(Mandatory = $true)]
    [ValidateSet('eastus', 'eastus2', 'centralus', 'northcentralus', 'southcentralus', 'westcentralus', 'westus', 'westus2', 'westus3')]
    [string]$Location,

    [Parameter(Mandatory = $true)]
    [string]$ResourceGroupInstance,

    [Parameter(Mandatory = $true)]
    [string]$StorageAccountInstance,

    [Parameter(Mandatory = $true)]
    [string]$ContainerName,

    [Parameter(Mandatory = $true)]
    [string]$IdentityResourceGroupName,

    [Parameter(Mandatory = $true)]
    [string]$IdentityName,

    [Parameter(Mandatory = $true)]
    [string]$OutputPath
)

$ErrorActionPreference = "Stop"

# Naming: a small manual replica of infra/terraform/modules/naming/locals.tf's
# CAF pattern (that module can't be called from a standalone PowerShell
# script). Keep the region abbreviations and resource-type abbreviations below
# in sync with locals.tf, infra/policy/naming.rego, and
# scripts/New-IdentityResourceGroup.ps1.
function Get-RegionAbbreviation {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Location
    )

    # Mirrors locals.tf's region_abbreviations map (Azure public-cloud US regions).
    $regionAbbreviations = @{
        eastus         = "eus"
        eastus2        = "eus2"
        centralus      = "cus"
        northcentralus = "ncus"
        southcentralus = "scus"
        westcentralus  = "wcus"
        westus         = "wus"
        westus2        = "wus2"
        westus3        = "wus3"
    }

    if (-not $regionAbbreviations.ContainsKey($Location)) {
        throw "Unknown region '$Location'. Add it to region_abbreviations in this script and to infra/terraform/modules/naming/locals.tf and infra/policy/naming.rego."
    }

    return $regionAbbreviations[$Location]
}

$regionAbbr = Get-RegionAbbreviation -Location $Location
$rgName = "rg-$Workload-$Environment-$regionAbbr-$ResourceGroupInstance"

# Storage accounts use locals.tf's "compact" scheme: no hyphens, lowercase,
# truncated to 24 characters.
$storageAccountName = "st$Workload$Environment$regionAbbr$StorageAccountInstance".ToLower()
if ($storageAccountName.Length -gt 24) {
    $storageAccountName = $storageAccountName.Substring(0, 24)
}
$stateKey = "$Environment.tfstate"
$softDeleteRetentionDays = 30

$context = Get-AzContext
if (-not $context) {
    throw "Not logged in to Azure. Run Connect-AzAccount first."
}

$context = Set-AzContext -SubscriptionId $SubscriptionId
$SubscriptionId = $context.Subscription.Id

Write-Host "Environment       : $Environment"
Write-Host "Subscription      : $SubscriptionId"
Write-Host "Resource group    : $rgName"
Write-Host "Storage account   : $storageAccountName"
Write-Host "Container         : $ContainerName"
Write-Host "Pipeline identity : $IdentityResourceGroupName/$IdentityName"
Write-Host ""

# 0. Pipeline identity must already exist (New-IdentityResourceGroup.ps1).
# Checked first so a missing identity fails before anything is created.
$identity = Get-AzUserAssignedIdentity -ResourceGroupName $IdentityResourceGroupName -Name $IdentityName -ErrorAction SilentlyContinue
if (-not $identity) {
    throw "Managed identity $IdentityName not found in $IdentityResourceGroupName. Run scripts/New-IdentityResourceGroup.ps1 for '$Environment' first."
}

# 1. State resource group
$resourceGroup = Get-AzResourceGroup -Name $rgName -ErrorAction SilentlyContinue
if (-not $resourceGroup) {
    Write-Host "Creating resource group $rgName..."
    $resourceGroup = New-AzResourceGroup -Name $rgName -Location $Location
}
else {
    Write-Host "Resource group $rgName already exists."
}

# 2. Storage account
$storageAccount = Get-AzStorageAccount -ResourceGroupName $rgName -Name $storageAccountName -ErrorAction SilentlyContinue
if (-not $storageAccount) {
    $availability = Get-AzStorageAccountNameAvailability -Name $storageAccountName
    if (-not $availability.NameAvailable) {
        throw "Storage account name '$storageAccountName' is not available ($($availability.Reason): $($availability.Message)). Re-run with a different -StorageAccountInstance."
    }

    Write-Host "Creating storage account $storageAccountName..."
    $storageAccount = New-AzStorageAccount `
        -ResourceGroupName $rgName `
        -Name $storageAccountName `
        -Location $Location `
        -SkuName Standard_LRS `
        -Kind StorageV2 `
        -MinimumTlsVersion TLS1_2 `
        -AllowBlobPublicAccess $false `
        -EnableHttpsTrafficOnly $true
}
else {
    Write-Host "Storage account $storageAccountName already exists."
}

# 3. State protection: blob versioning plus blob/container soft delete, so a
# corrupted or deleted state file can be recovered. Applied on every run —
# these cmdlets are idempotent.
Write-Host "Ensuring blob versioning and $softDeleteRetentionDays-day soft delete..."
Update-AzStorageBlobServiceProperty `
    -ResourceGroupName $rgName `
    -StorageAccountName $storageAccountName `
    -IsVersioningEnabled $true | Out-Null
Enable-AzStorageBlobDeleteRetentionPolicy `
    -ResourceGroupName $rgName `
    -StorageAccountName $storageAccountName `
    -RetentionDays $softDeleteRetentionDays | Out-Null
Enable-AzStorageContainerDeleteRetentionPolicy `
    -ResourceGroupName $rgName `
    -StorageAccountName $storageAccountName `
    -RetentionDays $softDeleteRetentionDays | Out-Null

# 4. State container. Created through the management plane (AzRm cmdlets), so
# the operator doesn't need a blob data-plane role themselves.
$container = Get-AzRmStorageContainer `
    -ResourceGroupName $rgName `
    -StorageAccountName $storageAccountName `
    -Name $ContainerName `
    -ErrorAction SilentlyContinue
if (-not $container) {
    Write-Host "Creating blob container $ContainerName..."
    New-AzRmStorageContainer `
        -ResourceGroupName $rgName `
        -StorageAccountName $storageAccountName `
        -Name $ContainerName `
        -PublicAccess None | Out-Null
}
else {
    Write-Host "Blob container $ContainerName already exists."
}

# 5. RBAC: Storage Blob Data Contributor on the storage account. Subscription
# Contributor (from New-IdentityResourceGroup.ps1) doesn't include blob data
# actions, which Terraform's azurerm backend needs with use_azuread_auth.
# Retry briefly, same as New-IdentityResourceGroup.ps1, in case the role
# assignment API hasn't caught up yet.
$roleName = "Storage Blob Data Contributor"
$storageScope = $storageAccount.Id
$roleAssignment = Get-AzRoleAssignment `
    -ObjectId $identity.PrincipalId `
    -RoleDefinitionName $roleName `
    -Scope $storageScope `
    -ErrorAction SilentlyContinue

if (-not $roleAssignment) {
    Write-Host "Assigning $roleName to $IdentityName on $storageAccountName..."
    $maxAttempts = 5
    for ($attempt = 1; $attempt -le $maxAttempts; $attempt++) {
        try {
            New-AzRoleAssignment `
                -ObjectId $identity.PrincipalId `
                -RoleDefinitionName $roleName `
                -Scope $storageScope | Out-Null
            break
        }
        catch {
            if ($attempt -eq $maxAttempts) {
                throw
            }
            Write-Host "Role assignment not ready yet (attempt $attempt/$maxAttempts); retrying in 10s..."
            Start-Sleep -Seconds 10
        }
    }
}
else {
    Write-Host "$roleName role assignment on $storageAccountName already exists."
}

$result = [pscustomobject]@{
    Environment        = $Environment
    ResourceGroupName  = $rgName
    StorageAccountName = $storageAccountName
    ContainerName      = $ContainerName
    StateKey           = $stateKey
    SubscriptionId     = $SubscriptionId
}

Write-Host ""
Write-Host "Values for the Terraform backend / GitHub Environment variables:"
$result | Format-List

# Set-Content -Encoding utf8 adds a BOM on Windows PowerShell 5.1, which can
# trip up strict JSON consumers (e.g. gh CLI) — write BOM-less UTF-8 directly,
# same as New-IdentityResourceGroup.ps1.
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($OutputPath, ($result | ConvertTo-Json), $utf8NoBom)
Write-Host "Also written to $OutputPath"

$result
