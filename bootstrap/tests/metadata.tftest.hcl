mock_provider "aws" {}

variables {
  aws_account_id = "121754142617"
  github_subject_prefixes = {
    api      = "repo:pknfelps/GerenciamentoMecanicaSistema"
    infra    = "repo:pknfelps/GerenciamentoMecanicaInfraestrutura"
    database = "repo:pknfelps/GerenciamentoMecanicaBancoDados"
    auth     = "repo:pknfelps/GerenciamentoMecanicaAutenticacao"
  }
}

run "metadata_permissions_are_scoped" {
  command = plan
  assert {
    condition = alltrue([for environment in local.environments :
      jsondecode(aws_iam_role_policy.base_metadata_network[environment].policy).Statement[1].Condition.StringEquals["aws:RequestTag/Environment"] == environment &&
      jsondecode(aws_iam_role_policy.base_metadata_network[environment].policy).Statement[2].Condition.StringEquals["ec2:ResourceTag/Environment"] == environment &&
      jsondecode(aws_iam_role_policy.base_metadata_network[environment].policy).Statement[3].Condition.StringEquals["ec2:CreateAction"] == "CreateSecurityGroup" &&
      jsondecode(aws_iam_role_policy.base_metadata_network[environment].policy).Statement[4].Condition.StringEquals["ec2:ResourceTag/Name"] == "mecanica-${environment}-auth" &&
      toset(jsondecode(aws_iam_role_policy.base_metadata_network[environment].policy).Statement[4].Action) == toset(["ec2:DeleteSecurityGroup", "ec2:RevokeSecurityGroupEgress"]) &&
      length(aws_iam_role_policy.base_metadata_network[environment].policy) + length(jsonencode(local.pipeline_policies["${environment}-base"])) < 10240
    ])
    error_message = "Extensão deve ficar no ambiente/SG reservado e dentro da quota inline da role."
  }
  assert {
    condition = alltrue([for environment in local.environments :
      one([for statement in local.pipeline_policies["${environment}-base"].Statement : statement if statement.Sid == "PublishOwnMetadata"]).Resource == ["arn:aws:ssm:us-east-1:121754142617:parameter/mecanica/${environment}/base/v1/*"] &&
      one([for statement in local.pipeline_policies["${environment}-database"].Statement : statement if statement.Sid == "PublishOwnMetadata"]).Resource == ["arn:aws:ssm:us-east-1:121754142617:parameter/mecanica/${environment}/database/v1/*"]
    ])
    error_message = "Base e banco devem publicar somente no próprio namespace."
  }
}
