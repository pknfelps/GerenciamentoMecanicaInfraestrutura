mock_provider "aws" {}

variables {
  aws_account_id = "121754142617"
  github_subject_prefixes = {
    api      = "repo:pknfelps/GerenciamentoMecanicaSistema"
    infra    = "repo:pknfelps@114608389/GerenciamentoMecanicaInfraestrutura@1375105948"
    database = "repo:pknfelps@114608389/GerenciamentoMecanicaBancoDados@1375106298"
    auth     = "repo:pknfelps@114608389/GerenciamentoMecanicaAutenticacao@1375105446"
  }
}

run "isolated_bootstrap_plan" {
  command = plan

  assert {
    condition     = length(aws_iam_role.pipeline) == 10 && length(aws_iam_openid_connect_provider.github) == 1
    error_message = "Devem existir cinco roles por ambiente e um único provider compartilhado."
  }
  assert {
    condition = alltrue([
      for role in values(aws_iam_role.pipeline) :
      jsondecode(role.assume_role_policy).Statement[0].Action == "sts:AssumeRoleWithWebIdentity" &&
      jsondecode(role.assume_role_policy).Statement[0].Principal.Federated == "arn:aws:iam::121754142617:oidc-provider/token.actions.githubusercontent.com" &&
      jsondecode(role.assume_role_policy).Statement[0].Condition.StringEquals["token.actions.githubusercontent.com:aud"] == "sts.amazonaws.com"
    ])
    error_message = "Trust deve exigir o provider GitHub correto e audience STS."
  }
  assert {
    condition = alltrue(flatten([
      for key, role in aws_iam_role.pipeline : [
        for subject in jsondecode(role.assume_role_policy).Statement[0].Condition.StringEquals["token.actions.githubusercontent.com:sub"] :
        endswith(subject, ":environment:${split("-", key)[0]}") && !strcontains(subject, "*") &&
        jsondecode(role.assume_role_policy).Statement[0].Condition.StringEquals["token.actions.githubusercontent.com:ref"] == (startswith(key, "hom-") ? "refs/heads/develop" : "refs/heads/main")
      ]
    ]))
    error_message = "Nenhuma role pode aceitar o outro ambiente ou subjects com curingas."
  }
  assert {
    condition = (
      toset(jsondecode(aws_iam_role.pipeline["hom-gateway"].assume_role_policy).Statement[0].Condition.StringEquals["token.actions.githubusercontent.com:sub"]) ==
      toset([
        "${var.github_subject_prefixes.infra}:environment:hom",
        "${var.github_subject_prefixes.api}:environment:hom",
        "${var.github_subject_prefixes.auth}:environment:hom"
      ]) &&
      jsondecode(aws_iam_role.pipeline["hom-base"].assume_role_policy).Statement[0].Condition.StringEquals["token.actions.githubusercontent.com:sub"] ==
      ["${var.github_subject_prefixes.infra}:environment:hom"]
    )
    error_message = "Gateway deve aceitar os chamadores previstos; base deve aceitar somente infra."
  }
  assert {
    condition = alltrue([
      for bucket in values(aws_s3_bucket_public_access_block.shared) :
      bucket.block_public_acls && bucket.block_public_policy && bucket.ignore_public_acls && bucket.restrict_public_buckets
    ])
    error_message = "Todos os buckets precisam bloquear acesso público."
  }
  assert {
    condition = alltrue([
      for versioning in values(aws_s3_bucket_versioning.shared) :
      versioning.versioning_configuration[0].status == "Enabled"
      ]) && alltrue([
      for encryption in values(aws_s3_bucket_server_side_encryption_configuration.shared) :
      one(encryption.rule).apply_server_side_encryption_by_default[0].sse_algorithm == "AES256"
    ])
    error_message = "Buckets precisam de versionamento e criptografia."
  }
  assert {
    condition = alltrue([
      for policy in values(aws_s3_bucket_policy.shared) :
      jsondecode(policy.policy).Statement[0].Effect == "Deny" &&
      jsondecode(policy.policy).Statement[0].Condition.Bool["aws:SecureTransport"] == "false"
      ]) && (
      jsondecode(aws_s3_bucket_policy.shared["artifacts"].policy).Statement[1].Condition.Null["s3:if-none-match"] == "true" &&
      jsondecode(aws_s3_bucket_policy.shared["artifacts"].policy).Statement[1].Condition.Bool["s3:ObjectCreationOperation"] == "true"
    )
    error_message = "Buckets devem negar HTTP e artefatos devem exigir escrita condicional."
  }
  assert {
    condition     = aws_ecr_repository.api.image_tag_mutability == "IMMUTABLE" && !aws_ecr_repository.api.force_delete && alltrue([for bucket in values(aws_s3_bucket.shared) : !bucket.force_destroy])
    error_message = "Não permitir sobrescrita de tags ou remoção forçada dos dados compartilhados."
  }
  assert {
    condition = alltrue(flatten([
      for key, policy in aws_iam_role_policy.pipeline : [
        for statement in jsondecode(policy.policy).Statement :
        alltrue([for resource in statement.Resource : !strcontains(resource, "/${startswith(key, "hom-") ? "prd" : "hom"}/")]) &&
        alltrue([for action in statement.Action : !startswith(action, "iam:") && !startswith(action, "secretsmanager:") && action != "*"]) &&
        (contains(statement.Resource, "*") ? statement.Sid == "EcrAuthentication" : true)
      ]
    ]))
    error_message = "Roles não podem acessar outro ambiente, alterar IAM/secrets ou receber Resource * fora da autenticação ECR."
  }
  assert {
    condition = alltrue(flatten([
      for key, policy in aws_iam_role_policy.pipeline : [
        for statement in jsondecode(policy.policy).Statement :
        contains(statement.Action, "s3:DeleteObject") ? alltrue([for resource in statement.Resource : endswith(resource, ".tflock")]) : true
      ]
    ]))
    error_message = "Roles podem excluir somente seu lock, nunca estado ou artefatos."
  }
  assert {
    condition = alltrue([
      for key, config in output.backend_configs :
      config.use_lockfile && config.encrypt && startswith(config.key, "${split("-", key)[0]}/") &&
      !startswith(config.key, "shared/")
    ]) && length(output.backend_configs) == 8
    error_message = "Oito estados distintos, com locking/criptografia e sem acesso ao estado compartilhado."
  }
  assert {
    condition = (
      length(distinct([for config in values(output.backend_configs) : config.key])) == 8 &&
      !contains(keys(output.backend_configs), "hom-api") &&
      !contains(keys(output.backend_configs), "prd-api") &&
      !strcontains(aws_iam_role_policy.pipeline["hom-api"].policy, local.bucket_arns.state) &&
      !strcontains(aws_iam_role_policy.pipeline["prd-api"].policy, local.bucket_arns.state)
    )
    error_message = "API não usa Terraform; estados não podem colidir."
  }
  assert {
    condition = (
      !strcontains(aws_iam_role_policy.pipeline["hom-auth"].policy, "\"ecr:PutImage\"") &&
      strcontains(aws_iam_role_policy.pipeline["hom-api"].policy, "\"ecr:PutImage\"") &&
      !strcontains(aws_iam_role_policy.pipeline["hom-auth"].policy, "\"s3:DeleteObjectVersion\"")
    )
    error_message = "Somente API publica imagens; roles não excluem versões de artefatos."
  }
}

run "reuse_existing_provider" {
  command = plan
  variables {
    existing_github_oidc_provider_arn = "arn:aws:iam::121754142617:oidc-provider/token.actions.githubusercontent.com"
  }
  assert {
    condition     = length(aws_iam_openid_connect_provider.github) == 0 && length(aws_iam_role.pipeline) == 10
    error_message = "Provider existente não deve ser criado ou assumido por este estado."
  }
}

run "reject_wildcard_subject" {
  command = plan
  variables {
    github_subject_prefixes = {
      api      = "repo:pknfelps/*"
      infra    = "repo:pknfelps/infra"
      database = "repo:pknfelps/database"
      auth     = "repo:pknfelps/auth"
    }
  }
  expect_failures = [var.github_subject_prefixes]
}

run "reject_duplicate_repository" {
  command = plan
  variables {
    github_subject_prefixes = {
      api      = "repo:pknfelps/same"
      infra    = "repo:pknfelps/same"
      database = "repo:pknfelps/database"
      auth     = "repo:pknfelps/auth"
    }
  }
  expect_failures = [var.github_subject_prefixes]
}

run "reject_foreign_oidc_provider" {
  command = plan
  variables {
    existing_github_oidc_provider_arn = "arn:aws:iam::999999999999:oidc-provider/token.actions.githubusercontent.com"
  }
  expect_failures = [var.existing_github_oidc_provider_arn]
}

run "reject_invalid_account" {
  command = plan
  variables {
    aws_account_id = "not-an-account"
  }
  expect_failures = [var.aws_account_id]
}