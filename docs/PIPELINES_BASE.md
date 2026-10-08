# Provisionamento e descarte da base

Pré-requisitos: bootstrap aplicado; Environments hom/prd limitados a develop/main, com AWS_BASE_ROLE_ARN. hom-approval/prd-approval devem ter required reviewers e impedir autoaprovação; são os Environments protegidos existentes. Conferir essa proteção no GitHub antes de executar, pois um Environment sem proteção não cria aprovação humana.

Disparar manualmente base-provision e escolher ambiente. Há três jobs:

1. Plan: checkout github.sha, OIDC, init com backend do ambiente, validate, plan -out=tfplan, show textual. Artefato tfplan/tfplan.txt da execução, retido sete dias.
2. Approval: Environment protegido; sem checkout/autenticação AWS.
3. Apply: mesmo commit, OIDC novo, download pelo ID do artefato produzido por plan; init com lock de providers versionado; apply tfplan. Depois, update-kubeconfig e kubectl apply -k kubernetes.

Não há plan depois da aprovação. Estado alterado invalida o plano pelo Terraform; iniciar nova execução e revisar. Expiração do artefato também exige nova execução. Concurrency serializa provision/destroy deste repositório por ambiente; mantenedor serializa as demais unidades/repos.

base-destroy executa plan -destroy salvo, approval e apply; antes do apply configura kubeconfig isolado e remove os manifestos Kubernetes. Consumidores e banco já devem estar descartados, inclusive ConfigMap/Secrets/Job do namespace reservado. Se o EKS já foi removido fora deste fluxo, não ignore a falha: revise o estado/configuração e prepare um procedimento de recuperação explicitamente aprovado.

CI de PR/push é somente fmt/validate/Kustomize; não provisiona. aws-oidc-check é diagnóstico manual STS, sem escrever evidência SSM. [Migração](MIGRACAO_DECLARATIVA.md) deve preceder a primeira execução nova; não usar destroy para testar.
