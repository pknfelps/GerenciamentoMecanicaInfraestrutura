# Gerenciamento Mecânica — Infraestrutura

Infraestrutura AWS em Terraform, manifestos Kubernetes e configuração do New Relic para o sistema de gerenciamento de oficina. **Estado em 21/10/2026:** hom implantado, validado e depois destruído pelo mantenedor. E5/E6 encerradas no escopo acordado, sem comprovação de prd, coexistência, carga, rollback ou concorrência de publicação. [Encerramento e custos](https://github.com/pknfelps/GerenciamentoMecanicaSistema/blob/develop/docs/ENCERRAMENTO_E6_E_CUSTOS_2026-10-21.md).

## Unidades e arquitetura

| Diretório | Responsabilidade |
|---|---|
| bootstrap | Backend S3, artefatos, ECR, OIDC, IAM persistente das pipelines/autenticação e metadados dos Secrets de observabilidade |
| terraform | VPC/subnets, NAT, EKS/add-ons/acessos, SGs, NLB/ASG, JWT/Pod Identity da API, identidade do Collector e catálogo SSM base v2 |
| kubernetes | Service da API, namespace database-init, SMTP4dev efêmero e Kustomizations independentes do Collector |
| gateway | REST API Regional, VPC Link V2, integrações HTTP/Lambda, access logs e catálogo SSM Gateway v2 |
| observability/newrelic | Três dashboards, cinco alertas e notificações, com estado persistente independente do destroy AWS |

O [banco](https://github.com/pknfelps/GerenciamentoMecanicaBancoDados) administra RDS/SQL/Job. A [API](https://github.com/pknfelps/GerenciamentoMecanicaSistema) administra seu Deployment/HPA/ServiceAccount. A [autenticação](https://github.com/pknfelps/GerenciamentoMecanicaServerless) usa SAM/CloudFormation e ZIP; sua role runtime é persistente no bootstrap.

Gateway público HTTPS → VPC Link → NLB interno HTTP/80 → NodePort/30080 → API/8080. A outra integração chama uma versão numérica da Lambda. API, Lambda e RDS usam rede privada; NAT atende saídas necessárias. Endpoint administrativo EKS e endpoint público Gateway têm finalidades distintas. [Diagrama completo e limites de rede](https://github.com/pknfelps/GerenciamentoMecanicaSistema/blob/develop/docs/arquitetura/diagramas/COMPONENTES.md).

Hom/develop e prd/main têm configurações separadas, uma VPC/EKS por ambiente, um nó t3.small (mínimo/desejado/máximo 1). HPA da API permite 1–3 réplicas, sem ampliar nós ou garantir alta disponibilidade. Metrics Server e Pod Identity Agent estão previstos; não há EBS CSI em uso. EKS, NLB e identidade do Collector pertencem à base, RDS ao banco, regras de saída da autenticação ao SAM.

## Ferramentas e validação local

Terraform 1.15.9; providers AWS 6.58.0 e random 3.7.2 conforme lockfiles. New Relic usa provider 3.99.3. Há versões de ferramentas adicionais fixadas nos workflows; não atualizar lockfiles apenas para revisar documentação.

```bash
terraform -chdir=bootstrap fmt -check
terraform -chdir=bootstrap init -backend=false
terraform -chdir=bootstrap validate
terraform -chdir=terraform fmt -check
terraform -chdir=terraform init -backend=false
terraform -chdir=terraform validate
terraform -chdir=gateway fmt -check
terraform -chdir=gateway init -backend=false
terraform -chdir=gateway validate
kubectl kustomize kubernetes
kubectl kustomize kubernetes/observability/hom
kubectl kustomize kubernetes/observability/prd
```

Esses comandos validam configuração; não aplicam recursos nem substituem plano AWS. Não há executável de aplicação, Dockerfile, Swagger ou Postman próprios neste repositório. Os Collectors usam imagens/layer oficiais; o contrato HTTP e as coleções pertencem aos repositórios das aplicações.

## Pipelines e operação

| Workflow | Função |
|---|---|
| ci | Validação Terraform sem backend, Kustomize e unidade New Relic sem credenciais reais |
| aws-oidc-check | Conferência manual de identidade OIDC |
| base-provision / base-destroy | Plano salvo → aprovação protegida → apply exclusivo do plano aprovado |
| gateway-provision / gateway-destroy | Mesmo fluxo, para a unidade Gateway |
| newrelic-provision | Manual, somente main, plano → aprovação → apply dos dashboards/alertas persistentes |

OIDC identifica cada execução na conta 121754142617/us-east-1. Branches e Environments separam hom/prd. Um plano obsoleto exige execução completa e nova aprovação, sem replan automático. A diferença entre este fluxo manual e o requisito original R06 está registrada, com revisão adiada pelo mantenedor; não descrever como deploy automático por push.

Provisionar bootstrap aprovado → base → banco/Job → API e autenticação → Gateway. API e autenticação precisam do banco e podem ser preparadas independentemente entre si. O Gateway deve consumir a versão numérica publicada pela autenticação. O catálogo SSM v2 fornece configuração, não sinal de prontidão; não há publicador `/api/v2/` no código entregue.

Destruir Gateway → API e autenticação → banco/email → base; email entra na cadeia quando sua função e workflow forem publicados na AE.8. API/auth verificam Gateway; banco verifica API/auth e resíduos associados; base verifica banco e email (função, ENIs e egress no SG reservado). Base/banco repetem as verificações antes do plan e do apply. Recursos ainda em exclusão e falhas de consulta bloqueiam; não há espera por ENIs, remoção automática de finalizadores ou coordenação entre execuções concorrentes. [Mapa de descarte](https://github.com/pknfelps/GerenciamentoMecanicaSistema/blob/develop/docs/DESTRUICAO_AMBIENTE.md).

base-provision aplica o Collector separadamente da Kustomization raiz, reinicia e aguarda rollout por 300 segundos. base-destroy remove o overlay do Collector antes dos demais manifestos e do Terraform. Atualizações isoladas do ConfigMap exigem restart.

## Observabilidade vigente

Collector Contrib 0.161.0 em observability, uma réplica/Recreate, requests 100m/128Mi e limits 500m/256Mi, GOMEMLIMIT 192MiB. Executa sem root, filesystem somente leitura, token Kubernetes apenas no pod para RBAC de leitura. Recebe OTLP HTTP/4318 por Service interno; isso não constitui isolamento entre pods por NetworkPolicy. Probes/13133 verificam o processo, não a entrega ao destino externo.

- Traces, métricas técnicas/de negócio/integrações e logs sanitizados da API seguem ao New Relic US. Enriquecimento Kubernetes preserva serviço/versão/ambiente.
- 23 métricas Kubernetes a cada 30 segundos: nós, pods, containers e disponibilidade. Kubeletstats acompanha somente o nó do Collector; mudança permanente de topologia exige revisão.
- 13 estatísticas CloudWatch Gateway/Lambda/RDS: período/coleta de 60 segundos, atraso de dez minutos. Logs do Gateway retomam os últimos cinco minutos a cada inicialização, sem checkpoint persistente ou deduplicação. Lacunas/duplicações são aceitas.
- A Lambda tem Collector próprio como extensão; não envia seus sinais ao Collector EKS.
- Aplicações usam propagação W3C. X-Ray nativo é independente, com integração por polling no New Relic, sem união automática entre os dois caminhos. Gateway hom solicita X-Ray; prd mantém false. Segmentos nativos não passam pela sanitização da aplicação.

A License Key de ingestão fica no Secrets Manager, lida pelo provider nativo alpha dos Collectors. Não está no código, estado Terraform, GitHub Secret, variável Lambda ou Kubernetes Secret. Pod Identity identifica o Collector; a extensão compartilha a role da Lambda. Mudanças da chave exigem reinicializar o Collector e publicar nova revisão da função.

E5 encerrada por aceite em hom: ingestão, métricas, logs, SQL, ciclo Lambda e três alertas foram conferidos conforme [evidências e dispensas](https://github.com/pknfelps/GerenciamentoMecanicaSistema/blob/develop/docs/ENCERRAMENTO_E5_2026-10-21.md). Não foram feitos disparos de CPU/memória nem carga. Não tratar limites aceitos como comprovação desses cenários.

## Dashboards e alertas persistentes

A unidade [observability/newrelic](observability/newrelic/README.md) administra os dashboards **Operação da API e Kubernetes**, **Ordens de serviço** e **Integrações e autenticação**, com filtro hom/prd. Cinco alertas: falha técnica de OS, falha de notificação, CPU sobre alocável >80%, working set sobre alocável >85% e API sem réplica disponível. Condições separadas hom/prd; ausência de sinal encerra sem comprovar recuperação. A disponibilidade inclui escala intencional para zero; manutenção exige silenciamento manual.

newrelic-provision usa Environments newrelic/newrelic-approval, User API Key e variável NEW_RELIC_ALERT_EMAIL, sem imprimir destinatário. A User API Key administra recursos e não substitui a License Key de ingestão. Backend compartilhado shared/newrelic/terraform.tfstate, locking, workspace default e proteção prevent_destroy. Os dashboards/alertas já foram publicados e conferidos; persistem após descartar o ambiente AWS. Não executar Terraform local em concorrência com a pipeline.

O encerramento preserva bootstrap, buckets/artefatos, ECR, IAM, Secrets e New Relic. O relatório de custos distingue recursos descartados de resíduos históricos e consumo estimado; ausência de workloads não significa custo futuro zero.

## Procedimentos e contratos

- [Bootstrap administrativo](bootstrap/README.md)
- [Workflows da base](docs/PIPELINES_BASE.md)
- [Gateway e contrato público](docs/GATEWAY.md)
- [NLB interno](docs/NLB_INTERNO.md)
- [Catálogo base SSM v2](docs/METADADOS_BASE.md)
- [JWT compartilhado](docs/JWT_COMPARTILHADO.md)
- [Runtime da API](docs/API_RUNTIME.md)
- [Collector e Kubernetes](docs/COLLECTOR_API.md)
- [CloudWatch](docs/CLOUDWATCH.md)
- [New Relic e rotação](docs/NEW_RELIC.md)
- [Contratos entre repositórios](https://github.com/pknfelps/GerenciamentoMecanicaSistema/blob/develop/docs/arquitetura/CONTRATOS_ENTRE_REPOSITORIOS.md)
- [Revisão documental E7](https://github.com/pknfelps/GerenciamentoMecanicaSistema/blob/develop/docs/REVISAO_DOCUMENTACAO_E7_2026-10-21.md)

O endpoint Gateway é publicado por ambiente no catálogo e resumo do provisionamento. Como o ambiente foi destruído, URLs de validações anteriores são evidências históricas, não um deploy ativo. Nenhum novo recurso foi criado para esta revisão documental.


## Extra planejado — autenticação e captura SMTP

Decisão de 22/10/2026, ainda sem implantação: SMTP4dev privado/efêmero no EKS, sem relay externo, com envio centralizado em EmailFunction invocada por API/auth. O cliente solicita/confirma o código e recebe JWT Customer; sem Authorizer ou token por OS. O repositório já renomeado GerenciamentoMecanicaServerless reunirá as funções, com dois SAM/stacks e workflows independentes/reutilizáveis. A migração inclui OIDC, rotas/permissões Gateway, catálogo de envio e novos bloqueios: email exige API/auth removidas; base exige banco e email ausentes. A ordem operacional atual só muda quando essa implementação for publicada. [Escopo de infraestrutura](docs/AUTENTICACAO_E_EMAIL_PLANEJADO.md) · [Plano AE.1–AE.10](https://github.com/pknfelps/GerenciamentoMecanicaSistema/blob/develop/docs/PLANO_EXTRA_AUTENTICACAO_E_EMAIL.md). Checklists oficiais preservados.

AE.4: [IAM do envio preparado e validado localmente](docs/AE4_IAM_EMAIL.md), com roles próprias email e consumo restrito por API/auth. [Manifestos SMTP4dev e captura efêmera validados localmente](docs/AE4_SMTP4DEV_MANIFESTOS.md), incluídos na raiz Kubernetes. [Rede privada SMTP e chaves SSM preparadas e validadas localmente](docs/AE4_REDE_SMTP.md), reutilizando NLB/ASG existentes. [Inspeção View/default e bloqueio base-destroy por email preparados e validados localmente](docs/AE4_INSPECAO_E_DESCARTE.md). Preparação local AE.4 concluída; aplicação e comprovação AWS pendentes. EmailFunction e seu workflow próprio de descarte seguem na AE.5/AE.8; nenhum plano/apply AWS nesta preparação.
