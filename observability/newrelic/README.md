# Dashboard persistente de operação — New Relic

Unidade Terraform independente da base, Gateway e bootstrap. Define **Mecânica — Operação da API e Kubernetes**, uma página com 20 painéis de consulta e dois blocos de orientação. Fonte: `dashboards/operations.json.tftpl`; recurso `newrelic_one_dashboard_json.operations`.

**Estado da entrega:** definição e consultas históricas validadas em 18/10/2026. Dashboard ainda não publicado; plano remoto, apply e conferência visual dependem de autorização posterior. Não há workflow novo nem inclusão nos workflows existentes.

## Identidade, propriedade e estado

- Terraform `~> 1.15.0` (validação com 1.15.9); provider `newrelic/newrelic 3.99.3`, lockfile Windows/Linux.
- Região New Relic `US`; `new_relic_account_id` obrigatório e positivo. `terraform.tfvars.example` contém o Account ID não secreto 8626152.
- Variável do dashboard `environment`: lista hom/prd, seleção única, padrão hom. É filtro de visualização; não fornece isolamento de acesso. Não excluir o filtro ao comparar ambientes.
- Permissão `PUBLIC_READ_ONLY`: leitura pelos usuários autorizados da conta; edição pelo proprietário. Não configura acesso público pela internet, links públicos ou compartilhamento externo.
- Backend S3 existente `mecanica-tfstate-121754142617-us-east-1`, chave `shared/newrelic/terraform.tfstate`, região us-east-1, criptografia e lockfile nativo. Somente workspace default. Nenhuma leitura de estados externos.
- O dashboard tem `prevent_destroy=true`. Os destroys AWS não alcançam esta unidade. Não executar destroy, remover proteção ou apagar o objeto de estado como parte do descarte de hom/prd.
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

Usar workspace default e revisar Account ID/credencial antes do plano. A primeira publicação deve propor **um dashboard criado**, sem mudanças AWS. `tfplan` é local/ignorado. Encerrar a sessão ou remover a variável ao terminar; ela precisará ser fornecida novamente se o apply ocorrer em outro processo.

**Parar para revisão do plano salvo.** Somente após sua aprovação, no mesmo checkout e unidade, com credenciais válidas no processo:

```powershell
terraform apply tfplan
terraform output -raw operations_dashboard_guid
terraform output -raw operations_dashboard_permalink
terraform plan -var-file=terraform.tfvars -detailed-exitcode
```

O último comando deve retornar código 0/nenhuma alteração; código 2 indica diferenças, não autorização para aplicar outro plano. Conferir layout, filtro hom/prd, período, unidades e ausência de dados na interface. Não importar/publicar o JSON manualmente em paralelo ao Terraform. Limpar a variável ao encerrar:

```powershell
Remove-Item Env:NEW_RELIC_API_KEY
```

## Painéis e semântica

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

## Referências

- [Provider 3.99.3 — recurso JSON](https://github.com/newrelic/terraform-provider-newrelic/blob/v3.99.3/newrelic/resource_newrelic_one_dashboard_json.go)
- [Exemplos de widgets/variáveis da mesma versão](https://github.com/newrelic/terraform-provider-newrelic/blob/v3.99.3/newrelic/resource_newrelic_one_dashboard_json_test.go)
- [Dashboards com Terraform e templates JSON](https://newrelic.com/blog/infrastructure-monitoring/create-nr-dashboards-with-terraform-part-1)
- [Variáveis nativas do dashboard](https://docs.newrelic.com/docs/query-your-data/explore-query-data/dashboards/dashboard-template-variables/)
- [Métricas OpenTelemetry no New Relic](https://docs.newrelic.com/docs/opentelemetry/best-practices/opentelemetry-best-practices-metrics/)
- [NRQL: percentis, campos compostos e funções](https://docs.newrelic.com/docs/nrql/nrql-syntax-clauses-functions/)
- [Coleta e consultas Kubernetes](../../docs/COLLECTOR_API.md)
- [Validação da correlação/API em hom](https://github.com/pknfelps/GerenciamentoMecanicaSistema/blob/develop/docs/VALIDACAO_CORRELACAO_HOM_2026-10-18.md)
