# GerenciamentoMecanicaInfraestrutura

Responsável pela infraestrutura AWS e plataforma Kubernetes do sistema de oficina. Repositório separado na E1.2 do Tech Challenge Fase 3.

## Estado atual

`terraform/` contém a base da Fase 2 transferida sem mudança funcional: VPC/subnets públicas, EKS, IAM e add-ons. **Ainda não implementa a arquitetura privada hom/prd da Fase 3.** Não aplicar esta base como se o Aurora, Gateway, NLB interno ou OIDC já estivessem configurados. Nenhum recurso foi provisionado nesta separação.

| Caminho | Responsabilidade |
|---|---|
| `terraform/` | Base AWS existente; adaptar na E2 para rede privada, ambientes, backend e bootstrap |
| `kubernetes/` | Service de entrada da API, transferido sem mudança funcional; controller/NLB interno seguem na E2 |
| `kubernetes/optional/metrics-server.yaml` | Manifesto alternativo já versionado, para clusters sem o add-on; não aplicar junto com o add-on Terraform |
| `docs/origem-fase2.json` | Repositório/commit de origem, mapeamento e hashes dos arquivos transferidos (UTF-8/LF) |

O Kustomize deste repositório inclui apenas o Service. Deployment/HPA pertencem à aplicação; banco/esquema ao repositório de banco. O EBS CSI permanece na base transferida e sua necessidade será revista com a remoção do PostgreSQL do EKS em E2. Configurações locais, tfstate, tfvars preenchidos e caches de providers não foram transferidos; verificar estados/recursos anteriores antes de qualquer apply para não criar duplicatas.

## Verificações locais

Pré-requisitos: Terraform conforme `terraform/versions.tf` e kubectl com Kustomize.

```powershell
terraform -chdir=terraform init -backend=false
terraform -chdir=terraform validate
kubectl kustomize kubernetes
```

Esses comandos não aplicam recursos. Pipelines e configuração final de implantação serão implementadas nas etapas seguintes. `.terraform.lock.hcl` foi preservado.

## Referências

- [Aplicação e plano central](https://github.com/pknfelps/GerenciamentoMecanicaSistema)
- [Banco](https://github.com/pknfelps/GerenciamentoMecanicaBancoDados)
- [Autenticação](https://github.com/pknfelps/GerenciamentoMecanicaAutenticacao)

O plano e os ADRs ficam em `PLANO_FASE_3.md` e `docs/` na aplicação; consulte a branch da implementação enquanto o PR não estiver integrado. Gateway/VPC Link/composição OpenAPI terão unidade própria, separada da base Terraform, na E2/E3. Este README inicial não substitui a documentação de implantação final da E1.3/E7.
