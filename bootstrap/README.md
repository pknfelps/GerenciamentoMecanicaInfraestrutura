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
