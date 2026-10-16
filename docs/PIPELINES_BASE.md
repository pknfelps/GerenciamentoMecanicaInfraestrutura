# Provisionamento e descarte da base

Pré-requisitos: bootstrap aplicado; Environments hom/prd limitados a develop/main, com AWS_BASE_ROLE_ARN. hom-approval/prd-approval devem ter required reviewers e impedir autoaprovação; são os Environments protegidos existentes. Conferir essa proteção no GitHub antes de executar, pois um Environment sem proteção não cria aprovação humana.

Disparar manualmente base-provision e escolher ambiente. Há três jobs:

1. Plan: checkout github.sha, OIDC, init com backend do ambiente, validate, plan -out=tfplan, show textual. Artefato tfplan/tfplan.txt da execução, retido sete dias.
2. Approval: Environment protegido; sem checkout/autenticação AWS.
3. Apply: mesmo commit, OIDC novo, download pelo ID do artefato produzido por plan; init com lock de providers versionado; apply tfplan. Depois, update-kubeconfig, kubectl apply -k kubernetes e aplicação independente de kubernetes/observability/<ambiente>. Reinicia explicitamente o Collector e aguarda seu rollout por até 300 segundos; cada execução recarrega o ConfigMap estável, mesmo sem alteração Terraform. A estratégia Recreate pode interromper brevemente a coleta. O resumo confirma saúde do processo, sem declarar ingestão externa. Falhas exibem Deployment, pods, eventos e logs limitados, sem rollback automático. Os manifestos usam o mesmo SHA da execução; seu conteúdo é revisado no PR e não integra o plano Terraform.

Não há plan depois da aprovação. Estado alterado invalida o plano pelo Terraform; iniciar nova execução e revisar. Expiração do artefato também exige nova execução. Concurrency serializa provision/destroy deste repositório por ambiente; mantenedor serializa as demais unidades/repos.

base-destroy executa plan -destroy salvo, approval e apply; antes do apply configura kubeconfig isolado, remove kubernetes/observability/<ambiente> com espera/cascade foreground/timeout de 300 segundos e, depois, os manifestos Kubernetes da base. Recursos já ausentes são tolerados; falhas reais de remoção interrompem o job e impedem o apply Terraform. Não forçar finalizadores nem ignorar erros. Consumidores e banco já devem estar descartados, inclusive ConfigMap/Secrets/Job do namespace reservado. Se o EKS já foi removido fora deste fluxo, não ignore a falha: revise o estado/configuração e prepare um procedimento de recuperação explicitamente aprovado.

CI de PR e manual executa fmt/validate, Kustomize da raiz e do Collector, além de validar o YAML com docker run da imagem Contrib 0.161.0; não provisiona. A role base já possui acesso administrativo ao EKS, sem ampliar permissões da API. Instalar o Collector não ativa Telemetry__Enabled nos manifestos da API. aws-oidc-check é diagnóstico manual STS, sem escrever evidência SSM. [Migração](MIGRACAO_DECLARATIVA.md) deve preceder a primeira execução nova; não usar destroy para testar.

## Workflows Gateway

Gateway fica separado da base: gateway-provision/gateway-destroy manuais, com environment, api_commit e auth_commit. Develop/hom ou main/prd, role AWS_GATEWAY_ROLE_ARN existente, três jobs plan → aprovação → apply. Os contratos verificados acompanham o plano salvo no mesmo artefato (sete dias); apply usa o mesmo SHA e artefato por ID, sem replan ou novo download S3. A fila gateway por ambiente cobre provisionamento/descarte; o mantenedor serializa mudanças entre componentes. CI também valida a unidade gateway. [Entradas, sequência e descarte](GATEWAY.md).

## Destino New Relic

base-provision sempre exige Secret persistente do ambiente com AWSCURRENT (inspeção antes do plan e novamente antes do apply), aplica kubernetes/observability/<ambiente> e mantém restart/rollout e apply exclusivo do plano aprovado. Sem input de ativação/destino. base-destroy remove o mesmo overlay; CI renderiza hom/prd e valida o único exporter de produção com chave fictícia, sem AWS. [Procedimento completo](NEW_RELIC.md).
