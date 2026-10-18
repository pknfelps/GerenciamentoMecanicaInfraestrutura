# CloudWatch pelo Collector Kubernetes — E5

## Estado e composição

**18/10/2026 — preparado e validado localmente para hom/prd.** Implantação, coleta AWS e ingestão dessas novas séries/logs ainda não comprovadas. E5.14 permanece parcial. A validação anterior de OTLP, Kubernetes e X-Ray em hom continua válida no seu próprio escopo.

O Collector Contrib `0.161.0` existente recebe duas instâncias de `aws_cloudwatch` (logs/métricas alpha). `logs/cloudwatch` e `metrics/cloudwatch` reutilizam memory_limiter, batch e exporter New Relic. Não passam por k8sattributes/resource/cluster; não recebem a identidade da API ou do pod coletor.

A configuração é composta pelos argumentos nativos:

```text
--config=/etc/otelcol-contrib/collector.yaml
--config=/etc/otelcol-contrib/collector-cloudwatch.yaml
```

`base/collector.yaml` contém consultas, transformações e pipelines comuns. Cada overlay acrescenta ao ConfigMap estável um pequeno `collector-cloudwatch.yaml` com o grupo de logs literal do ambiente. Isso evita interpolar variáveis em chaves de mapas YAML, que o resolvedor não expande. Somente os overlays hom/prd são implantáveis; a base é o componente comum. Não há geração de YAML por script.

Os manifestos declaram `AWS_REGION`, `DEPLOYMENT_ENVIRONMENT`, `GATEWAY_NAME`, `AUTH_FUNCTION_NAME` e `DATABASE_INSTANCE_IDENTIFIER`. Nomes previsíveis dispensam descoberta, SSM, acesso ao estado de outros repositórios ou dependência Terraform da base para consumidores. Grupo ainda inexistente pode gerar diagnóstico de coleta; métricas de recursos ausentes não são preenchidas com zero.

Preservados imagem, uma réplica/Recreate, requests 100m CPU/128Mi, limits 500m CPU/256Mi, GOMEMLIMIT 192MiB, probes, RBAC, Pod Identity, Secret e exportador. A carga adicional precisa de conferência em hom, antes de qualquer redimensionamento.

## Logs do Gateway

- Grupo exclusivo `/aws/apigateway/mecanica-<ambiente>-gateway`, todos os seus streams, sem autodiscovery.
- Polling de 60 segundos, `initial_lookback: 5m`, até 1.000 eventos por solicitação e paginação nativa. O limite é por página, não por ciclo completo.
- Sem `storage`, `start_from`, volume, deduplicação, fila persistente ou mecanismo próprio de recuperação. A posição vive na memória do processo; cada inicialização relê os últimos cinco minutos.
- Transformação nativa conserva somente `requestId`, `extendedRequestId`, `xrayTraceId`, `method`, `route`, `status`, `durationMs`, `integrationMs` e `responseLength`, além do atributo nativo `id` do evento CloudWatch. Status/tamanho são inteiros; durações são números em milissegundos. Valores não convertíveis, como `-`, são omitidos.
- Corpo exportado fixo: **Requisição processada pelo Gateway.** O JSON original não é exportado. Somente objetos JSON válidos passam pelo filtro. Campos extras são descartados; não coletar payload, query ou headers.
- Parsing/conversão usam `error_mode: silent` para evitar que o erro inclua conteúdo do registro. JSON inválido é descartado por `filter/gateway`; seu diagnóstico técnico é a contagem interna nativa `otelcol_processor_filter_logs_filtered`, identificada pelo processor, sem log do conteúdo ou da exceção de parsing. A configuração não exporta novas métricas internas nem cria um log por descarte. Não habilitar debug de OTTL para inspecionar entradas reais.
- Recursos: `service.name=mecanica-gateway`, `deployment.environment.name`, `cloud.provider=aws`, `cloud.account.id=121754142617`, `cloud.region=us-east-1`, grupo/stream nativos (`cloudwatch.log.group.name`, `cloudwatch.log.stream`; receiver também fornece `aws.region`). `xrayTraceId` é um atributo próprio: não é convertido para TraceId OTLP nem comprova correlação W3C/X-Ray.

O Gateway continua com execution logs **OFF**, `data_trace_enabled=false` e retenção de sete dias. Logs de aplicação da API/Lambda continuam exclusivamente pelos caminhos OTLP existentes.

### Retomada e perdas aceitas

O lookback aplica-se somente à inicialização, não é uma janela sobreposta repetida a cada polling. Reinícios podem duplicar eventos da janela; indisponibilidade superior a cinco minutos pode deixar lacunas. Eventos publicados tardiamente também podem ficar fora da posição já avançada. Recebimento pelo Collector não comprova entrega ao New Relic: fila cheia, falha de exportação ou encerramento abrupto podem perder sinais. Não há garantia de entrega única ou recuperação completa.

Na análise estática de `logsReceiver.poll`/`persister.go` da versão 0.161.0, o checkpoint é atualizado mesmo após erro de polling. Com armazenamento persistente, o próximo ciclo pode usar essa posição e pular um intervalo que falhou; persistência não assegura recuperação. Não foi reproduzido esse erro na AWS, não foi corrigido o receiver e não há fork. A escolha vigente é **não configurar armazenamento**, aceitando os limites acima.

## As 13 métricas

Polling e período de 60 segundos; atraso explícito de dez minutos para publicação CloudWatch. Sem discovery/ListMetrics ou backfill. Cada consulta solicita uma estatística, produzindo **Gauge por período** com `stat`; não são contadores cumulativos nem Summaries. Nomes nativos: `amazonaws.com/<namespace>/<métrica>`.

| Namespace | Métrica | stat | Unidade |
|---|---|---|---|
| AWS/ApiGateway | Count | SampleCount | Contagem (`1`) |
| AWS/ApiGateway | 4XXError | Sum | Contagem (`1`) |
| AWS/ApiGateway | 5XXError | Sum | Contagem (`1`) |
| AWS/ApiGateway | Latency | Average | Milissegundos (`ms`) |
| AWS/ApiGateway | IntegrationLatency | Average | Milissegundos (`ms`) |
| AWS/Lambda | Invocations | Sum | Contagem (`1`) |
| AWS/Lambda | Errors | Sum | Contagem (`1`) |
| AWS/Lambda | Throttles | Sum | Contagem (`1`) |
| AWS/Lambda | Duration | Average | Milissegundos (`ms`) |
| AWS/Lambda | ConcurrentExecutions | Maximum | Contagem (`1`) |
| AWS/RDS | CPUUtilization | Average | Percentual (`%`) |
| AWS/RDS | FreeableMemory | Average | Bytes (`By`) |
| AWS/RDS | DatabaseConnections | Average | Contagem (`1`) |

A transformação declara essas unidades, ausentes na conversão nativa do receiver. Achata somente `ApiName`, `Stage`, `FunctionName` e `DBInstanceIdentifier`, preservando `Namespace`, `MetricName` e `stat`, e remove o mapa `Dimensions`. Atributos escalares são compatíveis com o transporte de métricas ao New Relic.

Dimensões consultadas:

- Gateway: `ApiName=mecanica-<ambiente>-gateway` e `Stage=<ambiente>`. Métricas básicas, sem habilitar métricas detalhadas por método. `Count` usa **SampleCount**, conforme a definição do Gateway.
- Lambda: `FunctionName=mecanica-<ambiente>-auth`, agregando versões da função; não fixar versão numérica.
- RDS: `DBInstanceIdentifier=mecanica-<ambiente>-postgres`.

Recursos CloudWatch recebem conta, região, provider e ambiente; métricas não recebem `service.name=mecanica-api`. CPU RDS não é CPU de nó, e duração Lambda não substitui a duração medida pelo handler. Ausência de série não é zero. Média das médias de minutos não é média ponderada por invocações; máximos de concorrência devem ser comparados com `Maximum`.

## IAM e ordem de aplicação

`terraform/collector-runtime.tf` administra a nova policy inline `read-cloudwatch` da role `mecanica-<ambiente>-collector-runtime`:

- `logs:FilterLogEvents` somente em `arn:aws:logs:us-east-1:121754142617:log-group:/aws/apigateway/mecanica-<ambiente>-gateway:*`.
- `cloudwatch:GetMetricData`, `Resource="*"`, condicionado a `aws:RequestedRegion=us-east-1`.

A leitura de métricas clássicas não tem isolamento IAM por recurso/ambiente: a role pode consultar outras métricas da conta nessa região. O YAML seleciona somente recursos do ambiente. Não há ListMetrics, DescribeLogGroups/Streams, escrita CloudWatch ou acesso novo a Secrets. A confiança e a associação Pod Identity existentes são preservadas.

O bootstrap já permite à pipeline da base administrar policies inline dessa role; **não precisa de alteração ou apply adicional**. Terraform só usa nomes determinísticos, sem consultar os consumidores. A role depende das policies antes de sua associação inicial. A política é removida com a base; não é persistente no bootstrap.

Após os PRs, executar **somente base-provision**: plan salvo → aprovação → apply do plano aprovado → aplicação do overlay → restart/rollout existentes. Esperado: nova policy e descrição da role atualizada, sem substituição de VPC/EKS/NLB ou alteração de RDS/Lambda/Gateway. Não é necessário deploy API/auth, banco ou Gateway para esta coleta. Workflows e seus inputs permanecem iguais.

## Validação local

Executados Terraform 1.15.9 `fmt -check`, `init -backend=false -lockfile=readonly` e `validate`; renderização dos overlays hom/prd e da raiz; revisão das duas permissões e limites das policies. Ambos os overlays mantêm sete recursos e ConfigMap com dois arquivos.

O comando `validate` do Collector 0.161.0 constrói os componentes com os dois arquivos, incluindo expressões OTTL. Executado com `--network=none`, UID/GID 10001, filesystem readonly, capabilities removidas e limites de recursos existentes. Somente para essa validação: header fictício via `--set`, token fictício montado e CA local do bundle público da imagem para kubeletstats. Não se iniciam receivers/exporters, não se usam Secrets reais e não se altera a configuração de produção.

Conferidas 13 consultas/estatísticas explícitas, unidades/dimensões, grupos hom/prd isolados, lookback de cinco minutos e ausência de persistência/discovery. OTLP, pipeline Kubernetes, exporter, recursos e credencial preservados. Evidências locais ignoradas em `GerenciamentoMecanicaSistema/artifacts/e5-cloudwatch`. Sem scripts operacionais, mocks, suítes de telemetria ou novos steps CI. Não executado plano/apply/destroy AWS nem workflow remoto.

## Conferência posterior em hom

1. Após base-provision, conferir `kubectl -n observability rollout status deployment/otel-collector --timeout=300s`, pods, `kubectl top` e logs limitados. Procurar erros IAM, receiver ou exporter; não expor chave nem habilitar debug dos payloads.
2. Gerar chamadas controladas ao Gateway e comparar CloudWatch/New Relic por `requestId` e `id` do evento. Conferir mensagem fixa, números e ausência de campos extras; API/Lambda não devem aparecer duplicadas por CloudWatch.
3. Aguardar pelo menos o atraso de dez minutos mais os ciclos de coleta/exportação; comparar períodos completos de 60 segundos com a mesma dimensão/stat do CloudWatch. A publicação pode atrasar mais que a janela configurada; não prometer reconsulta de períodos perdidos.
4. Conferir continuidade OTLP, métricas Kubernetes e indicadores de negócio, além de consumo/reinícios do Collector. Problemas exigem diagnóstico antes de ampliar recursos/permissões.
5. Somente mediante autorização, reiniciar o Collector de forma controlada, comparar IDs antes/depois e confirmar releitura dos cinco minutos, aceitando duplicações/lacunas. Não exigir exatamente uma entrega.

Antes de destruir o Gateway, interromper tráfego e confirmar no New Relic a última coleta/exportação, respeitando o atraso das métricas. **O destroy do Gateway exclui seu grupo de logs**; sete dias de retenção valem somente enquanto o grupo existir. A base é destruída depois dos consumidores, quando já não poderá recuperar os logs desse grupo removido. Não foram acrescentadas esperas automáticas/drain nos workflows.

## Consultas NRQL

Selecionar a conta New Relic US 8626152. Trocar hom/nomes por prd quando necessário. Consultas para conferência, não dashboards ou alertas:

```sql
SELECT timestamp, message, id, requestId, extendedRequestId, xrayTraceId,
       method, route, status, durationMs, integrationMs, responseLength
FROM Log
WHERE service.name = 'mecanica-gateway'
  AND deployment.environment.name = 'hom'
  AND cloud.account.id = '121754142617'
  AND cloud.region = 'us-east-1'
SINCE 30 minutes ago LIMIT 100
```

```sql
SELECT uniques(metricName)
FROM Metric
WHERE cloud.account.id = '121754142617'
  AND cloud.region = 'us-east-1'
  AND deployment.environment.name = 'hom'
  AND Namespace IN ('AWS/ApiGateway', 'AWS/Lambda', 'AWS/RDS')
FACET Namespace, stat SINCE 40 minutes ago UNTIL 10 minutes ago
```

```sql
SELECT sum(`amazonaws.com/AWS/ApiGateway/Count`)
FROM Metric
WHERE cloud.account.id = '121754142617'
  AND cloud.region = 'us-east-1' AND deployment.environment.name = 'hom'
  AND ApiName = 'mecanica-hom-gateway' AND Stage = 'hom'
  AND stat = 'SampleCount'
SINCE 40 minutes ago UNTIL 10 minutes ago TIMESERIES 1 minute
```

```sql
SELECT latest(`amazonaws.com/AWS/Lambda/Duration`)
FROM Metric
WHERE cloud.account.id = '121754142617'
  AND cloud.region = 'us-east-1' AND deployment.environment.name = 'hom'
  AND FunctionName = 'mecanica-hom-auth' AND stat = 'Average'
SINCE 40 minutes ago UNTIL 10 minutes ago TIMESERIES 1 minute
```

```sql
SELECT latest(`amazonaws.com/AWS/RDS/CPUUtilization`),
       latest(`amazonaws.com/AWS/RDS/FreeableMemory`),
       latest(`amazonaws.com/AWS/RDS/DatabaseConnections`)
FROM Metric
WHERE cloud.account.id = '121754142617'
  AND cloud.region = 'us-east-1' AND deployment.environment.name = 'hom'
  AND DBInstanceIdentifier = 'mecanica-hom-postgres' AND stat = 'Average'
SINCE 40 minutes ago UNTIL 10 minutes ago TIMESERIES 1 minute
```

Somas de gauges por período pressupõem uma amostra por janela; duplicações podem alterar totais. Para diagnosticar releitura de logs, comparar `count(*)` e `uniqueCount(id)` por grupo/stream, sem deduplicação automática. A verificação definitiva das consultas/atributos e da ingestão ocorrerá após implantação.

## Referências e limites

[Receiver 0.161.0](https://github.com/open-telemetry/opentelemetry-collector-contrib/tree/v0.161.0/receiver/awscloudwatchreceiver), [métricas Gateway](https://docs.aws.amazon.com/apigateway/latest/developerguide/api-gateway-metrics-and-dimensions.html), [escopo IAM de métricas](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/cloudwatch-dashboard-sharing.html) e [limites OTLP New Relic](https://docs.newrelic.com/docs/opentelemetry/best-practices/opentelemetry-otlp/).

E5.14 permanece parcial até implantação e comprovação. Correlação X-Ray/OTLP, dashboards, alertas e recuperação robusta são entregas separadas.
