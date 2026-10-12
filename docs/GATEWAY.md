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

Access log JSON em `/aws/apigateway/mecanica-<ambiente>-gateway`, retenção de sete dias: IDs, método, rota parametrizada, status, latência e tamanho da resposta. Sem corpo, documento, token, cabeçalhos, IP ou caminho contendo valores reais. Execution logs, data tracing, cache e X-Ray desabilitados; observabilidade completa permanece na E5. A role de logs e a configuração regional API Gateway pertencem ao bootstrap persistente.

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
