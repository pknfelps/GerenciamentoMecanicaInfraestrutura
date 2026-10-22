# Infraestrutura planejada — autenticação e captura SMTP

**22/10/2026 — plano de infraestrutura com avanços locais registrados abaixo.** Sem aplicação AWS nesta preparação. [Plano extra AE.1–AE.10](https://github.com/pknfelps/GerenciamentoMecanicaSistema/blob/develop/docs/PLANO_EXTRA_AUTENTICACAO_E_EMAIL.md), independente de E5/E6/E7. O repositório de funções já foi renomeado GerenciamentoMecanicaServerless na AE.2 e administrará auth/email em duas stacks SAM separadas.

## Responsabilidades a implementar

- Bootstrap: revisar confiança OIDC de transição de nome, policies de pipeline por componente e role runtime email; conceder à API/auth invocação restrita do alias email do ambiente. Email não precisa de acesso ao RDS ou Secret JWT. Logs/configuração/SMTP e eventual telemetria terão somente as permissões necessárias.
- Base: SMTP4dev por ambiente em EKS, relay externo desabilitado e mensagens efêmeras sem PVC. Expor endpoint SMTP privado alcançável pela função email na VPC; apenas ClusterIP ou DNS do Service não basta. AE.1 define NLB interno existente TCP 2525, target group/NodePort 30025 próprios e SG de origem email, preservando o listener da API. Captura demonstrativa sem TLS/autenticação SMTP, sem apresentar rede privada como criptografia. AE.4 implementará e comprovará regras/capacidade; sem IP efêmero fixado em configuração.
- Caixa: acesso operacional privado por port-forward, não uma rota pública da API ou funcionalidade do JWT Mechanic. Não enviar código em logs/respostas públicas. Captura simula recebimento e não comprova e-mail pessoal.
- Gateway: admitir somente os dois endpoints HTTP novos de auth, remover a restrição exclusiva customers/validate e ajustar Invoke permission/contrato. Encaminhar JWT às operações da API sem Authorizer nem substituição por JWT vinculado à OS. Preservar integração privada, logs sanitizados, retention/data tracing atuais e versão numérica de auth.
- Integração email: catálogo separado com ARN de alias estável, versão auditável e metadados técnicos sem segredos. API/auth invocam sincronamente e verificam erros da função, respeitando prazo total; sem fila/retry próprio/garantia de entrega única.

As roles persistentes continuam no bootstrap e são referenciadas pelo SAM; não transferir recursos já existentes de proprietário automaticamente. Prefixos S3/SSM e permissões das pipelines auth/email devem ser independentes. A função nova é privada, sem Gateway/Function URL de envio.

## Ordem futura e bloqueios

Provisionar bootstrap aprovado/aplicado → base com SMTP4dev → banco inicializado e email → API/auth → Gateway. Banco e email são independentes; API/auth podem seguir após suas dependências. Dois templates/stacks permitem atualizar o envio sem republicar auth/API somente para trocar número de versão.

Destruir Gateway → API/auth → banco/email → base. Email-destroy bloqueia enquanto API/auth existirem e verifica seus resíduos de rede. Database-destroy mantém seus consumidores API/auth; não inventar dependência de RDS para email. Base-destroy precisa exigir também email ausente, além de banco, porque a função depende da rede/SMTP4dev da base. Falhas de inspeção não são ausência; preservar bloqueio imediato, sem exclusão manual de ENIs ou alterações automáticas de estado.

Renomear o repositório exige revisar OIDC, links/referências, Environments/variáveis/required checks e proteções de artefatos antes de executar workflows novos. Preparar/aplicar a confiança necessária antes da troca e retirar confiança antiga depois, mediante autorização. Não ampliar principal ou região como atalho.

## Validação e limites

Preparar Kustomize, Terraform/bootstrap/base, SAM e actionlint/ShellCheck com ferramentas existentes, sem scripts auxiliares ou mocks operacionais. Validar capacidade/rede, caixa sem relay e sem persistência, IAM e isolamento entre ambientes, endpoint privado e fluxos com falhas. Aplicações/contratos e banco mudam nos seus repositórios, de forma coordenada; não basta instalar SMTP4dev.

Mensagens poderão ser perdidas ao recriar pod/ambiente. Desafios continuam no banco até expiração/consumo e a aplicação deve permitir solicitar novo código. Sem envio externo, UI pública, persistência da caixa, teste de carga ou novo aceite E5. Planos/apply das próximas entregas, destroy e publicação dependem de autorização posterior; a transição administrativa AE.2 tem registro específico abaixo.


## Consolidação AE.1

[Contrato central](https://github.com/pknfelps/GerenciamentoMecanicaSistema/blob/develop/docs/CONTRATOS_EXTRA_AUTENTICACAO_E_EMAIL.md): SMTP4dev 3.15.0 com banco em memória, 100 mensagens/sessões, sem PVC/relay; web somente ClusterIP/port-forward. Base publica smtp-host/smtp-port/email-security-group-id; stack email publica catálogo email/v1 e alias live. EmailFunction recebe configuração SMTP no deploy, sem acesso a banco/JWT. Não criar outro NLB nem expor SMTP/UI publicamente. Os recursos e suas permissões continuam pendentes, sujeitos aos planos/aprovações próprios.


## AE.2 — migração e finalização OIDC

Transição inicial aprovada/aplicada em 22/10/2026: 0 criações, 3 alterações de trust e 0 exclusões nas roles auth-ci/hom-auth/prd-auth, sem mudanças de permissões. GitHub/raiz/remote já usam GerenciamentoMecanicaServerless, mantendo owner/repository ID, visibilidade, proteções e Environments. [Auth-ci #16](https://github.com/pknfelps/GerenciamentoMecanicaServerless/actions/runs/39812817320) passou em develop e confirmou a autenticação OIDC do novo nome.

O prefixo canônico auth em bootstrap.tfvars local e bootstrap.tfvars.example agora usa GerenciamentoMecanicaServerless. A variável e o exemplo temporários foram retirados do código local. [Plano final salvo](https://github.com/pknfelps/GerenciamentoMecanicaSistema/blob/develop/docs/AE2_FINALIZACAO_OIDC_2026-10-22.md): 0 criações, 3 alterações, 0 exclusões; remove somente os subjects antigos. Aprovado/aplicado com hash conferido: 0 criações, 3 alterações e 0 exclusões. Trust policies implantadas conferidas, subjects antigos ausentes e Terraform posterior sem diferenças (código 0). AE.2 concluída; alterações locais seguem para PR do mantenedor. Não reaplicar o plano inicial consumido nem usar os antigos tfvars de transição.

Estrutura AuthFunction/EmailFunction validada localmente; função de envio, SMTP, IAM e publicação permanecem nas próximas etapas AE, sem alterações funcionais nesta migração.


## Revisão do mantenedor — AE.3

Tabelas customer_auth_challenges/customer_auth_request_limits diretamente no Init.sql para banco vazio; sem migrations. O destroy do ambiente remove a instância RDS, e novo provisionamento recria os dados a partir do SQL. Nenhum CHECK de negócio, UNIQUE condicionado ao estado, FK nova de cliente ou cascata; regras de validade, tentativas, estados e consumo são implementadas/validadas em C#, com transações e operações condicionais.

Auth consulta o cliente antes de qualquer gravação. Se ausente, registra somente mensagem fixa sanitizada e retorna imediatamente o 202 genérico com identificador opaco em memória; não persiste desafio, limite ou auditoria nem executa envio/limpeza. Para cliente existente elegível, limites usam customer_id; não há HMAC/HKDF do documento para o índice. Código continua protegido por PBKDF2-SHA256. Esse fluxo será implementado na AE.6; o ajuste atual consolida o contrato e o DDL.

## AE.4 — IAM preparado localmente

[Registro de implementação](AE4_IAM_EMAIL.md): bootstrap declara roles runtime/pipeline email hom/prd, policies próprias para SAM/artefatos/catálogo email/v1, consumo do alias live pelo runtime auth e autorização da base para os futuros SG/target group SMTP/access entry de inspeção. terraform/api-email.tf acrescenta o consumo ao runtime API no seu proprietário atual. As policies/trusts antigas auth/CI e os workflows permanecem intactos.

Terraform fmt/init sem backend/validate aprovados no bootstrap e na base; JSONs/trusts hom/prd e limites conferidos localmente. A confiança email exige audience/subject exatos; develop/hom e main/prd dependerão das restrições GitHub/workflows AE.8, sem claim ref personalizada. Roles separadas com o mesmo contexto OIDC não isolam acesso aos workflows. A AE.2 permanece concluída, sem refazer rename/trust antigos.

Esta parte não criou SMTP4dev, SG/listener/target group, access entry, catálogos, função, alias ou workflow email. Eles permanecem nas etapas próprias da AE.4/AE.5/AE.8. Publicação/aplicação e comprovação na AWS exigem autorização posterior; AE.4 não foi marcada como concluída.

## AE.4 — manifestos SMTP4dev validados localmente

[Implementação e evidências](AE4_SMTP4DEV_MANIFESTOS.md): Kustomization comum em kubernetes/smtp4dev, incluída na raiz; namespace/ServiceAccount sem token, Deployment sem root/capabilities com readonly e emptyDirs em memória, ConfigMap com hash, Service SMTP NodePort 30025 e web ClusterIP. Container usa 2525/8080; Services preservam 25/80. Captura 3.15.0 sem relay/PVC, retenção 100/100, limite MIME 512 KiB e logs técnicos sem conteúdo.

Renderização hom/prd e schemas Kubernetes aprovados; Docker confirmou captura, retenção, bloqueio de settings, ausência de dados fictícios no stdout e perda integral da caixa após reinício. Não é comprovação de acesso Lambda ou capacidade EKS. Terraform/rede/SSM, bloqueios de descarte e associação de inspeção continuam pendentes. Workflows não foram alterados/executados e AE.4 continua parcial. A remoção do volume SMTP do Compose local será feita na integração AE.5/AE.7, sem alterar o volume PostgreSQL.

## AE.4 — rede SMTP e metadados preparados localmente

[Implementação/revisão](AE4_REDE_SMTP.md): SG reservado email, listener TCP 2525 no NLB existente, target group SMTP/30025 com health TCP e attachment independente ao mesmo ASG; regras entre SG email → NLB → EKS. Preservados HTTP/80, target group e health check API, VPC Link e recursos de rede. Base/v2 ganha smtp-host, smtp-port e email-security-group-id. Permissões previamente preparadas cobrem esta parte, sem ampliar bootstrap.

Terraform fmt/init sem backend/validate aprovados, com lockfile/providers preservados. Nenhum plano, apply ou teste AWS. Associação de inspeção e bloqueios de descarte continuam pendentes na AE.4; função/egress SAM e consumidores nas AE.5–AE.8. Os registros anteriores descrevem o escopo de cada parte, não comprovação de implantação.

## AE.4 — inspeção/descarte e preparação local concluída

[View/default e bloqueios da base](AE4_INSPECAO_E_DESCARTE.md) implementados: a pipeline email pode inspecionar os consumidores da API; base-destroy verifica função email, ENIs e egress antes do plan e antes da limpeza/apply, além do banco. SG reservado isolado é permitido. Erros e resíduos bloqueiam imediatamente. Bootstrap troca GetFunctionConfiguration pela listagem Lambda regional em JSON, sem escrita/Invoke ou acesso a Secrets.

Terraform da base/bootstrap e actionlint/ShellCheck aprovados; policy base-email com 3.112 caracteres por ambiente. Preparação local AE.4 concluída, sem aplicação/comprovação AWS. EmailFunction segue na AE.5; email-destroy e seus próprios bloqueios seguem junto dos workflows na AE.8. Registros anteriores descrevem o estado de cada etapa; os aceites oficiais E5/E6/E7 permanecem intactos.
