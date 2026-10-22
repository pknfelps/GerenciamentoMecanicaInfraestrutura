# AE.4 — Rede privada SMTP e metadados

**22/10/2026 — preparado e validado localmente para hom/prd.** Sem login AWS, leitura de estado remoto, plano, apply ou execução de workflow. Continuação dos [manifestos SMTP4dev](AE4_SMTP4DEV_MANIFESTOS.md) e do [IAM preparado no bootstrap](AE4_IAM_EMAIL.md). A preparação local da AE.4 foi completada em etapa própria de [inspeção e descarte](AE4_INSPECAO_E_DESCARTE.md); esta configuração ainda não comprova conectividade implantada.

## Caminho declarado

```text
EmailFunction, SG mecanica-ENV-email
  → NLB interno existente mecanica-ENV-api:2525/TCP
  → target group mecanica-ENV-smtp, instance:30025/TCP
  → nós do mesmo ASG do EKS
  → Service smtp4dev/smtp4dev-smtp, NodePort 30025
  → SMTP4dev, porta smtp/2525
```

ENV é hom ou prd, validado pela variável existente. Cada ambiente tem sua VPC, NLB, SGs e cluster próprios. Não foi criado outro NLB, nó/ASG, subnet, NAT ou endpoint público. O DNS publicado é o do NLB interno; não fixar IPs nem usar o DNS ClusterIP como endpoint da função fora do cluster.

`terraform/smtp-network.tf` reserva o SG mecanica-ENV-email e declara target group, listener, regra de entrada nos nós e attachment independente ao ASG. `terraform/nlb.tf` acrescenta duas regras inline ao SG atual, preservando seu proprietário e padrão de administração. O listener 80, target group API/30080, health check HTTP /health/ready, attachment API, VPC Link e enforcement PrivateLink permanecem intactos. Nomes/descrição do SG NLB e atributos do balanceador não foram modificados para evitar substituições desnecessárias.

## Regras e proprietários

| Origem | Destino | Porta | Proprietário |
|---|---|---|---|
| SG EmailFunction | SG NLB | TCP 2525, entrada no NLB | Base |
| SG NLB | SG EKS | TCP 30025, saída do NLB e entrada nos nós | Base |
| SG EmailFunction | SG NLB | TCP 2525, saída da função | SAM email, pendente |
| SG EmailFunction | Serviços AWS necessários | HTTPS conforme template | SAM email, pendente |

O SG reservado não possui regras funcionais de ingresso/egress declaradas pela base. O provider remove a saída irrestrita padrão na criação; as regras de saída serão recursos independentes do SAM email. Não acrescentar egress inline à base, pois haveria dois proprietários. A captura só ficará utilizável pela função depois de implementar/aplicar esse SAM.

A única nova origem autorizada no listener SMTP é o SG email do próprio ambiente. Não se abriu CIDR da VPC/internet, porta web, ingresso de API/auth direto no SMTP ou porta SMTP no Gateway. As permissões IAM existentes de Invoke email continuam separadas da conectividade de rede.

O SG dos nós recebe a referência ao SG do NLB para o NodePort, cobrindo tráfego e health check mesmo com preservação do IP do cliente. Isso segue a [orientação AWS para SGs do NLB](https://docs.aws.amazon.com/elasticloadbalancing/latest/network/load-balancer-security-groups.html). Essa regra adicional não remove as regras internas preexistentes do EKS nem representa NetworkPolicy/isolamento entre pods.

SMTP continua TCP sem TLS/autenticação no cenário demonstrativo acordado. Nenhuma proteção de certificados foi desabilitada para simular criptografia; relay externo e persistência da caixa continuam desabilitados pelos manifestos. A interface web permanece ClusterIP/port-forward, sem listener no NLB.

## Targets e saúde

O target group SMTP usa instâncias na porta 30025 e health check TCP nessa mesma porta. O attachment usa o ASG publicado pelo managed node group, assim como o attachment API existente, sem administrar IDs efêmeros das instâncias. O registro SMTP é independente e não substitui o da API.

A associação depende do listener e da regra de entrada SMTP nos nós. As demais referências produzem dependências nativas entre VPC, EKS, SGs e NLB, sem scripts. Health check TCP comprova conexão ao listener; não comprova conteúdo da mensagem, captura posterior ou autenticação do cliente. Antes do rollout SMTP, targets podem ficar unhealthy sem que isso seja tratado como confirmação de envio.

## Metadados e outputs

Três novas chaves String no catálogo Terraform já existente:

| Chave em /mecanica/ENV/base/v2/ | Valor |
|---|---|
| smtp-host | DNS privado do NLB existente |
| smtp-port | 2525, derivado do listener |
| email-security-group-id | ID do SG reservado da EmailFunction |

As chaves anteriores foram preservadas, incluindo nlb-security-group-id e workload-subnet-ids. A futura pipeline email já tem autorização declarada para ler exatamente os campos necessários; passará a configuração no deploy SAM. A função não precisa consultar SSM por mensagem, e API/auth não recebem host/porta SMTP.

Outputs acrescentados: smtp_host, smtp_port, email_security_group_id e smtp_target_group_arn, todos metadados não secretos. `configuration_parameters` já inclui automaticamente os caminhos das três novas chaves. Catálogo é configuração, sem sinalização de prontidão.

## Revisão IAM e validação local

- Terraform 1.15.9: fmt -check, init -backend=false -input=false -lockfile=readonly e validate aprovados. Providers AWS 6.58.0/random 3.7.2 e lockfile preservados.
- Referências/dependências e filtros por ambiente revisados. O NodePort 30025 corresponde ao manifesto; portas Service 25/container 2525 e web Service 80/container 8080 preservadas.
- Bootstrap preservado: email-base-permissions permite SG email com tags próprias e target group SMTP; base-nlb cobre listener no balanceador atual/attachment do ASG; base-gateway-network/base-nlb cobrem regras nos SGs NLB/EKS; base-metadata-network permite uso da VPC/tag na criação do SG. identity.tf cobre publicação sob base/v2; email-pipeline.tf já contém as seis leituras estritas da base para o futuro deploy email. Não foram acrescentadas permissões.
- Diff conferido: recursos atuais API/NLB/EKS/VPC e catálogos anteriores mantêm endereço/configuração; somente SG NLB recebe regras adicionais. Não foram alterados workflows, IAM, aplicações, banco ou manifestos.

Este passo acrescenta **oito recursos declarados** em relação ao código anterior: um SG reservado, uma regra de ingresso nos nós, um target group, um listener, um attachment e três parâmetros SSM; altera as regras inline de um SG existente. Isso é revisão do código, não resultado de plano AWS. O plano completo também refletirá as etapas anteriores ainda não aplicadas e a recriação do ambiente destruído. Não prometer ausência de substituições sem revisar o plano salvo real.

Nenhuma chamada AWS, simulação IAM, teste de conectividade VPC ou envio SMTP foi executado nesta parte. A captura em Docker permanece comprovada no registro dos manifestos; Docker não valida SGs/health checks do NLB. Não foram criados mocks, scripts auxiliares ou suítes de telemetria.

## Continuação e implantação posterior

[Acesso View/default da pipeline email e bloqueios de descarte da base implementados e validados localmente](AE4_INSPECAO_E_DESCARTE.md). O workflow email-destroy e suas checagens próprias permanecem na AE.8. O rollout SMTP já pode ser conferido manualmente pelo procedimento dos manifestos. EmailFunction/egress SAM, alias/catálogo email/v1 e seus consumidores permanecem nas etapas AE.5–AE.8.

Após completar o código e mediante autorização: aplicar o bootstrap aprovado, gerar/revisar o plano salvo da base por ambiente, aplicar somente o aprovado e conferir rollout SMTP/saúde dos targets. Depois da publicação da função, validar envio privado real com dados fictícios, ausência de exposição/relay e preservação do caminho HTTP API. Não usar saúde TCP como confirmação Captured. Não executar destroy como teste; atualizar seus bloqueios antes de utilizar a nova cadeia.
