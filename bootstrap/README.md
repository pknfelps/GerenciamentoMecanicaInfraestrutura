# Bootstrap administrativo persistente

## Decisão SAM da autenticação — 2026-10-11

[ADR 009](https://github.com/pknfelps/GerenciamentoMecanicaSistema/blob/develop/docs/arquitetura/adrs/009-SAM-AUTENTICACAO.md) define SAM/CloudFormation para os recursos auth, sem migrar este bootstrap. Role/policies auth-runtime continuam persistentes e serão reutilizadas pela stack; sua exclusão não fará parte do destroy auth, preservando a limpeza posterior de ENIs. Buckets/OIDC/role CI e IAM das pipelines continuam Terraform.

auth-sam-permissions.tf acrescenta policies gerenciadas às roles auth hom/prd para a stack do ambiente, transforms Serverless/LanguageExtensions e upload/exclusão nativos SAM. DeleteObject fica restrito a sam/auth/<ambiente>/*; ListBucket exige esse prefixo. Não permitir DeleteObjectVersion, DeleteBucket ou exclusão de contratos/pacote/outro ambiente. ListChangeSets atende estados parciais; DescribeStacks na stack auxiliar de nome calculado pelo SAM permite inspeção sem exclusão/ECR. auth-permissions.tf administra aliases e egress nativo sem tags de regra, restrito ao SG reservado. Sem role de execução CloudFormation adicional, leitura de Secrets ou alteração do IAM runtime. Auth deixa de acessar seu backend Terraform e artefatos lambda antigos. Plano CI/SAM delete aprovado e aplicado em 2026-10-11; futuros applies exigem nova revisão/aprovação de plano salvo.

Template/workflows SAM com ZIP estão implementados e validados localmente. Inventário AWS em 2026-10-11 não encontrou função/stack/log/auth-v2 nem objetos/versões históricos de estado auth; código Terraform auth retirado sem destroy/exclusão de estado. Registros datados das partes 5/6 abaixo são históricos; o novo plano CI/SAM substitui o plano antigo de somente CI.

Mantém estados S3 versionados/locking, artefatos imutáveis, ECR, OIDC e permissões por componente/ambiente. Não pertence ao descarte normal de hom/prd. Nenhum workflow administrativo novo foi criado.

Usar Terraform 1.15.9, provider lock versionado, credencial administrativa autenticada na conta 121754142617/us-east-1. Preservar backend.hcl/backend.s3.tf e bootstrap.tfvars locais existentes; não versionar estado, planos ou credenciais. O exemplo de tfvars documenta inputs não secretos.

```powershell
terraform init -backend-config=backend.hcl -lockfile=readonly
terraform fmt -check
terraform validate
terraform plan -var-file=bootstrap.tfvars -out=bootstrap.tfplan
terraform show -no-color bootstrap.tfplan
# Somente depois da aprovacao do plano exibido:
terraform apply bootstrap.tfplan
```

Mudanças declarativas: base recebe CRUD NLB/target group/listener e attach/detach do ASG exclusivo do EKS; SGs próprios. Banco recebe gestão dos metadados/versões write-only de seus secrets API/auth e leitura do segredo RDS administrativo existente. Credenciais atuais tagged database-provision são aceitas para adoção; novos recursos usam Terraform. SSM Put/Tag/Delete é exclusivo de v2 do próprio produtor; leitura de v2 no ambiente. Sem permissão para publicar releases v1.

`allow_legacy_cleanup=true` mantém exclusivamente leitura/descarte de roles controller/CSI e Delete de SSM v1 próprio. Necessário até o apply de remoção da base e retirada v1. Depois da migração, gerar/revisar novo plano com `-var=allow_legacy_cleanup=false`, aplicar o binário aprovado e persistir essa escolha no bootstrap.tfvars local. Não retirar antes: a pipeline ainda precisa apagar os recursos no estado. Permissões de rede usadas pelo Terraform permanecem. A desativação também retira leitura do namespace v1 do próprio produtor.

Aplicado em 2026-10-08, após aprovação do plano salvo: 2 policies criadas, 22 atualizadas e nenhuma exclusão, cobrindo hom/prd. A conferência Terraform posterior retornou `No changes`. `allow_legacy_cleanup=true` permanece até a remoção dos recursos antigos e a migração SSM v2; sua desativação exige outro plano aprovado. Ordem/procedimento em [migração](../docs/MIGRACAO_DECLARATIVA.md).

Correção adicional aplicada em 2026-10-08 com plano salvo aprovado: 4 policies atualizadas, sem criações ou exclusões, adicionando `ssm:DescribeParameters` às roles base/banco de hom/prd. A leitura de metadados usa `Resource="*"`, restrita a `us-east-1`; os valores e a escrita dos parâmetros mantêm o escopo atual. Simulação IAM das quatro roles retornou `allowed`; conferência Terraform posterior retornou `No changes`.

JWT E2.12: implementação local acrescenta a policy gerenciada mecanica-<ambiente>-base-jwt à role da base em hom/prd. Autoriza administração do Secret /mecanica/<ambiente>/base/jwt, da role mecanica-<ambiente>-api-runtime e de sua associação Pod Identity; PassRole restrito a pods.eks.amazonaws.com. Não concede leitura do valor JWT à pipeline da base nem altera as policies inline existentes. O provider AWS 6.58.0 inspeciona versões write-only por metadados. Aplicação desta mudança depende de novo plano salvo aprovado; [operação JWT](../docs/JWT_COMPARTILHADO.md).

Bootstrap JWT aplicado em 2026-10-08 usando exatamente o binário aprovado: 4 criações (duas policies gerenciadas e duas associações), nenhuma alteração/exclusão. Conferência Terraform posterior: No changes. Simulação das roles base hom/prd: DescribeSecret permitido e GetSecretValue negado. JWT/SSM/role/associação do runtime serão criados pela base após PR e aprovação do base-provision; nenhum apply da base foi executado nesta operação.

E2.6: a nova policy read-database pertence ao Terraform da base e usa as permissões GetRolePolicy/PutRolePolicy/DeleteRolePolicy já concedidas por base-jwt à role API exata. Não exige alteração de código/apply do bootstrap. Revisar/aprovar o plano da base antes de aplicar; a simulação das permissões administrativas confirmou allowed para hom. Consulte [runtime API](../docs/API_RUNTIME.md).

## Lambda de autenticação — parte 5 (preparação local)

auth-runtime.tf define mecanica-hom-auth-runtime e mecanica-prd-auth-runtime com confiança exclusiva no serviço Lambda. Roles e policies de execução pertencem ao estado persistente do bootstrap, não ao auth; o destroy normal da função preserva essas permissões para que a AWS conclua a limpeza de suas interfaces de rede. A base continua dona do SG reservado e auth administra somente suas duas regras de saída. Aguardar liberação de ENIs antes de descartar banco/base/rede; o retorno de DeleteFunction não comprova limpeza concluída. [Permissões VPC e limpeza](https://docs.aws.amazon.com/lambda/latest/dg/configuration-vpc.html).

A execução recebe GetParameters exclusivamente nos nove nomes SSM v2 do carregador, GetSecretValue somente em AWSCURRENT dos Secrets /mecanica/<ambiente>/base/jwt e /mecanica/<ambiente>/database/auth (sufixo AWS de seis caracteres), escrita no próprio log group e ações EC2 necessárias às ENIs em us-east-1. O Deny condicionado a lambda:SourceFunctionArn impede essas ações EC2 quando chamadas pelo código da própria função, preservando as chamadas do serviço Lambda. Não há leitura de secrets administrativos, database/api ou outro ambiente.

auth-permissions.tf acrescenta a policy gerenciada mecanica-<ambiente>-auth-provision à role OIDC auth existente. Administra a função/versões/concorrência/log group, egress do SG reservado identificado por tags e as tags das regras próprias; permite inspeção de rede/metadados, leitura de versões dos artefatos e invocação futura da própria função. GetRole e PassRole são limitados à role auth-runtime; PassRole exige lambda.amazonaws.com. A pipeline não modifica essa role/policy nem lê valores de Secrets. A permissão de invocação pelo Gateway pertence à unidade gateway futura. As policies inline atuais das pipelines foram preservadas.

Nesta parte não houve login, Access Analyzer, plan AWS ou apply. Gerar/revisar/aplicar o plano salvo do bootstrap na próxima entrega usando os comandos administrativos acima, antes de plan da função. A criação declarada não comprova que a role exista na AWS. Preservar backend/nomes/estado e allow_legacy_cleanup=false já adotado em 2026-10-09; os registros anteriores com true são históricos.

Pré-requisitos atuais: bootstrap CI/SAM aplicado, quota suficiente, base/banco recriados, Job database-init concluído e publicação SAM/OpenAPI do commit. A stack referencia ARN da role runtime persistente. ZIP/template nativos, deploy/descarte SAM manuais sem aprovação intermediária e limpeza somente do ZIP atual/templates operacionais estão no [procedimento auth](https://github.com/pknfelps/GerenciamentoMecanicaAutenticacao/blob/develop/docs/DEPLOY.md). Nenhuma função é implantada por este bootstrap.
**2026-10-09 — Bootstrap auth aplicado:** após aprovação explícita do plano salvo, aplicado exatamente o binário bootstrap-auth-runtime.tfplan (SHA-256 522ED5C8F0272A66F5D66D979CF3BE1B953E2DE77EE6925179C1F73C84E30160), com a sessão administrativa existente na conta 121754142617. Resultado: oito criações, zero alterações/exclusões — roles auth-runtime, policies de execução, policies auth-provision e associações em hom/prd. Quatro policies validadas pelo Access Analyzer sem findings; conferência posterior Terraform retornou No changes. Trust Lambda, policy inline e associação à pipeline conferidas nas duas roles. Simulações IAM hom/prd: JWT/auth do próprio ambiente em AWSCURRENT permitidos, database/api e JWT do outro ambiente negados; pipelines auth sem leitura dos dois Secrets. Nenhum valor de Secret foi consultado. allow_legacy_cleanup=false preservado. Evidências locais em artifacts/bootstrap-auth-runtime. Função, ZIP/OpenAPI, workflows e Gateway permanecem pendentes; base/banco precisam ser recriados antes do deploy.
## CI da autenticacao — parte 6

auth-ci.tf acrescenta somente a role mecanica-auth-ci-github, path /mecanica/pipelines/, e sua policy inline ReadAuthContracts100. Trust OIDC usa audience sts.amazonaws.com e subjects exatos do repositorio auth para pull_request, develop e main, sem Environment e sem alterar a trust das roles de deploy. A policy permite somente s3:GetObject nos dois objetos Auth.Contracts/1.0.0 (nupkg e .sha256), sem ListBucket, escrita, SSM, estado ou Secrets.

O output auth_ci_role_arn deve preencher AWS_CI_ROLE_ARN como variavel do repositorio de autenticacao. Variavel CI ja configurada no GitHub. Environments de aprovacao criados anteriormente nao sao mais utilizados pelos workflows auth; hom/prd continuam fornecendo OIDC/variaveis. Nenhuma configuracao remota foi removida nesta simplificacao. A role CI ainda precisa de novo plano salvo revisado/aprovado antes de apply; o bootstrap auth-runtime aplicado na parte 5 nao inclui essa role nova.

Validar fmt/init sem backend/validate e gerar plano administrativo com bootstrap.tfvars. O plano atual inclui CI e SAM: seis criações, cinco alterações e zero exclusões; allow_legacy_cleanup=false preservado. Não ampliar roles de deploy para PRs. [Procedimento auth](https://github.com/pknfelps/GerenciamentoMecanicaAutenticacao/blob/develop/docs/DEPLOY.md).

Plano CI anterior em artifacts/bootstrap-auth-ci (duas criações, hash A08A38085549F28BBA6C7025572102248677B428128BAEA3D2B2F003C46E67F6) é histórico e foi substituído pelo novo plano CI/SAM direto abaixo. Não aplicar esse plano antigo contra o código SAM atual.

## Plano CI/SAM delete — aplicado em 2026-10-11

[Plano textual](../artifacts/bootstrap-auth-sam-delete/tfplan.txt) e [revisão](../artifacts/bootstrap-auth-sam-delete/REVISAO.md). Binário bootstrap-auth-sam-delete.tfplan; SHA-256 D396D208E6D9A7D99D104E52A33FA1994F7B4EC963D802C31C224E861454F5A5. Substitui bootstrap-auth-sam-direct, bootstrap-auth-sam e bootstrap-auth-ci; não aplicar os binários antigos.

- Seis criações: role/policy CI, duas policies auth-sam e suas associações. SAM pode fazer deploy/delete na stack própria e administrar os arquivos nativos do ambiente.
- Cinco alterações: duas policies auth-provision (alias/egress nativo), duas policies pipeline (sem backend auth/artefatos antigos) e policy do bucket de artefatos.
- Nenhuma exclusão/substituição; runtime IAM/buckets/OIDC/ECR/estados existentes preservados. Exceção de escrita condicional exclusivamente sam/auth/hom/ e sam/auth/prd/; contratos/NuGet protegidos.
- Mudança desde o plano direto: somente duas policies SAM recebem DeleteObject/ListBucket restritos ao ambiente, ListChangeSets próprio e DescribeStacks da stack auxiliar. Sem DeleteObjectVersion, DeleteBucket ou exclusão de ECR/stack auxiliar/outro ambiente. Policies SAM com 1.991/6.144 caracteres; seis restantes idênticas ao plano anterior.
- Duas policies SAM validadas no Access Analyzer sem findings; 52 decisões IAM simuladas confirmam os limites. actionlint/ShellCheck e Terraform fmt/validate aprovados. Não comprova deploy/destroy SAM real.
- Quota total/não reservada anteriormente conferida: 10; reserva cinco requer mínimo 105 sem outras reservas. Pedido 110 pendente; não reduzir automaticamente a reserva.

Plano aprovado pelo mantenedor e aplicado exatamente pelo binário acima: 6 recursos criados, 5 alterados, nenhum removido. Terraform pós-apply retornou No changes. Policies/associações SAM, trust/policy CI e policy/versionamento do bucket conferidos na AWS. Evidências apply.txt, post-apply-plan.txt e deployed-*.json no mesmo diretório. Não reaplicar o binário consumido. A aplicação não cria a Lambda nem recria base/banco. Próximo: quota suficiente → base/banco/Job → publicação → sam deploy manual → hom. Publicação, implantação e destroy ficam a cargo do mantenedor. auth-provision/auth-destroy executam completos após disparo manual, sem job de aprovação; bootstrap Terraform mantém plano aprovado.

## Gateway REST — 12/10/2026

O bootstrap mantém a service-linked role API Gateway (ops.apigateway.amazonaws.com), a role mecanica-apigateway-logs e a configuração regional de CloudWatch. São persistentes; o estado Gateway administra apenas seus log groups. A policy de logs é limitada aos dois grupos /aws/apigateway/mecanica-<ambiente>-gateway e ao grupo técnico /aws/apigateway/welcome utilizado pela validação da AWS, com inspeção regional de grupos.

Gateway possui uma policy gerenciada por ambiente em gateway-permissions.tf: criação com nome/tags exigidos, gerenciamento de API/VPC Link pelos tags do ambiente, logs próprios, rede somente inspeção e AddPermission apenas para apigateway.amazonaws.com na versão auth própria. Não concede leitura de Secrets, modificação da Lambda ou administração de outro ambiente. A confiança OIDC aceita somente o repositório infra; contracts/api e contracts/auth são somente leitura. Policies inline base-gateway-permissions.tf permitem criar/administrar o SG reservado, sua saída e o ingresso NLB, sem abertura de CIDRs.

Plano original em artifacts/bootstrap-gateway/bootstrap-gateway.tfplan: 10 criações, 4 alterações, nenhuma exclusão/substituição. Aplicado parcialmente; a configuração regional de logs foi concluída pelo plano complementar aprovado abaixo. Binários consumidos são históricos e não devem ser reaplicados. [Sequência e operação](../docs/GATEWAY.md).

### Resultado do apply Gateway — 12/10/2026

Plano aprovado aplicado parcialmente: nove criações/quatro alterações IAM concluídas, configuração regional de logs falhou. CloudTrail comprovou CreateLogGroup negado em /aws/apigateway/welcome, usado pela AWS para validar a role. Código acrescenta apenas esse grupo/streams à policy regional; as pipelines Gateway continuam restritas aos respectivos ambientes. Plano complementar artifacts/bootstrap-gateway/bootstrap-gateway-welcome.tfplan aprovado e aplicado: uma criação/uma alteração/zero exclusões. Configuração regional aponta à role mecanica-apigateway-logs, conferida por GetAccount; plano posterior retornou No changes. Evidências welcome-apply.log, post-welcome-account.json e post-welcome-plan.txt no mesmo diretório. Não reaplicar o plano original após a alteração de estado. [Revisão local](../artifacts/bootstrap-gateway/REVISAO-WELCOME.md).

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
