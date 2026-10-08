# Migração declarativa e validação

Preparação local autorizada; cada operação AWS exige plano salvo e aprovação. Preservar chaves dos backends, nomes e endereços VPC/EKS/RDS. Não há reconstrução planejada desses recursos. Rejeitar replacement deles no plano e investigar antes de aplicar. Remoções esperadas: EBS CSI, sua role/policy/identidade, controller/role/identidade se estiverem no estado, terraform_data de geração/snapshot, e posteriormente SSM v1 ativo. Criações esperadas: NLB/listener/target group/ASG attachment, SSM v2 e objetos do Job.

## 1. Permissões e controller legado

Revisar/aplicar plano do bootstrap com allow_legacy_cleanup=true. Se houver Service LoadBalancer/controller já implantados, fazer a limpeza com o mecanismo antigo ainda disponível, antes do primeiro apply novo:

```bash
aws eks update-kubeconfig --region us-east-1 --name mecanica-hom-eks --kubeconfig ./migration-kubeconfig
kubectl --kubeconfig ./migration-kubeconfig -n default get service svc-gerenciamento-api
kubectl --kubeconfig ./migration-kubeconfig -n kube-system get deployment aws-load-balancer-controller
# Somente se o Service antigo existir e for LoadBalancer:
kubectl --kubeconfig ./migration-kubeconfig -n default delete service svc-gerenciamento-api --wait=true
# Com o ARN do NLB antigo conferido no console/describe-load-balancers:
aws elbv2 wait load-balancers-deleted --region us-east-1 --load-balancer-arns <ARN-ANTIGO>
# Somente depois da limpeza AWS, se o chart tiver sido instalado:
helm --kubeconfig ./migration-kubeconfig uninstall aws-load-balancer-controller -n kube-system
```

Helm aparece somente para desinstalar o legado, não na nova operação. Não remover finalizers à força. Conferir também target groups/SGs legados antes de criar recurso com o mesmo nome. Se não houver controller/Service/NLB antigos, não há essa limpeza. Role/associação gerenciadas no estado antigo serão retiradas pelo novo plano Terraform. Remover Job/ConfigMap/Secrets antigos em default com role base/operador, antes de restringir database a database-init; o banco novo não terá autorização em default.

## 2. Base e banco v2

Publicar os arquivos por PR. Executar base-provision, revisar preservação de VPC/EKS/node group, remoção CSI/controller e novos recursos NLB/SSM. Aprovar somente esse plano. Após apply, namespace database-init e Service NodePort devem existir. Não é necessário target healthy antes da API.

Executar database-provision pela primeira vez com adopt_existing_credentials=true se os secrets API/auth já existem. Importa apenas metadados, cria versão write-only copiando a senha AWSCURRENT e entrega Secrets temporários ao Job. RDS e regras existentes permanecem. Em prd novo, usar false. Após adoção bem-sucedida, voltar a false nas execuções seguintes; revisão write-only fixa evita rotação. Não importar secret versions comuns, não exibir valores, não habilitar TF_LOG.

Validar Job Complete/logs, repetir provisionamento com false: mensagem Matching schema already initialized, initialized_at original preservado, roles/grants mantidos, Secrets temporários ausentes. Consultar marcador manualmente somente com cliente/credencial autorizados, sem publicar senha. SQL incompatível deve interromper sem reaplicar; não mudar Init.sql vivo apenas para provocar erro.

## 3. Consumidores e retirada v1 em planos dedicados

Migrar consumidores existentes para `/v2/`; API/auth/Gateway ainda sem consumidor de infraestrutura implantado seguem o contrato v2 ao serem implementados. Não retirar v1 usado por revisões antigas em execução. Manter operações sequenciais e gerar outro plano dos consumidores após alteração de dependências.

`terraform/legacy-ssm.tf` permite adotar parâmetros públicos ativos no MESMO estado/backend do produtor. Inventariar nomes pelo console ou `aws ssm get-parameters-by-path --path /mecanica/hom/base/v1/ --recursive --query 'Parameters[].Name'`. Não buscar valores de Secrets Manager. Selecionar apenas parâmetros ativos; não incluir caminhos de attempts nem registros históricos de tentativas; candidatos/evidências ativos antigos podem ser retirados após a migração.

No root Terraform do produtor, usar init/backend do ambiente e gerar plano de adoção, por exemplo:

```bash
terraform plan -var-file=environments/hom.tfvars -var='legacy_parameter_names=["/mecanica/hom/base/v1/database-release"]' -out=adopt-v1.tfplan
terraform show -no-color adopt-v1.tfplan
# Apos revisao/aprovacao:
terraform apply adopt-v1.tfplan
# Sem a lista, planeja a remocao dos objetos adotados:
terraform plan -var-file=environments/hom.tfvars -out=retire-v1.tfplan
terraform show -no-color retire-v1.tfplan
# Apos NOVA revisao/aprovacao:
terraform apply retire-v1.tfplan
```

Conferir que esses planos mostram apenas adoção/retirada pretendida; no banco também haverá recriação dos Secrets temporários após cleanup. Se usar operação local do banco, executar Job/diagnóstico/cleanup com os mesmos comandos documentados no seu README ao final, inclusive em erro. Backend do banco mantém sua chave; não importar seus parâmetros no estado da base. Histórico fica fora do Terraform legado. Em seguida, plano administrativo allow_legacy_cleanup=false retira permissões temporárias.

## Validação padrão

fmt/validate e renderização Kustomize cobrem sintaxe. Plano remoto comprova preservação/migração. Workflows devem aguardar required reviewer e aplicar artefato daquele run, sem novo plan. Conferir no console Secrets temporários removidos e estados sem secret_string/data comuns com valores; não anexar estados/logs sensíveis como evidência. Depois do deploy API, targets healthy e /health/ready 200 pelo caminho privado/Gateway. Descarte só no ciclo solicitado: consumidores → banco → base; backend/bootstrap e outro ambiente permanecem.

Não há novos scripts de teste ou descarte de validação. Validação remota da reformulação permanece pendente até o mantenedor aprovar e executar os planos.
