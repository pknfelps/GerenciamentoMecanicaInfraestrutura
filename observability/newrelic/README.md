# Dashboards e alertas persistentes — New Relic

Unidade Terraform independente da base, Gateway e bootstrap. Define **Mecânica — Operação da API e Kubernetes**, uma página com 20 painéis de consulta e dois blocos de orientação. Fonte: `dashboards/operations.json.tftpl`; recurso `newrelic_one_dashboard_json.operations`. Acrescenta **Mecânica — Ordens de serviço**, uma página com 15 consultas e dois blocos de orientação, em `dashboards/orders.json.tftpl`/`newrelic_one_dashboard_json.orders`. Acrescenta **Mecânica — Integrações e autenticação**, uma página com 24 consultas/dois textos, em `dashboards/integrations.json.tftpl`/`newrelic_one_dashboard_json.integrations`. Cada dashboard tem seu próprio filtro hom/prd.

**Estado da entrega:** os três dashboards foram publicados e conferidos; a correção de facetas Kubernetes foi publicada pela [execução 39303143995](https://github.com/pknfelps/GerenciamentoMecanicaInfraestrutura/actions/runs/39303143995), com conferência posterior sem diferenças. Em 19/10/2026, os cinco alertas previstos foram preparados em Terraform, com condições hom/prd: falha técnica de processamento de OS, falha de notificação de OS, CPU elevada do nó, memória elevada do nó e API sem réplica disponível. CPU e memória usam referências alocáveis, acima de 80%/85% por cinco minutos; disponibilidade usa zero réplicas por dois minutos. O mantenedor confirmou o cadastro de NEW_RELIC_ALERT_EMAIL. Os cinco alertas estão definidos localmente; o mantenedor poderá publicar o PR e executar o workflow com revisão/aprovação do plano salvo. Nenhum alerta foi publicado nesta implementação; disparo e recebimento reais continuam pendentes. Os registros históricos abaixo preservam as evidências de preparação e não substituem este estado atual.

## Identidade, propriedade e estado

- Terraform `~> 1.15.0` (validação com 1.15.9); provider `newrelic/newrelic 3.99.3`, lockfile Windows/Linux.
- Região New Relic `US`; `new_relic_account_id` obrigatório e positivo. `terraform.tfvars.example` contém o Account ID não secreto 8626152.
- Variável do dashboard `environment`: lista hom/prd, seleção única, padrão hom. É filtro de visualização; não fornece isolamento de acesso. Não excluir o filtro ao comparar ambientes.
- Permissão `PUBLIC_READ_ONLY`: leitura pelos usuários autorizados da conta; edição pelo proprietário. Não configura acesso público pela internet, links públicos ou compartilhamento externo.
- Backend S3 existente `mecanica-tfstate-121754142617-us-east-1`, chave `shared/newrelic/terraform.tfstate`, região us-east-1, criptografia e lockfile nativo. Somente workspace default. Nenhuma leitura de estados externos.
- Os três dashboards têm `prevent_destroy=true`. Os destroys AWS não alcançam esta unidade. Não executar destroy, remover proteção ou apagar o objeto de estado como parte do descarte de hom/prd.
- Todos os mantenedores usam o mesmo backend/Account ID. Não inicializar estados locais paralelos para publicar cópias. Outputs contêm GUID/permalink dos dashboards e IDs das policies/condições dos cinco alertas; não expõem o destinatário.
- Mudanças seguem PR e plano salvo. Edição manual no console causa divergência; refletir a mudança no template ou revisar o próximo plano antes de aplicar. Não importar exports com GUIDs/IDs de páginas/widgets como fonte de uma criação nova.

## Credenciais

A **User API Key** administra os recursos desta unidade (dashboards, policy/condições e notificações) e é diferente da **Ingest - License Key**, usada pelos Collectors para enviar telemetria. Esta unidade não lê o Secret de ingestão nem modifica IAM/Secrets Manager.

O mantenedor deve obter uma User API Key de um usuário autorizado a criar/atualizar dashboards, alertas e componentes de notificação na conta escolhida. Cadastrar no GitHub como Secret `NEW_RELIC_API_KEY` do Environment `newrelic`; em operação local alternativa, fornecer somente ao processo por essa variável. Não enviar a chave no chat, versionar, colocar em tfvars/backend, usar `-var`, imprimir o ambiente ou ativar `TF_LOG` durante operações autenticadas.

A autenticação AWS é usada somente pelo backend S3, com a cadeia padrão de credenciais local e acesso ao objeto de estado/lock. Não há provider AWS nesta unidade. O workflow usa a role dedicada `mecanica-newrelic-github`, declarada no bootstrap, exclusivamente para estado/lock; a alternativa local usa a identidade autorizada do mantenedor. Se o perfil escolhido não tiver acesso, interromper e revisar a identidade; não alterar policies automaticamente.

## Validação local sem autenticação

Executar dentro de `observability/newrelic`:

```powershell
terraform fmt -check
terraform init -backend=false -input=false -lockfile=readonly
```

O schema do provider exige a presença de `NEW_RELIC_API_KEY` até para `terraform validate`. Na validação offline, um placeholder não secreto basta; isso não testa credenciais, NRQL, backend ou criação no New Relic. Usar um processo sem chave real configurada:

```powershell
$env:NEW_RELIC_API_KEY = 'local-validation-only-not-a-real-key'
try {
    terraform validate -no-color
} finally {
    Remove-Item Env:NEW_RELIC_API_KEY
}
```

Para renderizar o template sem backend/provider, abrir `terraform console` em uma pasta vazia de artefatos e avaliar, usando o caminho absoluto do checkout:

```hcl
jsondecode(templatefile("C:/caminho/GerenciamentoMecanicaInfraestrutura/observability/newrelic/dashboards/operations.json.tftpl", { account_id = 8626152 }))
```

A renderização resolve somente o Account ID; `{{environment}}` permanece para substituição nativa pelo New Relic. Não criar scripts para gerar/publicar o JSON. Ao alterar a versão do provider, regenerar o lockfile com `terraform providers lock -platform=windows_amd64 -platform=linux_amd64` e revisar seus checksums.

## Publicação padrão pelo GitHub Actions

Workflow [.github/workflows/newrelic-provision.yml](../../.github/workflows/newrelic-provision.yml), somente `workflow_dispatch` na **main**, sem input hom/prd. Os três dashboards são compartilhados e possuem seus filtros de ambiente. A fila `newrelic-dashboards`, sem cancelamento em andamento, coordena as execuções deste workflow; não coordena comandos locais. Não executar Terraform local em paralelo; o lock S3 continua ativo.

### Preparação obrigatória antes da primeira execução

1. Revisar/aprovar e aplicar o plano salvo adicional do bootstrap. Esperado: role `mecanica-newrelic-github`, policy `newrelic-state-access` e output `newrelic_pipeline_role_arn`; outros diffs exigem revisão própria. Não usar este workflow para aplicar o bootstrap.
2. Criar os Environments **antes de disparar**: referenciar Environment inexistente pode criá-lo sem a proteção desejada.
3. Publicar o workflow na main pelo fluxo normal de PR; develop passa pelo CI, mas não publica dashboards.

| Environment | Configuração |
|---|---|
| `newrelic` | Branch main somente, sem tags. Variável `AWS_NEW_RELIC_ROLE_ARN` com o output do bootstrap; variável `NEW_RELIC_ACCOUNT_ID=8626152`; variável `NEW_RELIC_ALERT_EMAIL` com o destinatário escolhido; Secret `NEW_RELIC_API_KEY` com uma User API Key autorizada a administrar dashboards, alertas e notificações |
| `newrelic-approval` | Branch main somente, sem tags; reviewer `pknfelps`, autorrevisão permitida. Não cadastrar credenciais, secrets ou variáveis AWS/New Relic |

Usar usuário autorizado também a editar os dashboards já existentes; permissões PUBLIC_READ_ONLY não dão edição a todos os usuários. A chave deve ser cadastrada pelo mantenedor diretamente no GitHub, sem enviá-la no chat. Não usar License Key de ingestão, AWS Secrets Manager ou tfvars para essa credencial. Não cadastrar cópias desnecessárias da User API Key como repository/organization secret: este workflow espera a credencial no Environment `newrelic`.

### Plano, aprovação e aplicação

- **plan:** checkout do SHA exato da execução; checks de repositório/main/configuração; OIDC para conta 121754142617/us-east-1; Terraform 1.15.9, provider/lockfile existentes, workspace default e backend.hcl. Init com lockfile readonly, fmt/validate e `plan -out=tfplan -lock-timeout=60s`. A conta positiva validada fica registrada como output do job, usada pelo plano e pelo apply/conferência, mesmo se a variável do Environment mudar durante a aprovação.
- O plano binário e `tfplan.txt` são os únicos arquivos enviados pelo upload-artifact, retidos por sete dias. Revisar o texto/commit/Account ID antes de aprovar. Com os cinco alertas ainda não publicados, esperar vinte e seis recursos novos: cinco policies, dez condições, um destino compartilhado, cinco canais e cinco workflows New Relic. Preservar os três dashboards existentes. Se o estado estiver inesperadamente vazio ou houver outras diferenças, revisar antes de aprovar. O artefato contém configuração/estado planejado; não publicar externamente nem incluir .terraform, credenciais ou tfvars no upload.
- **approval:** Environment `newrelic-approval`, `permissions: {}`, sem checkout, autenticação AWS, User API Key ou acesso aos artefatos pelo job. A revisão é feita pelo mantenedor no plano do job anterior.
- **apply:** checkout do mesmo SHA, autenticação nova e download pelo ID retornado pelo plan desta execução; init readonly e `terraform apply ... tfplan`. Não recria o plano antes do apply. Resumo com commit, Account ID, GUIDs/permalinks dos três dashboards e IDs das policies/condições dos cinco alertas.
- Conferência posterior executa `plan -detailed-exitcode`, sem salvar/aplicar outro plano: 0 confirma ausência de diferenças; 2 falha com diagnóstico de divergência; demais erros também falham. Não há rollback/reparo automático.

A User API Key real existe no ambiente apenas dos passos Create saved plan, Apply approved plan e Check for remaining changes. Validate usa placeholder não secreto; os passos de aprovação, autenticação OIDC, upload/download, show e outputs não recebem a chave. O provider lê a chave do processo; ela não é argumento Terraform, variável TF_VAR, arquivo ou output. Não ativar TF_LOG, imprimir ambiente ou adicionar headers/chave aos diagnósticos.

Plano obsoleto, credencial inválida, diferença de estado ou artefato indisponível/expirado interrompe o fluxo. Corrigir a causa e iniciar **nova execução completa**, com novo plano/revisão/aprovação; não repetir somente o apply nem gerar outro plano dentro dele. O lock permanece necessário em plan/apply/conferência; não forçar unlock como recuperação automática.

### Acesso AWS e limites

Role persistente em `/mecanica/pipelines/`, confiança no OIDC existente com audience sts.amazonaws.com e subject exato do repositório/Environment newrelic. A main é restringida no Environment e nos checks dos dois jobs, sem inventar claim OIDC ref. A policy permite GetBucketLocation no bucket existente, ListBucket com prefixos do estado/lock/enumeração de workspaces da unidade, Get/Put no estado exato e Get/Put/Delete somente no .tflock. Não permite apagar estado, ler outros estados, Secrets/artefatos ou provisionar AWS. O ARN é conferido antes de assumir a role; allowed-account-ids limita a conta.

Nenhum workflow de destroy, input hom/prd, dependência de base/API/Lambda/banco/Gateway ou mudança dos dashboards/queries. O estado S3 e os dashboards continuam persistentes e protegidos. As permissões OIDC/S3/New Relic e a execução do workflow precisam de conferência posterior real; validação local não as comprova.

### Validação local do workflow — 18/10/2026

Actionlint **1.7.12** com ShellCheck **0.11.0** aprovou newrelic-provision e CI alterado. Actions fixadas por SHA; a referência v4 de azure/setup-kubectl foi conferida no repositório oficial antes de fixar. Bootstrap: fmt/init sem backend/validate aprovados; JSON nativo de trust/permissões renderizado/revisado (quatro statements, 886 caracteres na policy inline com os valores deste projeto, abaixo do limite).

O passo offline novo do CI foi executado localmente em Bash, com placeholder e sem backend: fmt/init/validate New Relic e renderização dos três templates aprovados. Nenhuma chave/OIDC é usada no CI de PR, que mantém contents:read. Preservados templates, recursos/provider/backend/lockfile New Relic. Evidências locais ignoradas na API: `artifacts/newrelic-workflow/`. Sem login, plano remoto, apply, chamada AWS/New Relic, configuração GitHub ou execução remota; publicação/conferência visual continuam pendentes.

## Operação local alternativa — somente após autorização

Não é necessário subir API, Lambda, banco ou Gateway para publicar o dashboard ou consultar dados históricos ainda retidos. Preparar autenticação AWS local e a User API Key. Em PowerShell 7, a leitura mascarada abaixo evita incluir o valor no histórico do comando:

```powershell
$env:NEW_RELIC_API_KEY = Read-Host 'New Relic User API Key' -MaskInput
Copy-Item terraform.tfvars.example terraform.tfvars
# Preencher new_relic_alert_email no terraform.tfvars local antes do plan.
terraform init -backend-config=backend.hcl -input=false -lockfile=readonly
terraform workspace show
terraform plan -var-file=terraform.tfvars -out=tfplan
terraform show -no-color tfplan
```

Usar workspace default e revisar Account ID/credencial antes do plano. A primeira publicação desta unidade, se nenhum dashboard tiver sido publicado, deve propor **três dashboards criados**, sem mudanças AWS. Se operação e/ou ordens já existirem no estado, esperar somente os recursos ainda não publicados, preservando os existentes sem alterações. Não usar `-target` para esconder diferenças; revisar o plano completo. `tfplan` é local/ignorado. Encerrar a sessão ou remover a variável ao terminar; ela precisará ser fornecida novamente se o apply ocorrer em outro processo.

**Parar para revisão do plano salvo.** Somente após sua aprovação, no mesmo checkout e unidade, com credenciais válidas no processo:

```powershell
terraform apply tfplan
terraform output -raw operations_dashboard_guid
terraform output -raw operations_dashboard_permalink
terraform output -raw orders_dashboard_guid
terraform output -raw orders_dashboard_permalink
terraform output -raw integrations_dashboard_guid
terraform output -raw integrations_dashboard_permalink
terraform plan -var-file=terraform.tfvars -detailed-exitcode
```

O último comando deve retornar código 0/nenhuma alteração; código 2 indica diferenças, não autorização para aplicar outro plano. Conferir layout, filtro hom/prd, período, unidades e ausência de dados na interface. Não importar/publicar o JSON manualmente em paralelo ao Terraform. Limpar a variável ao encerrar:

```powershell
Remove-Item Env:NEW_RELIC_API_KEY
```

## Operação — painéis e semântica

| Bloco | Fontes e apresentação |
|---|---|
| Contexto | Última amostra UTC por pod da API e por nó Kubernetes, no período selecionado; orientações em Markdown |
| HTTP | Contagem e req/min por `http.server.request.duration`, códigos HTTP, percentual 5xx, média/p50/p95 em ms e tabela método/modelo da rota |
| Atividade | `http.server.active_requests` por pod; working set do processo .NET em MiB |
| Workloads | Réplicas desejadas/disponíveis; fase dos pods; readiness/reinícios por container |
| Pods/containers | CPU em cores; working set em MiB; requests/limits por container |
| Nós | CPU usada/alocável, working set/alocável/disponível, condições e uptime cumulativo em segundos |

Todas as consultas usam `Metric`; não contam spans ou access logs. As consultas da aplicação selecionam `service.name=mecanica-api` e ambiente. Kubernetes também seleciona `k8s.cluster.name=mecanica-<ambiente>-eks`. Inclui namespaces do cluster, não apenas a API. Facets preservam pod/UID e container quando aplicáveis; LIMIT 100 limita as tabelas/séries, não promete cobertura de clusters maiores.

HTTP concluído exclui as probes com **e sem barra inicial**, pois as séries históricas usam `health/live`, `health/ready` e `health/startup`. Rotas desconhecidas com atributo ausente continuam no total; tabelas por rota podem não listar a parcela sem esse atributo. A métrica de requisições ativas pode incluir probes e é exibida por pod, sem somar amostras temporais.

4xx e 5xx são categorias distintas. Percentual 5xx usa requisições concluídas como denominador; sem denominador, fica nulo. Percentis vêm da distribuição HTTP, com `getField(percentile(...), '50.0'/'95.0')` antes de multiplicar por 1000; não usar matemática no mapa composto retornado por percentile. São estimativas dos histogramas recebidos. A média é calculada sobre as amostras agregadas, não por média das médias dos pods.

Gauges usam `latest` por recurso/período/bucket. Não usar `sum` ao longo do tempo como consumo simultâneo; reinícios são o acumulado do container atual, não eventos ocorridos no período. Uptime usa `getField(..., 'cumulative')`, preservando o tempo total do nó. Requests/limits ausentes permanecem nulos. CPU alocável não é capacidade física; memória disponível/working set/alocável têm definições distintas e não devem ser somadas.

As tabelas de última amostra usam o campo `timestamp` consultável em Metric, que representa o instante inicial do período da métrica; não é o horário de chegada ao exporter/New Relic. Essa diferença de coleta deve ser considerada ao interpretar a atualização.

Todas as consultas respeitam o seletor global de período; nenhuma contém data fixa, SINCE/UNTIL próprios, EXTRAPOLATE ou preenchimento com `OR 0`. A janela sugerida é 30 minutos. `count` e `rate(count)` podem retornar zero nativo quando não há requisições; isso não comprova que houve coleta ou disponibilidade. Conferir as últimas amostras, especialmente com ambiente desligado. Percentuais sem amostras e gauges ausentes não são convertidos para zero. Os gráficos podem mostrar recursos já removidos se eles existiram dentro do intervalo escolhido.

Sem indicadores de OS, CloudWatch/Gateway/Lambda/RDS, notificações ou árvore X-Ray/OTLP nesta página. Não altera coleta, código das aplicações, consultas SQL, recursos AWS ou permissões. Os demais dashboards e alertas permanecem separados.

## Conferência histórica desta entrega

Consultas executadas pela sessão do navegador na conta 8626152, sem chave administrativa no processo e sem publicar dashboard. Janela principal: **18/10/2026 15:40–16:10 UTC**. Substituição de `{{environment}}` por valores literais somente nas consultas de validação; no template, continua declarativa.

- Vinte consultas hom e vinte prd conferidas quanto à execução/sintaxe. Prd sem séries na janela; isso não comprova instrumentação ou operação de prd.
- Total HTTP hom: **19 chamadas da API**, coerente com as evidências da validação funcional. Excluídas 711 probes; consulta anterior que ignorava a diferença da barra inicial contava 730 e foi corrigida antes da conclusão.
- Cinco códigos HTTP e quatro combinações método/rota; nenhuma 5xx na amostra. Percentis e média em ms conferidos com dados reais.
- API com uma réplica disponível; CPU request/limit 0,2/0,75 core e memória request/limit 256/512 MiB. Valores de working set variam conforme a amostra.
- Nó com 1,93 core alocável, 1433,58203125 MiB alocáveis, Ready=1 e pressões=0; uptime cumulativo retornou 5673 s na amostra final selecionada. Esses são registros históricos, não estado atual.
- Sem gráficos com dados de hom ao selecionar prd. Não se realizou criação, alteração de dashboard, plano remoto, apply, chamadas à API, reinício do Collector ou provisionamento AWS.

A validação local usa o schema HCL do provider, JSON renderizado e revisão dos campos contra os tipos/exemplos do cliente oficial. A validação final do serviço para o documento, as permissões reais e o layout visual só será concluída no apply/conferência posterior. Evidências locais ignoradas no repositório da API: `artifacts/newrelic-operations/`.

## Ajuste das consultas Kubernetes — 19/10/2026

Os painéis Kubernetes restringem `metricName` às métricas utilizadas em cada consulta, além do ambiente e do cluster. O filtro evita que métricas de outros níveis (por exemplo, réplicas de Deployment, sem identificação de pod/container) produzam facetas vazias nos painéis de memória. Preservados os cálculos, as facetas de identidade, as unidades e os valores legitimamente ausentes de requests/limits; não há substituição de nulos por zero nem alteração de coleta.

Comparação pela sessão New Relic, com os dados históricos de **18/10/2026 15:40–16:10 UTC**, sem subir o ambiente:

- Memória dos pods: 13 facetas na consulta original; nove com a métrica explicitamente selecionada. Removidas quatro facetas sem medição; os nove conjuntos de identidade/valores permaneceram exatamente iguais.
- Memória dos containers: 24 facetas originais, 14 totalmente vazias; dez após selecionar working set, request e limit. Todas as dez medições válidas foram preservadas exatamente, sem identidades incompletas. Requests/limits não definidos continuam ausentes.
- Condições/uptime: o aviso de expressões incompatíveis em prd sem dados foi substituído por uma informação de conversão interna para o formato legado. A consulta continua sem facetas em prd; não se afirma ausência de todas as mensagens do serviço. Hom preservou Ready=1, pressões=0 e uptime=5673 segundos.

A evidência aponta para seleção de métricas na consulta; não comprovou falha de enriquecimento do Collector. Referência do comportamento de compatibilidade: [métricas dimensionais e formato legado](https://docs.newrelic.com/docs/nrql/using-nrql/query-infrastructure-dimensional-metrics-nrql/).

A seleção foi estendida aos dez painéis Kubernetes que ainda não tinham filtro explícito. O painel de última amostra Kubernetes já selecionava sua métrica. Não alterados os painéis HTTP/.NET, os dashboards de ordens/integrações, os Collectors, recursos AWS ou workflows. Publicar pelo `newrelic-provision`: esperar somente atualização do dashboard de operação, preservando os outros dois e sem criar/excluir dashboards. Não é necessário subir API, Lambda, banco, Gateway ou Collector.

## Ordens de serviço — painéis e semântica

Fonte: `dashboards/orders.json.tftpl`; 15 consultas e dois textos, sem datas fixas. Respeita o período global; sugestão de negócio: **sete dias**. A unidade usa o mesmo backend/provider/Account ID e a mesma User API Key; não inicializar um estado separado para ordens. Renderização offline: repetir o comando `templatefile` acima com `dashboards/orders.json.tftpl`.

| Bloco | Fonte e regra |
|---|---|
| Atualização | Último `timestamp` por uma das cinco métricas de OS selecionadas; início do período da métrica, não chegada ao New Relic |
| Volume | `sum(mecanica.orders.created)` no período; por dia com `FACET dateOf(timestamp)`, `WITH TIMEZONE 'America/Sao_Paulo'` e `LIMIT MAX` |
| Diagnóstico | `stage=diagnosis`: média em minutos, quantidade de amostras e evolução da média |
| Execução | `stage=execution`: média em minutos, quantidade de amostras e evolução da média |
| Espera pela entrega | `stage=delivery_wait`, dois grupos explícitos: `completion.reason=service_completed` e `budget_rejected`; média, amostras e evolução para cada grupo |
| Serviço completo | `mecanica.orders.service.duration`: média em minutos, serviços medidos e evolução |
| Falhas | Soma de `mecanica.orders.processing.failures` por `operation`, separada da soma de `mecanica.orders.telemetry.failures` |

Todas as consultas usam **Metric**, `service.name=mecanica-api` e `deployment.environment.name={{environment}}`. O filtro nativo substitui o ambiente como string; não colocar aspas extras em `{{environment}}`. Não usar identidade pessoal, UUID ou documento como dimensão. Não misturar ambientes, filtrar por pod/version ou contar spans/logs para obter volume de OS.

`average(histograma)/60` exibe minutos; `count(histograma)` conta intervalos concluídos. A média usa todas as amostras recebidas de todas as réplicas, sem média de médias. `TIMESERIES AUTO` usa buckets escolhidos pelo New Relic; uma média por bucket não deve ser promediada novamente para obter a média do período. Não somar médias de etapas para calcular o serviço completo. Contadores usam soma dos incrementos, sem `rate` para representar o total.

Diagnóstico: InDiagnosis → WaitingForApproval. Execução: InExecution → Finished/ServiceCompleted. Espera pela entrega: Finished → Delivered, separando conclusão e recusa. Serviço completo: Received → Finished/ServiceCompleted, sem aguardar entrega e sem incluir orçamento recusado. O período da duração está associado à medição da transição concluída, não à abertura da OS. Intervalos abertos/incompatíveis não são amostras zero; duração efetivamente zero é válida.

Criações confirmadas permanecem contadas após exclusão/recusa. A amostragem HTTP atual não produz estoque de OSs abertas, distribuição atual por estado, aprovação percentual ou relatório individual de OS. Falha técnica é resposta 500 de ação reconhecida de OS; negativas 4xx e cancelamento pelo cliente não entram. Falha de leitura/cálculo da medição após o commit é indicador de qualidade dos dados e não desfaz a operação persistida. Não há percentual de falhas usando criações como denominador.

Volume diário usa o dia do timestamp da métrica em São Paulo; início/fim selecionados podem cortar dias. `LIMIT MAX` continua sujeito ao limite de facets do New Relic; não garante uma quantidade ilimitada de dias. Janelas OTLP podem atravessar meia-noite; **SQL é a referência exata por data do acontecimento**, com início inclusivo e fim exclusivo. As [regras e consultas SQL existentes](https://github.com/pknfelps/GerenciamentoMecanicaSistema/blob/develop/docs/OBSERVABILIDADE_NEGOCIO.md) permanecem a fonte de reconciliação, inclusive para OS excluída. Destruir o banco encerra a disponibilidade daquele histórico.

Não há preenchimento de lacunas, `OR 0`, backfill, reprocessamento, deduplicação ou garantia de entrega única. Contadores e contagem de amostras podem retornar zero nativo sem séries; médias ausentes ficam nulas e gráficos facetados podem ficar vazios. Conferir atualização; zero não comprova saúde/coleta. Notificações, integrações e alertas ficam em entrega separada.

### Conferência histórica de ordens — 18/10/2026

As 15 consultas foram executadas para hom e para prd pela sessão do New Relic na conta 8626152, sem User API Key local, publicar dashboard, acessar banco ou gerar novas requisições. Janela **18/10/2026 00:22:30–00:49:40 UTC**, equivalente à noite de **17/10 em São Paulo**. A tabela diária retornou `October 17, 2026` com três criações.

| Indicador hom | Amostras | Soma de referência (s) | Média consultada (min) |
|---|---:|---:|---:|
| Criações | 3 | — | — |
| Diagnóstico | 2 | 3,112321 | 0,02593600833333333 |
| Execução | 1 | 1,087185 | 0,01811975 |
| Entrega após serviço concluído | 1 | 1,304562 | 0,0217427 |
| Entrega após orçamento recusado | 1 | 1,659814 | 0,027663566666666663 |
| Serviço completo | 1 | 9,681048 | 0,16135080000000002 |

As médias/contagens reproduzem as somas e amostras da [evidência SQL já salva](https://github.com/pknfelps/GerenciamentoMecanicaSistema/blob/develop/docs/VALIDACAO_HOM_2026-10-17.md). Séries temporais retornaram os buckets com médias correspondentes, sem preencher períodos sem amostras. Não há falhas de processamento na janela (sem facets); falhas de medição retornaram zero nativo. Isso valida as consultas, não um cenário de falha não ocorrido. Prd ficou sem séries: médias nulas, contagens/somas nativas zero, nenhuma mistura com hom; não comprova operação de prd.

As 30 consultas executadas correspondem às strings renderizadas do template, com substituição literal de ambiente/janela somente na validação. Evidências locais ignoradas no repositório da API: `artifacts/newrelic-orders/` (JSON renderizado, resultados consolidados e fingerprints das consultas). Terraform fmt/init sem backend/validate e renderização pelo `terraform console` em pasta de artefatos aprovados. Não alterados provider/lockfile, backend, recursos AWS, aplicações, Collectors ou workflows.

**Publicação pendente:** gerar plano salvo após autorização, revisar e aplicar exclusivamente o plano aprovado. Depois conferir layout/período/filtro/unidades/ausência de dados e novo plano sem diferenças. E5.6/E5.7/E5.7a têm definição e consultas preparadas/validadas, sem marcar publicação/conferência visual como concluídas.

## Integrações e autenticação — painéis e semântica

Fonte: `dashboards/integrations.json.tftpl`; recurso `newrelic_one_dashboard_json.integrations`, 24 consultas/dois textos. Reutiliza estado, provider, proteção, permissões e credenciais dos dois dashboards anteriores. Filtro único hom/prd, padrão hom; recomendação de período **60 minutos**, sem SINCE/UNTIL nos widgets. Os outputs novos são somente GUID/permalink de integrações. Renderização offline: repetir o comando `templatefile` com `dashboards/integrations.json.tftpl`.

| Bloco | Painéis/fontes |
|---|---|
| Atualização (3 consultas) | Último timestamp da autenticação, notificações e três fontes CloudWatch; início do período métrico, não chegada ao New Relic |
| Clientes (5) | `mecanica.auth.invocations`: total, categorias e percentual técnico; `mecanica.auth.invocation.duration`: média/p50/p95 e evolução em ms |
| Login interno (3) | `http.server.request.duration` em POST/Authentication: códigos, percentual 5xx e média/p95 em ms |
| CloudWatch (8) | Cinco métricas Gateway, cinco Lambda e três RDS em gráficos separados por unidade/fonte |
| Notificações (3) | `mecanica.orders.notifications`: tentativas, resultados e percentual de falha por tipo/modo |
| Diagnóstico (2) | Logs técnicos da autenticação com timeout/technical-failure/status 500 e access logs 5xx do Gateway; até 100 registros por tabela |

**OTLP:** filtrar `service.name=mecanica-auth` ou `mecanica-api` e ambiente; não filtrar commit, versão, réplica ou perfil. Invocações usam soma dos incrementos; categorias são authenticated, invalid-request, invalid-document, not-eligible, timeout e technical-failure. Percentual técnico = soma de timeout/technical-failure dividida pelas invocações concluídas, vezes 100. Negativas 400/401 não são falha técnica. O histograma do handler inclui inicialização tardia quando ocorre e termina antes do flush; não mede duração faturada/extensão inteira.

Login interno usa método POST e modelos `Authentication`/`/Authentication`, não caminho recebido nem o nome do usuário. Volumes/códigos vêm de `count(http.server.request.duration)` e falhas são somente 500–599; não usar 401 como falha técnica ou segmentar Admin/Mechanic sem dimensão existente. Média e percentis agregam distribuições de todas as réplicas, sem média de médias.

**Percentis e ausência:** o New Relic devolveu percentil zero nativo para prd sem amostras. A consulta extrai o escalar com `getField(percentile(...), '50.0'/'95.0')`, converte para ms e multiplica por `count(histograma)/count(histograma)`: fator 1 com amostras, nulo com denominador zero. Assim, ausência fica nula e duração efetivamente zero com amostras continua zero. A mesma regra vale por bucket da evolução. Percentis são estimativas da distribuição, não percentis dos valores médios. Percentuais também permanecem nulos sem denominador; não usar OR 0.

**Notificações:** somar tentativas concluídas por notification.type (budget_available/status_changed), mode (smtp/simulated) e outcome (success/failure). Percentual = failure dividido por success+failure, dentro do mesmo tipo/modo. A tentativa pode falhar nas consultas necessárias ao envio; não é somente o transporte SMTP. Success em simulated não afirma entrega. As notificações não são contadas novamente por logs nem confundidas com falha da operação persistida.

**CloudWatch:** filtrar cloud.account.id=121754142617, cloud.region=us-east-1, ambiente, Namespace, stat e nomes exatos derivados do ambiente (Gateway ApiName/Stage, Lambda FunctionName e RDS DBInstanceIdentifier). Métricas são gauges com estatística por **60 segundos**. Atraso configurado de dez minutos, além de publicação/exportação; não eliminar esse intervalo com UNTIL próprio no widget: a última amostra mostra o atraso.

| Fonte | Estatística/apresentação por ponto |
|---|---|
| Gateway Count/4XXError/5XXError | latest da estatística SampleCount/Sum de 60 s, cada uma com filtro stat próprio |
| Gateway Latency/IntegrationLatency | latest Average de 60 s, em ms |
| Lambda Invocations/Errors/Throttles | latest Sum de 60 s |
| Lambda Duration | latest Average de 60 s, em ms |
| Lambda ConcurrentExecutions | maior Maximum no bucket |
| RDS CPUUtilization | latest Average de 60 s, em % |
| RDS FreeableMemory | latest Average de 60 s dividido por 1048576, em MiB |
| RDS DatabaseConnections | latest Average de 60 s, contagem |

TIMESERIES AUTO pode agrupar vários minutos; latest mostra a última estatística de um minuto em cada bucket, **não o total/média ponderada daquele bucket ou do intervalo**. Concorrência preserva o maior máximo. Não somar gauges médios, calcular percentis sobre médias de minutos ou misturar unidades no mesmo gráfico. A consulta de atualização usa agregações filtradas por serviço/recurso: uma tentativa anterior de combinar os três conjuntos de dimensões por OR no WHERE retornou tabela vazia na consulta Metric; foi substituída e conferida com dados reais.

Errors da plataforma Lambda inclui erros de função/runtime/timeouts e pode continuar zero quando o handler retorna HTTP 500 tratado. Throttles não entra em Invocations. As estatísticas AWS e a instrumentação do handler têm fronteiras e janelas diferentes; não exigir igualdade entre Duration AWS e histograma ou entre métricas de intervalos diferentes. As 13 métricas já estavam coletadas: nada foi habilitado na AWS nesta entrega.

**Diagnóstico:** selecionar somente timestamp, categoria/status, duração e IDs técnicos. Autenticação usa lambdaRequestId/gatewayRequestId/trace.id/span.id; Gateway usa método, modelo da rota, durações e requestId/extendedRequestId/id/xrayTraceId. Não selecionar message/body, payloads, credenciais, documentos, tokens ou segmentos X-Ray. As duas tabelas são apoio limitado, sem derivar volume/taxa oficial de logs. A amostra anterior recebeu 19 de 28 request IDs; não promete cobertura completa, deduplicação ou recuperação. A causa das nove lacunas não foi estabelecida. IDs X-Ray não são normalizados para declarar árvore única OTLP.

**Cobertura:** CPU/memória/conexões do RDS não são taxa de falha PostgreSQL. Ainda faltam contadores completos de tentativas/falhas de PostgreSQL, SSM e Secrets Manager; spans não os substituem. E5.8 fica preparada no escopo dos sinais disponíveis, sem concluir essas lacunas. Sem séries não equivale a saúde/zero; contadores podem retornar zero nativo, latências/percentuais vazios ficam nulos. Não adicionados instrumentos, scripts, suítes de telemetria, exporter, alteração de workflow, Collector, IAM ou aplicação.

### Conferência histórica de integrações — 18/10/2026

As **24 consultas hom e 24 prd** foram executadas pela sessão New Relic na conta 8626152; strings finais conferidas com o template renderizado. Substituição literal de ambiente/períodos somente na validação. Sem chave administrativa no processo, tráfego novo ou acesso AWS.

- Autenticação/login: **15:40–16:10 UTC**. Oito invocações: 2 authenticated, 2 invalid-request, 2 invalid-document, 2 not-eligible; percentual técnico 0%. Média/p50/p95 do handler: **390,4211625 / 59,5703125 / 1718,5071 ms**. Login interno: 11 chamadas (3 HTTP 200, 5 HTTP 400, 3 HTTP 401), zero 5xx; média/p95 **58,511890909090916 / 242,9362 ms**.
- CloudWatch: **15:47–15:48 UTC**. Gateway 7 requisições/5 erros 4xx/0 erros 5xx, latências 848,285714/843,714286 ms; Lambda 4 invocações/0 Errors/0 Throttles, Duration 250,1975 ms e concorrência 1; RDS CPU 4,474776261186941%, memória livre **179,92578125 MiB** (188665856 bytes), conexões 2. As 13 estatísticas coincidem com o [snapshot histórico AWS já documentado](https://github.com/pknfelps/GerenciamentoMecanicaSistema/blob/develop/docs/VALIDACAO_CORRELACAO_HOM_2026-10-18.md#cloudwatch).
- Notificações: **00:22:30–00:49:40 UTC**. Onze tentativas simuladas com sucesso: 9 status_changed e 2 budget_available; falhas 0% por tipo/modo. Não comprova entrega SMTP.
- Falhas técnicas de autenticação/5xx Gateway: tabelas vazias na janela; não houve falha induzida. Os campos selecionados foram conferidos em registros históricos existentes, sem exportar corpos brutos. Não se registra cenário de falha inexistente como validado operacionalmente.
- Prd sem amostras; todos os pontos das séries consultadas nulos, percentuais/médias/percentis nulos e tabelas vazias, sem dados de hom. Isso valida sintaxe/filtros/ausência, não operação de prd. Não houve preenchimento com zeros.

fmt/init sem backend/validate e renderização Terraform aprovados. JSON, grade sem sobreposição, defaults e projeção de logs revisados; templates operação/ordens, provider/lockfile/backend preservados por checksum. Evidências locais ignoradas na API: `artifacts/newrelic-integrations/` (renderização, baseline, fingerprints das 48 consultas e resultados consolidados).

**Publicação pendente:** plano remoto salvo/revisão/apply, layout e conferência visual. Se a unidade nunca tiver sido aplicada, esperar três dashboards criados; caso contrário somente os ausentes, preservando os existentes sem alterações. Não houve plano remoto/apply, criação de dashboard ou reprovisionamento. Atualização visual e tráfego novo permanecem separados; não é necessário subir aplicações para publicar e consultar dados ainda retidos.

## Referências

- [Provider 3.99.3 — recurso JSON](https://github.com/newrelic/terraform-provider-newrelic/blob/v3.99.3/newrelic/resource_newrelic_one_dashboard_json.go)
- [Exemplos de widgets/variáveis da mesma versão](https://github.com/newrelic/terraform-provider-newrelic/blob/v3.99.3/newrelic/resource_newrelic_one_dashboard_json_test.go)
- [Dashboards com Terraform e templates JSON](https://newrelic.com/blog/infrastructure-monitoring/create-nr-dashboards-with-terraform-part-1)
- [Variáveis nativas do dashboard](https://docs.newrelic.com/docs/query-your-data/explore-query-data/dashboards/dashboard-template-variables/)
- [Métricas OpenTelemetry no New Relic](https://docs.newrelic.com/docs/opentelemetry/best-practices/opentelemetry-best-practices-metrics/)
- [NRQL: percentis, campos compostos e funções](https://docs.newrelic.com/docs/nrql/nrql-syntax-clauses-functions/)
- [Coleta e consultas Kubernetes](../../docs/COLLECTOR_API.md)
- [Validação da correlação/API em hom](https://github.com/pknfelps/GerenciamentoMecanicaSistema/blob/develop/docs/VALIDACAO_CORRELACAO_HOM_2026-10-18.md)

- [NRQL: agrupamento por data e fuso horário](https://docs.newrelic.com/docs/nrql/nrql-references/nrql-group-results-across-time/)

- [Métricas Lambda: Errors, Invocations, Throttles e Duration](https://docs.aws.amazon.com/lambda/latest/dg/monitoring-metrics-types.html)

## Alerta de processamento de OS

**19/10/2026 — Implementado e validado localmente, sem publicação ou envio de e-mail.** Esta seção descreve o primeiro alerta; a entrega seguinte de notificação de OS está documentada abaixo. O primeiro alerta permanece inalterado. Nenhuma alteração de instrumentação, Collector, IAM ou infraestrutura AWS.

### Fonte e avaliação

`orders-alerts.tf` acrescenta uma policy com `PER_CONDITION` e duas condições habilitadas, uma para hom e outra para prd. Cada consulta soma `mecanica.orders.processing.failures`, restringindo explicitamente `metricName`, `service.name=mecanica-api` e o ambiente. Todas as operações, réplicas e versões participam da soma; não há FACET, taxa, denominador, filtro por pod/commit ou contagem por logs/spans. A API já conta uma falha por resposta 500 de ação de OS, excluindo cancelamento pelo cliente e respostas 400/401/403/404/409/422.

| Configuração | Valor |
|---|---|
| Severidade | Critical; sem Warning |
| Limiar | Soma >= 1 |
| Janela | 300 segundos, sem sobreposição |
| Fechamento da janela | event_timer, temporizador de 60 segundos |
| Avaliação do limiar | threshold_duration=300, AT_LEAST_ONCE |
| Lacunas | fill_option=none, sem preencher com zero/último valor |
| Expiração | 600 segundos sem pontos recebidos para o sinal |
| Na expiração | Encerrar incidentes; não abrir incidente por ausência |

Uma falha isolada pode disparar, sem exigir falhas contínuas por cinco minutos. Coleta, transporte, fechamento da janela e avaliação acrescentam atraso; o temporizador não é promessa de entrega do e-mail em 60 segundos. As condições são de streaming: não reprocessam a janela histórica dos dashboards.

Uma medição real abaixo do limiar pode encerrar o incidente pelas regras nativas. **Encerramento por dez minutos sem pontos indica ausência de sinal, não recuperação comprovada da API.** Depois de desligar o ambiente, ausência de pontos não abre um novo incidente. Um incidente já aberto pode encerrar por expiração e enviar sua notificação de encerramento. A plataforma exige um limite máximo de duração do incidente: configurado o máximo nativo de 30 dias, independente da expiração de dez minutos. Fechamento manual ou por esse limite também não comprova recuperação.

### E-mail e isolamento

A variável obrigatória `new_relic_alert_email`, marcada como sensível, recebe o destinatário por `NEW_RELIC_ALERT_EMAIL` no Environment GitHub `newrelic`. O mantenedor deve cadastrar ali o endereço que escolheu para os alertas; nenhum endereço pessoal foi versionado. O exemplo usa `alerts@example.invalid`, apenas para validação, e deve ser substituído antes de qualquer publicação local. O destino `mecanica-alertas-email` poderá ser reutilizado pelas próximas entregas.

O valor fica oculto no plano textual e não é output/resumo. Isso não o remove do plano binário/estado Terraform: ambos devem continuar protegidos no backend/artefato existentes. A User API Key continua somente em `NEW_RELIC_API_KEY`; não reutilizar License Key, alterar IAM ou ampliar acesso automaticamente se a conta/usuário não puder administrar alertas/notificações.

O canal EMAIL/IINT inclui estado, nome da condição (com ambiente), link do incidente e dashboard de ordens. Não acrescenta dados pessoais de clientes, payloads, documentos, tokens, credenciais ou mensagens de exceção. O workflow **de notificações New Relic** filtra somente o ID desta policy, avisa apenas ACTIVATED/CLOSED e respeita silenciamento total/parcial. Não há novo workflow GitHub, agendamento ou regra de muting. Condições e incidentes são separados por ambiente.

### Publicação

1. `NEW_RELIC_ALERT_EMAIL` já foi cadastrada no Environment `newrelic`, conforme confirmação do mantenedor; preservar a mesma User API Key e as demais variáveis. Não cadastrar credenciais no `newrelic-approval`.
2. Aguardar a preparação dos cinco alertas previstos antes do PR para main e da execução de `newrelic-provision`. Não publicar este alerta isoladamente nesta etapa.
3. O primeiro alerta representa **6 recursos novos**, uma policy, duas condições, um destino, um canal e um workflow New Relic. Somado ao alerta de notificação, são **11 criações esperadas neste estágio**; o plano final incorporará os próximos três alertas. Dashboards e recursos AWS não devem mudar. Revisar diferenças inesperadas antes de aprovar.
4. Aprovar e aplicar exclusivamente o plano salvo. O destinatário do apply é o congelado no plano. A conferência posterior usa o valor atual da variável do Environment; se ela mudar durante a aprovação, a divergência exigirá nova execução completa, sem segundo apply automático.
5. Conferir resumo com IDs da policy e das condições, final sem diferenças, condições habilitadas, consulta/tempos, filtro da policy, muting e gatilhos de e-mail. Concluir confirmação de destinatário se exigida pelo serviço. Não disparar mensagem de teste sem autorização.

O mesmo backend persistente conserva dashboards e alertas fora dos destroys AWS. Não é necessário subir API, Lambda, banco, Gateway ou Collector para publicar a configuração. O CI existente valida a unidade e mantém a renderização dos três dashboards sem credenciais reais; nenhuma suíte, script ou mock novo.

### Investigação e comprovação posterior

Na abertura, identificar ambiente, condição e janela no incidente; consultar o dashboard de ordens no mesmo ambiente/período, somar as falhas e verificar a operação. Usar os logs sanitizados/correlação para investigar a causa; não reenviar conteúdo sensível. Não confundir falha de processamento com falha de notificação ou de medição após commit. No encerramento, conferir a causa: ausência de pontos exige verificar a saúde/coleta separadamente.

Após publicação, em uma etapa autorizada com hom ativo: provocar uma falha controlada de ação de OS, confirmar resposta 500, incremento da métrica, incidente e recebimento do e-mail. Uma única falha deve bastar; negativas de negócio não devem disparar. Conferir que o incidente de hom não abre em prd, que não há notificação duplicada de abertura e que o encerramento após ausência do sinal não é apresentado como recuperação comprovada. Não criar endpoint de falhas, enviar métrica sintética ou causar indisponibilidade como parte desta implementação.

Se pontos reais de valor zero continuarem chegando depois da falha, o cenário não é de ausência de sinal: registrar o fechamento normal e reservar a comprovação dos 600 segundos de silêncio para uma etapa controlada autorizada. Falha na entrega/ativação exige diagnóstico; não ampliar permissões ou repetir e-mails automaticamente.

fmt/init sem backend/validate, renderização dos três JSONs, grafo Terraform e actionlint 1.7.12 com ShellCheck 0.11.0 aprovados localmente, com placeholders e sem acesso AWS/New Relic. Templates/provider/lockfile/backend/CI preservados por checksum. **E5.5 permanece parcial até o disparo e recebimento reais.**

## Alerta de notificação de OS

**19/10/2026 — Implementado e validado localmente, com publicação conjunta posterior.** Segundo dos cinco alertas previstos, independente do alerta de processamento de OS. Sem publicação, mensagens de teste, tráfego induzido ou operações AWS. O destino de e-mail existente é compartilhado; não há outro destinatário, variável ou workflow GitHub.

### Fonte e avaliação

`order-notification-alerts.tf` define a policy **Mecânica — Falhas de notificação de OS**, com `PER_CONDITION`, e duas condições estáticas habilitadas, uma por ambiente. A consulta soma os incrementos de todas as versões e réplicas da API e dos dois tipos de notificação; não segmenta por FACET, pod, commit ou OS. Para prd, o Terraform troca somente o ambiente da consulta:

```sql
SELECT sum(`mecanica.orders.notifications`)
FROM Metric
WHERE metricName = 'mecanica.orders.notifications'
  AND `service.name` = 'mecanica-api'
  AND `deployment.environment.name` = 'hom'
  AND outcome = 'failure'
  AND `notification.type` IN ('budget_available', 'status_changed')
  AND mode IN ('smtp', 'simulated')
```

| Configuração | Valor |
|---|---|
| Severidade e limiar | Critical, soma >= 1; sem Warning |
| Janela | 300 segundos, sem janela deslizante |
| Agregação | event_timer, temporizador de 60 segundos |
| Avaliação | threshold_duration=300, AT_LEAST_ONCE |
| Lacunas | Nenhum preenchimento; fill_option=none |
| Expiração | 600 segundos após o último ponto do sinal |
| Ao expirar | Encerrar incidentes existentes, sem abrir por ausência |
| Limite máximo nativo | 30 dias, independente da expiração |

Uma falha isolada pode disparar; não precisa ocorrer continuamente por cinco minutos. Transporte, fechamento da janela e avaliação acrescentam atraso: não há promessa de e-mail imediato. Logs, spans, falhas HTTP gerais e percentuais não são fonte desta condição. Pontos reais de zero podem encerrar pelo comportamento normal; silêncio é um cenário distinto e não deve ser simulado com preenchimento artificial.

A tentativa inclui consultas de cliente/veículo, montagem da mensagem e envio. **Em hom/prd, o adaptador de envio é simulado**: falha no fluxo não afirma tentativa de entrega SMTP real. A falha tratada não desfaz a operação persistida da OS. Métricas ausentes ou encerramento por dez minutos sem pontos não comprovam recuperação, entrega posterior ou reprocessamento. Não há reenvio automático. Fechamento manual ou pelo limite máximo também não prova recuperação.

### E-mail e isolamento

O canal EMAIL/IINT reutiliza `newrelic_notification_destination.alerts_email` e `new_relic_alert_email`, recebida por `NEW_RELIC_ALERT_EMAIL` no Environment `newrelic`, já cadastrada pelo mantenedor. O exemplo versionado permanece fictício; nenhum endereço pessoal é acrescentado ao código ou aos outputs. O plano binário e o estado ainda contêm o valor sensível e continuam protegidos pelos mecanismos existentes.

O workflow de notificações New Relic filtra `labels.policyIds` pelo ID exato desta nova policy, notifica somente `ACTIVATED`/`CLOSED` e respeita silenciamento total/parcial. Não mistura incidentes com a policy de processamento. Assunto/corpo indicam condição/ambiente e estado; incluem link do incidente e do **dashboard Integrações e autenticação**, para consultar o bloco de notificações. Mensagens fixas sem dados do destinatário de negócio, documentos, tokens ou mensagens originais de exceção.

### Investigação e comprovação posterior

1. Conferir ambiente, condição e janela do incidente; consultar o bloco de notificações no dashboard de integrações usando o mesmo ambiente/período.
2. Separar `notification.type=budget_available/status_changed`, `mode=smtp/simulated` e `outcome=failure`, sem confundir sucesso simulado com entrega real ou falha de notificação com falha da operação persistida.
3. Investigar logs sanitizados e traces disponíveis, incluindo falhas nas consultas necessárias ao envio. Não reenviar payloads ou valores sensíveis. Ausência de logs/spans não prova ausência de falha.
4. No encerramento, verificar se houve avaliação abaixo do limiar, expiração, fechamento manual ou limite máximo; não declarar recuperação nem reenvio pelo simples fechamento.

Depois da publicação conjunta e de autorização específica, em hom ativo, conferir uma falha controlada do fluxo de notificação, incremento da métrica, abertura do incidente e recebimento do e-mail do New Relic. Confirmar preservação da operação persistida da OS, isolamento de prd, gatilhos/muting e encerramento após ausência de sinal. Não provocar HTTP 500 como requisito deste teste: o handler trata a falha de notificação separadamente. Se zeros reais continuarem chegando, registrar o fechamento normal e reservar o teste de silêncio para outra janela autorizada. Nenhuma falha, métrica sintética, mensagem de teste ou novo endpoint será criado nesta implementação.

O e-mail do **New Relic** avisa o mantenedor; não comprova que a API entregou e-mail de negócio ao cliente. Se o serviço exigir confirmação do destinatário, concluí-la antes do teste real. Não alterar permissões, reenviar mensagens ou implementar retentativas automaticamente.

### Publicação conjunta e validação

Este alerta acrescenta **5 recursos**: uma policy, duas condições, um canal e um workflow New Relic. Reutiliza o destino do primeiro alerta (6 recursos), totalizando **11 criações esperadas neste estágio**, sem mudanças nos três dashboards. O mantenedor optou por concluir os cinco alertas antes do PR e da execução de `newrelic-provision`; o plano final será revisado considerando todas essas entregas.

A pipeline existente conserva plan → aprovação → apply exclusivo do plano salvo e conferência sem segundo apply. O resumo acrescenta `orders_notifications_alert_policy_id` e `orders_notifications_alert_condition_ids` (hom/prd), sem expor o destinatário. Publicação independe de API/Lambda/banco/Gateway ativos; comprovação do disparo requer etapa autorizada com o fluxo funcionando em hom.

Terraform fmt/init sem backend/validate, grafo de dependências, validação no mesmo modo offline do CI, renderização dos três JSONs e actionlint 1.7.12/ShellCheck 0.11.0 aprovados localmente, com placeholders sem credenciais reais. Primeiro alerta, templates, recursos dos dashboards, provider, lockfile, backend, variáveis e CI/renderização preservados por checksum (13 arquivos). Evidências locais ignoradas na API: `artifacts/newrelic-notification-alert/`. Nenhuma suíte de telemetria, mock ou script criado. A validação local não comprova aceitação remota da consulta, roteamento ou entrega. **E5 permanece parcial até publicação e comprovação real de disparo, recebimento e encerramento.**

## Alerta de CPU elevada do nó

**19/10/2026 — Terceiro alerta implementado e validado localmente, com publicação conjunta posterior.** CPU média utilizada acima de **80% da CPU alocável** por cinco minutos consecutivos, com condições estáticas habilitadas hom/prd. A referência alocável foi escolhida pelo mantenedor: a capacidade total inclui reservas do Kubernetes e não é o denominador deste alerta. Sem alteração de Collector, instrumentação, recursos AWS, alertas anteriores ou dashboards.

### Consulta e avaliação por nó

`node-cpu-alerts.tf` define a policy **Mecânica — CPU elevada do nó**, com `PER_CONDITION_AND_TARGET`, separando incidentes por condição e nó. Consulta para hom (prd usa seu ambiente e cluster):

```sql
SELECT 100 * average(`k8s.node.cpu.usage`)
  / latest(`k8s.node.allocatable_cpu`)
FROM Metric
WHERE `deployment.environment.name` = 'hom'
  AND `k8s.cluster.name` = 'mecanica-hom-eks'
  AND metricName IN (
    'k8s.node.cpu.usage',
    'k8s.node.allocatable_cpu'
  )
FACET `k8s.node.name`
```

Cada nó usa a CPU média utilizada e o valor de CPU alocável mais recente **da mesma janela de um minuto**. Ambos estão em cores; multiplicar a razão por 100 resulta em percentual. Não somar nós, amostras temporais ou containers como se fossem consumo simultâneo; não usar CPU da API/RDS, requests ou limits. Sem filtro service.name, porque estas métricas Kubernetes não pertencem ao serviço mecanica-api. Sem LIMIT/SINCE/UNTIL/TIMESERIES na condição de streaming.

Não fixar a capacidade em dois cores, reutilizar denominador de janela anterior, preencher ausência com zero/último valor ou limitar o percentual a 100%. Na evidência de hom, 1,93 cores eram alocáveis: 80% corresponde a 1,544 cores; 1,6 cores representa aproximadamente 82,90% alocável, embora represente 80% de dois cores totais. Esta diferença é intencional e não altera os painéis existentes de utilização/alocável em cores.

| Configuração | Valor |
|---|---|
| Severidade | Critical; sem Warning |
| Operador/limiar | above, 80; exatamente 80% não viola |
| Agregação | Janela de 60 s, event_flow, atraso de 60 s |
| Avaliação | threshold_duration=300, ALL; sem janela deslizante |
| Lacunas | fill_option=none, sem preenchimento |
| Expiração | 600 s sem pontos por sinal/faceta |
| Na expiração | Encerrar incidentes existentes, sem abrir por ausência |
| Limite máximo nativo | 30 dias, independente da expiração |

O alerta exige médias de um minuto superiores a 80% durante cinco minutos consecutivos; um pico isolado não basta. Não é a média única de cinco minutos nem garante que todas as amostras instantâneas ficaram acima do limiar. Event flow acompanha a coleta existente de 30 s; transporte, fechamento das janelas e avaliação acrescentam atraso, sem promessa de e-mail imediato.

CPU utilizada ou alocável ausente na janela não produz percentual válido e não conta como zero/minuto saudável. Sem denominador válido, não inventar capacidade. Uma leitura abaixo do limiar interrompe a sequência de violação; nenhuma lacuna é preenchida para manter ou encerrar artificialmente a sequência. Pontos válidos abaixo do limiar podem encerrar pelas regras nativas. **Encerramento por ausência de pontos, fechamento manual ou limite máximo não comprova recuperação.** Ambiente desligado não abre alerta por falta de sinal.

A cobertura não muda: kubeletstats coleta somente o nó em que o Collector executa; k8s_cluster observa alocáveis do cluster, mas capacidade sem uso não cria percentual. Nós transitórios ou expansão permanente não ganham cobertura automaticamente. Não interpretar ausência do alerta como ausência de saturação em nós não cobertos.

### Notificações e investigação

Reutiliza `newrelic_notification_destination.alerts_email` e a variável NEW_RELIC_ALERT_EMAIL existente, sem duplicar destino ou imprimir destinatário nos outputs/resumo. Canal EMAIL/IINT e workflow New Relic exclusivos filtram o ID exato desta policy, notificam somente ACTIVATED/CLOSED e respeitam muting total/parcial. Não há regra de silenciamento ou agendamento novo.

O e-mail inclui condição/ambiente, estado e links para o incidente e o dashboard **Operação da API e Kubernetes**. Identificar o nó pela faceta k8s.node.name no incidente, selecionar o mesmo ambiente/período e comparar uso médio/alocável por janela. Conferir pods e containers do nó, seus usos/requests/limits e atualização das séries; não confundir o denominador do nó com limites dos containers. Usar somente informações técnicas, sem dados de negócio ou mensagens originais de exceção.

No encerramento, conferir a causa antes de declarar recuperação. Ausência de sinal pode significar nó/coleta removidos ou falha de exportação. Não ampliar recursos, alterar IAM/topologia ou executar carga automaticamente para investigar este alerta.

### Publicação conjunta e validação

Acrescenta **5 recursos**: uma policy, duas condições, um canal e um workflow New Relic. Com os dois alertas anteriores ainda não publicados, são **16 criações esperadas neste estágio**, preservando dashboards. Os números das seções anteriores descrevem cada entrega no momento de sua preparação. O PR e a publicação ocorrerão somente após concluir os cinco alertas; os de memória e disponibilidade continuam separados.

`node_cpu_alert_policy_id` e `node_cpu_alert_condition_ids` (hom/prd) passam aos outputs e ao resumo de newrelic-provision. Preservados plano salvo → aprovação → apply exclusivo do plano salvo e conferência sem segundo apply. Publicar a definição independe de manter o ambiente ligado; verificar os valores e o disparo depende de dados reais retidos/novos e de etapa autorizada.

Conferência local concluída: Terraform 1.15.9 fmt/init sem backend/validate/grafo de dependências e revisão estrutural da consulta/condições, além de actionlint 1.7.12 com ShellCheck 0.11.0 e renderização dos três JSONs. Validate também passou sem valores TF_VAR, como no CI. Os 26 arquivos do baseline permaneceram idênticos por SHA-256, incluindo os dois alertas anteriores, dashboards, Collector, provider/lockfile/backend e CI. Evidências locais ignoradas na API: `artifacts/newrelic-node-cpu-alert/`. Não criar testes de telemetria, scripts, mocks, métricas sintéticas ou carga. Esta conferência não comprova aceitação remota da NRQL, sustentação de cinco minutos, disparo ou entrega.

Após publicação conjunta, conferir condições/facetas/roteamento e plano sem diferenças. Em hom ativo, comparar uso/alocável do mesmo nó/período com a expressão; comprovação de disparo/recebimento ocorrerá sob autorização própria, sem provocar carga nesta implementação. **E5 continua parcial: configuração local preparada, publicação e comprovação operacional pendentes.**

## Alerta de memória elevada do nó

**19/10/2026 — Quarto alerta implementado e validado localmente, com publicação conjunta posterior.** Working set acima de **85% da memória alocável** do nó por cinco minutos, com condições estáticas habilitadas hom/prd. O mantenedor escolheu o denominador alocável; não é a capacidade física total. Sem mudança de Collector, aplicações, recursos AWS, dashboards ou dos três alertas anteriores.

### Consulta e avaliação por nó

`node-memory-alerts.tf` define a policy **Mecânica — Memória elevada do nó**, com `PER_CONDITION_AND_TARGET`, separando incidentes por condição e nó. A consulta usa somente as duas métricas existentes, em bytes, sem service.name da API; prd recebe seu ambiente e cluster:

```sql
SELECT 100 * average(`k8s.node.memory.working_set`)
  / latest(`k8s.node.allocatable_memory`)
FROM Metric
WHERE `deployment.environment.name` = 'hom'
  AND `k8s.cluster.name` = 'mecanica-hom-eks'
  AND metricName IN (
    'k8s.node.memory.working_set',
    'k8s.node.allocatable_memory'
  )
FACET `k8s.node.name`
```

Cada nó usa o working set médio e o valor alocável mais recente **da mesma janela de um minuto**, multiplicando a razão por 100. Não somar nós/pods nem usar memória do processo .NET, requests ou limits como substitutos. Memória disponível, working set e alocável têm definições distintas: não obter o numerador subtraindo memória disponível da alocável. Não fixar denominador, carregar capacidade de janela anterior, preencher ausência com zero/último valor ou limitar resultados superiores a 100%. Não usar LIMIT/SINCE/UNTIL/TIMESERIES na consulta de streaming.

| Configuração | Valor |
|---|---|
| Severidade | Critical; sem Warning |
| Operador/limiar | above, 85; exatamente 85% não viola |
| Agregação | Janela de 60 s, event_flow, atraso de 60 s |
| Avaliação | threshold_duration=300, ALL; sem janela deslizante |
| Lacunas | fill_option=none, sem preenchimento |
| Expiração | 600 s sem pontos por sinal/faceta |
| Ao expirar | Encerrar incidentes existentes, sem abrir por ausência |
| Limite máximo nativo | 30 dias, independente da expiração |

Exige médias de um minuto superiores a 85% por cinco minutos consecutivos. Um pico isolado ou uma média única de cinco minutos não são a regra. Isso não garante que todas as amostras instantâneas estiveram acima de 85%. Event flow acompanha a coleta atual de 30 s; transporte, fechamento de janela e avaliação acrescentam atraso, sem promessa de e-mail imediato.

Working set ausente ou denominador ausente/inválido não produz percentual válido, não vira zero e não conta como minuto saudável. Não preencher lacunas para manter ou encerrar artificialmente a sequência. Pontos válidos abaixo do limiar podem encerrar pelo comportamento nativo. **Encerramento por expiração, fechamento manual ou limite máximo não comprova recuperação.** Ambiente desligado não abre alerta por falta de sinal.

Kubeletstats continua cobrindo somente o nó onde o Collector executa; a existência de alocáveis de outros nós não produz uso/percentual para eles. Nós transitórios ou expansão permanente não ganham cobertura automaticamente. Não interpretar ausência de alerta como ausência de saturação em nós sem coleta.

### Notificações e investigação

Reutiliza o destino EMAIL existente e NEW_RELIC_ALERT_EMAIL, sem novo destinatário ou variável. Canal EMAIL/IINT e workflow New Relic próprios filtram o ID exato desta policy, notificam somente ACTIVATED/CLOSED e respeitam muting total/parcial. Sem novas regras de silenciamento, agendamentos ou correção automática.

O e-mail inclui condição/ambiente, estado e links do incidente e do dashboard **Operação da API e Kubernetes**. Identificar o nó pela faceta k8s.node.name no incidente; selecionar o mesmo ambiente/período e comparar working set médio com alocável de cada janela. Conferir pods, containers, reinícios e condição MemoryPressure. **Percentual elevado não comprova OOM nem MemoryPressure**; investigar essas condições separadamente, sem confundir uso do nó com request/limit de container. Não incluir dados de negócio ou mensagens originais de exceção.

No encerramento, verificar se houve leituras abaixo do limiar, expiração, limite máximo ou fechamento manual. Ausência de sinal pode ser ambiente/coleta removidos ou falha de exportação; não declarar recuperação somente pelo fechamento. Não provocar pressão de memória, ampliar recursos ou alterar topologia/IAM automaticamente.

### Publicação conjunta e validação

Acrescenta **5 recursos**: uma policy, duas condições, um canal e um workflow New Relic. Com os três alertas anteriores ainda não publicados, são **21 criações esperadas neste estágio**, preservando os dashboards. As contagens das seções anteriores descrevem o momento de cada entrega. O mantenedor concluirá o quinto alerta antes do PR e da publicação conjunta.

Outputs `node_memory_alert_policy_id` e `node_memory_alert_condition_ids` (hom/prd) entram no resumo de newrelic-provision sem destinatário. Preservados plano → aprovação → apply exclusivo do plano salvo e conferência sem segundo apply. Publicação da configuração independe de ambiente ativo; medição/disparo reais dependem de dados e etapa autorizada posterior.

Conferência local concluída: Terraform 1.15.9 fmt/init sem backend/validate/grafo e validate no mesmo modo do CI sem valores TF_VAR, revisão de filtros/faceta/unidades e operador above 85/ALL por 300 s, actionlint 1.7.12 com ShellCheck 0.11.0 e renderização dos três JSONs. Os 27 arquivos conferidos por SHA-256 permaneceram idênticos, incluindo os três alertas anteriores, dashboards, Collector, provider/lockfile/backend e CI. Evidências locais ignoradas na API: `artifacts/newrelic-node-memory-alert/`. Não criar testes de telemetria, mocks, scripts, métricas sintéticas ou carga; validação local não comprova disparo/entrega no serviço.

Após publicação conjunta, conferir condições, facetas, roteamento e plano sem diferenças. Com hom ativo, comparar percentual com working set/alocável do mesmo nó e período. Comprovação de sustentação do limiar, disparo e recebimento requer etapa autorizada própria; não provocar pressão de memória nesta implementação. **Configuração preparada localmente; publicação e comprovação operacional continuam pendentes, E5 parcial.** O alerta de disponibilidade será outra entrega.

## Alerta de API sem réplica disponível

**19/10/2026 — Quinto alerta implementado e validado localmente, sem publicação ou indisponibilidade induzida.** Policy **Mecânica — API sem réplica disponível**, PER_CONDITION, com condições estáticas habilitadas hom/prd. Fonte exclusiva: k8s.deployment.available do Deployment default/deploy-gerenciamento-api no cluster do ambiente. Não há alteração de aplicações, HPA, Collector ou recursos AWS.

### Consulta e avaliação

`api-availability-alerts.tf` usa a consulta abaixo; prd substitui ambiente e cluster pelos correspondentes. Sem FACET, pois a consulta já seleciona um único Deployment por condição; não somar outros Deployments, pods, versões ou amostras:

```sql
SELECT max(`k8s.deployment.available`)
FROM Metric
WHERE metricName = 'k8s.deployment.available'
  AND `deployment.environment.name` = 'hom'
  AND `k8s.cluster.name` = 'mecanica-hom-eks'
  AND `k8s.namespace.name` = 'default'
  AND `k8s.deployment.name` = 'deploy-gerenciamento-api'
```

O máximo em cada janela de um minuto evita classificar como totalmente sem réplicas uma janela que contenha qualquer amostra de pelo menos uma réplica disponível. Não usar average/latest/min nem filtrar a consulta por valor zero antes da agregação: isso mudaria o tratamento de uma recuperação dentro da janela. Réplicas desejadas não são filtro; escala intencional para zero também pode disparar, conforme decisão do mantenedor. Logs, spans, códigos HTTP e volume de requisições não substituem esta métrica.

| Configuração | Valor |
|---|---|
| Severidade | Critical; sem Warning |
| Operador/limiar | below, 1; uma réplica disponível não viola |
| Agregação | Janela de 60 s, event_flow, atraso de 60 s |
| Avaliação | threshold_duration=120, ALL; sem janela deslizante |
| Lacunas | fill_option=none; sem preencher ausência com zero/último valor |
| Expiração | 600 s sem pontos |
| Ao expirar | Encerrar incidentes existentes, sem abrir por ausência |
| Limite máximo nativo | 30 dias, independente da expiração |

Exige duas janelas consecutivas cujo máximo observado seja zero, não uma amostra isolada. A coleta periódica de 30 s não comprova o estado em todos os instantes entre amostras. Transporte, fechamento de janela e avaliação acrescentam atraso: não prometer e-mail exatamente dois minutos após a primeira falha.

**Ausência de métrica não é zero.** Se o Deployment, cluster ou Collector forem removidos, ou a exportação parar, este alerta não detectará necessariamente a indisponibilidade. Sem preenchimento artificial, uma janela ausente não é janela saudável nem medição de zero. Um incidente existente poderá encerrar por expiração; isso, fechamento manual ou limite máximo não comprova recuperação. Pontos válidos fora do limiar podem encerrar conforme as regras nativas. Uma réplica disponível não comprova funcionamento ponta a ponta da API/Gateway/banco.

### Notificação, manutenção e investigação

Reutiliza o destino EMAIL e NEW_RELIC_ALERT_EMAIL existentes. Canal EMAIL/IINT e workflow New Relic próprios filtram o ID exato da policy, notificam ACTIVATED/CLOSED e respeitam muting total/parcial. Outputs api_availability_alert_policy_id e api_availability_alert_condition_ids (hom/prd) entram no resumo de newrelic-provision sem expor o destinatário. Sem novos inputs, variáveis, workflows GitHub, regras de silenciamento ou recuperação automática.

O e-mail inclui condição/ambiente, estado e links do incidente e dashboard **Operação da API e Kubernetes**. Conferir o Deployment exato, réplicas desejadas/disponíveis, estado dos pods, readiness, reinícios e eventos no mesmo ambiente/período. Investigar o problema antes de alterar recursos; o alerta não executa restart, escala ou reparo. Não enviar dados de negócio, credenciais ou mensagens originais de exceção nos diagnósticos.

Durante manutenção planejada, o mantenedor deverá silenciar manualmente as notificações no New Relic antes da intervenção e reativá-las ao encerrar a manutenção. Não desabilitar condições ou alterar réplicas para implementar o alerta; silenciamento pode suprimir notificação sem impedir a detecção/criação do incidente. Não criar agenda ou vincular execução de destroy/deploy a esse controle nesta entrega. Sem silenciamento, zero intencional por dois minutos pode gerar incidente/e-mail.

### Validação e comprovação posterior

Validações locais aprovadas: Terraform 1.15.9 fmt/init sem backend/validate/grafo e validate como CI sem valores TF_VAR, revisão estrutural de filtros/max/below 1/ALL por 120 s, ausência de filtro por desejadas e de preenchimento. Actionlint 1.7.12 com ShellCheck 0.11.0 e renderização dos três JSONs aprovados. Os 28 arquivos do baseline permaneceram idênticos por SHA-256, incluindo quatro alertas anteriores, templates, recursos dos dashboards, Collector, provider/lockfile/backend, variáveis e CI. Evidências locais ignoradas na API: `artifacts/newrelic-api-availability-alert/`. Não criar suíte de telemetria, mocks, scripts, métricas sintéticas ou indisponibilidade real. A conferência local não comprova aceitação remota da NRQL, disparo ou entrega.

Após publicação conjunta, conferir condições, roteamento, silenciamentos e plano sem diferenças. Em etapa separada autorizada com hom ativo, comprovar zero réplicas → métrica → incidente → e-mail, depois restaurar a configuração operacional e conferir encerramento. Qualquer intervenção deverá considerar o HPA existente; não escalá-lo ou alterar suas regras automaticamente como parte desta implementação. Ausência por exclusão do Deployment não será aceita como prova da condição de zero réplicas. Publicação/disparo/recebimento e disponibilidade real permanecem pendentes, E5 parcial.

## Cinco alertas — consolidação e publicação

Os cinco alertas estão definidos localmente, cada um com policy/canal/workflow New Relic próprios e condições hom/prd, compartilhando um único destino de e-mail. Os registros anteriores de contagens/preparação permanecem históricos; esta seção consolida a sequência atual.

| Alerta | Regra Critical | Dashboard para investigação |
|---|---|---|
| Falha técnica de processamento de OS | Soma >=1 em 300 s, event_timer 60 s, AT_LEAST_ONCE | Ordens de serviço |
| Falha de notificação de OS | Soma de outcome=failure >=1 em 300 s, event_timer 60 s, AT_LEAST_ONCE | Integrações e autenticação |
| CPU elevada do nó | CPU média usada / alocável >80%, janelas de 60 s/event_flow, ALL por 300 s, por nó | Operação da API e Kubernetes |
| Memória elevada do nó | Working set médio / alocável >85%, janelas de 60 s/event_flow, ALL por 300 s, por nó | Operação da API e Kubernetes |
| API sem réplica disponível | Máximo de réplicas disponíveis <1, janelas de 60 s/event_flow, ALL por 120 s | Operação da API e Kubernetes |

Todos usam fill_option=none; expiração de 600 s fecha incidentes sem abrir por ausência, com limite máximo nativo de 30 dias. Somente ACTIVATED/CLOSED; respeitar muting. Silêncio/encerramento não provam recuperação. Destinatário por NEW_RELIC_ALERT_EMAIL já cadastrada, sem endereço pessoal versionado ou no resumo; o valor sensível continua presente no estado/plano binário protegidos. Cada runbook documenta sua interpretação e seus limites.

1. Com a implementação dos cinco concluída, o mantenedor publica o PR e promove à main. O assistente não cria PR/commit ou executa publicação automaticamente.
2. Executar **newrelic-provision** e revisar o plano salvo completo: esperado **26 recursos novos** — cinco policies, dez condições, um destino, cinco canais e cinco workflows New Relic — preservando os três dashboards. Não há recursos AWS nesta unidade. Se houver estado/configuração divergente, revisar antes de aprovar, sem forçar a contagem.
3. Aprovar e aplicar exclusivamente o plano salvo; o workflow mantém o SHA, artefato e backend existentes. Conferência posterior deve terminar sem diferenças, sem segundo apply.
4. Conferir no New Relic as dez condições habilitadas, cinco policies, filtros de roteamento, destinatário, confirmações exigidas pelo serviço, gatilhos, muting e links de investigação. Não enviar mensagens de teste automaticamente.
5. Planejar e autorizar separadamente as comprovações reais em hom: gerar sinais controlados, verificar incidentes/e-mails e encerramento, preservando/restaurando a operação. Não provocar falhas, carga, pressão de memória ou indisponibilidade durante esta implementação.

Não é necessário subir API/Lambda/banco/Gateway para publicar a configuração. Não confundir os e-mails de alerta do New Relic com notificações simuladas da API. **Cinco alertas preparados localmente; publicação e comprovação operacional pendentes, E5 parcial.**


## Acessos técnicos PostgreSQL, SSM e Secrets Manager — E5.8

O dashboard de integrações recebe quatro painéis para mecanica.integrations.operations: última amostra por serviço/integração, operações concluídas, falhas/timeouts por operação e percentual de falhas. Reutiliza hom/prd, Account ID, estado persistente e o newrelic-provision. Operação/ordens e os cinco alertas permanecem intactos; publicação esperada altera somente o dashboard existente, sem recursos novos ou mudanças AWS.

Contador Mecanica.Integrations produzido pela Infrastructure da API e da autenticação. Cada ponto representa um acesso técnico concluído: aquisição lógica de conexão (inclusive pool), chamada Dapper, begin/commit/rollback, GetParameters em lote ou GetSecretValue. AWS incorpora o resultado final das retentativas internas; não conta tentativas físicas. Configuração inválida após uma resposta válida não transforma aquela chamada em falha de transporte. Uma falha SQL pode resultar em conflito HTTP; não equivale necessariamente a HTTP 500 ou banco indisponível.

Os painéis principais incluem purpose application/bootstrap e service.name mecanica-api/mecanica-auth. Percentual: (failure + timeout) / (success + failure + timeout), excluindo cancelamentos e mantendo nulo sem denominador. Readiness e consultas do histórico para telemetria ficam separados; cancelamentos originados no orçamento global da Lambda permanecem canceled neste contador, enquanto a métrica da invocação classifica o timeout do handler. Somente integration/operation/purpose/outcome de conjuntos definidos, sem SQL, ARNs, conteúdo de Secrets ou mensagens de exceção.

API antecipa um único provider de métricas antes das chamadas AWS e o reutiliza no host, com encerramento nativo de até 3.000 ms. Lambda mantém provider e flush atuais. Nenhuma garantia de entrega em falha fatal, encerramento abrupto ou Collector indisponível; sem replay, persistência ou recuperação automática. A leitura da License Key pelo Collector não é medida pela aplicação. A implementação não cria instrumentação de SMTP na AWS nem alerta adicional.

Consultas auxiliares de diagnóstico, substituindo o ambiente se necessário:

```sql
SELECT sum(`mecanica.integrations.operations`)
FROM Metric
WHERE metricName = 'mecanica.integrations.operations'
  AND `service.name` IN ('mecanica-api', 'mecanica-auth')
  AND `deployment.environment.name` = 'hom'
  AND purpose IN ('readiness', 'telemetry')
FACET `service.name`, integration, operation, purpose, outcome
LIMIT 100
```

```sql
SELECT sum(`mecanica.integrations.operations`)
FROM Metric
WHERE metricName = 'mecanica.integrations.operations'
  AND `service.name` IN ('mecanica-api', 'mecanica-auth')
  AND `deployment.environment.name` = 'hom'
  AND outcome = 'canceled'
FACET `service.name`, integration, operation, purpose
LIMIT 100
```

Respeitar o seletor global nos widgets; consultas diretas podem usar a janela selecionada pelo Query Builder. Nenhum preenchimento de lacunas ou reconstrução de dados antigos. Após os PRs: api-deploy, auth-publish/provision e atualização do Gateway para a nova versão, publicação do dashboard e conferência de séries reais em hom. Campos prd sem dados não comprovam operação. Falhas controladas e comprovação dos cinco alertas dependem de autorização separada. E5.8 permanece parcial até validar os novos sinais no New Relic.

### Validação local de 19/10/2026

Build Release e publish da API/Lambda aprovados; Lambda conferida com SDK 10.0.402, RID linux-x64 e self-contained=false. Certificado RDS, manifesto com o novo meter, dependências/runtimeconfig e ZIP local conferidos, sem exporter de teste. SAM validate --lint/build aprovados; Kustomize hom/prd renderizado. Terraform fmt/init sem backend/validate e template renderizado como JSON válido; quatro painéis adicionados sem sobreposição e sem alterar os outros dashboards, cinco alertas ou lockfile.

Regressão completa concluída após o mantenedor abrir o Docker: **1.187 testes API e 245 testes Lambda aprovados, zero falhas e zero ignorados**, sem filtros. Inclui PostgreSQL/Testcontainers, abertura/consulta, consulta sem resultado, erro de domínio fora da medição SQL, commit/rollback, readiness, histórico de telemetria e lookup da autenticação. Os novos cenários passaram sem ajustes adicionais de código. A execução anterior sem Docker (1.021/205 testes) foi parcial e está substituída por esta conferência completa. Não houve inicialização automática do Docker.

OpenAPI idêntico: SHA-256 D784C3B554A65C4F8CFE732C0975B8BFEDAF78D67F9C6ED69E2B07220C5F5D84. Avisos anteriores de dependências/analisadores permanecem. Evidências locais em artifacts/e5-integrations na API e na autenticação. Nenhum workflow remoto, deploy, consulta AWS ou publicação New Relic foi executado. E5.8 permanece parcial.
