# Dashboards e alertas — New Relic

Unidade Terraform persistente para três dashboards e cinco alertas, independente do descarte AWS. Terraform 1.15.9, provider newrelic/newrelic 3.99.3, região New Relic US, workspace default e backend shared/newrelic/terraform.tfstate.

## Dashboards

| Dashboard | Conteúdo |
|---|---|
| [Operação da API e Kubernetes](dashboards/operations.json.tftpl) | Requisições/latência/5xx, processos, pods/containers, réplicas, CPU/memória e uptime |
| [Ordens de serviço](dashboards/orders.json.tftpl) | Volume diário, durações por etapa, serviço completo e falhas de processamento/medição |
| [Integrações e autenticação](dashboards/integrations.json.tftpl) | Código/JWT, login interno, notificações e acessos PostgreSQL/SSM/Secrets; Gateway/Lambda/RDS via CloudWatch |

Cada dashboard possui seleção única hom/prd. O filtro é de visualização, não autorização. PUBLIC_READ_ONLY restringe edição; prevent_destroy protege os dashboards no Terraform.

Métricas HTTP e de autenticação usam distribuições para média/percentis. Durações de OS são calculadas do histórico persistido; SQL é a referência por data do acontecimento. Não somar médias de etapas ou tratar quantidade de amostras como estado atual das OSs.

CloudWatch usa estatísticas de 60 segundos com atraso de dez minutos; seus pontos não são totais do intervalo. Não preencher ausência com zero. Última amostra histórica não comprova disponibilidade atual.

## Configuração

| Entrada | Finalidade |
|---|---|
| NEW_RELIC_ACCOUNT_ID | Account ID do New Relic, inicialmente 8626152 |
| NEW_RELIC_API_KEY | User API Key de administração; somente no processo/passos Terraform necessários |
| NEW_RELIC_ALERT_EMAIL | Endereço de notificações, passado à variável new_relic_alert_email |
| AWS_NEW_RELIC_ROLE_ARN | Role OIDC com acesso somente ao backend desta unidade |

A User API Key não é a License Key de ingestão dos Collectors. Não gravar chaves em tfvars, argumentos, outputs ou artefatos. O endereço de notificação integra o estado/plano protegidos.

## Publicação padrão pelo GitHub Actions

[Newrelic-provision](../../.github/workflows/newrelic-provision.yml) é manual e somente main: plan → Environment newrelic-approval sem credenciais → apply exclusivo do plano salvo. Plan/apply usam o Environment newrelic, com branch main e as variáveis/Secret acima.

Artefato vinculado à mesma execução e SHA, retenção de sete dias e fila única. Plano obsoleto ou indisponível exige nova execução; sem replan automático antes do apply. A conferência posterior deve terminar sem diferenças. Não executar Terraform local em concorrência com a pipeline.

Validação estrutural local: terraform fmt -check, terraform init -backend=false e terraform validate. Credenciais reais não são necessárias ao modo sem backend com placeholders; consultar as variáveis em [variables.tf](variables.tf) e o [exemplo](terraform.tfvars.example).

## Regras comuns dos alertas

Condições separadas hom/prd, severidade Critical, sem preenchimento de lacunas. Expiração de 600 segundos encerra incidentes sem abrir por ausência; encerramento não comprova recuperação. Limite máximo nativo de 30 dias.

Um destino EMAIL compartilhado; canais/workflows próprios filtram o ID exato da policy. Notificam somente ACTIVATED/CLOSED e respeitam silenciamentos. Ambiente desligado não abre incidente por falta de sinal.

## Alerta de processamento de OS

[orders-alerts.tf](orders-alerts.tf): soma de mecanica.orders.processing.failures >=1 em janela de 300 s, event_timer de 60 s e AT_LEAST_ONCE. Conta falha técnica HTTP de OS; negativas de negócio/cancelamento do cliente ficam fora.

## Alerta de notificação de OS

[order-notification-alerts.tf](order-notification-alerts.tf): soma de mecanica.orders.notifications com outcome=failure >=1 em 300 s, event_timer de 60 s e AT_LEAST_ONCE. Inclui consultas/montagem/envio e não desfaz o commit da OS.

No modo atual smtp, API/auth invocam EmailFunction e SMTP4dev captura a mensagem; sucesso não comprova entrega externa. Registros históricos simulated representam somente conclusão da simulação.

## Alerta de CPU elevada do nó

[node-cpu-alerts.tf](node-cpu-alerts.tf): CPU média usada / CPU alocável >80%, por nó. Janelas de 60 s, event_flow com atraso de 60 s e ALL por 300 s. Exatamente 80% ou pico isolado não bastam; não é percentual de capacidade física total.

## Alerta de memória elevada do nó

[node-memory-alerts.tf](node-memory-alerts.tf): working set médio / memória alocável >85%, por nó. Janelas de 60 s, event_flow com atraso de 60 s e ALL por 300 s. Não comprova OOM/MemoryPressure; ausência do denominador não vira zero.

## Alerta de API sem réplica disponível

[api-availability-alerts.tf](api-availability-alerts.tf): max(k8s.deployment.available) <1 no Deployment default/deploy-gerenciamento-api. Janelas de 60 s, event_flow com atraso de 60 s e ALL por 120 s. Uma réplica disponível dentro da janela impede classificá-la como inteiramente sem réplicas.

Escala intencional para zero também pode disparar; manutenção planejada exige silenciamento manual. Exclusão do Deployment/coleta pode produzir ausência, não uma medição de zero.

## Limites

Kubeletstats acompanha somente o nó onde o Collector executa. Logs Gateway podem ter lacunas/duplicações e retomam cinco minutos por inicialização, sem checkpoint persistente. Tracing W3C e X-Ray são caminhos separados. Contadores podem retornar zero sem coleta; ausência de alerta não comprova saúde.

Os dashboards e alertas usam sinais existentes; não criam tráfego, carga ou ações de recuperação. [Fontes e semântica](https://github.com/pknfelps/GerenciamentoMecanicaSistema/blob/develop/docs/arquitetura/rfcs/003-DADOS-E-OBSERVABILIDADE.md).
