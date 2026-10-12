# Gerenciamento Mecanica — Infraestrutura

AWS deste repositório em Terraform; Service e namespace em manifestos Kubernetes próprios. Auth usa SAM/CloudFormation com ZIP ([ADR 009](https://github.com/pknfelps/GerenciamentoMecanicaSistema/blob/develop/docs/arquitetura/adrs/009-SAM-AUTENTICACAO.md)), template/workflows validados localmente e implantação pendente. Bootstrap/base/banco/Gateway permanecem Terraform, incluindo IAM runtime/CI persistentes. Sem wrappers/publicadores/controller. [Decisão](https://github.com/pknfelps/GerenciamentoMecanicaSistema/blob/develop/docs/arquitetura/adrs/008-INFRAESTRUTURA-DECLARATIVA.md).

| Unidade | Conteúdo |
|---|---|
| bootstrap | S3 estado/artefatos, ECR, OIDC, role/policy persistente auth-runtime e permissões das pipelines |
| terraform | VPC/subnets/NAT/EKS, add-ons, acessos, SGs, NLB/ASG, JWT/Pod Identity da API e SSM v2 |
| kubernetes | Service NodePort e namespace database-init |
| gateway | REST API Regional, VPC Link V2, integrações API/Lambda, logs e SSM próprios |

Hom/develop e prd/main: uma VPC/EKS independente, um nó t3.small 1/1/1. Metrics Server e Pod Identity Agent; EBS CSI removido por falta de uso. RDS pertence ao repositório do banco; Gateway tem unidade e workflows separados; implantação e validação HTTP pendentes.

CI: `terraform fmt -check`, `init -backend=false`, `validate` e `kubectl kustomize kubernetes`. Não há testes operacionais próprios; testes de negócio vivem nos repositórios das aplicações.

Provisionamento/destroy das unidades Terraform somente manuais: plan salvo → aprovação hom-approval/prd-approval → apply do mesmo artefato/commit. Nenhum apply por push ou replan após aprovação. O mantenedor deve coordenar alterações sequenciais por ambiente e gerar novo plano dos consumidores quando mudar uma dependência.

- [Workflows e operação](docs/PIPELINES_BASE.md)
- [Gateway REST](docs/GATEWAY.md)
- [NLB interno](docs/NLB_INTERNO.md)
- [SSM v2](docs/METADADOS_BASE.md)
- [JWT compartilhado](docs/JWT_COMPARTILHADO.md)
- [Permissões do runtime da API](docs/API_RUNTIME.md)
- [Migração e validação](docs/MIGRACAO_DECLARATIVA.md)
- [Bootstrap administrativo](bootstrap/README.md)

Implementação local preparada; a migração AWS exige revisão/aprovação dos planos. Não descartar recursos para testar esta reformulação.

Parte 6 da autenticacao: bootstrap prepara role CI de leitura exclusiva do pacote 1.0.0. Aplicacao exige plano salvo aprovado; workflows da funcao usam publicacao separada e provisionamento/destroy SAM manuais sem aprovacao intermediaria. sam delete remove ZIP atual/templates operacionais e preserva contratos, outras revisoes, bucket e IAM persistente. Consulte [bootstrap](bootstrap/README.md) e [procedimento auth](https://github.com/pknfelps/GerenciamentoMecanicaAutenticacao/blob/develop/docs/DEPLOY.md).
