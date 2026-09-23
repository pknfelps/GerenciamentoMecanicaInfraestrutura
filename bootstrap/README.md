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

O provider recusa conta diferente de `aws_account_id`. Backend remoto e recursos do bootstrap permanecem sob identidade administrativa própria, fora das roles de deploy. Nenhuma role das pipelines pode alterar IAM, excluir buckets, acessar o estado do bootstrap ou assumir outras roles.

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

Essas são roles de pipeline, não de execução dos pods/Lambda. Permissões para gerenciar EKS, Aurora, Lambda, Gateway, secrets e roles de execução serão implementadas/revisadas junto dos respectivos componentes em E2/E3. O bootstrap não fornece um deploy completo. Não usar AdministratorAccess ou PassRole irrestrito para preencher essas pendências.

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
