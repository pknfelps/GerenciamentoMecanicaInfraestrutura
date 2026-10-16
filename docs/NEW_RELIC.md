# New Relic US — API e autenticação

## Estado e propriedade

**Decisão vigente:** New Relic é permanente nos deploys da base e autenticação. Removidos os toggles de workflow e parâmetros SAM; X-Ray continua independente. A configuração local da API e dos testes não foi alterada.

Integração preparada para envio OTLP HTTP/protobuf de traces, métricas e logs para https://otlp.nr-data.net (HTTPS/443). Implementação e testes são locais; nenhuma aplicação AWS ou ingestão New Relic é comprovada por este documento. API → Collector Kubernetes e Lambda → extensão local continuam independentes.

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

A base cria mecanica-<ambiente>-collector-runtime, com Pod Identity do cluster do ambiente para observability/otel-collector. O ServiceAccount continua sem RBAC e automountServiceAccountToken=false; o token específico Pod Identity é entregue pelo EKS, independentemente da montagem automática de credenciais Kubernetes. Role permite somente GetSecretValue no ARN exato do Secret do ambiente. Não concede leitura JWT/banco nem escrita de Secrets.

A role persistente auth-runtime recebe GetSecretValue somente no Secret do ambiente. Extensão e código da Lambda compartilham a role e o processo da função pode acessar esse recurso: não existe isolamento IAM entre eles. As permissões já existentes de JWT/banco não são modificadas.

ConfigMaps, ZIPs, templates, ambientes Lambda e estado/planos Terraform contêm somente nomes/referências públicas, nunca o valor da License Key. Não usar print-config, exporter detailed ou captura de headers com a chave real.

## Ativação e descarte

1. Bootstrap aplicado e chave hom cadastrada.
2. Executar base-provision (develop/hom). O Collector sempre utiliza New Relic. Preserva plan → aprovação → apply do mesmo plano; o preflight ocorre antes do plan e novamente antes do apply. O Secret e sua versão atual são pré-requisitos de toda execução de provisionamento.
3. Executar auth-publish de uma revisão nova, com layer/OpenTelemetry permanentes e o único Function/Observability/collector.yaml de produção.
4. Executar auth-provision com environment=hom, artifact_commit do summary publicado e xray_enabled conforme desejado. OpenTelemetry, layer e New Relic são fixos no SAM; não há inputs ou parâmetros para desligá-los. A pipeline rejeita templates antigos com telemetria condicional; publicar revisão nova.
5. Atualizar o Gateway para consumir a nova revisão/versão numérica auth. Não é necessário novo deploy da API nem reaplicar o banco apenas por essa integração.
6. Com chamadas fictícias controladas, conferir no New Relic mecanica-api/mecanica-auth, versões/ambiente hom, traces/logs correlacionados, métricas técnicas/negócio, sanitização e possíveis NrIntegrationError. Validar também chamadas isoladas e memória/tempo reais da extensão.

New Relic é o destino permanente nos dois ambientes. Não há opção de deploy diagnóstico ou desativação de telemetria na Lambda; os Collectors locais de teste continuam independentes da AWS. Não há fallback para debug quando a chave não puder ser lida. Falha de resolução impede iniciar o Collector; destino indisponível depois de iniciado tem tentativas limitadas e pode perder sinais.

O Collector da API possui somente kubernetes/observability/base e os overlays hom/prd. Um único YAML de produção na base aponta para New Relic; os overlays definem o nome público do Secret do ambiente. Os nomes dos recursos existentes são preservados, sem recriar namespace/Service/Deployment. O restart existente continua necessário para reler o ConfigMap e a chave; pode interromper brevemente a coleta.

Descarte continua Gateway/consumidores → auth/API → banco → base; base-destroy remove kubernetes/observability/<ambiente> pelos mesmos nomes estáveis. Os Secrets e suas versões permanecem no bootstrap. Não limpar versões ou remover a chave no New Relic como parte do destroy dos ambientes.

## Filas e falhas

Kubernetes preserva memory_limiter 128/32 MiB e batch 512/1 s; exporter gzip, timeout 3 s, fila de 100 lotes por sinal, dois consumidores, retries 1–5 s por até 15 s. Sem armazenamento persistente. Probes verificam o processo, não a entrega no New Relic.

Lambda preserva memory_limiter 64/16 MiB e usa decouple por último, fila máxima 20 por pipeline, sem batch periódico. Exporter gzip/timeout 1 s, retries 200–500 ms por até 2 s e sending_queue=false (a extensão já desabilita essa fila). O decouple é específico da extensão e evita esperar a exportação externa na resposta; o tempo faturado pode incluir o trabalho posterior. Flush de aplicação e sua reserva de resposta permanecem os atuais. Não garantir entrega exatamente uma vez ou ausência de perdas em término abrupto, saturação, falhas permanentes ou congelamento.

401 indica autenticação de ingestão inválida; 429 indica limitação; 5xx/timeout podem ser transitórios. Não imprimir chave ou payload para investigar. Falhas de exportação não participam da transação da OS nem devem alterar seu resultado HTTP.

## Rotação e validação local

Para trocar a chave: cadastrar a nova versão no console, manter AWSCURRENT e reiniciar o Collector Kubernetes; publicar/provisionar uma nova revisão numérica da Lambda e atualizar o Gateway. Alterar só o valor do Secret não atualiza processos existentes. Não revogar a chave anterior antes de comprovar os novos consumidores.

Terraform fmt/init sem backend/validate, renderização Kustomize e validação SAM/workflows continuam conferindo a estrutura dos arquivos. Por decisão do mantenedor, foram removidos os testes .NET de conexão com New Relic e Collectors locais, os receptores HTTP fictícios e os steps CI que executavam as imagens para validar o exporter/YAML. Não substituir os cenários por testes ignorados ou mocks novos.

A imagem Contrib 0.151.0 não contém decouple; a layer oficial continua usando esse processor no YAML de produção. Não há overrides de teste ou prova automatizada de transporte. Ingestão, falhas de exportação, ciclo/fila/congelamento e comportamento dos Collectors serão conferidos operacionalmente na AWS. Testes funcionais e de instrumentação/sanitização InMemory permanecem.

Não acrescentados scripts, Operators, agentes, coleta stdout ou duplicação dos exporters. Somente o Compose/local de teste mantém debug, sem AWS/New Relic. Os deploys usam exclusivamente New Relic. Próximas entregas: ingestão comprovada, dashboards/alertas, coleta Kubernetes/CloudWatch e integração X-Ray/New Relic/correlação W3C.

## X-Ray nativo → New Relic — preparação declarativa

Implementação local de 15/10/2026; plano AWS, apply, conexão e ingestão desta integração ainda pendentes. Este caminho é independente do OTLP: o New Relic assume uma role AWS e consulta o X-Ray diretamente. Não passa pelos Collectors, não usa a License Key e não exige User API Key ou provider New Relic.

### Bootstrap e alcance do acesso

`bootstrap/newrelic-xray.tf` declara a role persistente `mecanica-newrelic-xray`, no path `/mecanica/observability/`, e a policy inline `read-regional-xray`. A confiança permite apenas `sts:AssumeRole` pela conta New Relic US `754728514883`, com `sts:ExternalId` exatamente igual a `new_relic_account_id`.

Antes do próximo plano administrativo, informar em `bootstrap.tfvars` o **Account ID do New Relic**, como string numérica positiva. A variável é obrigatória, sem default; o exemplo contém somente um formato fictício comentado. Esse identificador não é secreto. Não alterar o backend nem reutilizar planos anteriores à nova role.

A policy concede somente `xray:Get*` e `xray:BatchGet*`, com `Resource="*"` e `aws:RequestedRegion=us-east-1`. As consultas de traces não aceitam ARN por função/Gateway nem isolamento por ambiente. A role pode ler os traces disponíveis da conta AWS 121754142617 nessa região, inclusive hom/prd quando existirem; filtros do console não são controle de acesso IAM. Não anexar ReadOnlyAccess, Budgets, permissões CloudWatch, Secrets, escrita X-Ray ou administração de outros recursos. A role pertence ao bootstrap compartilhado e permanece após destroy de Gateway, auth, banco ou base.

### Sequência após autorização

1. Preencher `new_relic_account_id`; gerar o plano salvo do bootstrap e revisar. O esperado para esta entrega isolada é somente duas criações (role e policy inline), nenhuma alteração/exclusão de recursos existentes e o novo output `newrelic_xray_role_arn`. Se houver outras mudanças, revisá-las antes de aprovar.
2. Aplicar somente o binário aprovado, conferir trust/policy implantadas e obter o ARN com `terraform output -raw newrelic_xray_role_arn`. Não criar outra role manualmente.
3. No New Relic US, acessar **All capabilities → Infrastructure → AWS**, iniciar a conexão de API polling e usar o nome `mecanica-xray` e o ARN do output. O External ID será o Account ID dessa mesma conta New Relic. Usar a role personalizada existente; não seguir as opções de anexar ReadOnlyAccess ou Budgets do tutorial genérico.
4. Em **Manage services**, habilitar somente **AWS X-Ray**, limitar a `us-east-1` e manter polling em cinco minutos. Não habilitar EC2/EBS, outros serviços ou coleta adicional de tags/IPs. Não fornecer a License Key ou credenciais AWS permanentes. Se a interface ou a verificação exigir permissão além da policy aprovada, registrar o requisito e revisar antes de ampliar o acesso.
5. Para a comprovação em hom, executar `auth-provision` com `xray_enabled=true` e atualizar o Gateway para a nova versão numérica da função. Se for necessária publicação nova, usar `auth-publish` antes. O tfvars hom do Gateway já solicita X-Ray habilitado; mudanças de stage seguem seu plano/aprovação/apply. Prd permanece desabilitado. API e Collectors não exigem alteração por causa dessa integração.
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

**Limite desta entrega:** configuração e procedimento preparados localmente. E5.3/E5.14 continuam parciais: aplicação, ingestão real, conteúdo dos segmentos e correlação W3C/X-Ray precisam ser comprovados; receiver CloudWatch, dashboards e alertas ficam separados. A instrumentação atual continua W3C e mantém extração X-Ray desabilitada. Não executar destroy como teste.

Referências oficiais: [conexão AWS por polling](https://docs.newrelic.com/docs/infrastructure/amazon-integrations/connect/set-up-aws-api-polling/), [integração X-Ray](https://docs.newrelic.com/docs/infrastructure/amazon-integrations/aws-integrations-list/aws-x-ray-monitoring-integration/) e [ações/recursos IAM X-Ray](https://docs.aws.amazon.com/service-authorization/latest/reference/list_xray.html).

Validação local concluída: Terraform 1.15.9/AWS 6.58.0, fmt -check, init -backend=false com provider em cache e validate aprovados. JSON gerado pelo terraform console revisado com Account ID fictício 1234567: trust 220 e policy 208 caracteres. Inputs vazio, zero, negativo e não numérico produziram o diagnóstico esperado de validação; valor positivo aceito. Console pode retornar código zero mesmo emitindo esse diagnóstico, por isso a conferência considerou a mensagem nativa. Evidências locais em artifacts/e5-xray-newrelic/validation.json e policies-fictitious-account.json; nenhum teste operacional/script novo, chamada AWS, plano ou apply.
