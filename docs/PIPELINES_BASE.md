# Provisionamento e descarte da base

Pré-requisitos: bootstrap aplicado; Environments hom/prd limitados a develop/main, com AWS_BASE_ROLE_ARN. hom-approval/prd-approval devem ter required reviewers e impedir autoaprovação; são os Environments protegidos existentes. Conferir essa proteção no GitHub antes de executar, pois um Environment sem proteção não cria aprovação humana.

Disparar manualmente base-provision e escolher ambiente. Há três jobs:

1. Plan: checkout github.sha, OIDC, init com backend do ambiente, validate, plan -out=tfplan, show textual. Artefato tfplan/tfplan.txt da execução, retido sete dias.
2. Approval: Environment protegido; sem checkout/autenticação AWS.
3. Apply: mesmo commit, OIDC novo, download pelo ID do artefato produzido por plan; init com lock de providers versionado; apply tfplan. Depois, update-kubeconfig, kubectl apply -k kubernetes e aplicação independente de kubernetes/observability/<ambiente>. Reinicia explicitamente o Collector e aguarda seu rollout por até 300 segundos; cada execução recarrega o ConfigMap estável, mesmo sem alteração Terraform. A estratégia Recreate pode interromper brevemente a coleta. O resumo confirma saúde do processo, sem declarar ingestão externa. Falhas exibem Deployment, pods, eventos e logs limitados, sem rollback automático. Os manifestos usam o mesmo SHA da execução; seu conteúdo é revisado no PR e não integra o plano Terraform.

Não há plan depois da aprovação. Estado alterado invalida o plano pelo Terraform; iniciar nova execução e revisar. Expiração do artefato também exige nova execução. Concurrency serializa provision/destroy deste repositório por ambiente; mantenedor serializa as demais unidades/repos.

base-destroy executa plan -destroy salvo, approval e apply; antes do apply configura kubeconfig isolado, remove kubernetes/observability/<ambiente> com espera/cascade foreground/timeout de 300 segundos e, depois, os manifestos Kubernetes da base. Recursos já ausentes são tolerados; falhas reais de remoção interrompem o job e impedem o apply Terraform. Não forçar finalizadores nem ignorar erros. Consumidores e banco já devem estar descartados, inclusive ConfigMap/Secrets/Job do namespace reservado. Se o EKS já foi removido fora deste fluxo, não ignore a falha: revise o estado/configuração e prepare um procedimento de recuperação explicitamente aprovado.

CI de PR e manual executa fmt/validate e Kustomize da raiz e dos overlays do Collector; não provisiona nem executa testes de telemetria ou imagens Collector. A role base já possui acesso administrativo ao EKS, sem ampliar permissões da API. Instalar o Collector não ativa Telemetry__Enabled nos manifestos da API. aws-oidc-check é diagnóstico manual STS, sem escrever evidência SSM. [Migração](MIGRACAO_DECLARATIVA.md) deve preceder a primeira execução nova; não usar destroy para testar.

## Workflows Gateway

Gateway fica separado da base: gateway-provision/gateway-destroy manuais, com environment, api_commit e auth_commit. Develop/hom ou main/prd, role AWS_GATEWAY_ROLE_ARN existente, três jobs plan → aprovação → apply. Os contratos verificados acompanham o plano salvo no mesmo artefato (sete dias); apply usa o mesmo SHA e artefato por ID, sem replan ou novo download S3. A fila gateway por ambiente cobre provisionamento/descarte; o mantenedor serializa mudanças entre componentes. CI também valida a unidade gateway. [Entradas, sequência e descarte](GATEWAY.md).

## Destino New Relic

base-provision sempre exige Secret persistente do ambiente com AWSCURRENT (inspeção antes do plan e novamente antes do apply), aplica kubernetes/observability/<ambiente> e mantém restart/rollout e apply exclusivo do plano aprovado. Sem input de ativação/destino. base-destroy remove o mesmo overlay; CI renderiza hom/prd; a validação nativa do YAML é uma conferência local, sem novo step de workflow. [Procedimento completo](NEW_RELIC.md).

## Bloqueios de dependência no destroy — 17/10/2026

base-destroy consulta somente sua dependência direta, o banco, antes do plan e novamente no apply, antes de excluir Collector/manifestos. Exige ausência de RDS, DB subnet group e SG do banco, inclusive recursos em exclusão. Não repete as consultas de API/auth/Gateway: database-destroy verifica API/auth, e os destroys de API/auth verificam Gateway.

O job plan da base não precisa de kubectl para essa checagem. O job apply preserva kubectl para remover seus próprios manifestos depois de checar o banco. Esta entrega não recupera automaticamente Terraform/Kubernetes quando EKS/SSM já foram removidos.

Todas as checagens usam set -euo pipefail, JSON, paginação automática e nomes exatos hom/prd. Consulta negada, falha de rede ou parsing inválido interrompe o fluxo, sem inferir ausência. Recursos do banco em exclusão continuam bloqueando. Nenhuma espera automática ou rollback; concluir database-destroy antes de repetir.

Publicação: revisar/aplicar plano adicional do bootstrap, aplicar base com associação AmazonEKSViewPolicy em default para database, publicar os workflows e então usá-los. Preservados revisão/aprovação, artefatos, mesma revisão e apply do plano salvo. gateway-destroy não muda. Não ler estados externos, gravar prontidão no SSM nem executar destroy como teste desta implementação.

## Coleta Kubernetes — 17/10/2026

Os overlays observability/hom e prd incluem ClusterRole/ClusterRoleBinding, habilitação de token somente no pod, Downward API e identificação por cluster/ambiente. A aplicação/restart/espera e remoção existentes abrangem esses recursos sem modificar workflows ou permissões IAM. RBAC de escopo de cluster também é removido pelo delete do overlay; não basta apagar o namespace isoladamente.

Após o PR, executar base-provision e conferir coleta, RBAC/TLS, consumo e dados no New Relic conforme [Collector API](COLLECTOR_API.md). Não é necessário deploy dos consumidores. Instalação e saúde do processo não comprovam ingestão nem tornam E5.4/E5.12 concluídas.

**Conferência hom — 17/10/2026:** base-provision run 39086883099/revisão 92238eb aplicado pelo mantenedor. Coleta Kubernetes e enriquecimento comprovados no New Relic, com comparação dos valores, duas amostras por minuto e Collector Ready sem reinícios/erros. Sem alteração de recursos/permissões durante a validação. E5.4/E5.12 comprovadas em hom; prd e carga permanecem separados. [Evidência](https://github.com/pknfelps/GerenciamentoMecanicaSistema/blob/develop/docs/VALIDACAO_KUBERNETES_HOM_2026-10-17.md).

## Coleta CloudWatch — 18/10/2026

Workflows e inputs preservados. Após PR, executar somente base-provision para adicionar a policy read-cloudwatch da role Collector e sua descrição; Terraform vem antes dos overlays e restart já existentes. Plano salvo continua sujeito a aprovação, sem replan no apply. Não requer bootstrap, deploy API/auth, banco ou Gateway; ausência dos consumidores não cria dependência Terraform.

Os overlays montam os dois YAMLs públicos; uma alteração isolada de ConfigMap precisa do restart existente. Base-destroy já remove Collector/configuração antes de excluir role/policies. Antes de iniciar gateway-destroy, encerrar o tráfego e confirmar última coleta/exportação, respeitando os dez minutos de atraso de métricas: o grupo de logs é excluído pelo Gateway. Sem espera automática nova. [Procedimento e limites](CLOUDWATCH.md). E5.14 permanece parcial até conferência implantada.
