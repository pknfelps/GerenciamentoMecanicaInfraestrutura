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

Terraform fmt/init sem backend/validate e Kustomize validam arquivos. CI dos Collectors usa override nativo de api-key com valor fictício; nenhum Secret AWS é lido. Fixtures .NET usam destino OTLP local real, verificando headers, payloads, três sinais, sanitização e falhas 401/429/503/lentidão/indisponibilidade.

A imagem Contrib 0.151.0 não contém decouple, embora a layer oficial o inclua. Para testar SOMENTE transporte, os overrides nativos removem processors na fixture Contrib; o teste local Compose continua cobrindo o fluxo diagnóstico. O CI identifica esse limite explicitamente. Essa comprovação não valida ciclo/fila do decouple nem congelamento da extensão: esses cenários permanecem para AWS. Não há substituição no YAML empacotado em produção.

Não acrescentados scripts, Operators, agentes, coleta stdout ou duplicação dos exporters. Somente o Compose/local de teste mantém debug, sem AWS/New Relic. Os deploys usam exclusivamente New Relic. Próximas entregas: ingestão comprovada, dashboards/alertas, coleta Kubernetes/CloudWatch e integração X-Ray/New Relic/correlação W3C.
