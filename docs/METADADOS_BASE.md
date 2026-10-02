# Metadados da base para o banco — E2.14

Implementação local em 2026-10-02. A comprovação nos runners/AWS ainda está pendente.

Fonte do contrato: [Contratos entre repositórios, seção 4.1.1](https://github.com/pknfelps/GerenciamentoMecanicaSistema/blob/develop/docs/arquitetura/CONTRATOS_ENTRE_REPOSITORIOS.md).

## O que a implementação publica

`scripts/base_metadata.py` é chamado por `Invoke-BasePipeline.ps1`, com AWS CLI e Python padrão. Usa os outputs do próprio Terraform, valida recursos reais e publica `/mecanica/<hom|prd>/base/v1/database-release` por último. O JSON contém a geração persistida, os nove campos do perfil database, o commit aplicado e os checks aprovados. Valores de secrets não são consultados.

`terraform/metadata.tf` acrescenta o SG reservado à função, `database_exports` e `base_generation`. API/Job usam o SG efetivo dos nós EKS; o namespace inicial é `default`, já existente e autorizado. A geração é o ID UUID de `terraform_data.generation`, vinculado à VPC: atualização conserva o valor, recriação da VPC substitui o valor. O SG da função começa sem regras; conectividade específica será implementada na E2.12.

A release completa `base/v1/release` não é produzida neste bloco. Se ela já existir, o provisionamento com este publicador recusa a operação antes de invalidar metadados ou executar apply, evitando rebaixar uma base completa.

## Check com a identidade do banco

A role base não assume a role database. O fluxo usa dois parâmetros operacionais de diagnóstico, que não autorizam implantação de consumidores:

- `base/v1/database-candidate`: escrito pela base após validar VPC, subnets/rotas, EKS, namespace, SGs efetivos dos nós e configuração de acesso EKS do banco. Contém formato 1.0.0, ambiente/conta/região, geração, os nove exports e SHA-256 da configuração do acesso do banco.
- `database/v1/base-access-check`: escrito pelo workflow `aws-oidc-check` do banco com `check_kubernetes=true`. Registra identidade, geração, hash do candidato, run ID, horário UTC e as permissões Kubernetes verificadas com a role real.

O hash do candidato usa JSON UTF-8 ordenado e compacto. O candidato não contém timestamp ou run ID, para permitir reuso da evidência enquanto os recursos e o acesso continuarem iguais. A evidência vale por até 24 horas; geração, dados, identidade, permissões, prazo ou configuração de acesso divergentes bloqueiam a publicação. A base consulta novamente recursos e acesso antes de publicar. Essas verificações não substituem a coordenação entre repositórios: operar sequencialmente por ambiente.

## Primeira execução em hom

1. Publicar as alterações de infraestrutura e do banco em `develop`; os workflows manuais precisam existir também na branch padrão para aparecer no GitHub.
2. Revisar e aplicar administrativamente o bootstrap atualizado, usando seu backend existente. A nova policy inline `base-metadata-network` concede criação do SG marcado do ambiente, remoção da regra de egress padrão e exclusão desse SG. Não aplicar outro backend nem executar destroy do bootstrap. O código não altera trust OIDC nem concede à base escrita no namespace do banco.
3. Executar `base-provision` em `develop`, ambiente `hom`, ação `activate`, e aprovar o plano. Após criar/verificar os recursos, a execução ficará **bloqueada pela falta do check do banco**: o job falha com mensagem explícita e a tentativa SSM fica `blocked`. Recursos criados permanecem disponíveis; nenhuma release de prontidão é publicada.
4. No repositório do banco, executar `aws-oidc-check` em `develop/hom`, com `check_kubernetes=true`. O novo step registra a evidência depois de verificar as permissões reais de Jobs, pods/logs e service accounts. Não cria workloads nem provisiona Aurora.
5. Executar uma **nova ativação completa** da base e aprovar o novo plano. Também é possível usar **Re-run all jobs** para manter o commit. Não usar apenas Re-run failed jobs: o fingerprint de um plano anterior à criação não corresponde ao estado atual. Com recursos/acessos iguais e evidência válida, o workflow publica `database-release`.
6. Conferir o resumo e o parâmetro `database-release`: `status=ready`, `readinessProfile=database`, geração e exports presentes. A base completa, Aurora, SQL e implantação dos consumidores continuam nas próximas etapas.

Uma atualização comum da base pode reutilizar uma evidência de acesso ainda válida quando candidato e permissões não mudaram. Se a configuração mudar ou a evidência expirar, repetir os passos 4 e 5. Sem candidato, o diagnóstico OIDC do banco continua funcionando, mas informa que não registrou evidência SSM.

Repetir com `main/prd` para validar produção. Os namespaces, estados e roles continuam separados.

## Falhas e descarte

- `plan` não altera SSM. O fluxo de provisionamento bloqueia planos destrutivos e confirma commit/fingerprint antes dos metadados.
- Antes da mutação, a base remove e confirma ausência de `release`, `database-release` e `database-candidate`. Erro de leitura/exclusão bloqueia apply.
- A publicação respeita 30 segundos após exclusão antes de recriar nomes SSM. Campos são String/Standard, listas em JSON e limite de 4 KB em UTF-8.
- Falha após iniciar a operação invalida prontidão/candidato e registra `failed`. O caso de dependência bloqueada mantém apenas o candidato para o check do banco. Interrupção abrupta pode deixar `running`; recuperar por uma execução completa após inspeção, mantendo consumidores parados.
- Descarte aprovado invalida os metadados antes do apply, verifica ausência dos recursos, limpa campos ativos e só então registra `destroyed`. A ação `destroy` também executa essa limpeza quando o estado já está vazio e exige aprovação. `plan` permanece somente consulta.
- Registros `attempts/` e a evidência do produtor banco são preservados. A evidência antiga não será aceita por uma nova geração. Bootstrap e outro ambiente não são operados.
- Falha ao limpar SSM deve ser investigada antes de liberar consumidores. SSM não é uma trava distribuída; não executar base/banco/API/função simultaneamente no mesmo ambiente.

Nas tentativas iniciais da base, `generation` pode ser null enquanto o UUID ainda não foi persistido pelo primeiro apply; o mesmo vale para limpeza de estado/metadados vazios sem geração conhecida. Uma `database-release` pronta nunca aceita geração null.

## Verificação local

```powershell
terraform -chdir=terraform fmt -check -recursive
terraform -chdir=bootstrap fmt -check -recursive
terraform -chdir=terraform validate
terraform -chdir=bootstrap validate
terraform -chdir=bootstrap test
terraform -chdir=terraform test -var-file=environments/hom.tfvars
terraform -chdir=terraform test -var-file=environments/prd.tfvars
python -m unittest discover -s scripts/tests -p 'test_*.py' -v
pwsh -NoProfile -File scripts/tests/Test-BasePipeline.ps1
pwsh -NoProfile -File scripts/tests/Test-BaseDestroy.ps1
```

Usar init sem backend em diretório de dados próprio para validação; todos os testes Terraform acima usam provider AWS simulado. Não executar plan/apply AWS como parte desses testes.

Referências: [SSM DeleteParameter e espera de 30 segundos](https://docs.aws.amazon.com/systems-manager/latest/APIReference/API_DeleteParameter.html), [ações EC2 e condições IAM](https://docs.aws.amazon.com/service-authorization/latest/reference/list_ec2.html), [terraform_data](https://developer.hashicorp.com/terraform/language/resources/terraform-data).
