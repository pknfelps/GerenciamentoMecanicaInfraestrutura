# Permissões do runtime da API — E2.6

Implementação preparada em 2026-10-08. A base conserva role, confiança, associação Pod Identity e policy read-jwt existentes. Adiciona somente aws_iam_role_policy.api_database, chamada read-database, em terraform/api-runtime.tf. O apply está pendente de revisão/aprovação do plano salvo, sem deploy nesta entrega.

## Escopo

- secretsmanager:GetSecretValue: Secret /mecanica/<ambiente>/database/api, com ARN restrito à conta/região e seis caracteres de sufixo.
- ssm:GetParameter e ssm:GetParameters: endpoint, port, database-name, api-secret-arn, api-db-user e ssl-mode, exclusivamente em /mecanica/<ambiente>/database/v2/.
- Sem leitura do Secret administrativo RDS, credencial auth, parâmetros extras ou outro ambiente. A policy read-jwt permanece responsável pelo JWT.

Os ARNs do banco são construídos com environment, aws_region e data.aws_caller_identity.current.account_id. Não existem data sources SSM do banco na base, evitando dependência circular e preservando a ordem base → banco → API. O bootstrap já permite GetRolePolicy/PutRolePolicy/DeleteRolePolicy somente na role API do ambiente; nenhum código/apply administrativo adicional é necessário.

## Manifestos e publicação

O repositório da API prepara overlays hom/prd com ServiceAccount default/gerenciamento-api e serviceAccountName correspondente, AWS_REGION=us-east-1, AWS_EC2_METADATA_DISABLED=true e Runtime__Environment do ambiente. Hom usa Staging, prd Production; não copiam Secrets de banco/JWT para Kubernetes nem usam db-secrets. Startup probe tem 12 tentativas de cinco segundos; os demais recursos/probes/HPA permanecem. Service/NLB continuam na base.

Publicar os dois PRs e revisar/aprovar base-provision. O plano de hom deve acrescentar somente read-database, preservando VPC/EKS/NLB/JWT/Pod Identity. O workflow atual mantém plan salvo → aprovação → apply do mesmo artefato. Depois preparar publicação ECR/deploy E2.11 com digest; os overlays usam pending como placeholder e não devem ser aplicados agora. E2.6 fica aberta até validar runtime/RDS/TLS/probes no EKS.

## Validação padrão

terraform fmt -check e validate, kubectl kustomize dos conjuntos local/hom/prd, build/testes locais da API e IAM Access Analyzer. A simulação da policy candidata confirma os recursos próprios e nega auth/administrador/outro ambiente, sem ler credenciais. Após apply, simular a role real e validar Pod Identity no deploy. Não executar GetSecretValue pelo terminal para conferir valores nem aplicar/destroy para testar.

[Inicialização e conexão da API](https://github.com/pknfelps/GerenciamentoMecanicaSistema/blob/develop/docs/INICIALIZACAO_AWS.md) · [JWT compartilhado](JWT_COMPARTILHADO.md) · [Operação da base](PIPELINES_BASE.md).
