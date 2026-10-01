# Permissões e pipelines da base — E2.9/E2.4

Implementação local de 2026-09-30. Não comprova aplicação ou execução no GitHub/AWS.

## Propriedade e escopo

- `bootstrap/base-permissions.tf`: quatro policies gerenciadas por ambiente (criação EC2, manutenção EC2, EKS e IAM), anexadas somente à role base. Políticas completas estão nesse arquivo; cada policy tem precondition para o limite de 6144 caracteres do IAM. A role base não altera a própria role/trust/policies nem acessa o estado compartilhado.
- EC2: leituras regionais explicitamente listadas; criação com tags Project/Environment/ManagedBy; uso e manutenção de recursos existentes com essas tags. Tags de identidade não podem ser removidas ou trocadas pela pipeline. Wildcards de IDs são necessários para recursos ainda não criados; região/conta e tags delimitam o acesso.
- EKS: cluster e filhos do próprio ambiente; criação com tags, modo API_AND_CONFIG_MAP e bootstrap administrativo implícito desabilitado. Access entries limitadas a mecanica/base/API/banco do ambiente. Associação administrativa somente base/operador; Edit somente default para API/banco. ReadAddonCatalog/CreateCluster exigem Resource * conforme a referência AWS, com restrições de região/tags para criação.
- IAM: gerenciamento das três roles de execução EKS existentes no código. Cada role pode receber somente as policies AWS específicas do seu serviço; PassRole usa ARN exato e PassedToService. Criação de service-linked roles limitada a EKS/nodegroup/Auto Scaling; inicialização de suas policies limitada aos respectivos paths. O gerenciamento dessas roles pelas pipelines é a ampliação planejada em E2, preservando as roles OIDC sob administração do bootstrap.
- API/banco: inline policy separada concede apenas DescribeCluster do ambiente, para configurar kubeconfig. Autorização Kubernetes vem das access entries da base.
- `terraform/pipeline-access.tf`: três entries por cluster, base ClusterAdmin, API/banco Edit em default. `default` mantém compatibilidade com os manifests atuais; alterar namespace exige revisar manifests, escopos e policies juntos. Gateway/auth não usam kubectl neste passo.
- Rede Aurora/Secrets Manager/controller/NLB e policies desses componentes continuam nas etapas seguintes; este trabalho cobre a base EKS/VPC existente.

## Cluster existente e clusters novos

`environments/hom.tfvars` preserva bootstrap_cluster_creator_admin_permissions=true do cluster já criado pelo operador. Não mudar em lugar: esse atributo é de criação e o provider propõe substituir o cluster. `prd.tfvars` e o exemplo usam false para criação nova, evitando que EKS crie automaticamente uma entry da role base e conflite com a entry do Terraform.

Após um descarte autorizado de hom, mudar explicitamente o arquivo hom para false antes da recriação. O workflow recusa criar cluster com true. Não há import, target, force-unlock, migração, destroy ou alteração automática desse atributo. Se um cluster tiver sido criado fora desse fluxo pela mesma role base e já tiver entry implícita, revisar/adotar o recurso em uma operação explícita antes de prosseguir.

## Ordem de ativação pelo mantenedor

1. Revisar/commitar/agrupar PRs conforme a coordenação do usuário. PR para develop executa `ci`: fmt/validate, mocks hom/prd, testes de seleção, destino/aprovação e fingerprint. Não recebe credenciais AWS.
2. No repositório infra, autenticar uma identidade administrativa autorizada ao bootstrap, confirmar conta 121754142617 e usar o backend remoto existente. Gerar **novo** plano de bootstrap, revisar e aplicar localmente. Não reutilizar os planos antigos nem reiniciar com estado local vazio. Exemplo, depois do init remoto correto: `terraform -chdir=bootstrap plan -input=false -var-file=bootstrap.tfvars.example -out=bootstrap.tfplan`, seguido de `terraform -chdir=bootstrap show bootstrap.tfplan`; aplicar somente o plano revisado.
3. Conferir Environment variables: AWS_REGION=us-east-1, AWS_BASE_ROLE_ARN e TF_STATE_BUCKET em infra; AWS_ROLE_ARN em API/banco. hom aceita develop; prd aceita main. Provider/trust OIDC e Environments já existem; não é necessário recriá-los nem criar access keys.
4. Publicar os workflows. Para Run workflow, `workflow_dispatch` precisa existir na branch padrão; escolher develop/hom ou main/prd. Não promover código incompleto só para disponibilizar o botão: coordenar a publicação com a política das branches.
5. Executar `base-provision`, action=plan, em develop/hom. O workflow assume a role base, usa backend/params próprios, gera resumo com endereços/ações e fingerprint. Planos/estados/valores permanecem privados no runner, sem upload para artefatos, PRs ou logs públicos.
6. Revisar o código e o resumo. Executar action=apply com expected_commit igual ao SHA completo do run revisado e approved_plan_sha256 igual ao fingerprint. O workflow regenera o plano, compara o fingerprint e aplica esse mesmo binário. Mudança de commit/plano exige nova revisão. Planos com exclusão ou substituição são recusados, inclusive na execução manual. Não há workflow de descarte neste passo.
7. O workflow valida cluster/nodegroup/add-ons, Ready dos nós/pods de sistema e acesso Kubernetes da role base. Nos repositórios infra/API/banco, executar `aws-oidc-check` com check_kubernetes=true para validar cada identidade OIDC positiva e suas permissões de kubectl. Infra testa Kubernetes somente no job base; gateway mantém diagnóstico STS.
8. Repetir em prd na janela de uso escolhida, gerando plano e aprovação próprios. Nunca reutilizar fingerprint, backend ou kubeconfig de hom.

O primeiro apply das access entries pode ser feito pelo workflow base depois de aplicar as novas permissões do bootstrap; ele usa a API EKS e não precisa de kubectl para criar sua entry. Também é possível gerar/aplicar novo plano local com o operador mecanica, mantendo as mesmas configurações.

## Comportamento após merge

`base-provision` responde a push em develop/main quando terraform/scripts/seu próprio workflow mudam. develop seleciona hom; main seleciona prd. Inicializa o backend, planeja e aplica alterações não destrutivas somente se o plano não criar um cluster. Um ambiente ausente registra **ativação pendente** e não é criado automaticamente; a primeira ativação usa plan/apply manual com fingerprint. PR não ativa infraestrutura.

O apply automático presume código revisado pelas proteções do repositório; o workflow não cria essas proteções. Alterações apenas em bootstrap não disparam a base nem aplicam permissões automaticamente: permanecem sob identidade administrativa. O grupo concurrency base-hom/base-prd não cancela um apply em andamento; o lock S3 protege o estado contra outros processos. Esta concorrência é local ao repositório infra, não uma trava global entre os quatro componentes.

Falha parcial interrompe o workflow, preserva o estado e não marca sucesso. Nenhum retry de apply/descarte automático. Diagnóstico Kubernetes consulta identidade/can-i/listagens; não cria workloads. Não comprova capacidade funcional da API/observabilidade nem o lock concorrente E2.3.

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
pwsh -NoProfile -File scripts/tests/Test-BasePipelineTarget.ps1
pwsh -NoProfile -File scripts/tests/Test-BasePipeline.ps1
python -m unittest discover -s scripts/tests -p 'test_*.py' -v
```

Usar init -backend=false em TF_DATA_DIR de validação separado antes de validate/test; não reaproveitar metadados remotos no modo offline. Esses testes não conectam à AWS. Não iniciar Docker.

## Referências

- [Referência programática AWS de serviços](https://docs.aws.amazon.com/service-authorization/latest/reference/service-reference.html)
- [EKS access entries](https://docs.aws.amazon.com/eks/latest/userguide/access-entries.html)
- [STANDARD, PassRole e consistência eventual de access entries](https://docs.aws.amazon.com/eks/latest/userguide/creating-access-entries.html)
- [Permissões das access policies EKS](https://docs.aws.amazon.com/eks/latest/userguide/access-policy-permissions.html)
- [IAM PassRole](https://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles_use_passrole.html)
- [Execução manual de workflows](https://docs.github.com/en/actions/how-tos/manage-workflow-runs/manually-run-a-workflow)
