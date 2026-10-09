# JWT compartilhado por ambiente

## Recursos e contrato

Implementação da infraestrutura preparada em 2026-10-08. Bootstrap aplicado com plano salvo aprovado: 4 criações, nenhuma alteração/exclusão; conferência posterior No changes e simulação IAM confirmaram metadados permitidos sem leitura da chave pela base. Base hom aplicada pelo workflow e conferida em 2026-10-08: Secret/AWSCURRENT, SSM, confiança e associação Pod Identity corretos, agente ACTIVE, simulação IAM isolada e plano No changes sem rotação. A chave não foi lida. Consumo dos runtimes e provisionamento/validação prd permanecem pendentes. E2.12 continua aberta até integração da função e compatibilidade com a API.

A base administra o Secret /mecanica/<ambiente>/base/jwt e publica os parâmetros String /mecanica/<ambiente>/base/v2/jwt-secret-arn, jwt-issuer e jwt-audience. Hom usa issuer mecanica-hom-auth e audience mecanica-hom-api; prd usa mecanica-prd-auth e mecanica-prd-api. Issuer é um identificador lógico, sem exigir um endpoint OIDC. Algoritmo HS256, expiração de dez minutos, claims e tolerância de relógio permanecem definidos no contrato de autenticação.

O valor é JSON com somente o campo key: 64 caracteres alfanuméricos gerados criptograficamente por ephemeral.random_password. O recurso aws_secretsmanager_secret_version usa secret_string_wo e revisão fixa 1; não usar random_password persistente, secret_string, outputs da chave ou TF_LOG. Cada execução pode gerar um candidato efêmero, mas a revisão inalterada não publica outra versão. A chave efetiva fica somente no Secrets Manager, criptografada pela chave padrão do serviço.

Não habilitar rotação automática. Uma futura rotação exige plano e operação coordenada de ambos os emissores/validadores; os processos manterão a chave em memória até reiniciar. Não incrementar a revisão nem substituir a versão para validar esta entrega.

## Identidade da API e consumo posterior

A policy read-jwt da role mecanica-<ambiente>-api-runtime lê somente o Secret JWT exato e os três parâmetros JWT do seu ambiente. A E2.6 acrescenta a policy Terraform read-database para os seis parâmetros públicos database/v2 e o Secret database/api do mesmo ambiente; a implementação está preparada e o apply depende de plano salvo aprovado. A confiança exige pods.eks.amazonaws.com, sts:AssumeRole/sts:TagSession e tags de cluster ARN, namespace default e ServiceAccount gerenciamento-api. A base administra a associação EKS Pod Identity; o agente já existe.

O repositório da API implementa o ServiceAccount e serviceAccountName nos overlays hom/prd, com configuração runtime pelo SDK .NET. A associação existe antes desses manifestos. Sua aplicação exige primeiro o apply aprovado da policy do banco e a publicação da imagem ECR com digest; a tag provisória pending não deve ser aplicada. O modo local mantém db-secrets.

Na integração, API e função carregarão issuer/audience/ARN e a versão AWSCURRENT na inicialização usando SDK .NET, com credenciais de suas roles. Preencher Jwt:Key, Jwt:Issuer e Jwt:Audience, manter a chave em memória e não consultar AWS a cada requisição. Falha de leitura, JSON inválido, campo key ausente/curto ou issuer/audience vazios impedem a inicialização, sem fallback para a chave local. Não copiar a chave para Kubernetes, CI, imagem ou arquivo gerado.

A role de execução Lambda será provisionada pelo repositório de autenticação em sua etapa própria. Ela receberá leitura do JWT do ambiente; não há role provisória nesta entrega. A role da API receberá somente o Secret database/api e os seis parâmetros previstos após aprovação/apply da policy E2.6; não recebe auth, Secret administrativo RDS nem outro ambiente. As pipelines API/auth não precisam ler a chave.

## Provisionamento e aprovação

1. Revisar/aplicar o plano salvo administrativo do bootstrap, que acrescenta uma policy gerenciada base-jwt e sua associação para cada ambiente. Não aumenta policies inline e não concede GetSecretValue à pipeline da base.
2. Publicar o PR da base e disparar base-provision para hom; revisar os recursos JWT/identidade e os três parâmetros SSM. Preservar VPC/EKS/NLB e RDS. Prd será aplicado separadamente quando autorizado.
3. Aprovar no Environment protegido; o workflow aplica exatamente seu plano salvo. Seus três jobs e comandos Kubernetes permanecem iguais.
4. Conferir metadados/versão atual, SSM público, confiança e associação, e gerar novo plano sem mudanças. Isso valida a infraestrutura; não comprova emissão/aceitação de JWT pelos runtimes ainda não integrados.

## Conferência com ferramentas padrão

Exemplos para hom, usando perfil autorizado e sem imprimir a chave:

~~~powershell
aws secretsmanager describe-secret --region us-east-1 --secret-id /mecanica/hom/base/jwt
aws secretsmanager list-secret-version-ids --region us-east-1 --secret-id /mecanica/hom/base/jwt
aws ssm get-parameters --region us-east-1 --names /mecanica/hom/base/v2/jwt-secret-arn /mecanica/hom/base/v2/jwt-issuer /mecanica/hom/base/v2/jwt-audience
aws eks list-pod-identity-associations --region us-east-1 --cluster-name mecanica-hom-eks --namespace default --service-account gerenciamento-api
aws iam get-role --role-name mecanica-hom-api-runtime
aws iam get-role-policy --role-name mecanica-hom-api-runtime --policy-name read-jwt
terraform -chdir=terraform plan '-var-file=environments/hom.tfvars' -out=verification.tfplan
terraform -chdir=terraform show -no-color verification.tfplan
~~~

A repetição deve preservar VersionId/AWSCURRENT e não planejar rotação. Com IAM Policy Simulator, conferir leitura JWT/SSM permitida no ambiente, e negada para JWT do outro ambiente e Secrets administrativos RDS. Não é necessário executar GetSecretValue para simular autorização.

Revisar plano/estado com terraform show -json: secret_string_wo não é persistido e secret_string/secret_binary não devem conter valores. Nunca imprimir ou procurar o conteúdo da chave para fazer essa conferência. Inspecionar somente a estrutura desses atributos.

## Descarte

O destroy da base remove associação, role, parâmetros e Secret JWT sem janela de recuperação, seguindo a política já usada para as credenciais do banco. Consumidores e banco devem ser descartados antes. Recriação completa do ambiente gera nova chave e invalida tokens antigos. Não executar destroy para testar.

Referências: [contratos centrais](https://github.com/pknfelps/GerenciamentoMecanicaSistema/blob/develop/docs/arquitetura/CONTRATOS_ENTRE_REPOSITORIOS.md), [ephemeral Random](https://raw.githubusercontent.com/hashicorp/terraform-provider-random/v3.7.2/docs/ephemeral-resources/password.md), [versão write-only](https://raw.githubusercontent.com/hashicorp/terraform-provider-aws/v6.58.0/website/docs/r/secretsmanager_secret_version.html.markdown) e [Pod Identity](https://docs.aws.amazon.com/eks/latest/userguide/pod-id-association.html).
