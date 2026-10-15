# Collector da API — preparação local

O Collector pertence à infraestrutura. Os manifestos em [kubernetes/observability](../kubernetes/observability/kustomization.yaml) formam uma Kustomization independente e **não integram a raiz kubernetes**. O base-provision agora aplica essa unidade separadamente após os manifestos da base; base-destroy a remove antes deles e do apply Terraform. Hom/prd usam os mesmos arquivos em clusters separados.

Manifestos e integração dos workflows foram preparados e validados localmente. Não houve login, implantação, execução remota de workflows, operação AWS, alteração Terraform/IAM ou ativação da API.

## Recursos e configuração

| Recurso | Configuração |
|---|---|
| Namespace | `observability`, administrado por esta Kustomization |
| ServiceAccount | `otel-collector`, sem montagem de token, RBAC ou identidade AWS |
| ConfigMap | `otel-collector-config`, com `collector.yaml`, nome estável e volume somente leitura |
| Deployment | `otel-collector`, uma réplica, estratégia Recreate, encerramento de 30 s |
| Imagem | `otel/opentelemetry-collector-contrib:0.161.0` |
| Service | `otel-collector`, ClusterIP, somente TCP 4318 |
| Requests / limits | CPU 100m / 500m; memória 128Mi / 256Mi; GOMEMLIMIT 192MiB |

O processo usa UID/GID 10001, sem root, capabilities ou escalonamento de privilégios; filesystem somente leitura e seccomp RuntimeDefault. Não há disco persistente, HPA, Operator, Helm ou sidecar. Recreate evita uma segunda réplica durante a substituição e admite interrupção temporária da coleta. A capacidade do nó t3.small não foi comprovada localmente.

O receiver OTLP HTTP/protobuf escuta em 0.0.0.0:4318 dentro do pod. Traces, métricas e logs passam por memory_limiter (128 MiB, margem 32 MiB, intervalo 1 s) e batch (1 s, até 512 registros). O exporter debug usa **basic**, emitindo resumos por lote; não é armazenamento nem ingestão New Relic. Não altera serviço, versão ou ambiente recebidos da aplicação.

A extensão health_check escuta em 0.0.0.0:13133 e atende às três probes do Deployment. A porta não integra o Service. Não usar check_collector_pipeline. HTTP 200 demonstra o funcionamento do processo, sem comprovar um destino externo ou entrega dos sinais.

Service ClusterIP significa exposição interna, sem LoadBalancer/Ingress/NodePort. **Não restringe por si só quais pods podem enviar OTLP**; não há NetworkPolicy ou autenticação OTLP nesta etapa. Não há coleta de stdout, Kubernetes, CloudWatch, X-Ray ou segredos.

## Validação local

Docker Desktop com engine Linux deve estar ativo; não é iniciado automaticamente. Na raiz da infraestrutura:

```powershell
kubectl kustomize kubernetes/observability
kubectl kustomize kubernetes

$config = (Resolve-Path kubernetes/observability/collector.yaml).Path
docker run --rm --read-only --user 10001:10001 --cap-drop ALL --security-opt no-new-privileges --cpus 0.5 --memory 256m --env GOMEMLIMIT=192MiB --mount "type=bind,source=$config,target=/etc/otelcol-contrib/collector.yaml,readonly" otel/opentelemetry-collector-contrib:0.161.0 validate --config=/etc/otelcol-contrib/collector.yaml
```

A renderização da raiz deve continuar contendo somente os recursos anteriores; não instalar o Collector por inclusão acidental nessa raiz.

A fixture CollectorExportTests do repositório da API aceita o parâmetro NUnit `CollectorConfigPath`. Sem o parâmetro, mantém o YAML local atual do CI e não depende de checkout da infraestrutura. Com o parâmetro, usa o arquivo informado, monta-o somente para leitura, aplica o mesmo usuário/limites/restrições e espera HTTP 200 na porta de health.

Na raiz da API, substitua C:/caminho pelo caminho real:

```powershell
dotnet test ControllerTests/ControllerTests.csproj -c Release --filter FullyQualifiedName~CollectorExportTests -- 'TestRunParameters.Parameter(name="CollectorConfigPath",value="C:/caminho/GerenciamentoMecanicaInfraestrutura/kubernetes/observability/collector.yaml")'
```

Somente nesse teste, o comando nativo do Collector sobrepõe `debug.verbosity=detailed` para conferir conteúdo sanitizado/correlação/métricas. O YAML versionado permanece basic. O teste usa PostgreSQL/Collector reais descartáveis, sem AWS/RDS, e verifica continuidade da API/readiness com o Collector parado. Não habilitar detailed no manifesto de implantação.

O Collector com basic também é exercitado localmente sem override, conferindo health, recebimento de traces/métricas/logs e ausência do conteúdo dos registros nos resumos. Isso não substitui a futura validação Kubernetes.

## Workflows e operação — sem execução AWS nesta entrega

O mantenedor executará base-provision com plan salvo → aprovação → apply. Após o Terraform e os manifestos da base, o job aplica kubernetes/observability, executa rollout restart e aguarda rollout status por até 300 segundos. O restart é intencional em cada execução para reler o ConfigMap estável; Recreate admite breve interrupção. Falha encerra o job, apresenta recursos/eventos/logs limitados e não desfaz recursos já aplicados. O resumo comprova saúde do processo, sem declarar ingestão externa. A role base já tem acesso administrativo ao cluster; a pipeline da API mantém acesso ao namespace default e não administra estes recursos. Para operação manual, selecionar e conferir o contexto correto antes dos comandos abaixo.

```powershell
kubectl config current-context
kubectl apply -k kubernetes/observability
kubectl rollout status deployment/otel-collector --namespace observability --timeout=120s
kubectl get service otel-collector --namespace observability
kubectl logs deployment/otel-collector --namespace observability --tail=40
```

A API já terá o endpoint `http://otel-collector.observability.svc.cluster.local:4318` nos overlays hom/prd, mas **Telemetry__Enabled=false**. Instalar e conferir o Collector antes de habilitar a API em entrega posterior. Exportação não integra readiness nem transações da aplicação.

O ConfigMap não tem hash no nome. O Collector lê a configuração na inicialização; após mudança isolada de YAML, aplicar e reiniciar explicitamente:

```powershell
kubectl apply -k kubernetes/observability
kubectl rollout restart deployment/otel-collector --namespace observability
kubectl rollout status deployment/otel-collector --namespace observability --timeout=120s
```

Para remover, primeiro desabilitar a exportação da API em seu manifesto e concluir o rollout. Depois de aguardar o escoamento dos lotes, na raiz da infraestrutura:

```powershell
kubectl delete -k kubernetes/observability --ignore-not-found=true --wait=true --timeout=120s
```

O delete inclui o namespace e seus recursos. O namespace pertence a esta unidade; não é compartilhado com recursos de outros donos. api-destroy não remove este Collector. base-destroy, após aprovação do plano salvo, remove a unidade com --ignore-not-found=true --cascade=foreground --wait=true --timeout=300s, antes dos manifestos da base e do apply Terraform. Ausência é tolerada; falhas bloqueiam o descarte, sem forçar finalizadores. A ordem permanece Gateway/consumidores → auth/API → banco → base; o Collector é removido pela base depois de interromper sua exportação.

## Pendências

Execução dos workflows na AWS, ativação, New Relic/credencial do exporter, enriquecimento/métricas Kubernetes, CloudWatch/X-Ray e avaliação de consumo no EKS continuam pendentes. O CI já renderiza ambas as Kustomizations e valida o YAML com o comando nativo da imagem Contrib 0.161.0. Os manifestos não criam chaves, destinos fictícios ou permissões antecipadas. O SDK permanece responsável pela sanitização antes de exportar. E5.1–E5.3 continuam parciais.


## Resultado local — 15/10/2026

Configuração validada pelo binário fixado; Collector executado com o usuário, restrições e limites previstos. Health 200 e recebimento dos três sinais confirmados com debug basic sem conteúdo dos registros. Kustomization independente renderizada e raiz da infraestrutura idêntica à anterior. Na API, 90 testes de observabilidade aprovados sem falhas/ignorados; fixture executada também com este YAML e override detailed exclusivo do teste. OpenAPI inalterado. Evidências em artifacts/e5-collector dos dois repositórios. Nenhum recurso AWS foi alterado.
