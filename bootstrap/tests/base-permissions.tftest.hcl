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
  # CreateNodegroup valida a SLR existente mesmo quando CreateServiceLinkedRole está permitido.
  assert {
    condition = alltrue([
      for environment, policy in local.base_iam_policies :
      one([for statement in policy.Statement : statement if statement.Sid == "ReadEksNodegroupServiceRole"]).Effect == "Allow" &&
      one([for statement in policy.Statement : statement if statement.Sid == "ReadEksNodegroupServiceRole"]).Action == ["iam:GetRole"] &&
      one([for statement in policy.Statement : statement if statement.Sid == "ReadEksNodegroupServiceRole"]).Resource == [
        "arn:aws:iam::${var.aws_account_id}:role/aws-service-role/eks-nodegroup.amazonaws.com/AWSServiceRoleForAmazonEKSNodegroup"
      ] &&
      alltrue(flatten([for statement in policy.Statement : contains(statement.Action, "iam:GetRole") ? [for resource in statement.Resource : contains([
        "arn:aws:iam::${var.aws_account_id}:role/${var.project_name}-${environment}-eks-cluster-role",
        "arn:aws:iam::${var.aws_account_id}:role/${var.project_name}-${environment}-eks-node-role",
        "arn:aws:iam::${var.aws_account_id}:role/${var.project_name}-${environment}-eks-ebs-csi-role",
        "arn:aws:iam::${var.aws_account_id}:role/aws-service-role/eks-nodegroup.amazonaws.com/AWSServiceRoleForAmazonEKSNodegroup"
      ], resource)] : []]))
    ])
    error_message = "Base hom/prd precisam consultar a SLR de node groups, sem conceder GetRole em roles arbitrárias ou de outro ambiente."
  }
  # O provider consulta a prefix list ao ler o gateway endpoint S3, inclusive após create.
  assert {
    condition = alltrue([
      for environment, policy in local.base_network_create_policies :
      contains(one([for statement in policy.Statement : statement if statement.Sid == "ReadRegionalNetwork"]).Action, "ec2:DescribePrefixLists") &&
      one([for statement in policy.Statement : statement if statement.Sid == "ReadRegionalNetwork"]).Resource == ["*"] &&
      one([for statement in policy.Statement : statement if statement.Sid == "ReadRegionalNetwork"]).Condition.StringEquals["aws:RequestedRegion"] == var.aws_region &&
      aws_iam_role_policy_attachment.base_network_create[environment].role == aws_iam_role.pipeline["${environment}-base"].name
    ])
    error_message = "Base hom/prd precisam ler prefix lists regionais para criar/atualizar o endpoint S3."
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
      alltrue([for statement in policy.Statement : statement.Sid == "DisassociateMissingAddress" ?
        statement.Action == ["ec2:DisassociateAddress"] &&
        statement.Effect == "Allow" && !can(statement.Resource) &&
        statement.NotResource == ["arn:aws:ec2:*:*:elastic-ip/*", "arn:aws:ec2:*:*:network-interface/*"] &&
        statement.Condition.StringEquals == { "aws:RequestedRegion" = var.aws_region } &&
        statement.Condition.Null == { "ec2:AllocationId" = "true", "ec2:NetworkInterfaceID" = "true" } :
        statement.Sid == "TagOnCreation" ?
        statement.Condition.StringEquals["aws:RequestTag/Environment"] == environment :
        statement.Condition.StringEquals["ec2:ResourceTag/Environment"] == environment
      ]) &&
      one([for statement in policy.Statement : statement if statement.Sid == "RemoveAdditionalTags"]).Condition.Null["aws:TagKeys"] == "false" &&
      length([for statement in policy.Statement : statement if contains(statement.Action, "ec2:DisassociateAddress")]) == 1 &&
      contains(one([for statement in policy.Statement : statement if statement.Sid == "ManageOwnNetwork"]).Action, "ec2:ReleaseAddress")
    ])
    error_message = "Mutações EC2 reais devem exigir tags do ambiente; somente DisassociateAddress sem recurso real aceita região e IDs ausentes, excluindo todos os EIPs/ENIs reais."
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
