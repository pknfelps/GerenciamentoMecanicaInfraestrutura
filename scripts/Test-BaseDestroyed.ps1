#requires -Version 7.0
[CmdletBinding()]
param([Parameter(Mandatory)][ValidateSet('hom', 'prd')][string]$Environment)
$ErrorActionPreference = 'Stop'
# Called with the selected TF_DATA_DIR/workspace and authenticated base role.
$repoRoot = Split-Path $PSScriptRoot -Parent
$remaining = @(& terraform "-chdir=$repoRoot/terraform" state list)
if ($LASTEXITCODE -ne 0) { throw 'Falha ao consultar o estado após descarte.' }
if (@($remaining | Where-Object { $_.Trim() }).Count -gt 0) { throw 'O estado da base ainda contém recursos; descarte incompleto.' }
$dir = Join-Path $repoRoot "artifacts/terraform/$Environment/destroy-pipeline"
New-Item -ItemType Directory -Path $dir -Force | Out-Null
$clusterLog = Join-Path $dir 'cluster-absence.log'
& aws eks describe-cluster --name "mecanica-$Environment-eks" --region us-east-1 --output json *> $clusterLog
if ($LASTEXITCODE -eq 0) { throw 'O cluster ainda existe; descarte incompleto.' }
if ((Get-Content -LiteralPath $clusterLog -Raw) -notmatch '\(ResourceNotFoundException\)') {
    throw 'Não foi possível comprovar ausência do cluster; consulte a execução, sem repetir exclusões automaticamente.'
}
$filters = @('Name=tag:Project,Values=mecanica', "Name=tag:Environment,Values=$Environment", 'Name=tag:ManagedBy,Values=Terraform')
foreach ($query in @(
    @{Operation='describe-vpcs';Query='Vpcs[].VpcId'},
    @{Operation='describe-nat-gateways';Query="NatGateways[?State!='deleted'].NatGatewayId"},
    @{Operation='describe-addresses';Query='Addresses[].AllocationId'}
)) {
    $result = & aws ec2 $query.Operation --region us-east-1 --filters @filters --query $query.Query --output json
    if ($LASTEXITCODE -ne 0) { throw "Falha ao conferir $($query.Operation) após descarte." }
    $resources = @($result | ConvertFrom-Json)
    if ($resources.Count -gt 0) { throw "Ainda há recursos do ambiente em $($query.Operation); descarte incompleto." }
}
$message = "Base $Environment descartada e verificada: estado vazio; EKS/VPC/NAT/Elastic IP ausentes. Bootstrap e outro ambiente preservados pelo escopo da operação."
Write-Output $message
if ($env:GITHUB_STEP_SUMMARY) { $message | Add-Content -LiteralPath $env:GITHUB_STEP_SUMMARY }
