variable "allow_legacy_cleanup" {
  description = "Permissoes temporarias de leitura/descarte do controller, CSI e SSM v1. Desativar depois da migracao."
  type        = bool
  default     = true
}
resource "aws_iam_role_policy" "base_legacy_cleanup" {
  for_each = var.allow_legacy_cleanup ? local.environments : toset([])
  name     = "base-legacy-cleanup"
  role     = aws_iam_role.pipeline["${each.key}-base"].id
  policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Sid" : "ReadAndRemoveLegacyRoles",
        "Effect" : "Allow",
        "Action" : [
          "iam:GetRole",
          "iam:ListRoleTags",
          "iam:ListRolePolicies",
          "iam:ListAttachedRolePolicies",
          "iam:ListInstanceProfilesForRole",
          "iam:DeleteRole",
          "iam:GetRolePolicy",
          "iam:DeleteRolePolicy",
          "iam:DetachRolePolicy"
        ],
        "Resource" : [
          "arn:aws:iam::${var.aws_account_id}:role/${var.project_name}-${each.key}-eks-ebs-csi-role",
          "arn:aws:iam::${var.aws_account_id}:role/${var.project_name}-${each.key}-eks-nlb-controller-role"
        ]
      },
      {
        "Sid" : "RemoveLegacyCsiAddon",
        "Effect" : "Allow",
        "Action" : ["eks:DescribeAddon", "eks:DeleteAddon"],
        "Resource" : "arn:aws:eks:${var.aws_region}:${var.aws_account_id}:addon/${var.project_name}-${each.key}-eks/aws-ebs-csi-driver/*"
      },
      {
        "Sid" : "RemoveLegacyPodIdentity",
        "Effect" : "Allow",
        "Action" : [
          "eks:DescribePodIdentityAssociation",
          "eks:DeletePodIdentityAssociation"
        ],
        "Resource" : "arn:aws:eks:${var.aws_region}:${var.aws_account_id}:podidentityassociation/${var.project_name}-${each.key}-eks/*"
      }
    ]
  })
}
