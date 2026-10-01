# Permissões e pipelines da base — E2.9/E2.4

Implementação inicial de 2026-09-30; ativação simplificada em 2026-10-01. Testes locais e configuração GitHub concluídos; ativação/descarte estão em validação real pelo usuário. As recuperações IAM abaixo registram falhas dos runners e correções aplicadas; a comprovação do ciclo completo permanece pendente.

## Propriedade e escopo

- `bootstrap/base-permissions.tf`: quatro policies gerenciadas por ambiente (criação EC2, manutenção EC2, EKS e IAM), anexadas somente à role base. Políticas completas estão nesse arquivo; cada policy tem precondition para o limite de 6144 caracteres do IAM. A role base não altera a própria role/trust/policies nem acessa o estado compartilhado.
- EC2: leituras regionais explicitamente listadas; criação com tags Project/Environment/ManagedBy; uso e manutenção de recursos existentes com essas tags. Tags de identidade não podem ser removidas ou trocadas pela pipeline. A exceção DisassociateMissingAddress trata somente associação inexistente, excluindo todos os EIPs/interfaces reais, conforme recuperação abaixo. Wildcards de IDs são necessários para recursos ainda não criados; região/conta e tags delimitam o acesso.
- EKS: cluster e filhos do próprio ambiente; criação com tags, modo API_AND_CONFIG_MAP e bootstrap administrativo implícito desabilitado. Access entries limitadas a mecanica/base/API/banco do ambiente. Associação administrativa somente base/operador; Edit somente default para API/banco. ReadAddonCatalog/CreateCluster exigem Resource * conforme a referência AWS, com restrições de região/tags para criação.
- IAM: gerenciamento das três roles de execução EKS existentes no código. Cada role pode receber somente as policies AWS específicas do seu serviço; PassRole usa ARN exato e PassedToService. Criação de service-linked roles limitada a EKS/nodegroup/Auto Scaling; inicialização de suas policies limitada aos respectivos paths. O gerenciamento dessas roles pelas pipelines é a ampliação planejada em E2, preservando as roles OIDC sob administração do bootstrap.
- API/banco: inline policy separada concede apenas DescribeCluster do ambiente, para configurar kubeconfig. Autorização Kubernetes vem das access entries da base.
- `terraform/pipeline-access.tf`: três entries por cluster, base ClusterAdmin, API/banco Edit em default. `default` mantém compatibilidade com os manifests atuais; alterar namespace exige revisar manifests, escopos e policies juntos. Gateway/auth não usam kubectl neste passo.
- Rede Aurora/Secrets Manager/controller/NLB e policies desses componentes continuam nas etapas seguintes; este trabalho cobre a base EKS/VPC existente.

## Cluster existente e clusters novos

`environments/hom.tfvars`, `prd.tfvars` e o exemplo usam bootstrap_cluster_creator_admin_permissions=false. Hom foi descartado pelo mantenedor para evitar custos; a configuração agora atende criação e recriação, sem depender de cluster prévio. O Terraform cria explicitamente as access entries do operador e das pipelines, evitando conflito com uma entry implícita da role criadora.

Após cada descarte autorizado, manter o bootstrap persistente (backend, OIDC, roles e permissões) e executar uma nova ativação da base pelo workflow. Não é necessário criar VPC/EKS ou access entries manualmente. O descarte usa o workflow manual separado base-destroy, com revisão e aprovação próprias. Não há import, target, force-unlock, migração ou alteração automática do atributo. Se existir um cluster legado criado com true, não mudar o atributo em lugar: o provider propõe substituição e este workflow recusa planos destrutivos. Se já houver uma entry implícita da mesma role base, revisar/adotar o recurso em operação explícita antes de prosseguir.

## Ativação em uma execução

1. Publicar as alterações pelo fluxo de PR escolhido pelo mantenedor. O PR executa `ci` sem AWS. As permissões do bootstrap já aplicadas permanecem válidas; esta simplificação não altera Terraform/IAM.
2. Em Actions > base-provision > **Run workflow**, escolher **develop**, environment=**hom**, action=**activate**. Para produção, escolher **main** e **prd**. A ação **plan** continua disponível para consulta e termina sem aplicar.
3. Aguardar CI e plan. Abrir o resumo da execução e revisar o commit, os recursos/ações e o fingerprint. O workflow não publica planos binários, estados nem valores dos recursos.
4. Em **Review deployments**, selecionar **hom-approval** (ou **prd-approval**) e clicar **Approve and deploy**. A aprovação libera o apply na mesma execução: não copiar SHA/fingerprint nem iniciar outro workflow.
5. O apply obtém uma nova sessão OIDC, regenera o plano no mesmo commit e compara automaticamente o fingerprint com o plan revisado. Se mudar, interrompe sem apply: iniciar nova execução activate e revisar/aprovar novamente. Exclusões/substituições também são recusadas.
6. A execução valida cluster/node group/add-ons, nós Ready, pods de sistema e acesso Kubernetes da role base. Depois executar `aws-oidc-check` com check_kubernetes=true em infra/API/banco para comprovar as três identidades. Gateway mantém diagnóstico STS.

`workflow_dispatch` já existe na branch padrão main. Para testar esta versão em hom, publicar em develop e selecionar develop no botão Run workflow; a promoção para main é necessária para usar esta versão em prd. Não é necessário criar VPC/EKS/access entries manualmente.

## Descarte em uma execução — base-destroy

1. Publicar os workflows/scripts/testes em develop e promover a versão revisada para main. **base-destroy é novo e precisa existir em main (branch padrão) para aparecer no botão Run workflow.** Depois selecionar develop para hom; main para prd. A publicação não ativa base ausente.
2. Em Actions > base-destroy > Run workflow, escolher **develop / hom / destroy**. Para consultar exclusões sem aplicar, usar action=plan. Para prd: main / prd / destroy.
3. Aguardar CI e abrir o resumo do plan de descarte: conferir ambiente, commit e lista de exclusões. Em Review deployments, selecionar hom-approval (ou prd-approval) e clicar **Approve and deploy**. Não copiar SHA/fingerprint.
4. O job de descarte obtém sessão OIDC nova, regenera `plan -destroy` no mesmo commit, compara fingerprint e aplica somente o binário validado. Recurso ou plano alterado após aprovação interrompe a execução. Após falha parcial, preservar state e iniciar uma nova execução para revisar o que falta; não repetir automaticamente nem apagar o state.
5. Conferir a mensagem final: estado vazio e EKS/VPC/NAT/Elastic IP ausentes. Estado já vazio é verificado sem apply e sem etapa de aprovação. Erro de leitura, permissão negada ou recurso remanescente falha a execução; não é tratado como ausência.

Escopo: somente os recursos conhecidos de terraform/ e o backend `<ambiente>/base/terraform.tfstate`, workspace default. Inclui EKS, node group, add-ons, acessos EKS, roles de execução, VPC/subnets/rotas, NAT/Elastic IP e endpoint S3. O revisor valida endereços, tags Project/Environment/ManagedBy, nomes de cluster/roles, principals e vínculos de associações de rotas. Aceita somente exclusões; recusa criação, alteração, substituição, módulos, descarte parcial e recursos do bootstrap ou outro ambiente.

Bootstrap, bucket/versionamento/locks do backend, OIDC, roles das pipelines, usuário mecanica e GitHub Environments permanecem. O workflow não opera estados de banco/API/auth nem exclui recursos criados fora da base (como volumes de workloads e load balancers). Quando houver consumidores, limpar seus recursos/dependências pelos respectivos componentes antes da base; descarte coordenado deles continua em E2.8. Não usar este workflow como comprovação de ausência de todos os recursos faturáveis da conta.

Sem novos secrets ou apply de permissões para esta mudança: reutiliza as roles base e hom-approval/prd-approval. As policies versionadas já contêm as exclusões EKS/rede/IAM usadas. O grupo concurrency base-hom/base-prd é compartilhado com base-provision, impedindo operação concorrente dos dois workflows no mesmo ambiente, inclusive durante aprovação. Não existe trigger de push/PR/schedule para descarte.

## Validação direta pelas pipelines

Após publicar ambos os workflows, executar em hom na mesma revisão:

1. **base-provision**, develop / hom / activate → revisar plano → aprovar → conferir apply e validação de cluster/node group/add-ons/nós/pods.
2. **aws-oidc-check** em infra/API/banco, hom com check_kubernetes=true, para registrar as três identidades Kubernetes reais.
3. **base-destroy**, develop / hom / destroy → revisar exclusões → aprovar → conferir estado vazio e ausência de EKS/VPC/NAT/Elastic IP.
4. Opcionalmente repetir base-destroy/hom: ambiente já ausente deve passar nas consultas sem executar apply. Um push posterior em develop mantém ativação pendente; nova janela de uso começa com activate.

Registrar URLs/IDs e commits dos runs e seus resultados. Testes locais não substituem essas evidências. Não usar plan antigo salvo em artifacts para executar novas operações.

## Configuração GitHub da aprovação

Em Settings > Environments, manter hom/prd com as variáveis AWS_REGION, AWS_BASE_ROLE_ARN e TF_STATE_BUCKET e as restrições develop/main existentes. A autenticação AWS continua usando esses environments.

Dois environments separados guardam somente a revisão do plano:

| Environment | Branch permitida | Required reviewer |
|---|---|---|
| hom-approval | develop | pknfelps |
| prd-approval | main | pknfelps |

Configurados em 2026-10-01: Required reviewers habilitado, bypass administrativo desabilitado, sem secrets/variáveis. Prevent self-review permanece desabilitado para permitir que o único mantenedor revise e aprove a própria execução; ativá-lo exige outro aprovador. O job de aprovação não recebe token OIDC nem credenciais AWS.

`Assert-BaseApprovalEnvironment.ps1` consulta a configuração com GITHUB_TOKEN/Actions read antes da autenticação do plan de ativação e novamente antes do apply. Se o environment não existir ou não tiver Required reviewers, a ativação falha. A criação automática de um environment vazio pelo GitHub não autoriza apply. A aprovação fica registrada pelo GitHub na execução que produziu o plano.

## Comportamento após merge

O workflow ci independente responde somente a pull_request para develop/main, workflow_dispatch e workflow_call. O push não dispara um CI independente adicional; base-provision conserva sua chamada reutilizável para validar o commit implantado antes do apply. Checks antigos do mesmo PR são cancelados quando chegam novos commits, com grupo distinto por workflow/PR; execuções manuais e provisionamento ficam isolados por run_id. Nomes dos jobs exigidos pelas proteções foram preservados.


`base-provision` responde a push em develop/main quando terraform/scripts/seu próprio workflow mudam. develop seleciona hom; main seleciona prd. Inicializa o backend, planeja e aplica alterações não destrutivas somente se o plano não criar um cluster. Um ambiente ausente registra **ativação pendente** e não é criado automaticamente; a criação/recriação usa action=activate com aprovação nativa na mesma execução. PR não ativa infraestrutura.

O apply automático presume código revisado pelas proteções do repositório; o workflow não cria essas proteções. Alterações apenas em bootstrap não disparam a base nem aplicam permissões automaticamente: permanecem sob identidade administrativa. O grupo concurrency base-hom/base-prd serializa o workflow inteiro, incluindo plan e espera pela aprovação, e não cancela um apply em andamento; o lock S3 protege o estado contra outros processos. Esta concorrência é local ao repositório infra, não uma trava global entre os quatro componentes.

Falha parcial interrompe o workflow, preserva o estado e não marca sucesso. Nenhum retry de apply/descarte automático. Diagnóstico Kubernetes consulta identidade/can-i/listagens; não cria workloads. Não comprova capacidade funcional da API/observabilidade nem o lock concorrente E2.3.

## Recuperação de hom após falha DescribePrefixLists — 2026-09-30

Run 36802169063, action=apply, passou na revisão do commit/fingerprint e falhou por falta de ec2:DescribePrefixLists. Esta leitura está agora em ReadRegionalNetwork de base_network_create, Resource * com aws:RequestedRegion=us-east-1, para hom/prd. Aplicar o novo plano de bootstrap com identidade administrativa e seu backend existente antes de retomar a base. A role base não altera suas próprias permissões. A mudança esperada é nas duas policies base-network_create; revisar quaisquer outras diferenças.

Inspeção read-only encontrou hom/base/terraform.tfstate serial 16, cluster mecanica-hom-eks ACTIVE, nenhuma node group e endpoint vpce-09666702ffe0585f4 available. O endpoint tem tipo Gateway, serviço com.amazonaws.us-east-1.s3, VPC vpc-06c168312ef0b72f7, rota rtb-05995c7a25f0200c9 e tags Project=mecanica, Environment=hom, ManagedBy=Terraform, Name=mecanica-hom-s3. O state contém o mesmo endpoint, mas com status tainted devido à falha de leitura após criação. Na investigação inicial, nenhum state foi editado pelo assistente.

Para este incidente, depois de aplicar a correção de IAM, conferir novamente o ID/estado/tags/rotas e a marca tainted no state. Com nenhuma operação concorrente em andamento e as condições acima preservadas, remover somente a marca deste recurso (não recria nem exclui o endpoint):

```powershell
# Na raiz de GerenciamentoMecanicaInfraestrutura, identidade administrativa autorizada.
./scripts/Invoke-TerraformEnvironment.ps1 -Environment hom -Action Init
$selection = ./scripts/Invoke-TerraformEnvironment.ps1 -Environment hom -Action Show
$env:TF_DATA_DIR = $selection.DataDirectory
$env:TF_WORKSPACE = 'default'
terraform -chdir=terraform untaint -lock-timeout=60s 'aws_vpc_endpoint.s3'
```

O seletor fixa hom/base/terraform.tfstate; não executar contra backend prd/local/bootstrap nem apagar o estado. Se o endpoint não estiver saudável ou os IDs/configuração diferirem, reavaliar a recuperação; não retirar taint às cegas. Um plan antes do untaint propõe substituir o endpoint e o workflow bloqueia corretamente esse plano destrutivo.

Na versão original do fluxo, a recuperação usava plan e apply separados com commit/fingerprint copiados. Na versão atual, iniciar action=activate em develop/hom e aprovar o novo resumo na mesma execução. O plano deve preservar o cluster/rede/endpoint e completar node group/add-ons; quaisquer exclusões/substituições exigem investigação. Não reutilizar o fingerprint 95cff1bad7f5529068c5a898d4cdfe629efaceba44a708abdb9f1444e7ab2d97 do plano inicial. Após sucesso, validar Kubernetes com aws-oidc-check nos três repositórios. Bootstrap IAM e untaint são operações explícitas do mantenedor; o workflow não ignora exclusões nem faz recuperação automática do state.

Aplicação posterior autorizada pelo usuário em 2026-09-30: assistente revisou e aplicou somente +DescribePrefixLists nas duas policies base_network_create (0 add/2 change/0 destroy), confirmou No changes e simulação IAM allowed em hom/prd. O endpoint acima foi revalidado e somente sua marca tainted retirada, state hom serial 16→17, mantendo o ID. Novo plano de recuperação hom contém quatro criações (node group e três add-ons), sem exclusões/substituições. Os comandos de bootstrap/untaint desta seção já foram executados para este incidente; não repeti-los. A recuperação e o posterior descarte foram informados pelo usuário. Este registro histórico não deve ser repetido; para uma nova janela de uso, iniciar activate em develop/hom. Nenhum apply da base foi executado pelo assistente.

## Recuperação após falta de GetRole na SLR de node groups — 2026-10-01

A ativação hom no commit `379984fad0752fa168d26ec7bc03b8a012d8a6b6` passou na comparação do plano e falhou em `CreateNodegroup`: faltava `iam:GetRole` para validar `AWSServiceRoleForAmazonEKSNodegroup`. `CreateServiceLinkedRole` permite criar a role de serviço, mas não concede sua leitura. `ReadEksNodegroupServiceRole` em `base_iam` acrescenta somente GetRole no ARN exato dessa SLR da conta, para base hom/prd; não permite alterá-la/excluí-la nem ler qualquer role. As permissões de criação existentes continuam válidas para recriação sem SLR prévia.

1. Com identidade administrativa autorizada, aplicar um **novo plano do bootstrap**, no backend existente `shared/bootstrap/terraform.tfstate`, workspace default. Publicar código ou executar a base não atualiza essas permissões. A diferença esperada desta correção são duas policies `base_iam` atualizadas (hom/prd), sem criação/exclusão; revisar quaisquer outras diferenças antes de aplicar. Não usar estado local antigo nem reinicializar o bootstrap sem seu backend.
2. Publicar a correção em develop e iniciar uma **nova execução** `base-provision`, develop / hom / activate. Revisar o plano gerado após a falha parcial e aprovar em Review deployments. O estado remoto preserva os recursos já criados; não apagar o state, criar cluster manualmente ou reutilizar plano/fingerprint anterior. Exclusões/substituições exigem investigação, sem untaint automático.
3. Conferir sucesso do node group/add-ons e verificações de saúde; executar OIDC com Kubernetes em infra/API/banco. Depois validar `base-destroy` conforme o procedimento acima.

[Documentação AWS das roles de serviço de node groups](https://docs.aws.amazon.com/eks/latest/userguide/using-service-linked-roles-eks-nodegroups.html): a criação de managed node groups cria a SLR automaticamente quando necessária. Esta correção não depende de cluster pré-existente. A aplicação de IAM e a retomada real devem ser registradas separadamente dos testes simulados.

Aplicação desta correção concluída pelo assistente em 2026-10-01: identidade administrativa da conta conferida, backend persistente preservado, plano restrito à adição de GetRole nas duas base_iam revisado e aplicado (0 add/2 change/0 destroy). Plano posterior No changes; simulação IAM por recurso allowed na SLR e implicitDeny fora do escopo em hom/prd. Evidências privadas em artifacts/terraform/bootstrap/nodegroup-slr-recovery-2026-10-01. **O item 1 já foi executado para este incidente**; próximo: publicar a configuração em develop e iniciar nova activate conforme item 2. Nenhum apply/descarte da base nem alteração de seu state executado nesta correção. Não repetir os procedimentos históricos de untaint do incidente anterior.

## Recuperação do descarte após associação obsoleta do EIP — 2026-10-01

Run `36922551972`, commit `0fd56832812d8900af8ad1be6da0eaef79cebcc4`, passou no replan/fingerprint do descarte e falhou em `ec2:DisassociateAddress` para `eipassoc-07b94bed67120dd0e`. Consulta posterior confirmou `eipalloc-07f030983cdac38db` com tags hom/Terraform, sem AssociationId nem NetworkInterfaceId. O NAT já liberou sua associação, mas aws_eip no provider 6.58.0 usa o association_id anterior, salvo no plano; aceita InvalidAssociationID.NotFound, porém a AWS verifica IAM antes de devolver ausência. A mensagem decodificada identifica recurso genérico `arn:aws:ec2:us-east-1:121754142617:*/*`, sem identidade/tags de EIP/ENI. Conceder apenas DisassociateAddress no ARN de EIPs com tags não resolve esse caso.

`DisassociateMissingAddress` em base_network_manage permite exclusivamente essa chamada sem recurso real: ação DisassociateAddress, região us-east-1, AllocationId e NetworkInterfaceID ausentes. NotResource exclui **todos** os ARNs reais elastic-ip/network-interface, incluindo hom/prd, outras contas/regiões e recursos sem tags. Essas são as duas classes suportadas pela ação na referência AWS. A exceção não concede desassociação de recursos existentes; ReleaseAddress continua restrita às tags Project/Environment/ManagedBy do ambiente. Não usar Allow regional irrestrito nem tags IfExists para resolver a ausência. NAT continua sendo excluído antes do EIP por sua dependência Terraform.

Aplicar a correção no bootstrap persistente com a identidade administrativa; revisar plano contendo somente a adição desse statement em base_network_manage hom/prd (0 add/2 change/0 destroy). Verificar no simulador: ARN genérico sem IDs permitido na região; EIP/ENI reais, inclusive sem tags e de outro ambiente/conta, recusados; IDs presentes ou outra região recusados. Simulação não substitui a validação do ciclo real pelo runner.

Depois publicar a configuração em develop e iniciar **nova execução** base-destroy develop/hom/destroy; revisar o plano atualizado e aprovar. O estado preserva os remanescentes e o refresh reconhece a associação ausente. Não reutilizar plano/fingerprint antigo, apagar state, remover manualmente recursos ou aplicar o descarte pelo bootstrap. Conferir a verificação final de ausência; um novo ciclo completo de ativação/descarte deve validar que a primeira tentativa de descarte passa com NAT/EIP existentes.

[Implementação aws_eip do provider 6.58.0](https://github.com/hashicorp/terraform-provider-aws/blob/v6.58.0/internal/service/ec2/ec2_eip.go) e [API AWS DisassociateAddress](https://docs.aws.amazon.com/AWSEC2/latest/APIReference/API_DisassociateAddress.html).

Aplicação desta correção concluída pelo assistente em 2026-10-01: somente duas base_network_manage atualizadas, 0 add/2 change/0 destroy, plano posterior No changes. Access Analyzer sem findings e 24 decisões custom/principal IAM aprovadas, incluindo bloqueio de EIPs/ENIs reais, IDs presentes/outra região e isolamento de ReleaseAddress. Evidências privadas em artifacts/terraform/bootstrap/eip-disassociation-recovery-36922551972. **Permissões já aplicadas para este incidente**: retomar agora com nova base-destroy develop/hom/destroy e nova revisão/aprovação. Publicar a correção Terraform/testes em develop para persistência; não precisa novo workflow em main para essa retomada. Nenhuma exclusão real ou alteração do estado da base executada pelo assistente; ausência final e novo ciclo completo ainda pendentes do runner.

## Validação local

```powershell
terraform -chdir=bootstrap fmt -check -recursive
terraform -chdir=bootstrap validate
terraform -chdir=bootstrap test
terraform -chdir=terraform fmt -check -recursive
terraform -chdir=terraform validate
terraform -chdir=terraform test -var-file=environments/hom.tfvars
terraform -chdir=terraform test -var-file=environments/prd.tfvars
pwsh -NoProfile -File scripts/tests/Test-TerraformEnvironment.ps1
pwsh -NoProfile -File scripts/tests/Test-BaseApprovalEnvironment.ps1
pwsh -NoProfile -File scripts/tests/Test-BasePipelineTarget.ps1
pwsh -NoProfile -File scripts/tests/Test-BasePipeline.ps1
pwsh -NoProfile -File scripts/tests/Test-BaseDestroy.ps1
pwsh -NoProfile -File scripts/tests/Test-BaseDestroyed.ps1
python -m unittest discover -s scripts/tests -p 'test_*.py' -v
```

Usar init -backend=false em TF_DATA_DIR de validação separado antes de validate/test; não reaproveitar metadados remotos no modo offline. Esses testes não conectam à AWS. Não iniciar Docker.

Validação da simplificação em 2026-10-01: actionlint, 12 cenários de configuração da aprovação, 22 de destino/commit, 16 de orquestração, dez de seleção de ambiente e nove testes Python aprovados, sem GitHub/AWS nos testes. Incluem recusa de plano alterado entre jobs, proteção ausente, recriação sem cluster prévio e bloqueio de exclusões. A configuração dos environments foi conferida pela UI; nenhum workflow de ativação foi disparado nesta alteração.

## Referências

- [Referência programática AWS de serviços](https://docs.aws.amazon.com/service-authorization/latest/reference/service-reference.html)
- [EKS access entries](https://docs.aws.amazon.com/eks/latest/userguide/access-entries.html)
- [STANDARD, PassRole e consistência eventual de access entries](https://docs.aws.amazon.com/eks/latest/userguide/creating-access-entries.html)
- [Permissões das access policies EKS](https://docs.aws.amazon.com/eks/latest/userguide/access-policy-permissions.html)
- [IAM PassRole](https://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles_use_passrole.html)
- [Execução manual de workflows](https://docs.github.com/en/actions/how-tos/manage-workflow-runs/manually-run-a-workflow)

- [Aprovação nativa de deployments](https://docs.github.com/en/actions/how-tos/deploy/configure-and-manage-deployments/review-deployments)
- [Configuração de environments](https://docs.github.com/en/actions/how-tos/deploy/configure-and-manage-deployments/manage-environments)

Validação do descarte em 2026-10-01: 15 cenários de orquestração, nove de verificação de ausência e oito testes Python novos aprovados; 22 de destino, 16 de provisionamento e nove testes Python existentes continuam aprovados. Actionlint dos três workflows e diff sem erros. Revisor aceitou offline o JSON do plano histórico de hom com 37 exclusões; esse plano foi apenas lido, não aplicado. Nenhuma chamada real AWS ou exclusão executada nesta implementação.

- [Plan em modo destroy e aplicação de plano salvo](https://developer.hashicorp.com/terraform/cli/commands/plan)
