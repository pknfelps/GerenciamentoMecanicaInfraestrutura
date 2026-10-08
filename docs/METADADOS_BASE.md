# Configuração SSM da base

Fonte: `terraform/metadata.tf`, recursos aws_ssm_parameter.configuration. Namespace `/mecanica/<hom|prd>/base/v2/<campo>`, String/Standard; listas de subnets JSON.

Campos: vpc-id; workload-subnet-ids; database-subnet-ids; cluster-name; cluster-arn; namespace=default; init-namespace=database-init; api-security-group-id; auth-security-group-id; init-security-group-id; api-service-name; api-service-port; api-node-port; nlb-arn; nlb-dns-name; nlb-security-group-id; nlb-target-group-arn; nlb-listener-port; nlb-listener-protocol; api-integration-uri; ecr-repository-url; jwt-secret-arn; jwt-issuer; jwt-audience.

Banco lê somente campos de rede/EKS necessários via data sources Terraform. API/auth/Gateway serão adaptados quando seu Terraform/deploy for implementado. JWT implementado na base: Secret /mecanica/<ambiente>/base/jwt, issuer mecanica-<ambiente>-auth e audience mecanica-<ambiente>-api; aplicação/validação AWS e integração dos runtimes pendentes. Chave não pertence ao SSM. Observabilidade permanece posterior. [Consumo e operação JWT](JWT_COMPARTILHADO.md).

SSM descreve configuração e não garante prontidão. Sem releases, candidatos, tentativas, fingerprints ou validade de acesso. Workflow concluído, Job Complete e integração demonstram sucesso. Operações sequenciais por ambiente; dependência alterada exige plano novo dos consumidores. Não consumir estado de outro repositório.

Adotar/retirar v1 ativo somente depois de produtores/consumidores v2. [Procedimento](MIGRACAO_DECLARATIVA.md). Registros históricos de tentativas permanecem fora da adoção.
