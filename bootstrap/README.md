# Bootstrap administrativo persistente

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
