# Collector da API e métricas Kubernetes

## Estado e propriedade

A infraestrutura administra `kubernetes/observability/base` e seus overlays `hom`/`prd`. A Kustomization é independente da raiz `kubernetes`. `base-provision` já aplica o overlay do ambiente, reinicia e aguarda o Collector; `base-destroy` remove esse mesmo overlay antes do EKS, incluindo ClusterRole/ClusterRoleBinding. A coleta Kubernetes não criou workflows ou IAM adicional. A entrega CloudWatch posterior acrescenta somente uma policy inline à role do Collector administrada pela base; [procedimento](CLOUDWATCH.md).

**Comprovado em hom em 17/10/2026:** os três sinais OTLP da API/Lambda chegaram ao New Relic, incluindo métricas de negócio conferidas por SQL e `service.version` com o SHA da API. A integração nativa X-Ray também recebeu spans. [Evidência consolidada](https://github.com/pknfelps/GerenciamentoMecanicaSistema/blob/develop/docs/VALIDACAO_HOM_2026-10-17.md).

**Coleta Kubernetes comprovada em hom em 17/10/2026:** 23 métricas recebidas, quatro namespaces observados, valores comparados com Kubernetes/top e enriquecimento dos três sinais da API preservando serviço/versão/correlação. Collector Ready, zero reinícios, aproximadamente 2m CPU/55–56 MiB, sem erros RBAC/TLS/exportação na janela. Duas amostras/minuto na série conferida, sem duplicação observada. [Evidência e limites](https://github.com/pknfelps/GerenciamentoMecanicaSistema/blob/develop/docs/VALIDACAO_KUBERNETES_HOM_2026-10-17.md). E5.4/E5.12 comprovadas no escopo hom; prd e carga não foram validados.

## Recursos e segurança

| Item | Configuração |
|---|---|
| Namespace / ServiceAccount | `observability/otel-collector` |
| Deployment | Uma réplica, `Recreate`, encerramento de até 30 segundos |
| Imagem | `otel/opentelemetry-collector-contrib:0.161.0` |
| Requests / limits | CPU 100m / 500m; memória 128Mi / 256Mi; `GOMEMLIMIT=192MiB` |
| ConfigMap | `otel-collector-config`, nome estável, volume somente leitura |
| Service | ClusterIP, somente OTLP HTTP/protobuf TCP 4318 |
| Probes | `health_check` em 13133, fora do Service; verificam o processo |
| Processo | UID/GID 10001, sem root/capabilities/escalonamento, filesystem somente leitura e seccomp RuntimeDefault |

O ServiceAccount mantém `automountServiceAccountToken=false`; **somente o pod do Collector** o substitui por `true`. Token e CA Kubernetes autenticam a coleta/enriquecimento. Pod Identity continua fornecendo a identidade AWS para a leitura da License Key no Secrets Manager; as duas credenciais têm finalidades diferentes. Não há hostNetwork, hostPath, armazenamento persistente, HPA, Operator, Helm ou sidecar.

`ClusterRole/mecanica-otel-collector` e seu binding autorizam `get/list/watch` de nodes, namespaces, pods, replicationcontrollers, resourcequotas, services, daemonsets, deployments, replicasets, statefulsets, jobs, cronjobs e horizontalpodautoscalers. Essas coleções são observadas pelo `k8s_cluster` 0.161.0, mesmo quando suas métricas não entram na seleção de exportação. Acrescentado somente `get` em `nodes/stats`. Sem wildcard, Secrets, escrita, execução ou `nodes/proxy`.

PV/PVC e EndpointSlices não recebem permissão: na versão fixada, seus informers são condicionais às métricas correspondentes ou a destinos de metadados/eventos, todos desabilitados nesta configuração. Não há coleta de armazenamento, eventos Kubernetes como logs, stdout ou métricas de rede. Não extrair labels/annotations arbitrárias. Service interno não equivale a NetworkPolicy ou autenticação entre pods.

## Pipelines e identidade

- `traces`, `metrics` e `logs`: OTLP → memory_limiter → k8sattributes → resource/cluster → batch → New Relic.
- `metrics/kubernetes`: kubeletstats + k8s_cluster → memory_limiter → filtro de nomes permitidos → k8sattributes → seleção de atributos de recurso → resource/cluster → batch → o mesmo exporter New Relic.

Os dois receivers coletam a cada **30 segundos**. A lista explícita em `filter/kubernetes` é a autoridade de exportação: métricas padrão fora dela são descartadas, sem afetar métricas técnicas/de negócio recebidas por OTLP. Kubelet não habilita o grupo volume e desabilita suas métricas de rede. O receiver de cluster não está conectado a nenhuma pipeline de logs; `metadata_collection_interval=0s` desabilita a atualização periódica de metadados.

`k8sattributes` associa primeiro por `k8s.pod.uid`, quando presente, e depois pelo IP da conexão OTLP, antes do batch. Extrai somente namespace, nome/UID do pod, nó e Deployment; IP não é exportado como atributo. Não cria spans ou logs. A pipeline Kubernetes conserva somente esses identificadores e `k8s.container.name`, necessário para distinguir containers; remove outros atributos dos receivers, como ID/imagem do container e detalhes de recursos não selecionados.

Os overlays definem `K8S_CLUSTER_NAME=mecanica-<ambiente>-eks` e `DEPLOYMENT_ENVIRONMENT=hom|prd`. `resource/cluster` insere `k8s.cluster.name` e `deployment.environment.name` sem substituir valores já presentes. Não define `service.name` nas métricas Kubernetes e preserva serviço, versão, ambiente e correlação da API.

## Métricas selecionadas e unidades

| Origem | Nomes nativos 0.161.0 | Unidade / interpretação |
|---|---|---|
| Kubelet | `k8s.node.cpu.usage`, `k8s.pod.cpu.usage`, `container.cpu.usage` | Cores, não percentual; primeiras amostras podem depender de dois scrapes |
| Kubelet | `k8s.node.memory.working_set`, `k8s.pod.memory.working_set`, `container.memory.working_set` | Bytes de working set |
| Kubelet | `k8s.node.memory.available` | Bytes disponíveis |
| Kubelet | `k8s.node.uptime` | Segundos desde o início do nó |
| Cluster | `k8s.node.condition_ready`, `k8s.node.condition_memory_pressure`, `k8s.node.condition_disk_pressure`, `k8s.node.condition_pid_pressure` | true=1, false=0, unknown=-1; ausência não equivale a estado saudável |
| Cluster | `k8s.node.allocatable_cpu`, `k8s.node.allocatable_memory` | Cores e bytes **alocáveis**, não capacidade física |
| Cluster | `k8s.pod.phase` | Pending=1, Running=2, Succeeded=3, Failed=4, Unknown=5 |
| Cluster | `k8s.container.ready`, `k8s.container.restarts` | Readiness 0/1 e número atual de reinícios; pode reiniciar com a recriação do container |
| Workload | `k8s.deployment.desired`, `k8s.deployment.available` | Réplicas desejadas/disponíveis |
| Workload | `k8s.container.cpu_request`, `k8s.container.cpu_limit` | Cores solicitados/limitados |
| Workload | `k8s.container.memory_request`, `k8s.container.memory_limit` | Bytes solicitados/limitados |

A ausência de request/limit ou de uma série não deve ser interpretada automaticamente como zero. Kubeletstats consulta o `/stats/summary` do nó; o filtro controla as séries emitidas ao destino, não altera o conteúdo dessa resposta interna.

## Kubelet, TLS e cobertura

`K8S_NODE_NAME` vem de `spec.nodeName` pelo Downward API. O receiver acessa `https://${env:K8S_NODE_NAME}:10250`, com `auth_type=serviceAccount`, CA em `/var/run/secrets/kubernetes.io/serviceaccount/ca.crt` e `insecure_skip_verify=false`. Não há fallback sem TLS verificado.

A conferência anterior de hom validou os SANs DNS/IP do certificado público do kubelet e sua cadeia até a CA EKS. O manifesto usa o nome dinâmico, sem fixar nó ou certificado. Isso não substitui conferir autenticação e coleta após o rollout.

O receiver de cluster observa todos os namespaces, incluindo default, observability, kube-system e database-init quando presentes. Kubeletstats cobre somente o nó onde o Collector está executando. O cluster permanente atual tem um nó; nós transitórios de atualização não têm cobertura completa garantida. Expansão permanente exige revisar a topologia. Uma réplica/Recreate evita dois receivers de cluster simultâneos durante o rollout; não é garantia geral de entrega única.

## Exportação e limites

Preservados memory_limiter 128/32 MiB por segundo, batch 512/1 segundo, exporter OTLP HTTP/protobuf para `https://otlp.nr-data.net`, gzip, timeout de três segundos, fila de 100 lotes por sinal, dois consumidores e retentativas de um a cinco segundos por até 15 segundos. A pipeline Kubernetes também usa essa fila limitada de métricas. Não há fila persistente; saturação, restart ou indisponibilidade podem perder sinais.

A chave continua sendo resolvida pelo provider Secrets Manager nativo na inicialização. Não vai para ConfigMap, token Kubernetes ou variável de ambiente. [Cadastro/rotação](NEW_RELIC.md). O SDK da aplicação continua responsável pela sanitização antes do envio OTLP.

## Validação local desta entrega

Renderizar sem acessar o cluster:

```powershell
kubectl kustomize kubernetes/observability/hom
kubectl kustomize kubernetes/observability/prd
kubectl kustomize kubernetes
```

A raiz continua sem o Collector. Conferir sete recursos por overlay, incluindo RBAC no escopo do cluster, sujeito do binding em observability, identidade hom/prd, pod com token habilitado e ServiceAccount com padrão desabilitado.

Executado o comando nativo `validate` da imagem 0.161.0 com rede desabilitada, mesmo usuário/limites/restrições, header fictício sobrescrito por `--set` e token fictício somente no container local. A CA foi sobrescrita pelo bundle público da própria imagem, pois a CA de ServiceAccount só existe no pod. Não iniciado nenhum receiver ou exporter, não acessados AWS/New Relic e não alterado o TLS do manifesto. Essa validação confere construção/configuração, não conectividade ou autenticação real. Não foram criados scripts, mocks, suítes de telemetria ou validações em workflows.

## Implantação e conferência posterior

O mantenedor publica o PR e executa **somente base-provision** com plan → aprovação → apply. O job já aplica `kubernetes/observability/<ambiente>`, executa `rollout restart` e aguarda até 300 segundos, relendo o ConfigMap estável. Recreate admite breve interrupção. Não é necessário deploy de API/Lambda, banco ou Gateway.

Depois do rollout em hom, com contexto conferido:

```powershell
kubectl config current-context
kubectl rollout status deployment/otel-collector -n observability --timeout=300s
kubectl logs deployment/otel-collector -n observability --since=10m --tail=100
kubectl top nodes
kubectl top pods -A --containers
kubectl get nodes
kubectl get pods -A
kubectl get deployments -A
kubectl get clusterrole mecanica-otel-collector
kubectl get clusterrolebinding mecanica-otel-collector
```

Conferir ausência de erros de RBAC, autenticação, certificados e exportação; comparar séries com estado, reinícios, requests/limits e réplicas. Admitir diferenças de janela e definição de memória em relação a `kubectl top`; CPU em cores, onde 1000m equivale a um core. Verificar novos atributos nos três sinais da API, mantendo serviço/versão/trace.id, e continuidade dos indicadores de negócio. Inspecionar CPU/memória/reinícios do Collector no t3.small antes de propor mudanças de recursos ou permissões.

Para alteração isolada posterior, aplicar o overlay correto, reiniciar e aguardar rollout. O descarte já remove o overlay inteiro, incluindo RBAC, depois dos consumidores e banco; ausência tolerada, falhas de exclusão bloqueiam o Terraform. Não remover somente o namespace deixando os recursos de escopo de cluster.

## Consultas NRQL após implantação

Filtrar sempre o cluster/ambiente. Uptime é uma soma cumulativa monotônica no receiver: consultar seu campo cumulative, preservado pelo New Relic, para obter segundos de vida do nó, sem confundir com o incremento entre amostras. [Tratamento de métricas cumulativas](https://docs.newrelic.com/docs/data-apis/understand-data/metric-data/cumulative-metrics/). As famílias de consultas foram usadas na conferência de hom; os valores e a janela estão na evidência acima. Reexecutar para conferir o estado atual:

```sql
SELECT latest(`k8s.node.cpu.usage`), latest(`k8s.node.allocatable_cpu`),
       latest(`k8s.node.memory.working_set`), latest(`k8s.node.allocatable_memory`),
       latest(`k8s.node.memory.available`), latest(getField(`k8s.node.uptime`, 'cumulative')) AS node_uptime_seconds
FROM Metric
WHERE `k8s.cluster.name` = 'mecanica-hom-eks' AND `deployment.environment.name` = 'hom'
FACET `k8s.node.name` SINCE 15 minutes ago
```

```sql
SELECT latest(`k8s.pod.cpu.usage`), latest(`k8s.pod.memory.working_set`), latest(`k8s.pod.phase`)
FROM Metric
WHERE `k8s.cluster.name` = 'mecanica-hom-eks'
FACET `k8s.namespace.name`, `k8s.pod.name` LIMIT MAX SINCE 15 minutes ago
```

```sql
SELECT latest(`container.cpu.usage`), latest(`container.memory.working_set`),
       latest(`k8s.container.cpu_request`), latest(`k8s.container.cpu_limit`),
       latest(`k8s.container.memory_request`), latest(`k8s.container.memory_limit`),
       latest(`k8s.container.ready`), latest(`k8s.container.restarts`)
FROM Metric
WHERE `k8s.cluster.name` = 'mecanica-hom-eks'
FACET `k8s.namespace.name`, `k8s.pod.name`, `k8s.container.name` LIMIT MAX SINCE 15 minutes ago
```

```sql
SELECT latest(`k8s.node.condition_ready`), latest(`k8s.node.condition_memory_pressure`),
       latest(`k8s.node.condition_disk_pressure`), latest(`k8s.node.condition_pid_pressure`)
FROM Metric WHERE `k8s.cluster.name` = 'mecanica-hom-eks'
FACET `k8s.node.name` SINCE 15 minutes ago
```

```sql
SELECT latest(`k8s.deployment.desired`), latest(`k8s.deployment.available`)
FROM Metric WHERE `k8s.cluster.name` = 'mecanica-hom-eks'
FACET `k8s.namespace.name`, `k8s.deployment.name` LIMIT MAX SINCE 15 minutes ago
```

Para logs/traces de uma chamada nova, verificar `k8s.namespace.name`, `k8s.pod.name`, `k8s.pod.uid`, `k8s.node.name` e `k8s.deployment.name`, junto de `service.name`, `service.version` e `trace.id`. Não usar dimensões do cluster para reatribuir as métricas da API.

CloudWatch, correlação W3C/X-Ray, dashboards, alertas, testes de carga e mudanças da topologia continuam separados. E5.4/E5.12 comprovadas em hom após a implantação de 17/10/2026; prd, falhas/saturação e expansão de nós continuam pendentes.

Referências da versão fixada: [kubeletstats](https://github.com/open-telemetry/opentelemetry-collector-contrib/tree/v0.161.0/receiver/kubeletstatsreceiver), [k8s_cluster](https://github.com/open-telemetry/opentelemetry-collector-contrib/tree/v0.161.0/receiver/k8sclusterreceiver) e [k8sattributes](https://github.com/open-telemetry/opentelemetry-collector-contrib/tree/v0.161.0/processor/k8sattributesprocessor).

## Coleta CloudWatch — complemento de 18/10/2026

O mesmo Deployment passa a carregar collector.yaml e collector-cloudwatch.yaml do ConfigMap estável. Overlays hom/prd acrescentam somente o grupo Gateway e nomes previsíveis dos recursos consultados. Duas pipelines próprias coletam access logs e 13 métricas AWS sem k8sattributes/resource/cluster, reutilizando os limites/exporter existentes. Nenhuma alteração nos caminhos OTLP/Kubernetes ou em suas frequências. [Campos, estatísticas, IAM, retomada, validação local e conferência posterior](CLOUDWATCH.md).

A identidade Pod Identity agora lê também CloudWatch: FilterLogEvents no grupo exato do ambiente e GetMetricData regional. Não altera o RBAC Kubernetes. Base-provision aplica essas permissões antes de reiniciar o Collector. Implantação/ingestão CloudWatch pendentes; a conferência anterior de hom continua restrita aos sinais então implantados.
