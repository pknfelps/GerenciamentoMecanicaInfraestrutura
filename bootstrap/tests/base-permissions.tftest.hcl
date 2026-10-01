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

run "scoped_base_and_workload_permissions" {
  command = plan

  assert {
    condition = alltrue([
      for environment in local.environments :
      alltrue([for policy in [aws_iam_policy.base_network_create[environment], aws_iam_policy.base_network_manage[environment], aws_iam_policy.base_eks[environment], aws_iam_policy.base_iam[environment]] : length(policy.policy) <= 6144]) &&
      aws_iam_role_policy_attachment.base_iam[environment].role == aws_iam_role.pipeline["${environment}-base"].name
    ])
    error_message = "Somente base recebe as policies operacionais, dentro do limite IAM."
  }
  assert {
    condition = alltrue([
      for environment, policy in local.base_iam_policies :
      alltrue(flatten([for statement in policy.Statement : [for resource in statement.Resource :
        strcontains(resource, ":role/mecanica-${environment}-eks-") ||
        strcontains(resource, ":role/aws-service-role/") || resource == "arn:aws:iam::121754142617:user/mecanica"
      ]])) &&
      alltrue([for statement in policy.Statement : contains(statement.Action, "iam:PassRole") ?
        !contains(statement.Resource, "*") && can(statement.Condition.StringEquals["iam:PassedToService"]) : true
      ]) &&
      !strcontains(jsonencode(policy), ":role/mecanica/pipelines/") &&
      !strcontains(jsonencode(policy), "AdministratorAccess") &&
      !strcontains(jsonencode(policy), "iam:CreatePolicy")
    ])
    error_message = "Base não pode alterar roles de pipeline, criar policies arbitrárias ou passar qualquer role."
  }
  assert {
    condition = alltrue([
      for environment, policy in local.base_eks_policies :
      one([for statement in policy.Statement : statement if statement.Sid == "CreateTaggedCluster"]).Condition.Bool["eks:bootstrapClusterCreatorAdminPermissions"] == "false" &&
      one([for statement in policy.Statement : statement if statement.Sid == "AssociateWorkloadEdit"]).Condition["ForAllValues:StringEquals"]["eks:namespaces"] == ["default"] &&
      one([for statement in policy.Statement : statement if statement.Sid == "AssociateWorkloadEdit"]).Condition.Null["eks:namespaces"] == "false" &&
      alltrue([for principal in one([for statement in policy.Statement : statement if statement.Sid == "CreateKnownAccessEntries"]).Condition.StringEquals["eks:principalArn"] :
        principal == "arn:aws:iam::121754142617:user/mecanica" || strcontains(principal, "mecanica-${environment}-")
      ])
    ])
    error_message = "Criação EKS e access entries devem preservar isolamento e escopos explícitos."
  }
  assert {
    condition = alltrue([
      for environment, policy in local.base_network_manage_policies :
      alltrue([for statement in policy.Statement : statement.Sid == "TagOnCreation" ?
        statement.Condition.StringEquals["aws:RequestTag/Environment"] == environment :
        statement.Condition.StringEquals["ec2:ResourceTag/Environment"] == environment
      ]) &&
      one([for statement in policy.Statement : statement if statement.Sid == "RemoveAdditionalTags"]).Condition.Null["aws:TagKeys"] == "false"
    ])
    error_message = "Mutações EC2 devem exigir tags do ambiente e preservar tags de identidade."
  }
  assert {
    condition = length(aws_iam_role_policy.workload_eks) == 4 && alltrue([
      for key, policy in aws_iam_role_policy.workload_eks :
      jsondecode(policy.policy).Statement[0].Action == ["eks:DescribeCluster"] &&
      jsondecode(policy.policy).Statement[0].Resource == ["arn:aws:eks:us-east-1:121754142617:cluster/mecanica-${split("-", key)[0]}-eks"]
    ])
    error_message = "API/banco precisam somente DescribeCluster IAM, no próprio ambiente."
  }
}
