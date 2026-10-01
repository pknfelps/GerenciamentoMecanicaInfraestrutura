#requires -Version 7.0
[CmdletBinding()]
param([Parameter(Mandatory)][ValidateSet('hom', 'prd')][string]$Environment)
$ErrorActionPreference = 'Stop'
$clusterName = "mecanica-$Environment-eks"
function Read-AwsJson([string[]]$Arguments) {
    $result = & aws @Arguments --region us-east-1 --output json
    if ($LASTEXITCODE -ne 0) { throw "Falha na consulta AWS: $($Arguments[0..1] -join ' ')." }
    $result | ConvertFrom-Json
}
$cluster = (Read-AwsJson @('eks', 'describe-cluster', '--name', $clusterName)).cluster
if ($cluster.status -ne 'ACTIVE' -or $cluster.accessConfig.authenticationMode -ne 'API_AND_CONFIG_MAP') { throw 'Cluster não está ACTIVE no modo esperado.' }
$nodegroup = (Read-AwsJson @('eks', 'describe-nodegroup', '--cluster-name', $clusterName, '--nodegroup-name', "$clusterName-nodes")).nodegroup
if ($nodegroup.status -ne 'ACTIVE' -or @($nodegroup.health.issues).Count -gt 0) { throw 'Node group não está ACTIVE/saudável.' }
foreach ($addon in @('eks-pod-identity-agent', 'aws-ebs-csi-driver', 'metrics-server')) {
    $status = (Read-AwsJson @('eks', 'describe-addon', '--cluster-name', $clusterName, '--addon-name', $addon)).addon
    if ($status.status -ne 'ACTIVE' -or @($status.health.issues).Count -gt 0) { throw "Add-on $addon não está saudável." }
}
$previousKubeconfig = $env:KUBECONFIG
try {
    $env:KUBECONFIG = Join-Path $env:RUNNER_TEMP "base-$Environment-kubeconfig"
    & aws eks update-kubeconfig --name $clusterName --region us-east-1 --alias $clusterName
    if ($LASTEXITCODE -ne 0) { throw 'Falha ao configurar kubeconfig temporário.' }
    # Access entries/policies are eventually consistent; retry only read authorization.
    $authorized = $false
    for ($attempt = 0; $attempt -lt 12; $attempt++) {
        & kubectl --request-timeout=10s auth can-i get nodes
        if ($LASTEXITCODE -eq 0) { $authorized = $true; break }
        Start-Sleep -Seconds 5
    }
    if (!$authorized) { throw 'Acesso da role base não propagou ao Kubernetes.' }
    & kubectl --request-timeout=30s auth whoami -o json
    if ($LASTEXITCODE -ne 0) { throw 'Falha ao autenticar no Kubernetes.' }
    foreach ($authorizationArgs in @(@('get','nodes'), @('create','deployments','--namespace','default'))) {
        & kubectl --request-timeout=30s auth can-i @authorizationArgs
        if ($LASTEXITCODE -ne 0) { throw 'Permissão Kubernetes esperada ausente.' }
    }
    & kubectl --request-timeout=30s wait --for=condition=Ready nodes --all --timeout=120s
    if ($LASTEXITCODE -ne 0) { throw 'Nós não estão Ready.' }
    & kubectl --request-timeout=30s wait --for=condition=Ready pods --all --namespace kube-system --timeout=180s
    if ($LASTEXITCODE -ne 0) { throw 'Pods de sistema não ficaram Ready.' }
    $podsText = & kubectl --request-timeout=30s get pods --namespace kube-system -o json
    if ($LASTEXITCODE -ne 0) { throw 'Falha ao consultar pods de sistema.' }
    $pods = $podsText | ConvertFrom-Json
    if (@($pods.items).Count -eq 0) { throw 'Nenhum pod de sistema encontrado.' }
    foreach ($pod in $pods.items) {
        if ($pod.status.phase -eq 'Succeeded') { continue }
        $ready = @($pod.status.conditions | Where-Object { $_.type -eq 'Ready' -and $_.status -eq 'True' })
        if ($pod.status.phase -ne 'Running' -or $ready.Count -ne 1) { throw "Pod de sistema $($pod.metadata.name) não está Ready." }
    }
    Write-Output "Base $Environment validada pela role da pipeline; capacidade da API/observabilidade permanece pendente."
} finally { $env:KUBECONFIG = $previousKubeconfig }
