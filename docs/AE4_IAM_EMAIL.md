# AE.4 — Preparação IAM do envio centralizado

**22/10/2026 — preparado e validado localmente para hom/prd.** Sem login, plano AWS, apply, execução remota ou configuração GitHub. A AE.4 continua parcial: associação de inspeção, bloqueios dos workflows e implantação ainda estão pendentes. [Rede SMTP/catálogos da base preparados e validados localmente em etapa própria](AE4_REDE_SMTP.md). Os [manifestos SMTP4dev foram preparados e validados localmente em etapa própria](AE4_SMTP4DEV_MANIFESTOS.md). [Plano extra AE](https://github.com/pknfelps/GerenciamentoMecanicaSistema/blob/develop/docs/PLANO_EXTRA_AUTENTICACAO_E_EMAIL.md).

## Proprietários e identidades

| Identidade | Proprietário | Responsabilidade |
|---|---|---|
| mecanica-ENV-email-runtime | Bootstrap | Execução da futura função email: logs próprios e interfaces de rede Lambda |
| mecanica-ENV-email-github, path /mecanica/pipelines/ | Bootstrap | Publicação/provisionamento/descarte exclusivos da stack email e inspeção de seus consumidores |
| mecanica-ENV-auth-runtime | Bootstrap | Nova policy de descoberta/invocação email; permissões anteriores intactas |
| mecanica-ENV-api-runtime | Base | Nova policy de descoberta/invocação email em terraform/api-email.tf |
| mecanica-ENV-base-github | Bootstrap | Nova policy gerenciada para preparar recursos SMTP e acesso de inspeção; não recebe outra identidade |

ENV representa hom ou prd. A role da API não foi transferida para o bootstrap. Roles email são persistentes; o futuro SAM referencia a role runtime existente, sem administrá-la. O descarte da stack email não as remove e não interfere nas roles auth/API. Não há role CloudFormation adicional: o SAM usa as permissões da pipeline, como no fluxo auth existente.

## Permissões de execução e consumo

**EmailFunction** — bootstrap/email-runtime.tf:

- Trust de execução com principal lambda.amazonaws.com, conforme o modelo nativo de execution role. Não acrescenta condições de evento aws:SourceArn/SourceAccount à assunção que a Lambda faz da execution role.
- CreateLogStream/PutLogEvents somente em /aws/lambda/mecanica-ENV-email; o grupo será criado pelo SAM.
- As seis ações EC2 necessárias para interfaces da Lambda em VPC, Resource * e restrição regional us-east-1. Deny com lambda:SourceFunctionArn não qualificado impede o código dessa função de chamar essas ações, preservando as chamadas do serviço Lambda.
- Sem SSM, Secrets Manager, RDS, JWT, S3, invocação de outras funções, layer Collector ou X-Ray. Configuração SMTP não secreta virá do deploy; SMTP em si é controlado pela rede/SG, não por uma ação IAM ou SES.

Referências: [execution role](https://docs.aws.amazon.com/lambda/latest/dg/lambda-intro-execution-role.html), [permissões VPC e proteção do código](https://docs.aws.amazon.com/lambda/latest/dg/configuration-vpc.html#configuration-vpc-security), [SourceFunctionArn](https://docs.aws.amazon.com/lambda/latest/dg/permissions-source-function-arn.html).

**Consumidores API/auth** — terraform/api-email.tf e bootstrap/email-consumers.tf:

- GetParameters somente nas chaves invocation-arn e contract-version de /mecanica/ENV/email/v1/.
- InvokeFunction somente em arn:aws:lambda:us-east-1:121754142617:function:mecanica-ENV-email:live.
- Sem invocação do nome não qualificado, $LATEST, versões numéricas, outros aliases ou outro ambiente. Sem leitura do catálogo SMTP na nova policy; API/auth não recebem configuração do transporte.
- ARNs previsíveis não dependem de recursos da stack email nem consultam estado remoto. A existência do alias/catálogo não é comprovada pela policy.

Não cria resource policy pública/Function URL/Gateway para envio; os consumidores usarão suas identidades IAM da mesma conta. Isso não valida o conteúdo Invoke: o contrato v1 continua obrigatório na futura implementação C#.

## Pipeline email

bootstrap/email-pipeline.tf, email-permissions.tf e email-sam-permissions.tf:

- Trust no provider GitHub existente, audience sts.amazonaws.com e subject exato do repositório Serverless com Environment hom ou prd. Reutiliza github_subject_prefixes.auth, sem nova variável ou confiança no nome antigo.
- Não depende de claim ref personalizada. Branch develop/hom e main/prd deverão ser restringidas pelos Environments e conferidas pelos workflows AE.8. Nenhuma configuração GitHub foi alterada nesta preparação.
- **Limite de isolamento:** auth e email compartilham repositório/Environment. Roles separam as permissões de cada sessão, mas esse mesmo contexto OIDC pode assumir ambas; arquivos/workflows separados não constituem isolamento de identidade. Não criar novos Environments nesta etapa.
- Metadados de leitura da base: somente vpc-id, workload-subnet-ids, email-security-group-id, nlb-security-group-id, smtp-host e smtp-port. Ler/administrar somente as cinco chaves do catálogo email/v1: function-name, function-version, invocation-arn, contract-version e zip-key. Sem GetParametersByPath ou acesso a metadados de banco/JWT.
- CRUD da função/versões/aliases e logs de mecanica-ENV-email, stack mecanica-ENV-email e transforms SAM/LanguageExtensions. Somente DescribeStacks na stack auxiliar de nome calculado pelo padrão SAM existente. Sem CRUD da stack auth, IAM runtime, API Gateway ou Function URL.
- GetRole/PassRole exclusivamente na email-runtime do ambiente, com iam:PassedToService=lambda.amazonaws.com. A pipeline não pode criar/alterar roles/policies IAM nem passar auth-runtime/API-runtime.
- S3 limitado a sam/email/ENV/*, com leitura de VersionId, upload e exclusão do objeto corrente para o fluxo nativo SAM. Sem DeleteObjectVersion, acesso a outros estados/prefixos/contratos/NuGet ou Secrets. ListBucket exige o prefixo próprio.
- Egress nativo SAM somente no SG reservado com tags Project/Environment/ManagedBy=Terraform/Name=mecanica-ENV-email. Não pode editar egress auth/banco/NLB por essa autorização.
- Inspeção regional de rede, ListFunctions e ListClusters para as futuras checagens de descarte; DescribeCluster somente no cluster do ambiente. Listagens regionais Resource * podem revelar metadados de outro ambiente: os workflows devem filtrar nomes exatos. Isso não representa isolamento de leitura regional por ambiente.

Não adiciona permissão de invocação operacional à pipeline email. O CI não ganha role de deploy ou leitura de Secrets/layer; auth-ci e suas permissões anteriores permanecem intactos.

**Artefatos:** bootstrap/storage.tf estende exclusivamente a exceção de upload nativo SAM para sam/email/hom/* e sam/email/prd/*. Preserva as exceções auth existentes, TLS obrigatório, versionamento e a exigência de escrita condicional nos demais objetos. A proteção por revisão/checksum/VersionId do fluxo email será implementada na AE.8, sem alegar imutabilidade nova já comprovada na AWS.

Outputs: email_runtime_role_arns e email_github_environment_variables. Após apply aprovado, AWS_EMAIL_ROLE_ARN será variável do Environment Serverless hom/prd, coexistindo com a variável auth atual; AWS_REGION e ARTIFACTS_BUCKET mantêm os valores existentes. Nenhum ARN emitido antes do apply comprova implantação.

## Autorização da base para a próxima parte da AE.4

bootstrap/email-base-permissions.tf acrescenta uma policy gerenciada por ambiente, preservando as policies inline existentes:

- Criar/remover o SG mecanica-ENV-email, com tags obrigatórias e retirada do egress padrão. Autorização existente cobre uso da VPC própria/tag de criação; o SAM email administrará seu egress funcional.
- Criar/taguear/alterar/remover somente o target group mecanica-ENV-smtp. Não cria outro NLB. As permissões existentes já cobrem listener no NLB atual, associação do ASG próprio e regras NLB/nós necessárias; nenhuma regra/porta foi criada nesta etapa.
- GetFunctionConfiguration da função email do próprio ambiente para futura checagem base-destroy. ENIs/SGs usam as leituras regionais existentes.
- Administrar somente a access entry da pipeline email no cluster próprio e associar exclusivamente AmazonEKSViewPolicy no namespace default, com ForAllValues e Null exigindo namespaces presentes. Sem Edit, Secrets ou ClusterAdmin. Essa é autorização administrativa da base; access entry/associação físicas serão declaradas na próxima parte da AE.4.

O operador já utiliza o acesso EKS atual para port-forward; não foi criada autorização vinculada ao JWT Mechanic. Grupo SMTP4dev, UI privada, probes, recursos, catálogo base/SSM e rede ainda não existem por esta entrega.

## Validação local e limites

- Terraform 1.15.9, AWS provider 6.58.0 e lockfiles atuais: fmt -check, init -backend=false -lockfile=readonly e validate aprovados no bootstrap e na base.
- Terraform console em cópia isolada sem backend/estado remoto renderizou políticas e trusts hom/prd. A policy API foi avaliada com os valores públicos de conta/prefixo que correspondem à base; não houve substituição de datasource em código de produção ou mock de recurso AWS.
- JSON, principal, audience/subject, alias, chaves SSM, PassRole, condições regionais/tags e View/default revisados. Ações conferidas nas referências públicas programáticas de autorização AWS, sem usar credenciais da conta. Não é simulação de decisões IAM nem Access Analyzer remoto.
- Policies gerenciadas: consumo auth 481, provision email 2513, SAM email 1996 e base email 3121 caracteres por ambiente, abaixo de 6144. Inline: runtime 939, metadata da pipeline 1683 e consumo API 481. Trust runtime 130 e pipeline 422, abaixo do limite padrão de 2048. Preconditions preservam os limites individuais das novas policies do bootstrap. [Limites IAM](https://docs.aws.amazon.com/IAM/latest/UserGuide/reference_iam-quotas.html).
- A base passa a declarar nove associações de policies gerenciadas por role no escopo atual, incluindo a nova. Nenhuma nova policy inline nessa role; seu limite agregado anterior não foi ampliado. Cotas e associações efetivas na conta continuam exigindo conferência antes da aplicação.
- Confiança/policies existentes de auth/CI, factories de roles, variáveis, lockfiles, backend, workflows, SAM, manifestos, Gateway, C#, banco e configuração New Relic preservados. Não criados scripts operacionais, mocks AWS ou testes de telemetria.

Evidências locais ignoradas em artifacts/ae4/iam no repositório da API: logs init/validate, referências públicas, JSONs renderizados, tamanhos e revisão. A presença dos arquivos não comprova permissões implantadas, conectividade SMTP, bloqueios operacionais ou funcionamento de prd.

## Continuação

1. Manifestos e rede/catálogos SMTP preparados e validados localmente nos registros próprios. Implementar access entry View e bloqueios de descarte restantes na AE.4; manter os nomes e proprietários aqui definidos.
2. Implementar envio na AE.5 e workflows específicos/reutilizáveis na AE.8. Não implantar função vazia apenas para preencher a stack.
3. Somente mediante autorização posterior: gerar/revisar plano salvo do bootstrap e aplicar exclusivamente o aprovado. Esta preparação declara 24 recursos novos no bootstrap, mais a alteração esperada da bucket policy de artefatos; isso não substitui o resultado de um plano real. A policy de consumo da API pertence ao plano da base por ambiente.
4. Cadastrar as novas variáveis GitHub depois do apply e comprovar OIDC, IAM efetivo, aliases, rede e descarte na etapa AWS autorizada. Não executar destroy como teste.
