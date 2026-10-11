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
