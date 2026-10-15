# Gateway REST

Implementação local concluída em 12/10/2026; primeira aplicação e validação HTTP na AWS pendentes. A unidade `gateway/` pertence à infraestrutura e tem estado separado da base. Não depende de estado remoto de outro repositório.

## Pré-requisitos e sequência

1. Revisar e aplicar o plano salvo do bootstrap: permissões Gateway hom/prd, role regional de logs e service-linked role.
2. Publicar os workflows na branch padrão `main` pelo fluxo normal de PR. Conferir `AWS_GATEWAY_ROLE_ARN` nos Environments hom/prd e a proteção de hom-approval/prd-approval.
3. Executar base-provision e revisar seu plano: SG reservado Gateway, saída TCP 80 ao SG NLB, ingresso correspondente no NLB e novo parâmetro SSM. Não substituir VPC, EKS ou NLB.
4. Provisionar banco e concluir o Job; publicar e implantar API e autenticação.
5. Executar gateway-provision em develop/hom, informando os dois commits completos dos contratos publicados. Após a conferência, repetir em main/prd quando autorizado.

A base fornece a rede e o NLB. A API fornece seu OpenAPI publicado; estar saudável não é requisito de criação do Gateway, mas é necessário para responder às chamadas. A autenticação precisa estar implantada, pois o Terraform lê sua versão numérica pelo SSM e cria a permissão de invocação dessa versão. O banco é uma dependência dos backends, não uma dependência Terraform direta do Gateway.

## Provisionamento

gateway-provision e gateway-destroy têm três jobs: plan → aprovação protegida sem AWS → apply. O SHA da execução fixa o Terraform. `api_commit` e `auth_commit` são SHAs completos de outros repositórios e fixam os contratos; não são hashes de arquivos nem versões S3.

O job plan baixa `contracts/api/<commit>/openapi.json` e `contracts/auth/<commit>/openapi.json`, verifica seus sidecars SHA-256 e gera tfplan/tfplan.txt. Os contratos entram no mesmo artefato GitHub do plano, com retenção de sete dias. O apply baixa esse artefato por ID e aplica o plano salvo com o mesmo checkout e lockfile; não baixa contratos novamente nem gera outro plano. Mudanças nas dependências exigem nova execução antes de aplicar. O mantenedor coordena base, banco, API, auth e Gateway sequencialmente por ambiente.

Backend: `mecanica-tfstate-121754142617-us-east-1`, chave `<ambiente>/gateway/terraform.tfstate`, workspace default, locking S3. Terraform 1.15.9, AWS provider 6.58.0, região us-east-1 e conta 121754142617.

## Rede e rotas

REST API Regional `mecanica-<ambiente>-gateway`, stage hom/prd e URL HTTPS pública. VPC Link V2 nas duas subnets privadas de workloads, com o SG `mecanica-<ambiente>-gateway` reservado pela base. Base administra esse SG e sua única saída TCP 80 ao NLB. O SG NLB recebe TCP 80 desse SG; NLB → nós continua TCP 30080. Não abrir CIDRs da VPC ou da internet.

Terraform compõe a definição de roteamento em `gateway/contracts.tf` usando jsondecode/jsonencode, sem construir arquivo por script. A projeção preserva os caminhos, métodos, parâmetros de caminho e descrições de respostas. Os schemas/modelos e a descrição Bearer continuam nos contratos originais; o importador REST da AWS não aceita o esquema HTTP Bearer. A projeção não configura validação de corpo ou authorizer no Gateway: a API continua validando JWT e aplicando suas permissões atuais.

- Rotas da API: HTTP_PROXY, método correspondente, URI HTTP privada explícita e parâmetros de caminho mapeados. Corpo, query, Authorization e respostas passam ao backend.
- POST /customers/validate: AWS_PROXY para a versão numérica publicada da Lambda, sem alias live ou $LATEST.
- /health/live, /health/startup e /health/ready ficam fora da entrada pública. Não há ANY ou rota genérica `{proxy+}`.

O import usa overwrite e fail_on_warnings. O deployment muda pelo hash da definição e dos contratos, com create_before_destroy. O tráfego externo usa HTTPS; o trecho privado usa HTTP na porta 80. Conferir no primeiro deploy que o stage não aparece no caminho recebido pela API.

## Configuração e logs

SSM String/Standard em `/mecanica/<ambiente>/gateway/v2/`: rest-api-id, vpc-link-id, stage-name, endpoint, api-openapi-key, auth-openapi-key e auth-invocation-arn. São configuração, não prova de prontidão.

Access log JSON em `/aws/apigateway/mecanica-<ambiente>-gateway`, retenção de sete dias: IDs, `xrayTraceId` (`$context.xrayTraceId`), método, rota parametrizada, status, latência e tamanho da resposta. Sem corpo, documento, token, cabeçalhos, IP ou caminho contendo valores reais. Execution logs permanecem OFF, data tracing e cache desabilitados. O campo de correlação não comprova existência de segmento exportado. A role de logs e a configuração regional API Gateway pertencem ao bootstrap persistente.

## Validação

Antes dos PRs: fmt/validate nas unidades base/bootstrap/Gateway, actionlint/ShellCheck, renderização Kubernetes e composição Terraform com contratos publicados. Conferir policies e isolamento hom/prd com ferramentas AWS padrão. Não criar scripts operacionais de teste.

Após provisionar hom: conferir VPC Link AVAILABLE, targets NLB saudáveis, stage/SSM e logs. Exercitar documento inválido → 400, cliente ausente → 401 e cliente elegível → 200. Usar o JWT somente em memória para verificar assinatura/compatibilidade na API, sem imprimir documento/token. Uma resposta 403 em rota de Admin pode demonstrar a role Customer atual; não alterar autorização de negócio para contornar isso. E3/E2.12 permanecem abertas até comprovação real das integrações.

## Descarte

gateway-destroy usa os mesmos commits e contratos disponíveis e aplica somente o plano -destroy aprovado. Remover Gateway antes de auth/API e antes de banco/base. Preservar bootstrap, artefatos, SG reservado e outro ambiente. As dependências SSM/NLB/Lambda devem permanecer disponíveis para planejar o descarte.

Depois de concluir o descarte, conferir as ENIs do SG reservado com comandos padrão antes de destruir a base. A liberação pode continuar após a remoção do VPC Link; não excluir interfaces à força.

```bash
gateway_sg="$(aws ec2 describe-security-groups --filters 'Name=group-name,Values=mecanica-hom-gateway' --query 'SecurityGroups[0].GroupId' --output text)"
aws ec2 describe-network-interfaces --filters "Name=group-id,Values=$gateway_sg" --query 'NetworkInterfaces[].{Id:NetworkInterfaceId,Status:Status,Description:Description}'
```

Não executar destroy para testar esta entrega. Referências: [VPC Link V2 REST](https://docs.aws.amazon.com/apigateway/latest/developerguide/set-up-private-integration.html), [limites do importador](https://docs.aws.amazon.com/apigateway/latest/developerguide/api-gateway-known-issues.html) e [logs](https://docs.aws.amazon.com/apigateway/latest/developerguide/set-up-logging.html).

## Configuração regional de logs — conferência AWS de 12/10/2026

O API Gateway valida sua role regional tentando escrever no grupo técnico /aws/apigateway/welcome. A policy da role permite esse grupo/streams além dos dois grupos de acesso do projeto; não permite outros grupos. A primeira aplicação concluiu nove criações/quatro alterações IAM, mas falhou nessa validação. Correção mínima aprovada e aplicada pelo plano complementar: uma criação/uma alteração/zero exclusões. GetAccount confirmou a role mecanica-apigateway-logs e o plano posterior do bootstrap retornou No changes. Evidências em artifacts/bootstrap-gateway/welcome-apply.log, post-welcome-account.json e post-welcome-plan.txt. O provisionamento Gateway e a validação HTTP/JWT continuam pendentes. Não reutilizar o plano original, pois o estado já mudou.

## Correção da autorização Gateway → NLB — 12/10/2026

base-provision falhou em AuthorizeSecurityGroupEgress no recurso security-group-rule/*: a autorização do Security Group existia, mas faltava a autorização da regra criada com tags. O bootstrap acrescenta somente esse Allow, exigindo Project, Environment, Component=gateway-network e ManagedBy=Terraform. Mantém a restrição ao grupo reservado e o isolamento hom/prd.

Novo plano em artifacts/bootstrap-gateway-egress/bootstrap-gateway-egress.tfplan: zero criações, duas alterações de policies inline e zero exclusões. SHA-256 4D1D9D7A1B40ED8AD8516A772EA21AECF41253BE8D5383CBE531DD675EE5EEA1. Terraform fmt/validate, duas policies Access Analyzer sem findings e 26 decisões IAM conferidas. Plano aprovado e aplicado: zero criações, duas alterações e zero exclusões. Policies hom/prd conferidas na AWS; simulação nas roles reais permitiu a criação nos recursos Security Group e Security Group Rule. Plano posterior retornou No changes. Evidências apply.log, post-apply-plan.txt e deployed-*.json no mesmo diretório. Não reaplicar o binário consumido. [Plano textual](../artifacts/bootstrap-gateway-egress/tfplan.txt) e [revisão](../artifacts/bootstrap-gateway-egress/REVISAO.md).

Após aplicar o bootstrap, executar novo base-provision com plano salvo revisado/aprovado para concluir a implantação parcial e aplicar os manifestos Kubernetes. Não reutilizar o plano anterior nem executar destroy para essa correção.

## Tags na criação do Gateway — plano de 12/10/2026

gateway-provision falhou em CreateVpcLink por falta de autorização de tags no caminho /vpclinks. O bootstrap acrescenta apigateway:PATCH somente nas coleções /vpclinks e /restapis, condicionado às tags da requisição Project=mecanica, Environment correspondente, Component=gateway e ManagedBy=Terraform. Mantém todas as permissões existentes, o isolamento hom/prd e as restrições aos recursos já criados.

Plano artifacts/bootstrap-gateway-tags/bootstrap-gateway-tags.tfplan: zero criações, duas alterações (policies gerenciadas Gateway hom/prd), zero exclusões/substituições. SHA-256 A8720C2E52C4C9028EB3092E22CC0F1B6EDEB55106AAD0D8EFE7522E718CDF27. Terraform validado, duas policies Access Analyzer sem findings e doze decisões IAM VPC Link conferidas. A simulação PATCH /restapis é inconclusiva: negou inclusive o controle hipotético Action=*/Resource=*; validação REST real fica para o workflow. [Plano textual](../artifacts/bootstrap-gateway-tags/tfplan.txt) e [revisão](../artifacts/bootstrap-gateway-tags/REVISAO.md).

Plano acima aprovado e aplicado: zero criações, duas alterações e zero exclusões. Policies v2/associações hom/prd conferidas; simulação nas roles reais autorizou tags na criação do VPC Link. Plano posterior retornou No changes. Evidências apply.log, post-apply-plan.txt e deployed-*.json no mesmo diretório. Não reaplicar o binário consumido. Executar nova execução gateway-provision com novo plano revisado/aprovado, preservando a implantação parcial; não reutilizar o plano da execução que falhou. Nenhum deploy Gateway ou destroy executado nesta correção.

## Endpoints de tags — revisão adicional de 12/10/2026

A nova execução gateway-provision continuou falhando em CreateVpcLink após a aplicação da policy v2. CloudTrail confirmou role e tags corretas; a permissão PATCH anteriormente simulada não cobriu toda a autorização de tags. A policy atual também nega os endpoints /tags/... das coleções de criação.

O código acrescenta POST/PUT somente nos endpoints de tags de /vpclinks e /restapis, com destinos literal/URL-encoded e condições Project=mecanica, Environment correspondente, Component=gateway e ManagedBy=Terraform. Não abre um wildcard para todos os endpoints de tags nem novos caminhos de IDs existentes. Demais statements preservados.

[Plano textual](../artifacts/bootstrap-gateway-tag-endpoints/tfplan.txt) e [revisão](../artifacts/bootstrap-gateway-tag-endpoints/REVISAO.md): zero criações, duas alterações das policies Gateway hom/prd, zero exclusões. Binário bootstrap-gateway-tag-endpoints.tfplan; SHA-256 FD2646E5E1AC2F8035B1BC6A1B66F2A60477315E045B640F760D5F5EFC5958B3. Terraform validado, Access Analyzer sem findings e 56 decisões PUT de simulação conferidas antes/depois e negativas de escopo. Não comprova o contexto interno inteiro de CreateVpcLink nem seu sucesso real. Plano salvo aprovado e aplicado: zero criações, duas alterações e zero exclusões. Policies v3/associações hom/prd conferidas; simulação PUT nas roles reais autorizou os quatro endpoints de tags previstos. Plano posterior retornou No changes. Evidências apply.log, post-apply-plan.txt e deployed-*.json no mesmo diretório. Não reaplicar o binário consumido. Próximo: nova execução gateway-provision com novo plano revisado/aprovado; sucesso real de CreateVpcLink/API REST ainda pendente. Nenhum deploy Gateway ou destroy executado nesta correção.

## Revisão integral da policy Gateway — 12/10/2026

A execução após v3 continuou falhando em CreateVpcLink. Esta revisão substitui os blocos especulativos PATCH/POST/PUT nas coleções de tags por criação/gerenciamento com apigateway:* limitado às coleções REST/VPC Link e aos recursos do projeto/ambiente com quatro tags. O registro AWS do VPC Link V2 declara TagResource; a autorização exata passa de implicitDeny na policy v3 para allowed na proposta. Endpoints de tags são tratados separadamente: não possuem ResourceTag, e o serviço também precisa autorizar o recurso original. A checagem conjunta será validada na AWS após apply/deploy; simulação isolada de endpoint não comprova isolamento da chamada inteira.

A ampliação de ações API Gateway é intencional e foi aprovada no plano; não concede AdministratorAccess, gestão de IAM, leitura de Secrets ou alterações de rede. Leitura SSM Gateway é reduzida aos vinte nomes utilizados (base oito, auth cinco, próprios sete), sem GetParametersByPath. Backend/locking, contratos somente leitura, permissão Lambda restrita e logs próprios foram revisados.

[Plano textual](../artifacts/bootstrap-gateway-policy-review/tfplan.txt) e [revisão completa](../artifacts/bootstrap-gateway-policy-review/REVISAO.md): zero criações, quatro alterações IAM (gerenciadas Gateway e inline bootstrap-access hom/prd), zero exclusões/substituições. SHA-256 do binário bootstrap-gateway-policy-review.tfplan: 4C353A917F50F525E1F1D51D3670296E0AE1D9F48EBB925C3861A624B5BB1E50. Terraform fmt/validate e quatro policies Access Analyzer sem findings. Das 108 decisões gerais simuladas, cem correspondem ao esperado e oito REST são inconclusivas, também negadas pelo controle hipotético irrestrito. Nenhum deploy ou destroy executado. Plano salvo aprovado e aplicado: zero criações, quatro alterações IAM e zero exclusões. Policies gerenciadas v4 e inline bootstrap-access hom/prd conferidas contra os documentos aprovados, com associações corretas. Simulação da ação exata apigateway:TagResource em /vpclinks nas duas roles reais retornou allowed com as quatro tags esperadas. Plano posterior retornou No changes. Evidências apply.log, post-apply-plan.txt, post-apply-verification.json, deployed-*.json e live-*-tagresource-result.json no mesmo diretório. Não reaplicar o binário consumido. Iniciar nova execução gateway-provision com novo plano revisado/aprovado, preservando a implantação parcial; não reutilizar o plano da execução que falhou. CreateVpcLink/API REST ainda exigem validação pela execução real. Nenhum deploy Gateway ou destroy executado nesta revisão.

## Recuperação após exclusão parcial e conflito de rotas — 12/10/2026

CloudTrail confirmou CreateVpcLink e CreateRestApi com sucesso. PutRestApi falhou porque /Catalog/{id} e /Catalog/{serviceId} eram recursos irmãos variáveis, proibidos pelo API Gateway REST. O destroy seguinte excluiu a API 9kp9vwexok, mas GetRestApi passou a retornar AccessDenied: a API excluída não oferece ResourceTag e a condição bloqueava a resposta NotFound. O estado ainda apontava para esse ID.

A policy do bootstrap acrescenta somente GET em /restapis/* de us-east-1 sem condição de tags. Essa leitura de metadados também pode alcançar APIs do outro ambiente na mesma conta; é uma exceção deliberada para reconciliar exclusões e implantação parcial. Escrita/exclusão continuam condicionadas às tags do ambiente. Nenhuma permissão de Secrets, IAM ou alterações de rede foi acrescentada.

A definição Terraform normaliza segmentos variáveis por posição, como /Catalog/{path2}, reunindo os métodos no mesmo recurso. Cada integração conserva a URI do backend e mapeia path2 para id ou serviceId conforme o método. Os nomes internos não mudam a URL concreta nem o contrato publicado da API. Uma precondition rejeita conflitos de método após a normalização. Campos internos de mapeamento não são publicados como parâmetros OpenAPI.

Recuperação autorizada pelo mantenedor e aplicada localmente com o perfil administrativo: duas policies Gateway atualizadas; VPC Link 5n94t4 preservado. A primeira tentativa local foi rejeitada por um campo interno no OpenAPI; a saída foi corrigida e somente sua API vazia e tainted e27sf379ff foi substituída. O Gateway final suee4aiawf, deployment qm9w49, stage hom e configuração SSM foram implantados. Base, banco, API e Lambda foram preservados.

Validação: Terraform fmt/validate aprovados, Access Analyzer sem findings, planos posteriores do bootstrap e Gateway No changes. HTTPS POST /customers/validate com documento inválido retornou 400; GET /Catalog sem token retornou 401, comprovando as duas integrações. Todas as rotas implantadas e os mapeamentos de Catalog foram conferidos. O plano destroy foi gerado com sucesso, mas não foi aplicado; a execução com OIDC pelo workflow ainda deve ser conferida pelo mantenedor.

Evidências em artifacts/gateway-recovery. Publicar as alterações Terraform antes do próximo gateway-provision; o código anterior ainda possui o conflito de rotas. Iniciar nova execução e revisar seu plano, sem reutilizar planos anteriores à recuperação. A validação de autenticação completa/JWT permanece na etapa funcional correspondente.

## Metadados SSM do Gateway — 12/10/2026

O gateway-destroy falhou no plan ao atualizar os sete recursos aws_ssm_parameter.configuration: faltava ssm:DescribeParameters. O provider AWS 6.58.0 usa GetParameter, DescribeParameters e ListTagsForResource na leitura do recurso; a conferência administrativa local anterior não demonstrava as permissões OIDC do workflow.

A policy Gateway hom/prd agora possui ReadRegionalParameterMetadata: somente ssm:DescribeParameters com Resource="*" e aws:RequestedRegion=us-east-1. A ação não oferece escopo por ARN e retorna metadados, sem valores. Ela pode descrever metadados de parâmetros de outros componentes/ambientes da conta; GetParameter/GetParameters, escrita e exclusão preservam os nomes/prefixos já autorizados.

Plano salvo aplicado dentro da autorização de recuperação do mantenedor: zero criações, duas alterações das policies Gateway e zero exclusões. Policies v6 conferidas; simulate-principal-policy das roles hom/prd retornou allowed para DescribeParameters em us-east-1. Simulações da proposta negaram us-west-2, Access Analyzer não retornou findings e o plano posterior do bootstrap mostrou No changes. Nenhum destroy Gateway foi executado nesta correção.

Evidências em artifacts/bootstrap-gateway-ssm-metadata. Iniciar uma nova execução gateway-destroy para gerar/revisar o plano e validar o fluxo com OIDC. A correção IAM já está aplicada na AWS; versionar gateway-permissions.tf e estes registros para preservar a declaração do bootstrap. Não é necessário alterar o workflow.

Referências: [ações SSM](https://docs.aws.amazon.com/service-authorization/latest/reference/list_ssm.html) e [provider 6.58.0](https://github.com/hashicorp/terraform-provider-aws/blob/v6.58.0/internal/service/ssm/parameter.go).

## Leitura do VPC Link durante o descarte — 12/10/2026

O destroy pelo workflow removeu SSM, stage, deployment, logs, permissão Lambda e API REST. DeleteVpcLink também foi aceito, mas a espera final GetVpcLink recebeu AccessDenied porque a leitura ainda dependia de ResourceTag. A consulta administrativa posterior retornou NotFound; o recurso já havia desaparecido e somente sua referência permanecia no estado Terraform.

A policy Gateway hom/prd acrescenta ReadRegionalVpcLinkMetadata, permitindo somente apigateway:GET em arn:aws:apigateway:us-east-1::/vpclinks/* sem exigir tags. Assim o provider consegue aguardar exclusão e receber NotFound. A leitura pode inspecionar metadados de VPC Links do outro ambiente na mesma região; escrita e exclusão mantêm as condições existentes. A exceção corresponde à leitura já adotada para APIs REST e não exige alterar workflows.

Plano salvo do bootstrap aplicado dentro da autorização de recuperação AWS: zero criações, duas alterações IAM e zero exclusões. Demais statements preservados. Terraform fmt/validate e Access Analyzer aprovados; simulações hom/prd autorizaram GET sem tags em us-east-1 e negaram us-west-2. A simulação das roles reais após o apply retornou allowed; o plano posterior do bootstrap mostrou No changes.

A reconciliação foi feita por plan -destroy salvo e apply do mesmo plano, sem state rm, edição manual ou alterações reais: 0 added, 0 changed, 0 destroyed. Estado final sem recursos managed; EC2 sem interfaces de rede associadas ao SG sg-0a0169a0068e6f502. O descarte do Gateway hom está concluído. O workflow ainda pode ser executado novamente para registrar sucesso no GitHub, usando novo plano; não reutilizar o plano que falhou.

Evidências em artifacts/bootstrap-gateway-vpc-link-read. Versionar a correção no bootstrap e estes registros. [Provider AWS 6.58.0: leitura e espera de exclusão](https://github.com/hashicorp/terraform-provider-aws/blob/v6.58.0/internal/service/apigatewayv2/vpc_link.go).

## X-Ray nativo — preparação E5 de 15/10/2026

A variável booleana `xray_tracing_enabled` controla somente o tracing nativo do stage e mantém padrão false. O tfvars hom agora define true para a validação AWS; prd permanece false. A ativação é versionada no tfvars e passa pelo plano salvo/aprovação/apply dos workflows existentes, sem input na interface de gateway-provision. Alterar o arquivo não aplica a configuração na AWS; nenhum input ou regra própria de amostragem foi acrescentado. Integrações, retenção e execução sem data tracing permanecem iguais.

O bootstrap já declara a service-linked role `AWSServiceRoleForAPIGateway`, do serviço `ops.apigateway.amazonaws.com`. A policy gerenciada AWS dessa role já permite as operações X-Ray necessárias. Não foi criada outra role nem ampliada a pipeline Gateway. [Documentação oficial do tracing](https://docs.aws.amazon.com/apigateway/latest/developerguide/apigateway-enabling-xray.html) e [policy oficial](https://docs.aws.amazon.com/aws-managed-policy/latest/reference/APIGatewayServiceRolePolicy.html).

Na autenticação, `XRayEnabled` é independente de `TelemetryEnabled`: false usa PassThrough; true usa Active. Uma nova versão numérica precisa ser consumida em nova execução gateway-provision, pois a integração não acompanha o alias live. Ativar somente o Gateway não ativa os providers OpenTelemetry nem conecta os dois caminhos de traces.

Sequência futura: revisar/aprovar/aplicar plano salvo do bootstrap → auth-publish de revisão nova → auth-provision com as duas opções explícitas → plano/aprovação/apply Gateway → conferir segmentos nativos com dados fictícios. Os segmentos nativos AWS não passam pela sanitização da aplicação; revisar seu conteúdo antes de uso normal. Correlação W3C/X-Ray, coleta CloudWatch, New Relic e comprovação real de amostragem/ausência de duplicação continuam pendentes. Esta entrega é local, sem plano AWS, aplicação ou ativação; E5.3/E5.14 permanecem abertas.
