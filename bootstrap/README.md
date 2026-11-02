# Bootstrap administrativo persistente

Unidade Terraform responsável pelos recursos compartilhados e pelas permissões das pipelines. Não pertence ao ciclo de destroy de hom/prd.

## Responsabilidades

- Backend S3 versionado/criptografado e locking; bucket de artefatos e ECR.
- Provider OIDC GitHub e roles de CI/provisionamento por componente/ambiente.
- Roles runtime persistentes de auth/email; SAM administra as funções, não essas roles.
- Metadados dos Secrets New Relic, leitura restrita da layer Collector e integração X-Ray por role de leitura.
- Role mecanica-newrelic-github para o backend exclusivo dos dashboards, sem provisionamento AWS ou acesso aos outros estados.

Os catálogos SSM e permissões são específicos de ambiente/serviço. Pipelines usam OIDC, sem credenciais AWS duráveis no GitHub. Políticas de branches dos Environments e checagens dos workflows complementam o subject OIDC.

## Configuração

Terraform 1.15.9 e lockfile versionado; conta 121754142617, região us-east-1. Backend e tfvars reais são locais/ignorados. Os exemplos documentam inputs não secretos:

- [backend.hcl.example](backend.hcl.example)
- [backend.s3.tf.example](backend.s3.tf.example)
- [bootstrap.tfvars.example](bootstrap.tfvars.example)

new_relic_account_id configura o ExternalId da confiança X-Ray. License Key é cadastrada diretamente no Secrets Manager; Terraform administra somente seus metadados. A User API Key dos dashboards é outra credencial e fica no Secret do Environment GitHub newrelic.

## Validação e aplicação

~~~powershell
terraform fmt -check
terraform init -backend-config=backend.hcl -lockfile=readonly
terraform validate
terraform plan -var-file=bootstrap.tfvars -out=bootstrap.tfplan
terraform show -no-color bootstrap.tfplan
~~~

A aplicação usa exclusivamente bootstrap.tfplan após revisão/aprovação. Um plano desatualizado exige nova execução e nova revisão. Não publicar planos, estados, valores de Secrets ou credenciais.

## Integração com os consumidores

Base, banco, API, auth, email e Gateway recebem permissões próprias. Alterações em IAM necessárias a um novo consumidor devem ser aplicadas antes de seus workflows. As roles runtime continuam disponíveis para a limpeza de ENIs após remover funções.

[Arquitetura e propriedade dos recursos](https://github.com/pknfelps/GerenciamentoMecanicaSistema/blob/develop/docs/arquitetura/CONTRATOS_ENTRE_REPOSITORIOS.md) · [Infraestrutura](../README.md) · [Dashboards New Relic](../observability/newrelic/README.md).
