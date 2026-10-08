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

run "database_can_prepare_only_own_auth_credential" {
  command = plan

  assert {
    condition = alltrue([for environment in local.environments :
      aws_iam_role_policy.database_auth_secret[environment].role == aws_iam_role.pipeline["${environment}-database"].name &&
      length(jsondecode(aws_iam_role_policy.database_auth_secret[environment].policy).Statement) == 3 &&
      alltrue([for statement in jsondecode(aws_iam_role_policy.database_auth_secret[environment].policy).Statement :
        statement.Effect == "Allow" &&
        statement.Resource == "arn:aws:secretsmanager:us-east-1:121754142617:secret:/mecanica/${environment}/database/auth-??????" &&
        statement.Condition.StringEquals["aws:RequestedRegion"] == "us-east-1"
      ]) &&
      toset(jsondecode(aws_iam_role_policy.database_auth_secret[environment].policy).Statement[0].Action) == toset(["secretsmanager:CreateSecret", "secretsmanager:TagResource"]) &&
      jsondecode(aws_iam_role_policy.database_auth_secret[environment].policy).Statement[0].Condition.StringEquals == {
        "aws:RequestedRegion"        = "us-east-1"
        "aws:RequestTag/Project"     = "mecanica"
        "aws:RequestTag/Environment" = environment
        "aws:RequestTag/ManagedBy"   = "database-provision"
      } &&
      jsondecode(aws_iam_role_policy.database_auth_secret[environment].policy).Statement[1].Action == ["secretsmanager:DescribeSecret"] &&
      jsondecode(aws_iam_role_policy.database_auth_secret[environment].policy).Statement[2].Action == ["secretsmanager:GetSecretValue"] &&
      jsondecode(aws_iam_role_policy.database_auth_secret[environment].policy).Statement[2].Condition.StringEquals == {
        "aws:RequestedRegion"         = "us-east-1"
        "aws:ResourceTag/Project"     = "mecanica"
        "aws:ResourceTag/Environment" = environment
        "aws:ResourceTag/ManagedBy"   = "database-provision"
      }
    ])
    error_message = "A pipeline deve criar/descrever/ler somente a credencial auth do proprio ambiente, com as tags exigidas."
  }

  assert {
    condition = alltrue([for environment in local.environments :
      sum([
        length(aws_iam_role_policy.pipeline["${environment}-database"].policy),
        length(aws_iam_role_policy.workload_eks["${environment}-database"].policy),
        length(aws_iam_role_policy.database_metadata_read[environment].policy),
        length(aws_iam_role_policy.database_rds[environment].policy),
        length(aws_iam_role_policy.database_network[environment].policy),
        length(aws_iam_role_policy.database_init_secret_read[environment].policy),
        length(aws_iam_role_policy.database_api_secret[environment].policy),
        length(aws_iam_role_policy.database_auth_secret[environment].policy)
      ]) <= 10240
    ])
    error_message = "As policies inline agregadas de cada role database devem caber na quota de 10240 caracteres."
  }
}
