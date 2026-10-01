#requires -Version 7.0
# Offline test: the Terraform command is replaced; no AWS call is possible here.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$fixtureRoot = Join-Path ([IO.Path]::GetTempPath()) ("mecanica-environment-tests-" + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path "$fixtureRoot/scripts", "$fixtureRoot/terraform/environments", "$fixtureRoot/terraform/backends" | Out-Null
Copy-Item "$repoRoot/scripts/Invoke-TerraformEnvironment.ps1" "$fixtureRoot/scripts/"
Copy-Item "$repoRoot/terraform/environments/*.tfvars" "$fixtureRoot/terraform/environments/"
Copy-Item "$repoRoot/terraform/backends/*.hcl" "$fixtureRoot/terraform/backends/"
$selector = "$fixtureRoot/scripts/Invoke-TerraformEnvironment.ps1"
$previousVariables = @{}
foreach ($name in @('TF_DATA_DIR', 'TF_WORKSPACE', 'TF_INPUT', 'TF_CLI_ARGS')) {
    $previousVariables[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
}
if (Test-Path Function:terraform) { throw 'Execute este teste em uma sessão sem função terraform definida.' }
$global:mecanicaTerraformTestCalls = [Collections.Generic.List[object]]::new()
$global:mecanicaTerraformTestExit = 0
function terraform {
    $global:mecanicaTerraformTestCalls.Add([pscustomobject]@{
        Arguments = @($args)
        Data = $env:TF_DATA_DIR
        Workspace = $env:TF_WORKSPACE
    })
    $global:LASTEXITCODE = $global:mecanicaTerraformTestExit
}
function Assert-That([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}
function Assert-Rejected([scriptblock]$Operation, [string]$ExpectedMessage) {
    $caught = $false
    try { & $Operation | Out-Null } catch {
        if ($_.Exception.Message -notlike "*$ExpectedMessage*") { throw }
        $caught = $true
    }
    Assert-That $caught "Operação deveria falhar: $ExpectedMessage"
}
try {
    $env:TF_DATA_DIR = 'previous-data-directory'
    $env:TF_WORKSPACE = 'default'
    $env:TF_INPUT = 'true'
    $env:TF_CLI_ARGS = $null
    foreach ($targetEnvironment in @('hom', 'prd')) {
        $global:mecanicaTerraformTestCalls.Clear()
        & $selector -Environment $targetEnvironment -Action Plan
        Assert-That ($global:mecanicaTerraformTestCalls.Count -eq 2) 'Plan precisa de init e plan.'
        $init = $global:mecanicaTerraformTestCalls[0]
        $plan = $global:mecanicaTerraformTestCalls[1]
        Assert-That ($init.Arguments -contains ("-backend-config=" + (Join-Path (Join-Path $fixtureRoot 'terraform') "backends/$targetEnvironment.hcl"))) 'Backend incorreto.'
        Assert-That ($plan.Arguments -contains ("-var-file=" + (Join-Path (Join-Path $fixtureRoot 'terraform') "environments/$targetEnvironment.tfvars"))) 'Parâmetros incorretos.'
        Assert-That ($plan.Arguments -contains "-var=environment=$targetEnvironment") 'Ambiente não foi fixado.'
        Assert-That ($init.Data -eq (Join-Path $fixtureRoot "artifacts/terraform/$targetEnvironment/remote") -and $plan.Data -eq $init.Data) 'Dados internos não foram separados por ambiente.'
        Assert-That ($init.Workspace -eq 'default') 'Workspace incorreto.'
        Assert-That ($env:TF_DATA_DIR -eq 'previous-data-directory' -and $env:TF_INPUT -eq 'true') 'Variáveis do processo não foram restauradas.'
    }
    $global:mecanicaTerraformTestCalls.Clear()
    & $selector -Environment hom -Action Validate
    Assert-That ($global:mecanicaTerraformTestCalls[0].Arguments -contains '-backend=false') 'Validate não pode acessar backend remoto.'
    Assert-That ($global:mecanicaTerraformTestCalls[0].Data -eq (Join-Path $fixtureRoot 'artifacts/terraform/hom/validation')) 'Validate deve ter dados separados dos comandos remotos.'
    $global:mecanicaTerraformTestExit = 17
    $global:mecanicaTerraformTestCalls.Clear()
    Assert-Rejected { & $selector -Environment hom -Action Plan } 'código 17'
    Assert-That ($global:mecanicaTerraformTestCalls.Count -eq 1 -and $env:TF_DATA_DIR -eq 'previous-data-directory') 'Falha no init deve interromper e restaurar o ambiente.'
    $global:mecanicaTerraformTestExit = 0
    $global:mecanicaTerraformTestCalls.Clear()
    Set-Content "$fixtureRoot/terraform/terraform.tfstate" '{"resources":[]}'
    Assert-Rejected { & $selector -Environment hom -Action Init } 'Estado local anterior'
    Assert-That ($global:mecanicaTerraformTestCalls.Count -eq 0) 'Estado antigo deve impedir invocação do Terraform.'
    Remove-Item -LiteralPath "$fixtureRoot/terraform/terraform.tfstate"
    Set-Content "$fixtureRoot/terraform/terraform.auto.tfvars" 'environment = "prd"'
    Assert-Rejected { & $selector -Environment hom -Action Plan } 'carregamento automático'
    Remove-Item -LiteralPath "$fixtureRoot/terraform/terraform.auto.tfvars"
    $env:TF_WORKSPACE = 'prd'
    Assert-Rejected { & $selector -Environment hom -Action Plan } 'workspace default'
    $env:TF_WORKSPACE = 'default'
    $env:TF_CLI_ARGS = '-lock=false'
    Assert-Rejected { & $selector -Environment hom -Action Plan } 'TF_CLI_ARGS'
    $env:TF_CLI_ARGS = $null
    $backendPath = "$fixtureRoot/terraform/backends/hom.hcl"
    $original = Get-Content -Raw $backendPath
    Set-Content $backendPath ($original.Replace('hom/base/terraform.tfstate', 'prd/base/terraform.tfstate'))
    Assert-Rejected { & $selector -Environment hom -Action Show } 'Backend incompatível'
    Set-Content $backendPath $original
    Set-Content "$fixtureRoot/terraform/environments/hom.tfvars" 'environment = "prd"'
    Assert-Rejected { & $selector -Environment hom -Action Show } 'parâmetros incompatível'
    Write-Output '10 cenários offline aprovados: seleção hom/prd, validate, erro do init, estado legado, auto tfvars, workspace, argumentos implícitos, backend e parâmetros incompatíveis.'
} finally {
    foreach ($entry in $previousVariables.GetEnumerator()) {
        [Environment]::SetEnvironmentVariable($entry.Key, $entry.Value, 'Process')
    }
    Remove-Item Function:terraform
    # Fixtures contain no secrets and are left in the temporary directory for inspection.
}
$global:LASTEXITCODE = 0
