# AE.4 — Manifestos do SMTP4dev

**22/10/2026 — manifestos preparados e captura comprovada no Docker local.** Sem login, plano/apply AWS, aplicação Kubernetes ou execução remota. Esta parte integra o [plano extra AE](https://github.com/pknfelps/GerenciamentoMecanicaSistema/blob/develop/docs/PLANO_EXTRA_AUTENTICACAO_E_EMAIL.md); não reabre os aceites E5/E6/E7. A [rede privada e os metadados SSM foram preparados em etapa própria](AE4_REDE_SMTP.md), sem aplicação AWS; [associação de inspeção e bloqueio base-destroy por email preparados em etapa própria](AE4_INSPECAO_E_DESCARTE.md), sem comprovação AWS.

## Recursos e integração com a base

`kubernetes/smtp4dev` é uma Kustomization comum, incluída na raiz `kubernetes`. Hom/prd usam a mesma configuração em seus clusters separados, sem compartilhar mensagens. Os workflows atuais já aplicam/removem a raiz; nenhum workflow foi alterado nesta etapa. O Collector continua em sua Kustomization independente.

| Recurso | Configuração |
|---|---|
| Namespace | smtp4dev |
| ServiceAccount | smtp4dev, sem token automático, RBAC ou identidade AWS |
| Deployment | smtp4dev, rnwood/smtp4dev:3.15.0, uma réplica, Recreate, término até 30 s |
| ConfigMap | smtp4dev-config com sufixo hash gerado pelo Kustomize |
| Service SMTP | smtp4dev-smtp, porta 25 → porta nomeada smtp/2525, NodePort 30025 |
| Service web | smtp4dev-web, ClusterIP, porta 80 → web/8080 |

A mudança do JSON gera outro nome de ConfigMap e atualiza a referência no pod, provocando rollout na próxima aplicação. Não desabilitar o hash nem alterar o ConfigMap gerado manualmente. Recreate interrompe a captura e apaga a caixa ao substituir o processo. ConfigMaps de revisões antigas podem permanecer até a remoção do namespace; não contêm mensagens ou credenciais.

O processo usa portas internas acima de 1024 para executar sem root e com todas as capabilities removidas. O futuro caminho será EmailFunction → NLB interno TCP 2525 → target group próprio → NodePort 30025 → container 2525. Este commit prepara o NodePort; **não cria listener, target group, regras SG, catálogo ou conectividade Lambda**. O nome do Service Kubernetes não será usado como endpoint da Lambda na VPC.

## Caixa e limites

`appsettings.json` define banco em memória (`ServerOptions.Database` vazio), retenção das últimas 100 mensagens por caixa e 100 sessões, sem PVC ou arquivo de banco. `/smtp4dev` e `/tmp` são emptyDir em memória, limitados a 32 MiB e 16 MiB. São usados somente por arquivos temporários/chaves internas do processo. Nenhum deles preserva a caixa após recriação do pod; o banco em memória também perde mensagens quando apenas o processo reinicia.

O tamanho máximo SMTP é 524.288 bytes (512 KiB) por mensagem MIME, acomodando o contrato Invoke v1 de até 128 KiB e sua codificação MIME. Não amplia os limites de assunto/corpos definidos para EmailFunction. A retenção é por quantidade, sem prazo de entrega ou conservação; probes TCP e futuros health checks também podem ocupar sessões. Mensagens maiores, fila cheia, reinício ou falta de memória podem impedir captura. Não há garantia de entrega única, replay ou recuperação de mensagens.

O JSON fixa relay sem servidor, destinatários automáticos, expressão ou credenciais. `LockSettings=true` impede reconfiguração pela interface/API administrativa. IMAP/POP3 estão desabilitados. SMTP opera internamente sem autenticação/TLS, conforme o limite demonstrativo aprovado; rede privada não cifra o conteúdo. Não usar isso como prova de acesso ao e-mail pessoal ou serviço de e-mail de produção.

## Segurança, recursos e diagnóstico

- UID/GID 1654 da imagem, runAsNonRoot, filesystem somente leitura, sem escalonamento de privilégios, seccomp RuntimeDefault e drop ALL de capabilities.
- JSON montado somente leitura em `/app/appsettings.json`; diretório de trabalho `/app`. Isso aplica o filtro Serilog também ao logger estático criado antes do host.
- Requests 100m CPU/128Mi memória/16Mi ephemeral-storage; limits 500m/256Mi/64Mi. EmptyDirs em memória consomem memória do container. Esses valores iniciais não comprovam capacidade no nó t3.small.
- Startup e liveness conferem HTTP `/`; readiness confere TCP SMTP. Essas probes verificam o processo/listener, sem afirmar captura persistente ou entrega externa.
- `DeliverToStdout` vazio e filtro Serilog permitem somente templates técnicos fixos de versão/inicialização/encerramento sem exceção. Destinatários, conteúdo, comandos SMTP e stack traces do fornecedor não são encaminhados ao stdout. O filtro também reduz diagnósticos do fornecedor; em falha de inicialização, conferir estado/exit code/probes e configuração versionada, sem remover o filtro em ambiente com mensagens.

A caixa e os registros de sessão na interface contêm intencionalmente o conteúdo recebido. A sanitização do stdout não os torna públicos ou inofensivos. ClusterIP/NodePort não são isolamento entre pods; não foi criada NetworkPolicy. A restrição do caminho Lambda por SG ainda será implementada. SMTP4dev não recebe credenciais AWS, de banco ou JWT.

## Acesso operacional após implantação autorizada

A execução de `base-provision` só deverá ocorrer na sequência aprovada após completar as dependências AE.4. O workflow atual inclui os recursos da raiz, mas ainda não possui uma etapa específica de espera pelo rollout SMTP. Conferir diretamente no contexto correto:

```bash
kubectl --context <contexto-do-ambiente> -n smtp4dev rollout status deployment/smtp4dev --timeout=300s
kubectl --context <contexto-do-ambiente> -n smtp4dev get pods,services
kubectl --context <contexto-do-ambiente> -n smtp4dev port-forward --address 127.0.0.1 service/smtp4dev-web 3000:80
```

Abrir http://127.0.0.1:3000 e encerrar o port-forward com Ctrl+C. A autenticação/autorização é a do kubeconfig operacional, com permissão para consultar o pod e abrir port-forward; não é o JWT Mechanic. Não foi criada outra access entry/RBAC nesta parte. Usar contexto explícito para não consultar a caixa de outro ambiente. Não publicar Ingress, LoadBalancer ou listener web.

Para verificar a perda da caixa em etapa autorizada, interromper envios e reiniciar o Deployment. Isso inutiliza a consulta de códigos já capturados; solicitar novo código respeitando o limite da autenticação. Não recuperar códigos por logs ou endpoint de debug.

A remoção pela Kustomization raiz inclui o namespace e a caixa. Os [bloqueios base-destroy já preparados](AE4_INSPECAO_E_DESCARTE.md) exigem EmailFunction ausente e rede liberada antes de descartar SMTP; ainda não foram comprovados na AWS. Não aplicar/remover o SMTP isoladamente enquanto houver consumidores ativos.

## Evidências locais de 22/10/2026

- Kustomize: raiz, SMTP4dev, Collectors hom/prd e API hom/prd renderizados. Kubeconform 0.7.0, pacote oficial com checksum conferido, schemas Kubernetes 1.36.0: **36 recursos válidos, zero inválidos/erros/ignorados** nos seis arquivos renderizados (inclui recursos repetidos entre raiz/componente e ambientes).
- Imagem 3.15.0: digest local `sha256:25c434c1900a9c5b61e17ead0a774d9e81b80554d05cf64719d69e5ea8c66537`. Execução com UID/GID 1654, cap drop ALL, no-new-privileges, readonly, CPU 0,5 e memória 256 MiB. `/proc/1/status` confirmou CapEff/CapBnd zero e NoNewPrivs=1. O teste elevou explicitamente o limite de portas privilegiadas para 1024, sem depender do padrão permissivo do Docker.
- Rede Docker interna sem saída externa; bind do JSON real e tmpfs nos dois diretórios. Nenhum volume persistente. Clientes HTTP/SMTP executados no container, sem publicar a caixa na rede externa.
- HTTP `/` retornou 200; estado SMTP ativo, retenção 100/100, portas IMAP/POP3 nulas, relay sem servidor e settingsAreEditable=false. Tentativa de alterar configuração retornou 401.
- **101 mensagens fictícias transmitidas em sessões separadas → 100 mensagens e 100 sessões retidas.** Tentativa de relay pela API nativa permaneceu isRelayed=false; esse endpoint retorna 200 mesmo sem retransmitir, portanto HTTP 200 não comprova relay.
- Logs conferidos após captura/relay: sem endereços, marcador/código fictício, conteúdo ou stack trace. Nenhum envio externo foi configurado ou realizado.
- Reinício do processo: **zero mensagens e zero sessões**, HTTP 200 e SMTP ativo novamente. Sem arquivo de banco nos diretórios temporários. Container/rede de teste removidos.
- Consumo pontual após captura: aproximadamente 127,9 MiB de memória, sem OOM. Não é teste de carga, capacidade EKS ou dimensionamento definitivo.

Essas evidências não comprovam scheduling, regras SG, NLB/health checks, acesso da Lambda ou capacidade AWS. O Compose local da API ainda tem seu volume SMTP anterior; sua remoção/alinhamento permanece na integração local AE.5/AE.7, preservando o volume PostgreSQL. Nenhum código das aplicações ou contrato HTTP foi alterado pelos manifestos.

## Próximas partes da AE.4

[Listener/target group/ASG attachment SMTP, SG reservado/regras mínimas e metadados SMTP/SG foram preparados e validados localmente](AE4_REDE_SMTP.md). [Associação de leitura para inspeção da pipeline email e bloqueios base-destroy preparados e validados localmente](AE4_INSPECAO_E_DESCARTE.md). O workflow email-destroy será criado na AE.8. Depois, preparar/publicar EmailFunction e consumidores conforme AE.5–AE.8. Planos/apply e comprovação na AWS dependem de autorização posterior.

Referências da imagem fixada: [opções de configuração](https://github.com/rnwood/smtp4dev/blob/3.15.0/Rnwood.Smtp4dev/appsettings.json), [inicialização/logger](https://github.com/rnwood/smtp4dev/blob/3.15.0/Rnwood.Smtp4dev/Program.cs) e [armazenamento em memória](https://github.com/rnwood/smtp4dev/blob/3.15.0/Rnwood.Smtp4dev/Startup.cs).
