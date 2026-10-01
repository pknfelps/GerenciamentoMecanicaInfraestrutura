#requires -Version 7.0
[CmdletBinding()]
param([Parameter(Mandatory)][ValidateSet('hom', 'prd')][string]$Environment)
$ErrorActionPreference = 'Stop'
$expectedRef = if ($Environment -eq 'hom') { 'refs/heads/develop' } else { 'refs/heads/main' }
if ($env:GITHUB_REPOSITORY -cne 'pknfelps/GerenciamentoMecanicaInfraestrutura' -or $env:GITHUB_REF -cne $expectedRef) {
    throw 'Aprovação aceita somente no repositório e branch do ambiente selecionado.'
}
$name = "$Environment-approval"
if (!$env:GH_TOKEN) { throw 'Token GitHub de leitura indisponível para conferir a aprovação.' }
try {
    $configuration = Invoke-RestMethod -Method Get -Uri "https://api.github.com/repos/pknfelps/GerenciamentoMecanicaInfraestrutura/environments/$name" -TimeoutSec 30 -Headers @{
        Authorization = "Bearer $($env:GH_TOKEN)"
        Accept = 'application/vnd.github+json'
        'X-GitHub-Api-Version' = '2026-03-10'
    }
} catch {
    # Não imprimir headers/token nem a resposta HTTP completa.
    throw "Não foi possível conferir $name. Configure Settings > Environments > $name com Required reviewers; nenhum apply autorizado."
}
$rules = @($configuration.protection_rules | Where-Object { $_.type -eq 'required_reviewers' })
$reviewers = @($rules | ForEach-Object { $_.reviewers } | Where-Object { $_ -and $_.reviewer.id })
if ($configuration.name -cne $name -or $rules.Count -ne 1 -or $reviewers.Count -eq 0) {
    throw "Configure Required reviewers em $name; sem essa proteção a ativação é recusada."
}
Write-Output "Aprovação obrigatória conferida em $name."
