#requires -Version 7.0
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('hom', 'prd')]
    [string]$Environment,

    [ValidateSet('Show', 'Validate', 'Init', 'Plan')]
    [string]$Action = 'Show'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$Environment = $Environment.ToLowerInvariant()
$repoRoot = Split-Path $PSScriptRoot -Parent
$terraformRoot = Join-Path $repoRoot 'terraform'
$backendPath = Join-Path $terraformRoot "backends/$Environment.hcl"
$variablesPath = Join-Path $terraformRoot "environments/$Environment.tfvars"
$mode = if ($Action -eq 'Validate') { 'validation' } else { 'remote' }
$dataPath = Join-Path $repoRoot "artifacts/terraform/$Environment/$mode"

# Validate the committed pair before invoking Terraform, including offline validation.
$backendText = Get-Content -Raw -LiteralPath $backendPath
$variablesText = Get-Content -Raw -LiteralPath $variablesPath
$expectedBackend = @{
    bucket = '"mecanica-tfstate-121754142617-us-east-1"'
    key = '"' + $Environment + '/base/terraform.tfstate"'
    region = '"us-east-1"'
    encrypt = 'true'
    use_lockfile = 'true'
    allowed_account_ids = '["121754142617"]'
    workspace_key_prefix = '"' + $Environment + '/base/workspaces"'
}
foreach ($entry in $expectedBackend.GetEnumerator()) {
    $matches = [regex]::Matches($backendText, '(?m)^\s*' + $entry.Key + '\s*=\s*(.+?)\s*$')
    if ($matches.Count -ne 1 -or $matches[0].Groups[1].Value -cne $entry.Value) {
        throw "Backend incompatível com $Environment no campo $($entry.Key)."
    }
}
$environmentMatches = [regex]::Matches($variablesText, '(?m)^\s*environment\s*=\s*"([^"]+)"\s*$')
if ($environmentMatches.Count -ne 1 -or $environmentMatches[0].Groups[1].Value -cne $Environment) {
    throw "Arquivo de parâmetros incompatível com $Environment."
}

if ($Action -eq 'Show') {
    [pscustomobject]@{
        Environment = $Environment
        Backend = $backendPath
        Variables = $variablesPath
        StateKey = "$Environment/base/terraform.tfstate"
        DataDirectory = $dataPath
        Workspace = 'default'
    }
    return
}

# No implicit flags or workspace may redirect the operation to another state.
if (@(Get-ChildItem Env: | Where-Object { $_.Name -like 'TF_CLI_ARGS*' -and $_.Value }).Count -gt 0) {
    throw 'Remova TF_CLI_ARGS/TF_CLI_ARGS_* antes de usar o seletor de ambiente.'
}
if ($env:TF_WORKSPACE -and $env:TF_WORKSPACE -ne 'default') {
    throw 'Este projeto utiliza somente o workspace default; remova TF_WORKSPACE.'
}
if ($Action -in @('Init', 'Plan')) {
    $legacyStates = @(Get-ChildItem -LiteralPath $terraformRoot -File -Filter '*.tfstate*')
    $workspaceStates = Join-Path $terraformRoot 'terraform.tfstate.d'
    if ($legacyStates.Count -gt 0 -or (Test-Path -LiteralPath $workspaceStates)) {
        throw 'Estado local anterior encontrado. Revisar e migrar explicitamente antes de inicializar o S3; nenhum estado foi alterado.'
    }
    $automaticVariables = @(Get-ChildItem -LiteralPath $terraformRoot -File | Where-Object {
        $_.Name -in @('terraform.tfvars', 'terraform.tfvars.json') -or $_.Name -like '*.auto.tfvars' -or $_.Name -like '*.auto.tfvars.json'
    })
    if ($automaticVariables.Count -gt 0) {
        throw 'Há arquivos tfvars de carregamento automático na raiz. Transfira os parâmetros públicos para environments/hom.tfvars ou prd.tfvars antes de continuar.'
    }
}

$previousEnvironment = @{}
foreach ($name in @('TF_DATA_DIR', 'TF_WORKSPACE', 'TF_INPUT')) {
    $previousEnvironment[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
}
function Invoke-CheckedTerraform([string[]]$Arguments) {
    & terraform "-chdir=$terraformRoot" @Arguments
    if ($LASTEXITCODE -ne 0) { throw "Terraform falhou com código $LASTEXITCODE; execução interrompida." }
}
try {
    $env:TF_DATA_DIR = $dataPath
    $env:TF_WORKSPACE = 'default'
    $env:TF_INPUT = 'false'
    if ($Action -eq 'Validate') {
        Invoke-CheckedTerraform @('init', '-backend=false', '-input=false', '-lockfile=readonly')
        Invoke-CheckedTerraform @('validate', '-no-color')
    } else {
        # Never reconfigure or migrate automatically: changed backend metadata must be reviewed.
        Invoke-CheckedTerraform @('init', '-input=false', '-lockfile=readonly', "-backend-config=$backendPath")
        if ($Action -eq 'Plan') {
            Invoke-CheckedTerraform @('plan', '-input=false', '-lock-timeout=60s', "-var-file=$variablesPath", "-var=environment=$Environment")
        }
    }
} finally {
    foreach ($entry in $previousEnvironment.GetEnumerator()) {
        [Environment]::SetEnvironmentVariable($entry.Key, $entry.Value, 'Process')
    }
}
