"""Accept only deletion of the known base resources in the selected environment."""
import argparse
import hashlib
import json
import re
from pathlib import Path
from review_base_plan import review

ACCOUNT = "121754142617"
TAGGED = {"aws_vpc", "aws_subnet", "aws_internet_gateway", "aws_route_table",
          "aws_eip", "aws_nat_gateway", "aws_vpc_endpoint", "aws_iam_role",
          "aws_eks_cluster", "aws_eks_node_group", "aws_eks_addon", "aws_security_group"}
SINGLE = {
    "terraform_data.generation", "aws_security_group.auth",
    "aws_vpc.main", "aws_internet_gateway.main", "aws_eip.nat", "aws_nat_gateway.main",
    "aws_vpc_endpoint.s3", "aws_eks_cluster.main", "aws_eks_node_group.main",
    "aws_iam_role.eks_cluster", "aws_iam_role.eks_nodes", "aws_iam_role.ebs_csi",
    "aws_iam_role_policy_attachment.eks_cluster_policy", "aws_iam_role_policy_attachment.eks_worker_node_policy",
    "aws_iam_role_policy_attachment.eks_ecr_pull_only_policy", "aws_iam_role_policy_attachment.eks_cni_policy",
    "aws_iam_role_policy_attachment.ebs_csi", "aws_eks_addon.pod_identity_agent",
    "aws_eks_addon.ebs_csi", "aws_eks_addon.metrics_server",
    "aws_eks_access_entry.operator", "aws_eks_access_policy_association.operator_admin",
    *{f"aws_route_table.{layer}" for layer in ("public", "workload", "database")},
    *{f'{kind}.pipeline["{component}"]' for kind in ("aws_eks_access_entry", "aws_eks_access_policy_association")
      for component in ("base", "api", "database")},
}


def review_destroy(plan, environment):
    if environment not in ("hom", "prd") or plan.get("variables", {}).get("environment", {}).get("value") != environment:
        raise ValueError("Parâmetros do plano incompatíveis com o descarte selecionado.")
    resources = [c for c in plan.get("resource_changes", []) if c.get("mode") == "managed"]
    previous = {c["address"]: c["change"].get("before") or {} for c in resources}
    prefix = f"mecanica-{environment}"
    cluster = f"{prefix}-eks"
    roles = {f"{cluster}-{suffix}-role" for suffix in ("cluster", "node", "ebs-csi")}
    principals = {f"arn:aws:iam::{ACCOUNT}:user/mecanica",
                  *{f"arn:aws:iam::{ACCOUNT}:role/mecanica/pipelines/{prefix}-{component}-github"
                    for component in ("base", "api", "database")}}
    attachments = {
        "eks_cluster_policy": (f"{cluster}-cluster-role", "AmazonEKSClusterPolicy"),
        "eks_worker_node_policy": (f"{cluster}-node-role", "AmazonEKSWorkerNodePolicy"),
        "eks_ecr_pull_only_policy": (f"{cluster}-node-role", "AmazonEC2ContainerRegistryPullOnly"),
        "eks_cni_policy": (f"{cluster}-node-role", "AmazonEKS_CNI_Policy"),
        "ebs_csi": (f"{cluster}-ebs-csi-role", "AmazonEBSCSIDriverPolicyV2"),
    }
    for item in resources:
        address, kind = item["address"], item["type"]
        allowed = address in SINGLE or re.fullmatch(r"aws_(subnet|route_table_association)\.(public|workload|database)\[[01]\]", address)
        if not allowed or item.get("module_address") or address.split(".")[0] != kind:
            raise ValueError("Plano contém recurso fora da base; descarte recusado.")
        change = item["change"]
        if change["actions"] not in (["delete"], ["no-op"]):
            raise ValueError("Descarte aceita somente exclusões; criação/alteração/substituição recusada.")
        before = change.get("before") or {}
        if before and change["actions"] == ["no-op"]:
            raise ValueError("Descarte parcial detectado; a base inteira deve ser removida.")
        if not before:
            if change["actions"] == ["delete"]:
                raise ValueError("Exclusão sem identidade anterior; descarte recusado.")
            continue
        if kind in TAGGED:
            tags = before.get("tags_all") or before.get("tags") or {}
            if any(tags.get(key) != value for key, value in {"Project": "mecanica", "Environment": environment, "ManagedBy": "Terraform"}.items()):
                raise ValueError("Recurso sem tags de propriedade do ambiente; descarte recusado.")
        if kind == "terraform_data":
            identity = before.get("input") or {}
            vpc = previous.get("aws_vpc.main", {}).get("id")
            if (identity.get("environment") != environment or
                    not re.fullmatch(r"vpc-[0-9a-f]{8,17}", identity.get("vpc_id", "")) or
                    (vpc and identity.get("vpc_id") != vpc)):
                raise ValueError("Geração fora da VPC/ambiente revisados.")
        if kind == "aws_security_group":
            if before.get("name") != f"{prefix}-auth" or before.get("vpc_id") != previous.get("aws_vpc.main", {}).get("id"):
                raise ValueError("Security group fora da base revisada.")
        if kind == "aws_iam_role" and before.get("name") not in roles:
            raise ValueError("Role fora da base; bootstrap deve ser preservado.")
        if kind == "aws_iam_role_policy_attachment":
            expected_role, policy = attachments[address.split(".")[1]]
            if before.get("role") != expected_role or before.get("policy_arn") != f"arn:aws:iam::aws:policy/{policy}":
                raise ValueError("Attachment fora das roles de execução da base.")
        if kind == "aws_route_table_association":
            layer = address.split(".")[1].split("[")[0]
            index = address[-2]
            subnet = previous.get(f"aws_subnet.{layer}[{index}]", {}).get("id")
            table = previous.get(f"aws_route_table.{layer}", {}).get("id")
            if not subnet or not table or before.get("subnet_id") != subnet or before.get("route_table_id") != table:
                raise ValueError("Associação de rotas fora da rede revisada; descarte recusado.")
        if kind == "aws_eks_cluster" and before.get("name") != cluster:
            raise ValueError("Cluster de outro ambiente; descarte recusado.")
        if kind in ("aws_eks_node_group", "aws_eks_addon", "aws_eks_access_entry", "aws_eks_access_policy_association") and before.get("cluster_name") != cluster:
            raise ValueError("Recurso EKS de outro cluster; descarte recusado.")
        if kind in ("aws_eks_access_entry", "aws_eks_access_policy_association") and before.get("principal_arn") not in principals:
            raise ValueError("Acesso EKS de outra identidade; descarte recusado.")
    result = review(plan)
    result["sha256"] = hashlib.sha256(f"destroy/{environment}/{result['sha256']}".encode()).hexdigest()
    return result


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("plan", type=Path)
    parser.add_argument("--environment", choices=("hom", "prd"), required=True)
    parser.add_argument("--report", type=Path, required=True)
    parser.add_argument("--expected-sha256", default="")
    args = parser.parse_args()
    result = review_destroy(json.loads(args.plan.read_text(encoding="utf-8-sig")), args.environment)
    if args.expected_sha256 and result["sha256"] != args.expected_sha256.lower():
        raise SystemExit("O descarte mudou após a revisão. Inicie nova execução e aprove o novo resumo; nenhum apply executado.")
    args.report.write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    main()
