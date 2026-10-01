#requires -Version 7.0
[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateSet('hom', 'prd')][string]$Environment,
    [ValidateSet('plan', 'apply', 'auto')][string]$Action = 'plan',
    [ValidateSet('provision', 'destroy')][string]$Operation = 'provision',
    [string]$ExpectedCommit = '',
    [string]$ApprovedPlanSha256 = ''
)
$ErrorActionPreference = 'Stop'
$expectedRef = if ($Environment -eq 'hom') { 'refs/heads/develop' } else { 'refs/heads/main' }
$expectedRole = "arn:aws:iam::121754142617:role/mecanica/pipelines/mecanica-$Environment-base-github"
if ($env:GITHUB_REPOSITORY -cne 'pknfelps/GerenciamentoMecanicaInfraestrutura' -or $env:GITHUB_REF -cne $expectedRef) {
    throw "Execute somente no repositório de infraestrutura em $expectedRef para $Environment."
}
if ($env:CONFIGURED_REGION -cne 'us-east-1' -or $env:CONFIGURED_ROLE_ARN -cne $expectedRole -or $env:CONFIGURED_STATE_BUCKET -cne 'mecanica-tfstate-121754142617-us-east-1') {
    throw 'Variáveis AWS_REGION/AWS_BASE_ROLE_ARN/TF_STATE_BUCKET incompatíveis com o destino.'
}
if ($Operation -eq 'destroy' -and ($env:GITHUB_EVENT_NAME -cne 'workflow_dispatch' -or $Action -eq 'auto')) {
    throw 'Descarte é exclusivo de workflow_dispatch, com plano e aprovação explícitos.'
}
if ($Action -eq 'auto' -and $env:GITHUB_EVENT_NAME -cne 'push') {
    throw 'Aplicação automática é exclusiva de push em develop/main.'
}
if ($Action -eq 'auto' -and ($ExpectedCommit -or $ApprovedPlanSha256)) {
    if ($ExpectedCommit -cnotmatch '^[a-f0-9]{40}$' -or $ExpectedCommit -cne $env:GITHUB_SHA -or $ApprovedPlanSha256 -cnotmatch '^[a-fA-F0-9]{64}$') {
        throw 'Auto exige commit/fingerprint internos válidos quando fornecidos pelo job de plan.'
    }
}
if ($Action -eq 'apply') {
    if ($env:GITHUB_EVENT_NAME -cne 'workflow_dispatch' -or $ExpectedCommit -cnotmatch '^[a-f0-9]{40}$' -or $ExpectedCommit -cne $env:GITHUB_SHA) {
        throw 'Apply exige commit interno da execução selecionada e workflow_dispatch.'
    }
    if ($ApprovedPlanSha256 -cnotmatch '^[a-fA-F0-9]{64}$') {
        throw 'Apply exige o fingerprint interno do job de plan revisado.'
    }
}
