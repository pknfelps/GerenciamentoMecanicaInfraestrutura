# Bootstrap persistente

Unidade Terraform independente de `../terraform/`, que ainda representa o EKS herdado. Prepara S3, ECR e a identidade GitHub/AWS compartilhados por hom/prd. Não cria workloads, banco, rede nem recursos Kubernetes.

## Recursos e propriedade

| Recurso | Configuração |
|---|---|
| Estado S3 | Nome `<projeto>-tfstate-<conta>-us-east-1`; privado, AES256, versionado, HTTPS |
| Artefatos S3 | Nome `<projeto>-artifacts-<conta>-us-east-1`; privado, AES256, versionado, escrita condicional |
| ECR | `<projeto>/api`; tags imutáveis, scan no push, AES256 |
| OIDC | GitHub, audience `sts.amazonaws.com`; criar ou referenciar provider existente |
| IAM | Dez roles: base, gateway, database, api e auth, para hom e prd |

Buckets, ECR e provider criado têm `prevent_destroy`. Buckets/ECR também não permitem remoção forçada de conteúdo. Não há expiração automática de imagens, versões ou contratos: referências por digest e rollback precisam continuar válidas. O bootstrap é persistente e nunca integra o descarte normal de um ambiente. As proteções do Terraform não substituem IAM e não protegem recursos removidos completamente da configuração.

O provider recusa conta diferente de `aws_account_id`. Backend remoto e recursos do bootstrap permanecem sob identidade administrativa própria, fora das roles de deploy. As roles base podem administrar somente as três roles de execução EKS do próprio ambiente, com associações de policies limitadas por role e PassRole por serviço. Nenhuma role pode alterar a identidade/permissões das pipelines, excluir buckets ou acessar o estado do bootstrap. Não há permissão sts:AssumeRole nas pipelines.

## Inputs e configuração inicial

Copiar `bootstrap.tfvars.example` para `bootstrap.tfvars` e revisar a conta, o prefixo de nomes e os subjects. Arquivos locais estão ignorados no Git; não inserir credenciais neles. Os nomes dos buckets incluem conta/região, mas disponibilidade global e eventual recurso já existente devem ser conferidos no plano real.

`github_subject_prefixes` exige quatro repositórios exatos. O código acrescenta `:environment:hom` ou `:environment:prd` e usa `StringEquals`, sem wildcard na confiança. Audience obrigatória: `sts.amazonaws.com`. A confiança também exige o claim `ref` exato: refs/heads/develop para hom e refs/heads/main para prd, conforme suporte atual documentado pela AWS.

O exemplo usa IDs públicos consultados em 2026-09-22 e o formato padrão documentado pelo GitHub: API criada antes de 15/07/2026 com subject por nome; três novos repositórios com owner/repository IDs imutáveis. Isso é uma previsão, não uma observação de tokens reais. Conferir o claim `sub` emitido pelo workflow antes da aplicação, especialmente se houver customização, renomeação ou transferência. Não registrar o JWT completo. Uma configuração divergente deve falhar na autenticação, sem ampliar a confiança para `repo:owner/*`.

Manter as regras de Environment: hom aceita somente develop e prd somente main. Jobs de PR validam localmente e não recebem as roles AWS. Jobs de deploy devem declarar o Environment explicitamente e solicitar `id-token: write`.

A role Gateway aceita subjects exatos de infra, API e autenticação do mesmo ambiente, pois um workflow reutilizável executa no contexto do chamador. Não aceita BancoDados nem o outro ambiente. O workflow reutilizável deverá ser fixado por commit; esta confiança não verifica ainda o SHA do workflow.

## Permissões disponíveis

Cada role possui uma política `bootstrap-access`. Os statements gerados em `identity.tf` têm os seguintes propósitos:

| Statement | Escopo |
|---|---|
| LocateStateBucket / ListOwnState | Localizar bucket e listar apenas a chave/lock da unidade; prefixo de descoberta de workspaces próprio |
| ReadWriteOwnState | Get/Put somente no estado da unidade/ambiente |
| OwnStateLock | Get/Put/Delete somente no arquivo .tflock correspondente |
| ReadArtifacts | Get somente nos prefixos consumidos pelo componente |
| PublishArtifacts | Put somente nos prefixos produzidos; sem Delete, ACL ou exclusão de versões |
| ReadEnvironmentMetadata | Leitura SSM somente em /mecanica/<ambiente>/; guardar ali apenas metadados não secretos |
| PublishOwnMetadata | Put/tag/Delete somente no namespace v1 produzido pelo componente |
| EcrAuthentication | Token ECR; Resource * exigido por essa operação, presente somente nas roles da API |
| PublishApiImage | Publicação/leitura das camadas somente no repositório ECR da API |

API não acessa estado Terraform. API publica `contracts/api/` e `packages/GerenciamentoMecanica.Auth.Contracts/`; autenticação lê o pacote e publica `contracts/auth/` e `lambda/`; Gateway lê os dois contratos e publica `contracts/gateway/`. Base/banco não recebem acesso ao bucket de artefatos neste estágio.

As permissões da base foram acrescentadas em [base-permissions.tf](base-permissions.tf): quatro policies gerenciadas por ambiente para EC2/EKS/IAM, anexadas somente à base; API/banco recebem DescribeCluster do ambiente. IAM/PassRole limitado às três roles EKS e policies de serviço correspondentes. Não há gerenciamento de roles OIDC pela pipeline. Access entries Kubernetes ficam na unidade da base. Aplicar estas alterações de bootstrap com identidade administrativa, seguindo [PIPELINES_BASE.md](../docs/PIPELINES_BASE.md).

Essas são roles de pipeline, não de execução dos pods/Lambda. A role database recebe permissões para RDS PostgreSQL em [database-rds-permissions.tf](database-rds-permissions.tf). Permissões de Lambda, Gateway e seus secrets continuam junto dos respectivos componentes em E2/E3. EKS e suas roles de execução estão cobertos pela ampliação da base descrita acima. O bootstrap não fornece um deploy completo. Não usar AdministratorAccess ou PassRole irrestrito para preencher essas pendências.

## Estados e locking

Use o workspace `default`, com um backend por unidade/ambiente:

- `shared/bootstrap/terraform.tfstate`: somente administração do bootstrap.
- `hom/<base|gateway|database|auth>/terraform.tfstate`.
- `prd/<base|gateway|database|auth>/terraform.tfstate`.

Todos os backends S3 devem usar `encrypt=true` e `use_lockfile=true`. O output `backend_configs` também define `workspace_key_prefix` por unidade; o prefixo pode ser listado para descoberta, mas estados de workspaces adicionais não têm acesso concedido. Não usar Terraform workspaces para separar hom/prd.

O lock protege cada estado. Coordenação entre repositórios/dependências ainda será implementada; locks distintos não impedem hom/prd coexistirem.

## Artefatos sem sobrescrita

A policy de artefatos exige `If-None-Match` na criação de objetos, inclusive conclusão de multipart; as etapas intermediárias de multipart são isentas porque não aceitam esse cabeçalho. Para arquivos pequenos, publicar usando chave por commit e:

```powershell
aws s3api put-object --bucket <bucket-artefatos> --key contracts/api/<commit>/openapi.json --body openapi.json --if-none-match "*"
```

Não usar `aws s3 cp` como substituto sem conferir suporte ao cabeçalho condicional. Uma publicação repetida deve conferir o checksum do objeto existente, não sobrescrevê-lo. Nenhuma role das pipelines exclui artefatos/versões. Versionamento isoladamente não garante imutabilidade; administradores da conta ainda podem administrar dados/policies.

## Validação local e CI

Terraform 1.15.9 e AWS provider 6.58.0, conforme lockfile com checksums Windows/Linux. Da raiz do repositório:

```powershell
terraform -chdir=bootstrap fmt -check -recursive
terraform -chdir=bootstrap init -backend=false -input=false -lockfile=readonly
terraform -chdir=bootstrap validate
terraform -chdir=bootstrap test
```

Os testes usam `mock_provider "aws"` e todos os runs usam `command=plan`. Não usam credenciais, backend remoto ou apply. Cobrem trust por ambiente/repositório, estado e permissões, proteção dos dados, reutilização de provider e rejeição de inputs inválidos.

O check existente `terraform-validate` valida as duas unidades (`terraform/` e `bootstrap/`) e executa os testes simulados. Planos simulados não comprovam permissões de provisionamento, disponibilidade de nomes ou login OIDC real.

## Primeira execução na AWS — etapa posterior

1. Autenticar localmente com uma identidade autorizada a administrar o bootstrap e conferir conta com `aws sts get-caller-identity`. A sessão do plugin AWS é independente da AWS CLI/Terraform.
2. Revisar subjects reais, providers existentes e os inputs. Se um provider do GitHub já pertencer a outro estado, preencher `existing_github_oidc_provider_arn` e conferir URL/audience. Não criar um segundo provider nem importar automaticamente recurso alheio.
3. Manter inicialmente backend local (não copiar ainda `backend.s3.tf.example`). Executar `terraform -chdir=bootstrap plan -var-file=bootstrap.tfvars -out=bootstrap.tfplan` e revisar com `terraform -chdir=bootstrap show bootstrap.tfplan`.
4. Somente na etapa de provisionamento, aplicar o plano revisado. Preservar o estado local até concluir a migração. Nunca versionar estado ou plano.
5. Conferir `terraform -chdir=bootstrap output bootstrap_backend_config`. Copiar `backend.s3.tf.example` para `backend.s3.tf` e `backend.hcl.example` para `backend.hcl`, ajustando nomes aos outputs. Migrar com `terraform -chdir=bootstrap init -migrate-state -backend-config=backend.hcl`. Não substituir por `-reconfigure`, que não migra o estado.
6. Conferir o estado remoto e um novo plano sem mudanças antes de remover cópias locais. Nas próximas execuções, reconstruir os arquivos de backend ignorados a partir desses exemplos e usar o S3; não reiniciar acidentalmente com estado local vazio.
7. Usar `terraform -chdir=bootstrap output -json github_environment_variables` para substituir as descrições provisórias nos oito Environments. Referência do ECR em `shared_resources`; o publicador de metadados da base ainda será implementado.
8. Validar OIDC por ambiente/componente e acesso aos recursos esperados, incluindo rejeição do ambiente/repositório errado. Só depois integrar deploys reais.

Não há workflow que aplique este bootstrap automaticamente. Alterações do bootstrap seguem a identidade administrativa inicial e revisão própria; suas pipelines de workload não podem editar a própria confiança/permissões.

## Referências

- [GitHub OIDC e formatos de subject](https://docs.github.com/en/actions/reference/security/oidc).
- [OIDC na AWS](https://docs.github.com/en/actions/how-tos/secure-your-work/security-harden-deployments/oidc-in-aws).
- [Terraform backend S3](https://developer.hashicorp.com/terraform/language/backend/s3).
- [Testes com provider simulado](https://developer.hashicorp.com/terraform/language/tests/mocking).
- [S3: exigir escrita condicional](https://docs.aws.amazon.com/AmazonS3/latest/userguide/conditional-writes-enforce.html).
- [AWS: claims GitHub disponíveis para condições IAM](https://docs.aws.amazon.com/IAM/latest/UserGuide/reference_policies_iam-condition-keys.html#condition-keys-wif).

## Consulta da base pela role do banco

`database-metadata-permissions.tf` acrescenta a policy inline `database-metadata-read`
nas roles database de hom/prd. Contém somente DescribeVpcs, DescribeSubnets,
DescribeRouteTables e DescribeSecurityGroups, limitadas a us-east-1. Essas ações EC2
exigem Resource `*`; o consumidor confere conta, ambiente, tags e relações dos recursos.
Não modifica trust, acesso Kubernetes, namespace SSM nem permissões de escrita.

A configuração passou nos testes simulados e foi aplicada no backend remoto existente
em 2026-10-02: 2 policies criadas, nenhuma alteração/exclusão. O plano posterior
retornou No changes; as policies IAM reais de hom/prd foram conferidas. Evidências
locais ignoradas pelo Git: `artifacts/terraform/bootstrap/database-release-read-2026-10-02`.
A configuração anterior criou `database-aurora-rds`, `database-aurora-network`
em hom/prd e a service-linked role compartilhada `AWSServiceRoleForRDS` em
2026-10-02 (5 criações, nenhuma alteração/exclusão). Access Analyzer não encontrou
findings naquele plano; as simulações cobriram os recursos Aurora de cada ambiente.
Evidência local ignorada pelo Git:
`artifacts/terraform/bootstrap/database-aurora-iam-2026-10-02`.

A configuração atual substitui as quatro policies inline de Aurora por
`database-rds` e `database-network`, preservando o endereço da service-linked role.
Cada role database pode criar e administrar a instância
`mecanica-<ambiente>-postgres`, seu subnet group e SG no próprio ambiente.
`CreateDBInstance` exige senha mestre gerenciada pelo RDS, armazenamento
criptografado e acesso privado. A role pode criar e etiquetar apenas secrets com
prefixo `rds!db-` na conta/região e descrever a chave KMS; essa policy não lê valores,
criar chaves nem usar `iam:PassRole`. A autorização para usar o subnet group na
criação da instância fica em statement separado, pois `rds:StorageEncrypted` só
é avaliado para a instância.

Aplicado no backend remoto em 2026-10-05: quatro policies antigas substituídas,
sem alterações em outros recursos. O Access Analyzer retornou zero findings para
as quatro policies novas. A simulação das roles reais confirmou criação no próprio
ambiente e negação no outro; negou também leitura do segredo e `iam:PassRole`.
O plano posterior retornou `No changes`.

Isso não cria a instância nem credenciais específicas da API/função.
[Procedimento do consumidor](https://github.com/pknfelps/GerenciamentoMecanicaBancoDados/blob/develop/docs/CONSUMO_BASE.md).

## Leitura temporária para o Job SQL

`database-init-secret-read.tf` acrescenta `secretsmanager:GetSecretValue` às roles
`mecanica-hom-database-github` e `mecanica-prd-database-github`. Cada policy exige
região `us-east-1`, segredo gerenciado pelo RDS e a tag AWS
`aws:rds:primaryDBInstanceArn` igual ao ARN da instância PostgreSQL do próprio
ambiente. O nome aleatório do segredo pode mudar ao recriar o banco sem ampliar
acesso ao outro ambiente. O workflow do banco também compara o ARN do segredo
retornado por Terraform ao da instância RDS selecionada.

Esta permissão pertence ao bootstrap persistente e não é aplicada pelo workflow
do banco. Antes de executar `database-provision/activate`, revisar e aplicar o
plano do backend `shared/bootstrap/terraform.tfstate` com identidade
administrativa. Sem a policy, `Initialize schema in EKS` falha em
`GetSecretValue` antes de criar o Job. O primeiro plano de 2026-10-06 prevê
apenas duas criações de policies, sem alterações ou exclusões. O plano
aprovado foi aplicado em 2026-10-06: 2 adicionadas, 0 alteradas e 0 excluídas.
As policies reais de hom/prd foram conferidas, a simulação da role hom no
segredo RDS real retornou `allowed` e um novo plano mostrou `No changes`.

## Credenciais PostgreSQL dos consumidores

`database-api-secret.tf` permite que a pipeline do banco crie e reutilize
`/mecanica/<ambiente>/database/api`. `database-auth-secret.tf` prepara a mesma
operação para `/mecanica/<ambiente>/database/auth`, usada por `mecanica_auth`.
Cada policy é vinculada somente à role database do próprio ambiente e autoriza
CreateSecret/TagResource com as tags Project=mecanica, Environment e
ManagedBy=database-provision, DescribeSecret no caminho exato e GetSecretValue
com as mesmas tags do recurso. O ARN inclui conta, região e sufixo de seis
caracteres do Secrets Manager. Não há leitura de outros ambientes, rotação,
exclusão ou replicação de secrets nessa ampliação.

A senha é gerada no runner e aplicada pelo Job SQL; não entra no estado Terraform.
A policy da API foi aplicada em 06/10/2026. A policy de autenticação foi aplicada
em 07/10/2026 no backend `shared/bootstrap/terraform.tfstate`, após autorização:
2 policies criadas, nenhuma alteração/exclusão; plano posterior `No changes`.
As policies de hom/prd foram conferidas. Simulação da role hom confirmou
CreateSecret, TagResource, DescribeSecret e GetSecretValue no Secret auth do
próprio ambiente e negou as quatro ações no de prd. Evidências locais ignoradas:
`artifacts/terraform/bootstrap/database-auth-secret-2026-10-07`.

O workflow do banco não aplica o bootstrap. O próximo passo é publicar as
alterações do banco e validar `database-provision` em hom; a criação do Secret
e do usuário PostgreSQL acontece nessa execução. A role de execução da Lambda
receberá acesso de leitura ao Secret auth na implementação da autenticação.
