#Requires -Version 5.1
#Requires -Modules Az.Accounts, Az.Resources, Az.ManagedServiceIdentity
<#
.SYNOPSIS
    Bootstraps the Azure identity resource group, user-assigned managed
    identity, and GitHub OIDC federation used by GitHub Actions to deploy
    Terraform, for one environment.
.DESCRIPTION
    Manual, human-run script (see docs/specs/003-identity-resource-group).
    For the given environment it creates (or confirms) a dedicated identity
    resource group, a user-assigned managed identity in it, a federated
    identity credential trusting GitHub Actions OIDC tokens for this repo,
    and a Contributor role assignment scoped to the subscription. Safe to
    re-run: every step checks for an existing resource before creating one.

    Requires an active `Connect-AzAccount` session before running.
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
    Reserved instance suffix for the bootstrap resource group, kept separate
    from workload instance numbers. Required.
.PARAMETER IdentityInstance
    Reserved instance suffix for the bootstrap managed identity. May be the
    same as -ResourceGroupInstance; the resource-type prefix (`rg-`/`id-`)
    already keeps the two names distinct. Required.
.PARAMETER GithubFederationName
    Base name for the GitHub OIDC federated identity credential; the actual
    credential is named "<GithubFederationName>-<Environment>". Required.
.PARAMETER Repository
    GitHub "owner/repo" the federated credential trusts. Required.
.PARAMETER RepositoryOwnerId
    Numeric GitHub ID of the repository owner (`gh api repos/<owner>/<repo>
    --jq .owner.id`). The repo uses GitHub's immutable OIDC subject
    (use_immutable_subject), whose subject embeds owner and repo IDs. Required.
.PARAMETER RepositoryId
    Numeric GitHub ID of the repository (`gh api repos/<owner>/<repo>
    --jq .id`). Required.
.PARAMETER OutputPath
    Path to also write the result as JSON, for feeding into
    `gh secret set` / `gh variable set` afterwards. Required.
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
    [string]$IdentityInstance,

    [Parameter(Mandatory = $true)]
    [string]$GithubFederationName,

    [Parameter(Mandatory = $true)]
    [string]$Repository,

    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[0-9]+$')]
    [string]$RepositoryOwnerId,

    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[0-9]+$')]
    [string]$RepositoryId,

    [Parameter(Mandatory = $true)]
    [string]$OutputPath
)

$ErrorActionPreference = "Stop"

# Naming: a small manual replica of infra/terraform/modules/naming/locals.tf's
# CAF pattern (that module can't be called from a standalone PowerShell
# script). Keep the workload token, region abbreviations, and resource-type
# abbreviations below in sync with locals.tf and infra/policy/naming.rego.
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
$identityName = "id-$Workload-$Environment-$regionAbbr-$IdentityInstance"
$federatedCredentialName = "$GithubFederationName-$Environment"
$issuer = "https://token.actions.githubusercontent.com"
$audience = "api://AzureADTokenExchange"
# The repo's OIDC setting has use_immutable_subject enabled, so GitHub
# presents "repo:<owner>@<ownerId>/<repo>@<repoId>:environment:<env>" rather
# than the name-only "repo:<owner>/<repo>:..." form. The IDs make the trust
# immune to the repo or org being renamed or its name re-registered.
$repositoryOwner, $repositoryName = $Repository.Split('/', 2)
$subject = "repo:${repositoryOwner}@${RepositoryOwnerId}/${repositoryName}@${RepositoryId}:environment:${Environment}"

$context = Get-AzContext
if (-not $context) {
    throw "Not logged in to Azure. Run Connect-AzAccount first."
}

if ($SubscriptionId) {
    $context = Set-AzContext -SubscriptionId $SubscriptionId
}
$SubscriptionId = $context.Subscription.Id
$tenantId = $context.Tenant.Id

Write-Host "Environment       : $Environment"
Write-Host "Subscription      : $SubscriptionId"
Write-Host "Resource group    : $rgName"
Write-Host "Managed identity  : $identityName"
Write-Host "Federated subject : $subject"
Write-Host ""

# 1. Identity resource group
$resourceGroup = Get-AzResourceGroup -Name $rgName -ErrorAction SilentlyContinue
if (-not $resourceGroup) {
    Write-Host "Creating resource group $rgName..."
    $resourceGroup = New-AzResourceGroup -Name $rgName -Location $Location
}
else {
    Write-Host "Resource group $rgName already exists."
}

# 2. User-assigned managed identity
$identity = Get-AzUserAssignedIdentity -ResourceGroupName $rgName -Name $identityName -ErrorAction SilentlyContinue
if (-not $identity) {
    Write-Host "Creating managed identity $identityName..."
    $identity = New-AzUserAssignedIdentity -ResourceGroupName $rgName -Name $identityName -Location $Location
}
else {
    Write-Host "Managed identity $identityName already exists."
}

# 3. GitHub OIDC federated credential
$federatedCredential = Get-AzFederatedIdentityCredential `
    -ResourceGroupName $rgName `
    -IdentityName $identityName `
    -Name $federatedCredentialName `
    -ErrorAction SilentlyContinue

if (-not $federatedCredential) {
    Write-Host "Creating federated identity credential $federatedCredentialName..."
    New-AzFederatedIdentityCredential `
        -ResourceGroupName $rgName `
        -IdentityName $identityName `
        -Name $federatedCredentialName `
        -Issuer $issuer `
        -Subject $subject `
        -Audience $audience | Out-Null
}
elseif ($federatedCredential.Issuer -ne $issuer -or $federatedCredential.Subject -ne $subject) {
    Write-Host "Federated identity credential $federatedCredentialName drifted; updating..."
    Update-AzFederatedIdentityCredential `
        -ResourceGroupName $rgName `
        -IdentityName $identityName `
        -Name $federatedCredentialName `
        -Issuer $issuer `
        -Subject $subject `
        -Audience $audience | Out-Null
}
else {
    Write-Host "Federated identity credential $federatedCredentialName already matches."
}

# 4. RBAC: Contributor at subscription scope. A freshly created identity's
# service principal can take a few seconds to replicate through Azure AD, so
# retry role assignment briefly instead of failing on the first attempt.
$subscriptionScope = "/subscriptions/$SubscriptionId"
$roleAssignment = Get-AzRoleAssignment `
    -ObjectId $identity.PrincipalId `
    -RoleDefinitionName "Contributor" `
    -Scope $subscriptionScope `
    -ErrorAction SilentlyContinue

if (-not $roleAssignment) {
    Write-Host "Assigning Contributor role at $subscriptionScope..."
    $maxAttempts = 5
    for ($attempt = 1; $attempt -le $maxAttempts; $attempt++) {
        try {
            New-AzRoleAssignment `
                -ObjectId $identity.PrincipalId `
                -RoleDefinitionName "Contributor" `
                -Scope $subscriptionScope | Out-Null
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
    Write-Host "Contributor role assignment at $subscriptionScope already exists."
}

# GitHub-side follow-up this script does not perform (see spec non-goals):
# the "environment:<environment>" subject above only matches pipeline runs
# once a GitHub Environment named '$Environment' exists in this repo's
# Settings > Environments. Create it there before relying on this identity.
Write-Host ""
Write-Host "NOTE: create a GitHub Environment named '$Environment' in $Repository's Settings" -ForegroundColor Yellow
Write-Host "      (Settings > Environments) for the federated subject above to match." -ForegroundColor Yellow

$result = [pscustomobject]@{
    Environment       = $Environment
    ResourceGroupName = $rgName
    IdentityName      = $identityName
    ClientId          = $identity.ClientId
    PrincipalId       = $identity.PrincipalId
    TenantId          = $tenantId
    SubscriptionId    = $SubscriptionId
}

Write-Host ""
Write-Host "Values for the GitHub Actions workflow:"
$result | Format-List

if ($OutputPath) {
    # Set-Content -Encoding utf8 adds a BOM on Windows PowerShell 5.1, which
    # can trip up strict JSON consumers (e.g. gh CLI) — write BOM-less UTF-8
    # directly, same fix as scripts/Test-NamingConvention.ps1.
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($OutputPath, ($result | ConvertTo-Json), $utf8NoBom)
    Write-Host "Also written to $OutputPath"
}

$result
