# New Relic US — API e autenticação

## Estado e propriedade

**Decisão vigente:** New Relic é permanente nos deploys da base e autenticação. Removidos os toggles de workflow e parâmetros SAM; X-Ray continua independente. A configuração local da API e dos testes não foi alterada.

Integração preparada para envio OTLP HTTP/protobuf de traces, métricas e logs para https://otlp.nr-data.net (HTTPS/443). Ingestão OTLP e X-Ray comprovadas em hom em 17/10/2026; [evidência e limites](https://github.com/pknfelps/GerenciamentoMecanicaSistema/blob/develop/docs/VALIDACAO_HOM_2026-10-17.md). Coleta/enriquecimento Kubernetes também comprovados em hom; [evidência](https://github.com/pknfelps/GerenciamentoMecanicaSistema/blob/develop/docs/VALIDACAO_KUBERNETES_HOM_2026-10-17.md). Prd não foi comprovado. API → Collector Kubernetes e Lambda → extensão local continuam independentes.

A chave é Ingest - License da conta US. Account ID não autentica o exporter e não precisa ser publicado em SSM. Os 100 GB informados pelo mantenedor são a franquia da conta, compartilhada pelo que ela recebe; não existe bloqueio automático por essa configuração. Acompanhar Data Management/consumo no New Relic antes e durante as janelas de validação. Dashboards, alertas de consumo e limites contratados devem ser conferidos na própria conta; não há garantia de custo zero na AWS.

Bootstrap administra somente os metadados de /mecanica/hom/observability/newrelic-license-key e /mecanica/prd/observability/newrelic-license-key. Secrets persistentes, criptografia padrão, recuperação de sete dias e prevent_destroy=true; sem secret_version, valor, rotação automática ou output sensível Terraform. Destroy de base/auth/banco não os remove.

## Cadastro pelo mantenedor

1. Gerar/revisar/aprovar o novo plano salvo do bootstrap e aplicar somente o plano aprovado. Não reutilizar planos antigos.
2. No console AWS da conta 121754142617, região us-east-1, abrir Secrets Manager e localizar o Secret de hom pelo nome exato acima.
3. Em Retrieve/Edit secret value, cadastrar em Plaintext apenas a License Key existente da conta New Relic US, sem JSON, aspas adicionais ou quebra de linha. Salvar uma versão AWSCURRENT. Não enviar a chave por chat nem colocá-la em arquivo versionado, argumento de workflow ou GitHub Secret.
4. Deixar prd sem versão até sua ativação deliberada. Seu primeiro provisionamento exige cadastro correspondente; pode receber uma chave própria da mesma conta.

Workflows inspecionam metadados e presença de exatamente uma versão AWSCURRENT. Isso não comprova validade da chave no New Relic; essa comprovação será feita após envio. Pipelines não leem seu valor.

## Configuração e segurança

Os dois binários fixados incluem o provider nativo secretsmanager, classificado alpha. O header api-key usa `${secretsmanager:${env:NEW_RELIC_LICENSE_KEY_SECRET}}`; a variável contém somente o NOME do Secret. O provider resolve a referência no início com credenciais temporárias e a versão atual padrão do serviço. Não acrescentar condição IAM exigindo VersionStage explícito: esse provider omite o campo na chamada.

A base cria mecanica-<ambiente>-collector-runtime, com Pod Identity do cluster do ambiente para observability/otel-collector. O ServiceAccount mantém automountServiceAccountToken=false; o pod do Collector habilita sua montagem para os receivers Kubernetes e k8sattributes, com RBAC somente leitura. O token específico Pod Identity é entregue pelo EKS e tem finalidade distinta. [Permissões e métricas](COLLECTOR_API.md). Role permite somente GetSecretValue no ARN exato do Secret do ambiente. Não concede leitura JWT/banco nem escrita de Secrets.

A role persistente auth-runtime recebe GetSecretValue somente no Secret do ambiente. Extensão e código da Lambda compartilham a role e o processo da função pode acessar esse recurso: não existe isolamento IAM entre eles. As permissões já existentes de JWT/banco não são modificadas.

ConfigMaps, ZIPs, templates, ambientes Lambda e estado/planos Terraform contêm somente nomes/referências públicas, nunca o valor da License Key. Não usar print-config, exporter detailed ou captura de headers com a chave real.

## Ativação e descarte

1. Bootstrap aplicado e chave hom cadastrada.
2. Executar base-provision (develop/hom). O Collector sempre utiliza New Relic. Preserva plan → aprovação → apply do mesmo plano; o preflight ocorre antes do plan e novamente antes do apply. O Secret e sua versão atual são pré-requisitos de toda execução de provisionamento.
3. Executar auth-publish de uma revisão nova, com layer/OpenTelemetry permanentes e o único Function/Observability/collector.yaml de produção.
4. Executar auth-provision com environment=hom, artifact_commit do summary publicado; X-Ray é permanente na Lambda. OpenTelemetry, layer e New Relic são fixos no SAM; não há inputs ou parâmetros para desligá-los. A pipeline rejeita templates antigos com telemetria condicional; publicar revisão nova.
5. Atualizar o Gateway para consumir a nova revisão/versão numérica auth. Não é necessário novo deploy da API nem reaplicar o banco apenas por essa integração.
6. Com chamadas fictícias controladas, conferir no New Relic mecanica-api/mecanica-auth, versões/ambiente hom, traces/logs correlacionados, métricas técnicas/negócio, sanitização e possíveis NrIntegrationError. Validar também chamadas isoladas e memória/tempo reais da extensão.

New Relic é o destino permanente nos dois ambientes. Não há opção de deploy diagnóstico ou desativação de telemetria na Lambda; os Collectors locais de teste continuam independentes da AWS. Não há fallback para debug quando a chave não puder ser lida. Falha de resolução impede iniciar o Collector; destino indisponível depois de iniciado tem tentativas limitadas e pode perder sinais.

O Collector da API possui somente kubernetes/observability/base e os overlays hom/prd. Um único YAML de produção na base aponta para New Relic; os overlays definem o nome público do Secret, cluster e ambiente. A pipeline exclusiva metrics/kubernetes coleta a cada 30 segundos e filtra nomes permitidos; k8sattributes enriquece os três sinais OTLP antes do batch, preservando a identidade da API. Os nomes dos recursos existentes são preservados, sem recriar namespace/Service/Deployment. O restart existente continua necessário para reler o ConfigMap e a chave; pode interromper brevemente a coleta.

Descarte continua Gateway/consumidores → auth/API → banco → base; base-destroy remove kubernetes/observability/<ambiente> pelos mesmos nomes estáveis. Os Secrets e suas versões permanecem no bootstrap. Não limpar versões ou remover a chave no New Relic como parte do destroy dos ambientes.

## Filas e falhas

Kubernetes preserva memory_limiter 128/32 MiB e batch 512/1 s; exporter gzip, timeout 3 s, fila de 100 lotes por sinal, dois consumidores, retries 1–5 s por até 15 s. Sem armazenamento persistente. Probes verificam o processo, não a entrega no New Relic.

Lambda preserva memory_limiter 64/16 MiB e usa decouple por último, fila máxima 20 por pipeline, sem batch periódico. Exporter gzip/timeout 1 s, retries 200–500 ms por até 2 s e sending_queue=false (a extensão já desabilita essa fila). O decouple é específico da extensão e evita esperar a exportação externa na resposta; o tempo faturado pode incluir o trabalho posterior. Flush de aplicação e sua reserva de resposta permanecem os atuais. Não garantir entrega exatamente uma vez ou ausência de perdas em término abrupto, saturação, falhas permanentes ou congelamento.

401 indica autenticação de ingestão inválida; 429 indica limitação; 5xx/timeout podem ser transitórios. Não imprimir chave ou payload para investigar. Falhas de exportação não participam da transação da OS nem devem alterar seu resultado HTTP.

## Rotação e validação local

Para trocar a chave: cadastrar a nova versão no console, manter AWSCURRENT e reiniciar o Collector Kubernetes; publicar/provisionar uma nova revisão numérica da Lambda e atualizar o Gateway. Alterar só o valor do Secret não atualiza processos existentes. Não revogar a chave anterior antes de comprovar os novos consumidores.

Terraform fmt/init sem backend/validate, renderização Kustomize e validação SAM/workflows continuam conferindo a estrutura dos arquivos. Por decisão do mantenedor, foram removidos os testes .NET de conexão com New Relic e Collectors locais, os receptores HTTP fictícios e os steps CI que executavam as imagens para validar o exporter/YAML. Não substituir os cenários por testes ignorados ou mocks novos.

A imagem Contrib 0.151.0 não contém decouple; a layer oficial continua usando esse processor no YAML de produção. Não há overrides de teste ou prova automatizada de transporte. Ingestão, falhas de exportação, ciclo/fila/congelamento e comportamento dos Collectors serão conferidos operacionalmente na AWS. Testes funcionais HTTP/JWT/PostgreSQL e sanitização do console permanecem; todos os testes automatizados de telemetria, incluindo InMemory, foram removidos por decisão do mantenedor.

Não acrescentados scripts, Operators, agentes, coleta stdout ou duplicação dos exporters. Somente o Compose/local de teste mantém debug, sem AWS/New Relic. Os deploys usam exclusivamente New Relic. Ingestão OTLP e X-Ray hom já comprovadas; coleta Kubernetes/enriquecimento hom comprovados em 17/10/2026. Próximas conferências: dashboards/alertas, CloudWatch, correlação W3C/X-Ray e escopos ainda não exercitados.

## X-Ray nativo → New Relic — preparação declarativa

Implementação de 15/10/2026; bootstrap aplicado, conexão mecanica-xray configurada e ingestão de 786 spans xray.polling observada na janela de validação de hom em 17/10/2026. A união dos contextos nativo/W3C continua pendente. Este caminho é independente do OTLP: o New Relic assume uma role AWS e consulta o X-Ray diretamente. Não passa pelos Collectors, não usa a License Key e não exige User API Key ou provider New Relic.

### Bootstrap e alcance do acesso

`bootstrap/newrelic-xray.tf` declara a role persistente `mecanica-newrelic-xray`, no path `/mecanica/observability/`, e a policy inline `read-regional-xray`. A confiança permite apenas `sts:AssumeRole` pela conta New Relic US `754728514883`, com `sts:ExternalId` exatamente igual a `new_relic_account_id`.

Em planos administrativos, informar manualmente `new_relic_account_id` com o **Account ID do New Relic**, como string numérica positiva, por argumento/variável Terraform local; por decisão do mantenedor, não é necessário versioná-lo. A variável é obrigatória, sem default; o exemplo contém somente um formato fictício comentado. Esse identificador não é secreto. Não alterar o backend nem reutilizar planos anteriores à nova role.

A policy concede somente `xray:Get*` e `xray:BatchGet*`, com `Resource="*"` e `aws:RequestedRegion=us-east-1`. As consultas de traces não aceitam ARN por função/Gateway nem isolamento por ambiente. A role pode ler os traces disponíveis da conta AWS 121754142617 nessa região, inclusive hom/prd quando existirem; filtros do console não são controle de acesso IAM. Não anexar ReadOnlyAccess, Budgets, permissões CloudWatch, Secrets, escrita X-Ray ou administração de outros recursos. A role pertence ao bootstrap compartilhado e permanece após destroy de Gateway, auth, banco ou base.

### Procedimento de configuração e recriação

1. Informar `new_relic_account_id`; gerar o plano salvo do bootstrap e revisar (adoção inicial já concluída). O esperado para esta entrega isolada é somente duas criações (role e policy inline), nenhuma alteração/exclusão de recursos existentes e o novo output `newrelic_xray_role_arn`. Se houver outras mudanças, revisá-las antes de aprovar.
2. Aplicar somente o binário aprovado, conferir trust/policy implantadas e obter o ARN com `terraform output -raw newrelic_xray_role_arn`. Não criar outra role manualmente.
3. No New Relic US, acessar **All capabilities → Infrastructure → AWS**, iniciar a conexão de API polling e usar o nome `mecanica-xray` e o ARN do output. O External ID será o Account ID dessa mesma conta New Relic. Usar a role personalizada existente; não seguir as opções de anexar ReadOnlyAccess ou Budgets do tutorial genérico.
4. Em **Manage services**, habilitar somente **AWS X-Ray**, limitar a `us-east-1` e manter polling em cinco minutos. Não habilitar EC2/EBS, outros serviços ou coleta adicional de tags/IPs. Não fornecer a License Key ou credenciais AWS permanentes. Se a interface ou a verificação exigir permissão além da policy aprovada, registrar o requisito e revisar antes de ampliar o acesso.
5. Para a comprovação em hom, executar `auth-provision` com tracing Active fixado no template, sem toggle e atualizar o Gateway para a nova versão numérica da função. Se for necessária publicação nova, usar `auth-publish` antes. O tfvars hom do Gateway já solicita X-Ray habilitado; mudanças de stage seguem seu plano/aprovação/apply. Prd permanece desabilitado. API e Collectors não exigem alteração por causa dessa integração.
6. Gerar chamadas controladas, com dados fictícios, incluindo sucesso e erros esperados. Conferir segmentos Gateway/Lambda, vínculos nativos e `xrayTraceId` dos access logs, além da amostragem efetiva. Não presumir que toda chamada foi amostrada e não adicionar regras próprias nesta entrega.
7. Aguardar a consulta da integração e executar no New Relic:

```sql
SELECT count(*)
FROM Span
WHERE newRelic.ingestPoint = 'xray.polling'
SINCE 30 minutes ago
```

Conferir serviço/região, IDs dos traces, horários e atraso observado com os segmentos AWS. O polling padrão é de cinco minutos e a primeira ingestão pode levar até vinte minutos. São coletados traces concluídos; spans com mais de vinte minutos são descartados. Não usar esse caminho para alertas imediatos nem configurar polling superior a cinco minutos.

### Critérios, falhas e pendências

- Conferir ausência de acesso com ExternalId ausente/incorreto ou principal diferente, usando revisão da trust e, posteriormente, as verificações autorizadas da integração. Não enfraquecer a confiança para contornar uma falha de conexão.
- Conferir que a policy permite leitura X-Ray em us-east-1 e não permite outra região, escrita X-Ray ou leitura de Secrets. Access Analyzer/simulação IAM ficarão para a etapa AWS autorizada; não criar scripts de teste.
- Segmentos nativos AWS não passam pela sanitização da API/Lambda e podem conter URL/IP. Inspecionar amostras fictícias antes de registrar a comprovação; não despejar documentos completos de traces em logs ou relatórios.
- O marcador `newRelic.ingestPoint='xray.polling'` distingue este caminho do OTLP. A habilitação não adiciona exporter X-Ray aos Collectors nem duplica o envio OTLP existente. A união dos dois contextos e a análise de possíveis sobreposições permanecem pendentes.
- Falha na integração não altera o fluxo de negócio nem o envio OTLP. Em ausência de spans, conferir conexão, região, permissão, tracing/amostragem nativa e janela de polling; não habilitar outros serviços nem imprimir credenciais como diagnóstico.

**Estado atual:** ingestão e amostra de segmentos nativos comprovadas em hom; conteúdo inclui URL/IP e não recebe a sanitização OTLP. E5.3/E5.14 continuam parciais nos escopos restantes, incluindo correlação W3C/X-Ray e prd; receiver CloudWatch, dashboards e alertas ficam separados. A coleta Kubernetes já foi implantada/conferida em hom em 17/10/2026; prd e falhas/carga seguem pendentes. A instrumentação atual continua W3C e mantém extração X-Ray desabilitada. Não executar destroy como teste.

Referências oficiais: [conexão AWS por polling](https://docs.newrelic.com/docs/infrastructure/amazon-integrations/connect/set-up-aws-api-polling/), [integração X-Ray](https://docs.newrelic.com/docs/infrastructure/amazon-integrations/aws-integrations-list/aws-x-ray-monitoring-integration/) e [ações/recursos IAM X-Ray](https://docs.aws.amazon.com/service-authorization/latest/reference/list_xray.html).

Validação local concluída: Terraform 1.15.9/AWS 6.58.0, fmt -check, init -backend=false com provider em cache e validate aprovados. JSON gerado pelo terraform console revisado com Account ID fictício 1234567: trust 220 e policy 208 caracteres. Inputs vazio, zero, negativo e não numérico produziram o diagnóstico esperado de validação; valor positivo aceito. Console pode retornar código zero mesmo emitindo esse diagnóstico, por isso a conferência considerou a mensagem nativa. Evidências locais em artifacts/e5-xray-newrelic/validation.json e policies-fictitious-account.json; nenhum teste operacional/script novo, chamada AWS, plano ou apply.

## Coleta CloudWatch — preparada localmente em 18/10/2026

O Collector EKS envia logs de acesso do Gateway (mensagem fixa e campos técnicos) e 13 gauges de Gateway/Lambda/RDS ao mesmo exporter New Relic. Não há integração AWS adicional por polling no console, nova chave, alteração da Lambda ou recoleta de logs de aplicação. X-Ray continua independente.

A role do Collector recebe somente FilterLogEvents no grupo do ambiente e GetMetricData regional; o bootstrap permanece igual. Após PRs, executar somente base-provision e seguir as [consultas NRQL e critérios de validação CloudWatch](CLOUDWATCH.md). Coleta e ingestão reais ainda pendentes. Cada restart relê cinco minutos de logs; métricas têm atraso de dez minutos, sem backfill. Confirmar última coleta antes do destroy do Gateway, que remove o grupo de logs.

## Dashboard de operação persistente — 18/10/2026

Definição JSON versionada e unidade Terraform local em [observability/newrelic](../observability/newrelic/README.md), fora dos workflows/destroys AWS. Vinte painéis de consulta e dois textos, ambiente hom/prd de seleção única e padrão hom; consultas HTTP e 23 métricas Kubernetes existentes. Sem dashboards de OS/integrações, alertas ou alterações de instrumentação nesta entrega.

Usa uma User API Key autorizada a administrar dashboards, fornecida por NEW_RELIC_API_KEY no processo local; não reutilizar a Ingest - License dos Collectors. Account ID não é secreto. Estado remoto compartilhado e persistente, outputs somente GUID/permalink e prevent_destroy; mudanças por PR/plano salvo. Documentados os comandos de init, plan, apply posterior e verificação de ausência de drift.

Preparação e consultas históricas hom/prd validadas; prd sem dados não é validação operacional. O dashboard ainda não foi criado: backend autenticado, plano remoto/aprovação, apply e layout visual permanecem pendentes. Não é necessário novo deploy da API ou infraestrutura para publicar o dashboard. A leitura histórica não elimina as ressalvas de cobertura dos access logs ou de representação diferente dos IDs xray.polling/OTLP.

## Dashboard persistente de ordens de serviço — 18/10/2026

A mesma [unidade Terraform local](../observability/newrelic/README.md#ordens-de-serviço--painéis-e-semântica) define **Mecânica — Ordens de serviço**, fonte `dashboards/orders.json.tftpl`, 15 consultas/dois textos. Reutiliza backend/provider/credencial e proteção de operação; não cria workflow ou estado paralelo. Outputs novos somente GUID/permalink de ordens. Cada dashboard tem seleção única hom/prd, padrão hom.

Volume confirmado no período e por dia America/Sao_Paulo; médias de diagnóstico, execução, espera pela entrega separada por conclusão/recusa e serviço completo, em minutos e com amostras concluídas. Falhas técnicas de OS por operação separadas de falhas de medição após commit. Sem estoque de OSs abertas, dados pessoais, notificações ou indicadores de integrações. Média ponderada pelas amostras, não média das médias dos pods; total do serviço não espera entrega nem inclui recusa.

Consultas históricas hom/prd conferidas na janela 18/10/2026 00:22:30–00:49:40 UTC: três criações no dia local 17/10; 2/1/2/1 amostras de diagnóstico/execução/entrega/serviço, coerentes com SQL salvo. Prd sem séries e ausência de falhas não comprovam esses cenários. SQL é exato por ocorrência; métricas possuem janelas, perdas possíveis e ausência de backfill. Sem amostras não equivale a duração zero ou saúde.

Definição/consultas validadas; **não publicado**. Plano remoto/aprovação/apply e conferência visual posteriores. Se a unidade ainda não tiver sido publicada, esperar duas criações (operação e OS); se operação já existir, somente ordens, sem alteração em operação. Não é necessário subir o ambiente para publicar ou conferir dados retidos. Não houve apply AWS/New Relic nem mudanças nas aplicações/Collectors nesta entrega. Integrações, alertas e pendências de correlação permanecem separados.

## Dashboard persistente de integrações e autenticação — 18/10/2026

**Mecânica — Integrações e autenticação**: `dashboards/integrations.json.tftpl` e recurso Terraform integrations na [unidade persistente](../observability/newrelic/README.md#integrações-e-autenticação--painéis-e-semântica), com 24 consultas/dois textos. Mantém seleção única hom/prd (padrão hom), PUBLIC_READ_ONLY, prevent_destroy, backend/provider/credenciais existentes. Outputs novos somente GUID/permalink; nenhum workflow ou estado paralelo.

Usa somente sinais existentes: invocações/categorias/latências/falhas técnicas da Lambda, POST/Authentication da API, 13 métricas CloudWatch Gateway/Lambda/RDS, notificações por tipo/modo e tabelas de logs técnicos de falha (até 100 registros). Não exibe corpo bruto/credenciais/dados de clientes ou segmentos X-Ray. Notificação simulated não é entrega; HTTP 500 tratado não equivale a AWS/Lambda Errors. 400/401 esperados não entram na taxa técnica. PostgreSQL/SSM/Secrets Manager ainda não têm contadores completos por tentativa/falha; RDS CPU/conexões não os substituem.

Período recomendado 60 minutos, considerando atraso CloudWatch de dez minutos. Cada ponto AWS mostra última estatística de 60 s, concorrência mostra maior Maximum; não são totais/médias ponderadas do intervalo. Percentis vazios retornavam zero nativo: consultas corrigidas e conferidas para manter nulo sem amostras. Logs são diagnóstico parcial (referência 19/28 request IDs), sem derivar taxas ou afirmar união automática X-Ray/OTLP.

Consultas históricas: 24 hom e 24 prd executadas. Na janela 15:40–16:10 UTC, autenticação com 8 invocações e login interno com 11, sem 5xx/falhas técnicas. As 13 estatísticas CloudWatch de 15:47–15:48 coincidiram com o snapshot documentado. Notificações 00:22:30–00:49:40: 11 tentativas simuladas concluídas, 9 status_changed/2 budget_available. Prd e falhas não ocorridas seguem sem comprovação operacional. Não houve tráfego, login/leitura de credencial AWS ou operações remotas de publicação.

Terraform/JSON/consultas preparados, **não publicado**. E5.8 preparada no escopo disponível, com lacunas explícitas; plano salvo/revisão/apply, conferência visual e tráfego novo posteriores. Se nenhum dashboard tiver sido publicado, plano esperado cria três; preservar os que já existirem sem alterações. Alertas e instrumentação adicional permanecem separados.

## Publicação dos dashboards por workflow — decisão de 18/10/2026

O caminho padrão passa a ser **newrelic-provision**, manual e somente main, na [unidade persistente](../observability/newrelic/README.md#publicação-padrão-pelo-github-actions). Sem input hom/prd, três dashboards com filtro próprio, plan → approval → apply do plano salvo; nenhuma relação com os destroys AWS. Role nova do bootstrap somente para estado/lock S3; User API Key em Secret do Environment newrelic (separada da License Key dos Collectors). Account ID 8626152 é variável não secreta, capturada no plan para todo o fluxo.

Antes da primeira execução, aplicar somente o plano salvo do bootstrap posteriormente aprovado; criar/proteger newrelic (main, variáveis AWS_NEW_RELIC_ROLE_ARN/NEW_RELIC_ACCOUNT_ID e Secret NEW_RELIC_API_KEY) e newrelic-approval (main, reviewer pknfelps, autorrevisão permitida, sem credenciais); publicar na main pelo fluxo de PR. Não deixar o primeiro dispatch criar Environments desprotegidos. O bootstrap permanece administrativo/manual; não é aplicado por este workflow.

Plan/apply usam o mesmo SHA e artefato por ID da execução, retido sete dias. Aprovação sem OIDC/Secret; chave real só em plan/apply/conferência Terraform. Resumo expõe somente commit/Account ID/GUIDs/links. Após apply, plan de conferência sem aplicação: diferença ou erro falha, sem segundo apply/rollback. Plano obsoleto/artefato indisponível exige novo fluxo completo e nova aprovação. CI de PR usa apenas placeholder não secreto, sem OIDC/chave real ou consultas remotas; renderiza os três JSONs pelo Terraform.

Actionlint/ShellCheck, Terraform bootstrap/New Relic, renderização offline Bash e revisão JSON/policies aprovados localmente. Environments, credenciais, bootstrap apply, publicação e layout visual permanecem pendentes. Não houve autenticação/alteração AWS, New Relic ou GitHub durante a implementação. Operação local alternativa permanece documentada, com o mesmo backend e sem paralelismo com a pipeline. Registros anteriores da publicação exclusivamente local são históricos; não exigem duplicar recursos/estado.

## Alerta de falha técnica de OS — 19/10/2026

Preparado na unidade persistente `observability/newrelic`, sem publicar ou enviar e-mail nesta entrega. [Configuração, avaliação e runbook](../observability/newrelic/README.md#alerta-de-processamento-de-os).

- Uma policy PER_CONDITION, duas condições habilitadas e isoladas por hom/prd: soma de `mecanica.orders.processing.failures` da API >= 1 em janela de 300 s, event_timer de 60 s, AT_LEAST_ONCE, sem lacunas preenchidas. Não depende de logs, spans ou taxas gerais HTTP.
- Depois de 600 s sem pontos, encerrar incidentes existentes sem abrir incidente por ausência. Encerramento por silêncio não comprova recuperação; o limite máximo obrigatório de incidente é 30 dias. Não criar alertas de notificação/CPU/memória/réplicas nesta entrega.
- Destino reutilizável EMAIL, canal IINT e workflow New Relic restrito à policy, somente abertura/encerramento e respeitando silenciamento. Mensagens incluem ambiente/condição, links de incidente/dashboard e interpretação do encerramento, sem dados de clientes ou conteúdo de exceções.
- O mantenedor cadastra o destinatário escolhido em `NEW_RELIC_ALERT_EMAIL`, variável do Environment `newrelic`; Terraform recebe `new_relic_alert_email` obrigatória/sensível. Não versionar endereço pessoal. A marca sensível oculta o plano textual, mas plano binário e estado ainda contêm o valor e devem ser protegidos.
- Reutilizar `newrelic-provision`: plan → aprovação → apply exclusivamente salvo; conferência posterior sem aplicação. Resumo com IDs da policy/condições, sem destinatário. Esperar seis recursos novos, preservando os três dashboards e AWS. A chave existente precisa permitir administração de alertas/notificações; falha de acesso interrompe o fluxo, sem ampliação automática.

Validação local: Terraform fmt/init sem backend/validate, três templates renderizados, grafo de dependências e actionlint/ShellCheck. Sem chave real, consulta remota, plano remoto ou tráfego induzido. Publicação e confirmação do destinatário, se exigida, ficam para o mantenedor. Demonstração de HTTP 500 → métrica → incidente → e-mail e encerramento ocorrerá posteriormente em hom, sob autorização; E5.5 permanece parcial. Não subir a infraestrutura apenas para publicar essa configuração.

## Alerta de falha de notificação de OS — 19/10/2026

Segundo alerta preparado na unidade persistente, com [consulta, regras e procedimento](../observability/newrelic/README.md#alerta-de-notificação-de-os). Policy PER_CONDITION exclusiva e condições hom/prd somam `mecanica.orders.notifications` somente com outcome=failure, tipos budget_available/status_changed e modos smtp/simulated, para service.name=mecanica-api e ambiente exato. Todas as versões/réplicas participam; sem FACET, logs/spans ou taxa HTTP como fonte.

Critical >=1 em 300 s, event_timer 60 s, AT_LEAST_ONCE, sem preenchimento. Expiração de 600 s encerra incidentes, sem abrir por ausência; limite máximo nativo de 30 dias. Silêncio/encerramento não comprovam recuperação, reenvio ou entrega. A falha pode estar nas consultas, montagem ou envio; em hom/prd o adaptador é simulado e a falha tratada não desfaz a operação persistida.

Reutiliza o destino de e-mail existente e NEW_RELIC_ALERT_EMAIL, cujo cadastro foi confirmado pelo mantenedor. Canal EMAIL/IINT e workflow New Relic próprios filtram o ID exato da nova policy, respeitam muting e avisam apenas ACTIVATED/CLOSED. Mensagem com ambiente/condição/estado, incidente e dashboard Integrações e autenticação; sem dados sensíveis. Outputs e resumo do newrelic-provision incluem os IDs, sem imprimir destinatário. Plano salvo/aprovação/apply e conferência sem segundo apply preservados.

Cinco novos recursos desta entrega; onze esperados somando o primeiro alerta ainda não publicado. **PR/publicação somente após concluir os cinco alertas previstos**, conforme decisão do mantenedor. Dashboards existentes não devem mudar. Esta etapa não configura outros alertas, publica, provoca falhas ou envia mensagens. Conferência local não comprova roteamento/entrega; posteriormente, sob autorização em hom, conferir falha do fluxo → métrica → incidente → e-mail New Relic → encerramento por ausência, sem confundir esse e-mail com entrega de negócio pela API. Investigação usa tipo/modo, período, logs sanitizados e traces disponíveis; não há recuperação automática. E5 permanece parcial.

Validação local concluída: fmt/init sem backend/validate, grafo Terraform, renderização dos três dashboards e actionlint/ShellCheck aprovados; primeiro alerta, templates, provider/lockfile/backend e CI preservados por checksum. Também conferido validate sem valores TF_VAR como no CI. Evidências locais em artifacts/newrelic-notification-alert/ na API. Sem chave real, plano remoto, consulta de dados ou publicação.

## Alerta de CPU elevada do nó — 19/10/2026

Terceiro alerta na unidade persistente, com [consulta, avaliação e procedimento](../observability/newrelic/README.md#alerta-de-cpu-elevada-do-nó). Condições hom/prd habilitadas filtram ambiente e cluster exatos; cada nó é uma faceta k8s.node.name, com incidentes PER_CONDITION_AND_TARGET. Percentual = 100 * CPU média utilizada / CPU alocável mais recente da mesma janela, pelas métricas existentes. Não usar capacidade total, requests/limits, CPU da API/RDS, denominador fixo ou soma de nós. O valor pode superar 100%; ausência de uso/alocável não vira zero ou capacidade antiga.

Critical above 80, janela de 60 s, event_flow/atraso 60 s, threshold_duration=300/ALL e sem janela deslizante. Exige médias de um minuto acima de 80% por cinco minutos consecutivos, não um pico nem média única de cinco minutos; exatamente 80% não viola. Nenhum preenchimento de lacunas; expiração de 600 s encerra sem abrir por ausência, limite máximo nativo de 30 dias. Silêncio/encerramento não comprovam recuperação. Cobertura continua limitada ao nó em que kubeletstats executa; sem alterações no Collector ou topologia.

Canal EMAIL/IINT e workflow New Relic próprios reutilizam destino/NEW_RELIC_ALERT_EMAIL, filtram exclusivamente a policy e respeitam muting, notificando ACTIVATED/CLOSED. Links para incidente e dashboard Operação da API e Kubernetes; identificar nó pela faceta e comparar CPU utilizada/alocável, pods e containers na mesma janela. Outputs/resumo incluem IDs da policy e condições, sem destinatário. Plano salvo/aprovação/apply e conferência sem reaplicação preservados.

Cinco recursos novos, dezesseis esperados somando os três alertas ainda não publicados. PR/publicação somente depois de preparar os cinco; não implementar memória/disponibilidade nesta entrega. Validação local não comprova disparo/entrega; depois da publicação conjunta, conferir condições/roteamento/plano sem diferenças e comparar amostras reais em hom. Carga/disparo/recebimento somente em etapa autorizada própria. Nenhuma operação AWS/New Relic ou mensagem de teste nesta implementação; E5 parcial.

Validação local aprovada: fmt/init sem backend/validate, grafo Terraform, validate no modo do CI sem valores TF_VAR, renderização dos três JSONs e actionlint/ShellCheck. Revisão estrutural confirmou operador above 80, ALL por 300 s, agregação de 60 s por nó, filtros hom/prd e ausência de preenchimento. Dois alertas anteriores, dashboards, Collector, provider/lockfile/backend e CI preservados por SHA-256 (26 arquivos). Evidências locais em artifacts/newrelic-node-cpu-alert/ na API; sem chave real, plano remoto ou publicação.

## Alerta de memória elevada do nó — 19/10/2026

Quarto alerta preparado na unidade persistente; [consulta, avaliação e procedimento](../observability/newrelic/README.md#alerta-de-memória-elevada-do-nó). Policy PER_CONDITION_AND_TARGET e condições hom/prd habilitadas calculam por FACET k8s.node.name: 100 * working set médio / memória alocável mais recente da mesma janela, usando bytes e filtros de ambiente/cluster exatos. Memória alocável é a referência escolhida, não capacidade física total. Não usar memória .NET, soma de pods, requests/limits, alocável menos disponível, denominador fixo ou valor antigo. Não limitar acima de 100%; ausências não viram zero/saúde.

Critical above 85; janelas de 60 s/event_flow/atraso 60 s, ALL por 300 s, sem janela deslizante. Cinco minutos consecutivos com médias acima de 85%; exatamente 85% e pico isolado não bastam. Sem preenchimento de lacunas; expiração 600 s encerra sem abrir por ausência, limite máximo 30 dias. Encerramento não comprova recuperação. Kubeletstats continua cobrindo somente o nó onde o Collector executa, sem ampliar coleta/topologia.

Canal EMAIL/IINT/workflow New Relic próprios reutilizam destino e NEW_RELIC_ALERT_EMAIL, filtram o ID da nova policy, respeitam muting e notificam ACTIVATED/CLOSED. E-mail aponta ao incidente e ao dashboard Operação da API e Kubernetes; conferir working set/alocável, pods/containers, reinícios e MemoryPressure do nó e período. Percentual alto não comprova OOM ou MemoryPressure. Outputs/resumo incluem IDs sem destinatário; plano salvo/aprovação/apply e conferência posterior preservados.

Cinco recursos novos; vinte e um previstos com os quatro alertas ainda não publicados. Concluir o quinto antes do PR/publicação conjunta. Sem novos inputs, variáveis, workflow GitHub, ação automática ou alerta de disponibilidade nesta entrega. Validar localmente sem credenciais reais e preservar alertas/dashboards/Collector existentes. Posteriormente conferir condições/facetas/roteamento, plano sem diferenças e valores reais em hom; disparo/recebimento em etapa autorizada própria, sem pressão de memória durante a implementação. Nenhuma publicação, e-mail ou operação AWS; E5 parcial.

Validações locais aprovadas: fmt/init sem backend/validate/grafo, validate no modo do CI sem valores TF_VAR, renderização dos três JSONs e actionlint/ShellCheck. Revisão estrutural confirma above 85, ALL/300 s, janela 60 s por nó, filtros hom/prd e ausência de preenchimento. Três alertas anteriores, dashboards, Collector, provider/lockfile/backend e CI preservados por SHA-256 (27 arquivos). Evidências em artifacts/newrelic-node-memory-alert/ na API; sem chave real, plano remoto, tráfego ou publicação.
