# Configuração SSM da base

Fonte: `terraform/metadata.tf`, recursos aws_ssm_parameter.configuration. Namespace `/mecanica/<hom|prd>/base/v2/<campo>`, String/Standard; listas de subnets JSON.

Campos: vpc-id; workload-subnet-ids; database-subnet-ids; cluster-name; cluster-arn; namespace=default; init-namespace=database-init; api-security-group-id; auth-security-group-id; gateway-security-group-id; init-security-group-id; api-service-name; api-service-port; api-node-port; nlb-arn; nlb-dns-name; nlb-security-group-id; nlb-target-group-arn; nlb-listener-port; nlb-listener-protocol; api-integration-uri; ecr-repository-url; jwt-secret-arn; jwt-issuer; jwt-audience.

Banco lê campos de rede/EKS via data sources Terraform. API/Gateway consomem configuração pública em seus deploys. Auth usa SAM/CloudFormation conforme ADR 009: workflow lê vpc-id, workload-subnet-ids, auth-security-group-id da base e security-group-id do banco com AWS CLI; jq transforma array JSON das subnets em lista CSV para o parâmetro CloudFormation. Confere VPC/ambiente, subnets em duas AZs e SGs, sem estado remoto ou valores secretos. Auth/v2 pertence à stack; base/database v2 permanecem Terraform. JWT implementado/validado em hom no ciclo anterior; recriar dependências antes de implantar auth. Chave no Secrets Manager, fora do SSM. [Consumo JWT](JWT_COMPARTILHADO.md).

SSM descreve configuração e não garante prontidão. Sem releases, candidatos, tentativas, fingerprints ou validade de acesso. Workflow concluído, Job Complete e integração demonstram sucesso. Operações sequenciais por ambiente; dependência alterada exige plano novo dos consumidores. Não consumir estado de outro repositório.

Adotar/retirar v1 ativo somente depois de produtores/consumidores v2. [Procedimento](MIGRACAO_DECLARATIVA.md). Registros históricos de tentativas permanecem fora da adoção.

## Configuração Gateway

A base publica gateway-security-group-id e permanece proprietária desse SG e de suas regras. O estado separado gateway publica sete parâmetros String/Standard em /mecanica/<ambiente>/gateway/v2/: rest-api-id, vpc-link-id, stage-name, endpoint, api-openapi-key, auth-openapi-key e auth-invocation-arn. Consome a rede/NLB da base e a versão numérica/contrato auth por data sources, sem valores secretos. [Procedimento](GATEWAY.md).
