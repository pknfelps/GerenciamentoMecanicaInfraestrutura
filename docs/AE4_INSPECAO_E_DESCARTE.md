# AE.4 — Inspeção Kubernetes e bloqueio do descarte da base

**22/10/2026 — preparado e validado localmente para hom/prd.** Sem login, plano/apply AWS, consulta de recursos, execução remota ou destroy. Completa a preparação local da AE.4 junto de [IAM](AE4_IAM_EMAIL.md), [manifestos/captura](AE4_SMTP4DEV_MANIFESTOS.md) e [rede/SSM](AE4_REDE_SMTP.md). Implantação, capacidade e comprovação AWS continuam na AE.10; workflows próprios email na AE.8.

## Acesso de inspeção da pipeline email

`terraform/pipeline-access.tf` inclui email no mapa existente, criando uma access entry STANDARD para a role persistente `arn:aws:iam::121754142617:role/mecanica/pipelines/mecanica-ENV-email-github` e associando `AmazonEKSViewPolicy` somente ao namespace default. ENV continua derivado do ambiente hom/prd validado e do cluster correspondente.

Permite conferir Deployment/HPA/ServiceAccount, pods e ReplicaSets da API antes do futuro email-destroy. A [policy AWS](https://docs.aws.amazon.com/eks/latest/userguide/access-policy-permissions.html#access-policy-permissions-amazoneksviewpolicy) não concede edição, leitura de Secrets, execução ou port-forward. O escopo default não dá acesso à caixa no namespace smtp4dev. O acesso web permanece operacional, via kubeconfig autorizado e port-forward, conforme o procedimento dos manifestos.

A role email pertence ao bootstrap; a base administra somente sua access entry/associação. As associações existentes de base, API, banco e operador permanecem intactas. As permissões administrativas do bootstrap já limitam criação/associação à role email exata, ViewPolicy e namespace default; não foi ampliada essa autorização.

## Check email removal no base-destroy

A etapa é executada no job plan antes de gerar tfplan e repetida no job apply antes de kubeconfig, remoção do Collector/SMTP4dev/manifestos e aplicação do plano aprovado. Preserva as checagens do banco e o fluxo plan → aprovação → apply exclusivo do plano salvo, sem replan.

A pipeline consulta somente as dependências diretas da base: banco e email. Não repete Gateway/API/auth; os bloqueios dos consumidores fazem a cadeia nas etapas correspondentes.

| Checagem email | Resultado necessário |
|---|---|
| Lambda ListFunctions com filtro exato mecanica-ENV-email | Array JSON vazio |
| SG reservado mecanica-ENV-email | Ausente ou sem regras de saída |
| Interfaces associadas a cada SG encontrado | Array JSON vazio |

A existência isolada do SG não bloqueia, pois pertence à própria base. A função bloqueia independentemente de estado/configuração; ENIs ou egress remanescentes bloqueiam mesmo depois de a função desaparecer. Interfaces pendentes provocam falha imediata: aguardar liberação e repetir o futuro email-destroy antes de tentar base-destroy. Não há espera automática, remoção manual de ENIs/finalizadores ou state rm.

Todas as buscas usam nome derivado de hom/prd, região us-east-1 e conta admitida 121754142617 na autenticação OIDC. Paginação automática preservada; sem --no-paginate/--max-items. `set -euo pipefail` e validação JSON fazem erro AWS, acesso negado, parsing inválido ou formato inesperado interromperem a execução. Não tratar exceções como lista vazia ou usar ausência de SSM como prova de remoção. Mensagens exibem somente ambiente, nome e ID técnico do SG.

## Ajuste da inspeção IAM

`bootstrap/email-base-permissions.tf` substitui o GetFunctionConfiguration exato, ainda preparado para a implementação anterior, por ListFunctions regional. A consulta fornece um array JSON mesmo quando o nome não existe, sem interpretar texto de erro ResourceNotFound da CLI. A permissão de leitura necessária a essa operação é:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "InspectRegionalEmailCollection",
      "Effect": "Allow",
      "Action": ["lambda:ListFunctions"],
      "Resource": "*",
      "Condition": {
        "StringEquals": {"aws:RequestedRegion": "us-east-1"}
      }
    }
  ]
}
```

Esse statement integra a policy base-email já declarada; não cria outra policy/role. ListFunctions não permite restrição por ARN de função. A autorização pode listar metadados das demais funções na região; o filtro exato limita a checagem do workflow e não é isolamento IAM por ambiente. O workflow seleciona somente FunctionName, sem registrar configurações. O GetFunctionConfiguration anterior é removido, sem manter leitura redundante ou acrescentar Invoke, escrita Lambda ou acesso a Secrets.

As consultas EC2 usam permissões de inspeção de rede já existentes. Preservados grants EKS View/default do bootstrap, autenticação OIDC, providers, lockfiles e permissões runtime API/auth/email.

## Validação local

- Terraform 1.15.9: fmt -check, init sem backend com lockfile readonly e validate aprovados na base e no bootstrap.
- Actionlint 1.7.12 com ShellCheck aprovou base-destroy.yml. Nenhuma supressão acrescentada.
- JSON da policy real avaliado com Terraform console em diretório temporário apenas com locals/variáveis, sem provider/backend: **3.112 caracteres por ambiente**, abaixo de 6.144. Conferidos action/Resource/condição regional e precondition de tamanho existente. Não é simulação IAM remota.
- Referência pública programática Lambda confirma ListFunctions como ação de listagem sem recurso ARN; policy EKS oficial confere recursos e ausência de Secret/edição. Não foram consultados recursos da conta.
- Revisão estrutural: função existente, egress ou ENIs impedem prosseguir; SG isolado e ausência dos consumidores permitem continuar; consulta falha ou JSON inválido não permite limpeza. Filtros de hom/prd não se misturam. Os dois blocos de checagem são idênticos e antecedem operações destrutivas.

Não foram criados mocks, scripts operacionais, suítes de telemetria ou recursos de teste. Não foram executados os comandos AWS/kubectl/sam do workflow. Os cenários de bloqueio ainda precisam de conferência operacional autorizada; revisão local não comprova acesso/ausência reais.

Este passo declara duas novas instâncias de recursos EKS por ambiente (access entry e associação) e altera o documento da policy base-email hom/prd no bootstrap, sem novas permissões de escrita. Isso é comparação do código, não plano AWS.

## Ordem e próximas etapas

Descarte-alvo: Gateway → API/auth → banco/email → base/SMTP4dev. Banco não depende de email; email não depende de RDS. Remover a base exige ambos ausentes, inclusive resíduos indicados pelos bloqueios. Falhas interrompem a sequência.

O workflow email-destroy ainda não existe: será criado com SAM/workflows email na AE.8, exigindo ausência de API/auth antes de sam delete e ausência de ENIs/egress depois. Não criar agora stack/template de função vazio ou workflow operacional incompleto. Database-destroy e auth-destroy permanecem inalterados.

A preparação local da AE.4 está concluída; o próximo passo funcional é AE.5, EmailFunction. Aplicação posterior: bootstrap aprovado/aplicado → base com acesso/rede/manifestos → publicação dos consumidores na sequência AE.10. A publicação do base-destroy atualizado depende do bootstrap revisado, pois leitura negada bloqueia corretamente. A conferência de conectividade e dos bloqueios implantados será feita depois, sem executar destroys como teste durante a implementação.
