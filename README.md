# Gerenciamento Mecanica — Infraestrutura

AWS em Terraform; Service e namespace em manifestos Kubernetes próprios. Sem wrappers, publicadores ou controller. [Decisão](https://github.com/pknfelps/GerenciamentoMecanicaSistema/blob/develop/docs/arquitetura/adrs/008-INFRAESTRUTURA-DECLARATIVA.md).

| Unidade | Conteúdo |
|---|---|
| bootstrap | S3 estado/artefatos, ECR, OIDC e IAM persistentes |
| terraform | VPC/subnets/NAT/EKS, add-ons, acessos, SGs, NLB/ASG, JWT/Pod Identity da API e SSM v2 |
| kubernetes | Service NodePort e namespace database-init |

Hom/develop e prd/main: uma VPC/EKS independente, um nó t3.small 1/1/1. Metrics Server e Pod Identity Agent; EBS CSI removido por falta de uso. RDS pertence ao repositório do banco; Gateway continua unidade posterior separada.

CI: `terraform fmt -check`, `init -backend=false`, `validate` e `kubectl kustomize kubernetes`. Não há testes operacionais próprios; testes de negócio vivem nos repositórios das aplicações.

Provisionamento/destroy somente manuais: plan salvo → aprovação hom-approval/prd-approval → apply do mesmo artefato/commit. Nenhum apply por push ou replan após aprovação. O mantenedor deve coordenar alterações sequenciais por ambiente e gerar novo plano dos consumidores quando mudar uma dependência.

- [Workflows e operação](docs/PIPELINES_BASE.md)
- [NLB interno](docs/NLB_INTERNO.md)
- [SSM v2](docs/METADADOS_BASE.md)
- [JWT compartilhado](docs/JWT_COMPARTILHADO.md)
- [Permissões do runtime da API](docs/API_RUNTIME.md)
- [Migração e validação](docs/MIGRACAO_DECLARATIVA.md)
- [Bootstrap administrativo](bootstrap/README.md)

Implementação local preparada; a migração AWS exige revisão/aprovação dos planos. Não descartar recursos para testar esta reformulação.
