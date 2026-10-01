import copy
import sys
import unittest
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parents[1]))
from review_base_destroy import review_destroy
from review_base_plan import review


def example(environment="hom"):
    tags = {"Project": "mecanica", "Environment": environment, "ManagedBy": "Terraform"}
    return {"format_version": "1.2", "terraform_version": "1.15.9", "complete": True,
            "variables": {"environment": {"value": environment}},
            "resource_changes": [{"address": "aws_vpc.main", "type": "aws_vpc", "mode": "managed",
                                  "change": {"actions": ["delete"], "before": {"id": f"vpc-{environment}", "tags_all": tags}, "after": None}}]}


class DestroyTests(unittest.TestCase):
    def test_both_environments_and_empty_state(self):
        for environment in ("hom", "prd"):
            plan = example(environment)
            self.assertTrue(review_destroy(plan, environment)["destructive"])
            plan["resource_changes"] = []
            self.assertFalse(review_destroy(plan, environment)["has_changes"])

    def test_scope_bootstrap_modules_and_other_types(self):
        for address, kind in [("aws_s3_bucket.state", "aws_s3_bucket"), ("aws_iam_role.pipeline", "aws_iam_role"),
                              ("module.other.aws_vpc.main", "aws_vpc"), ("aws_vpc.other", "aws_vpc")]:
            plan = example()
            plan["resource_changes"][0].update(address=address, type=kind)
            with self.assertRaises(ValueError): review_destroy(plan, "hom")

    def test_tags_and_environment_cannot_cross(self):
        for key, value in [("Project", "other"), ("Environment", "prd"), ("ManagedBy", "manual")]:
            plan = example()
            plan["resource_changes"][0]["change"]["before"]["tags_all"][key] = value
            with self.assertRaises(ValueError): review_destroy(plan, "hom")
        with self.assertRaises(ValueError): review_destroy(example("prd"), "hom")

    def test_non_destroy_actions_incomplete_or_missing_identity(self):
        for actions in (["create"], ["update"], ["delete", "create"], ["read"]):
            plan = example()
            plan["resource_changes"][0]["change"]["actions"] = actions
            with self.assertRaises(ValueError): review_destroy(plan, "hom")
        plan = example()
        plan["complete"] = False
        with self.assertRaises(ValueError): review_destroy(plan, "hom")
        plan = example()
        plan["resource_changes"][0]["change"]["before"] = None
        with self.assertRaises(ValueError): review_destroy(plan, "hom")

    def test_role_name_and_attachment_preserve_oidc_roles(self):
        plan = example()
        item = plan["resource_changes"][0]
        item.update(address="aws_iam_role.eks_nodes", type="aws_iam_role")
        item["change"]["before"]["name"] = "mecanica-hom-eks-node-role"
        review_destroy(plan, "hom")
        item["change"]["before"]["name"] = "mecanica-hom-base-github"
        with self.assertRaises(ValueError): review_destroy(plan, "hom")
        item.update(address="aws_iam_role_policy_attachment.eks_worker_node_policy", type="aws_iam_role_policy_attachment")
        item["change"]["before"] = {"role": "mecanica-hom-eks-node-role", "policy_arn": "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"}
        review_destroy(plan, "hom")
        item["change"]["before"]["role"] = "mecanica-prd-eks-node-role"
        with self.assertRaises(ValueError): review_destroy(plan, "hom")

    def test_eks_access_cluster_and_principals_are_scoped(self):
        plan = example()
        item = plan["resource_changes"][0]
        item.update(address='aws_eks_access_entry.pipeline["api"]', type="aws_eks_access_entry")
        item["change"]["before"] = {"cluster_name": "mecanica-hom-eks", "principal_arn": "arn:aws:iam::121754142617:role/mecanica/pipelines/mecanica-hom-api-github"}
        review_destroy(plan, "hom")
        item["change"]["before"]["cluster_name"] = "mecanica-prd-eks"
        with self.assertRaises(ValueError): review_destroy(plan, "hom")
        item["change"]["before"]["cluster_name"] = "mecanica-hom-eks"
        item["change"]["before"]["principal_arn"] = "arn:aws:iam::121754142617:root"
        with self.assertRaises(ValueError): review_destroy(plan, "hom")

    def test_fingerprint_binds_mode_identity_and_ignores_timestamp(self):
        plan = example()
        self.assertNotEqual(review(plan)["sha256"], review_destroy(plan, "hom")["sha256"])
        second = copy.deepcopy(plan)
        second["timestamp"] = "later"
        self.assertEqual(review_destroy(plan, "hom")["sha256"], review_destroy(second, "hom")["sha256"])
        second["resource_changes"][0]["change"]["before"]["id"] = "replacement-vpc"
        self.assertNotEqual(review_destroy(plan, "hom")["sha256"], review_destroy(second, "hom")["sha256"])
        self.assertNotIn("vpc-hom", str(review_destroy(plan, "hom")))

    def test_partial_destroy_and_route_association_of_another_vpc(self):
        plan = example()
        plan["resource_changes"][0]["change"]["actions"] = ["no-op"]
        with self.assertRaises(ValueError): review_destroy(plan, "hom")
        plan = example()
        tags = plan["resource_changes"][0]["change"]["before"]["tags_all"]
        for address, kind, before in [
            ('aws_subnet.public[0]', 'aws_subnet', {'id': 'subnet-hom', 'tags_all': tags}),
            ('aws_route_table.public', 'aws_route_table', {'id': 'rtb-hom', 'tags_all': tags}),
            ('aws_route_table_association.public[0]', 'aws_route_table_association', {'subnet_id': 'subnet-hom', 'route_table_id': 'rtb-hom'})]:
            plan['resource_changes'].append({'address': address, 'type': kind, 'mode': 'managed', 'change': {'actions': ['delete'], 'before': before, 'after': None}})
        review_destroy(plan, 'hom')
        plan['resource_changes'][-1]['change']['before']['subnet_id'] = 'subnet-prd'
        with self.assertRaises(ValueError): review_destroy(plan, 'hom')


if __name__ == "__main__": unittest.main()
