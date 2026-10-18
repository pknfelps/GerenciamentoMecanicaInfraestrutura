# Gerenciamento Mecanica — Infraestrutura

AWS deste repositório em Terraform; Service e namespace em manifestos Kubernetes próprios. Auth usa SAM/CloudFormation com ZIP ([ADR 009](https://github.com/pknfelps/GerenciamentoMecanicaSistema/blob/develop/docs/arquitetura/adrs/009-SAM-AUTENTICACAO.md)), template/workflows implantados e fluxo validado em hom. Bootstrap/base/banco/Gateway permanecem Terraform, incluindo IAM runtime/CI persistentes. Sem wrappers/publicadores/controller. [Decisão](https://github.com/pknfelps/GerenciamentoMecanicaSistema/blob/develop/docs/arquitetura/adrs/008-INFRAESTRUTURA-DECLARATIVA.md).

| Unidade | Conteúdo |
|---|---|
| bootstrap | S3 estado/artefatos, ECR, OIDC, role/policy persistente auth-runtime e permissões das pipelines |
| terraform | VPC/subnets/NAT/EKS, add-ons, acessos, SGs, NLB/ASG, JWT/Pod Identity da API e SSM v2 |
| kubernetes | Service NodePort e namespace database-init; Collector New Relic e coleta Kubernetes em Kustomization independente |
| gateway | REST API Regional, VPC Link V2, integrações API/Lambda, logs e SSM próprios |
| observability/newrelic | Dashboard persistente de operação, JSON versionado/Terraform local; independente dos destroys AWS |

Hom/develop e prd/main: uma VPC/EKS independente, um nó t3.small 1/1/1. Metrics Server e Pod Identity Agent; EBS CSI removido por falta de uso. RDS pertence ao repositório do banco; Gateway tem unidade e workflows separados; implantação e validação HTTP comprovadas em hom em 17/10/2026; prd não validado.

CI: `terraform fmt -check`, `init -backend=false`, `validate`, renderização das Kustomizations da base/Collector. Não executa testes de Collectors ou conexão New Relic. Não há testes operacionais próprios; testes de negócio vivem nos repositórios das aplicações.

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

## Collector da API e Kubernetes — E5

Collector Kubernetes administrado pela infraestrutura em kubernetes/observability/base, com overlays hom/prd. base-provision sempre aplica o overlay do ambiente, reinicia e aguarda rollout; base-destroy remove o mesmo overlay antes do EKS. O destino de produção é sempre New Relic; credencial no Secrets Manager e bootstrap aplicado são pré-requisitos. A API envia ao endpoint OTLP interno e mantém sua ativação no manifesto (hom habilitado; prd ainda conforme sua configuração versionada). Não há chave New Relic na aplicação.

Métricas de nós/pods/containers e disponibilidade, enriquecimento Kubernetes e RBAC somente leitura implantados e comprovados em hom em 17/10/2026: 23 métricas no New Relic, comparação com kubectl top/estado e sinais da API enriquecidos sem alterar serviço/versão/correlação. Collector Ready, zero reinícios, cerca de 2m CPU/55–56 MiB. Coleta a cada 30 segundos, TLS verificado e cobertura kubelet de um nó. E5.4/E5.12 comprovadas em hom; prd/carga continuam pendentes. [Métricas, permissões, NRQL e conferência](docs/COLLECTOR_API.md).

## X-Ray nativo — E5

O [Gateway](docs/GATEWAY.md) mantém `xray_tracing_enabled=false` como padrão Terraform; o tfvars hom define true para a validação AWS e prd continua false; seus logs de acesso incluem somente o identificador técnico adicional xrayTraceId. O [bootstrap](bootstrap/README.md) prepara escrita X-Ray regional para as roles runtime auth e leitura da versão exata da layer Collector pelas pipelines auth. Service-linked role Gateway e permissões CI/Secrets são preservadas. Controles independentes do OpenTelemetry. Permissões aplicadas e ingestão nativa em hom comprovada em 17/10/2026. A correlação W3C/X-Ray continua pendente; segmentos nativos podem conter URL/IP.

## New Relic US — ingestão hom comprovada

Os três sinais são enviados por OTLP com leitura nativa de Secret persistente. Não há toggle de destino nos workflows. Bootstrap/IAM e cadastro manual da chave de cada ambiente são pré-requisitos; a pipeline só inspeciona metadados. [Cadastro, sequência, rotação, testes e limites](docs/NEW_RELIC.md). Ingestão OTLP API/auth, versão da API pelo SHA e indicadores de negócio conferidos em hom; prd permanece pendente.

A integração nativa **X-Ray → New Relic** também está aplicada pelo bootstrap: role de leitura persistente, confiança na conta New Relic US com ExternalId obrigatório e restrição regional. Conexão manual mecanica-xray validada em hom, somente X-Ray/us-east-1. Não usa License Key/Collectors nem comprova correlação W3C. [Procedimento](docs/NEW_RELIC.md#x-ray-nativo--new-relic--preparação-declarativa).

## Bloqueios de destroy — 17/10/2026

base-destroy verifica somente o banco antes do plan e novamente antes de remover qualquer manifesto ou aplicar o plano salvo. RDS em deleting, DB subnet group ou SG do banco bloqueiam imediatamente. API/auth são verificadas pelo database-destroy; Gateway é verificado pelos destroys de API/auth. Falhas de consulta bloqueiam. Gateway destroy permanece inalterado.

O bootstrap prepara policies gerenciadas de inspeção para base/API/auth/banco hom/prd e a autorização da base para associar AmazonEKSViewPolicy à pipeline do banco somente em default. A base declara essa associação separada do acesso Edit em database-init. Aplicar bootstrap e base antes de usar os workflows novos. [Procedimento](docs/PIPELINES_BASE.md). Sem aplicação AWS nesta implementação.

## Coleta CloudWatch — E5

Preparada e validada localmente em 18/10/2026: logs de acesso do Gateway e 13 métricas essenciais Gateway/Lambda/RDS pelo Collector existente. Retomada dos últimos cinco minutos em cada inicialização, sem persistência ou deduplicação; consultas de métricas a cada minuto, com atraso de dez minutos. Terraform da base administra somente a policy adicional de leitura da role do Collector e sua descrição. Workflows/bootstrap/API/Lambda preservados. Após PRs, executar somente base-provision e conferir ingestão em hom; E5.14 permanece parcial. [Configuração, IAM, recuperação, NRQL e descarte](docs/CLOUDWATCH.md).

## Dashboard de operação como código — E5

Unidade independente em [observability/newrelic](observability/newrelic/README.md): um dashboard API/Kubernetes, JSON com 20 consultas e dois blocos explicativos, filtro hom/prd (padrão hom), provider New Relic 3.99.3 e estado S3 shared/newrelic/terraform.tfstate. Não participa de base-provision/base-destroy nem cria workflow. Usa User API Key apenas no ambiente do processo; a License Key de ingestão permanece exclusiva dos Collectors.

Definição e consultas históricas validadas em 18/10/2026; publicação ainda não realizada. Plano remoto/aplicação exigem autorização posterior, sem necessidade de subir API/EKS para consultar o histórico retido. Estado/dashboard persistem nos descartes AWS; prevent_destroy habilitado. Dashboards de OS/integrações e alertas ficam para próximas entregas.
