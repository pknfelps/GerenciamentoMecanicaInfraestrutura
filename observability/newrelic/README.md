# Dashboards persistentes — New Relic

Unidade Terraform independente da base, Gateway e bootstrap. Define **Mecânica — Operação da API e Kubernetes**, uma página com 20 painéis de consulta e dois blocos de orientação. Fonte: `dashboards/operations.json.tftpl`; recurso `newrelic_one_dashboard_json.operations`. Acrescenta **Mecânica — Ordens de serviço**, uma página com 15 consultas e dois blocos de orientação, em `dashboards/orders.json.tftpl`/`newrelic_one_dashboard_json.orders`. Acrescenta **Mecânica — Integrações e autenticação**, uma página com 24 consultas/dois textos, em `dashboards/integrations.json.tftpl`/`newrelic_one_dashboard_json.integrations`. Cada dashboard tem seu próprio filtro hom/prd.

**Estado da entrega:** definição e consultas históricas validadas em 18/10/2026. Dashboards ainda não publicados; plano remoto, apply e conferência visual dependem de autorização posterior. Não há workflow novo nem inclusão nos workflows existentes.

## Identidade, propriedade e estado

- Terraform `~> 1.15.0` (validação com 1.15.9); provider `newrelic/newrelic 3.99.3`, lockfile Windows/Linux.
- Região New Relic `US`; `new_relic_account_id` obrigatório e positivo. `terraform.tfvars.example` contém o Account ID não secreto 8626152.
- Variável do dashboard `environment`: lista hom/prd, seleção única, padrão hom. É filtro de visualização; não fornece isolamento de acesso. Não excluir o filtro ao comparar ambientes.
- Permissão `PUBLIC_READ_ONLY`: leitura pelos usuários autorizados da conta; edição pelo proprietário. Não configura acesso público pela internet, links públicos ou compartilhamento externo.
- Backend S3 existente `mecanica-tfstate-121754142617-us-east-1`, chave `shared/newrelic/terraform.tfstate`, região us-east-1, criptografia e lockfile nativo. Somente workspace default. Nenhuma leitura de estados externos.
- Os três dashboards têm `prevent_destroy=true`. Os destroys AWS não alcançam esta unidade. Não executar destroy, remover proteção ou apagar o objeto de estado como parte do descarte de hom/prd.
- Todos os mantenedores usam o mesmo backend/Account ID. Não inicializar estados locais paralelos para publicar cópias. GUID e permalink são os únicos outputs.
- Mudanças seguem PR e plano salvo. Edição manual no console causa divergência; refletir a mudança no template ou revisar o próximo plano antes de aplicar. Não importar exports com GUIDs/IDs de páginas/widgets como fonte de uma criação nova.

## Credenciais

A **User API Key** administra dashboards e é diferente da **Ingest - License Key**, usada pelos Collectors para enviar telemetria. Esta unidade não lê o Secret de ingestão nem modifica IAM/Secrets Manager.

O mantenedor deve obter uma User API Key de um usuário autorizado a criar/atualizar dashboards na conta escolhida. Fornecer somente ao processo local por `NEW_RELIC_API_KEY`. Não enviar a chave no chat, versionar, colocar em tfvars/backend, usar `-var`, imprimir o ambiente ou ativar `TF_LOG` durante operações autenticadas.

A autenticação AWS é usada somente pelo backend S3, com a cadeia padrão de credenciais local e acesso ao objeto de estado/lock. Não há provider AWS nesta unidade, role nova ou mudança de permissões. Se o perfil escolhido não tiver acesso, interromper e revisar a identidade; não alterar policies automaticamente.

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

## Publicação posterior — somente após autorização

Não é necessário subir API, Lambda, banco ou Gateway para publicar o dashboard ou consultar dados históricos ainda retidos. Preparar autenticação AWS local e a User API Key. Em PowerShell 7, a leitura mascarada abaixo evita incluir o valor no histórico do comando:

```powershell
$env:NEW_RELIC_API_KEY = Read-Host 'New Relic User API Key' -MaskInput
Copy-Item terraform.tfvars.example terraform.tfvars
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
