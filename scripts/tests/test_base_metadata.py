import copy
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import base_metadata as m

GEN = "88b99473-a7b0-4bf6-9e8d-3593135a12b4"


def exports(environment="hom"):
    return {"vpc-id": "vpc-11111111", "workload-subnet-ids": ["subnet-11111111", "subnet-22222222"],
            "database-subnet-ids": ["subnet-33333333", "subnet-44444444"],
            "cluster-name": f"mecanica-{environment}-eks", "cluster-arn": f"arn:aws:eks:us-east-1:{m.ACCOUNT}:cluster/mecanica-{environment}-eks",
            "namespace": "default", "api-security-group-id": "sg-11111111",
            "init-security-group-id": "sg-11111111", "auth-security-group-id": "sg-22222222"}


class ProtocolTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.store = {}
        self.events = []
        def write(name, value):
            self.events.append(("write", name))
            self.store[name] = value
        def delete(name):
            self.events.append(("delete", name))
            self.store.pop(name, None)
        for name, replacement in (("read_parameter", self.store.get), ("write_parameter", write), ("delete_parameter", delete)):
            p = patch.object(m, name, side_effect=replacement)
            p.start()
            self.addCleanup(p.stop)
        for target, kw in (("check_resources", {"return_value": "a"*64}), ("time.sleep", {"return_value": None})):
            p = patch("base_metadata." + target, **kw)
            p.start()
            self.addCleanup(p.stop)
        p = patch.dict(os.environ, GITHUB_REPOSITORY=m.REPOSITORY, GITHUB_SHA="a"*40, GITHUB_RUN_ID="123", GITHUB_RUN_ATTEMPT="1")
        p.start()
        self.addCleanup(p.stop)
        self.p = m.Protocol("hom", Path(self.tmp.name)/"context.json")
        self.plan = {"resource_changes": [{"address": "terraform_data.generation", "change": {"before": {"id": GEN}}}]}

    def prepare(self):
        self.p.begin(self.plan, "provision")
        candidate = self.p.prepare({"base_generation": {"value": GEN}, "database_exports": {"value": exports()}})
        evidence = {"schemaVersion": "1.0.0", "environment": "hom", "generation": GEN,
                    "candidateSha256": hashlib.sha256(m.packed(candidate).encode()).hexdigest(),
                    "roleArn": f"arn:aws:iam::{m.ACCOUNT}:role/mecanica/pipelines/mecanica-hom-database-github",
                    "recordedAt": m.now(), "checks": m.ACCESS_CHECKS}
        self.store["/mecanica/hom/database/v1/base-access-check"] = m.packed(evidence)
        return evidence

    def test_release_is_last_and_only_database_profile(self):
        self.prepare()
        self.assertTrue(self.p.publish())
        self.assertEqual(self.events[-1], ("write", self.p.prefix+"/database-release"))
        value = json.loads(self.store[self.p.prefix+"/database-release"])
        self.assertEqual(value["generation"], GEN)
        self.assertEqual(set(value["exports"]), set(m.FIELDS))
        self.assertNotIn(self.p.prefix+"/release", self.store)

    def test_bank_check_absent_blocks_without_ready(self):
        self.prepare()
        del self.store["/mecanica/hom/database/v1/base-access-check"]
        self.assertFalse(self.p.publish())
        self.p.failed()
        self.assertEqual(self.p.load()["status"], "blocked")
        self.assertIn(self.p.prefix+"/database-candidate", self.store)
        self.assertNotIn(self.p.prefix+"/database-release", self.store)

    def test_stale_wrong_role_generation_environment_and_permissions_rejected(self):
        for field, wrong in (("generation", "old"), ("roleArn", "base-role"), ("environment", "prd"),
                             ("candidateSha256", "b"*64), ("recordedAt", "2000-01-01T00:00:00Z"), ("checks", [])):
            with self.subTest(field=field):
                evidence = self.prepare()
                evidence[field] = wrong
                self.store["/mecanica/hom/database/v1/base-access-check"] = m.packed(evidence)
                self.assertFalse(self.p.publish())
                self.assertNotIn(self.p.prefix+"/database-release", self.store)

    def test_full_release_never_downgraded_or_invalidated_by_refused_operation(self):
        self.prepare()
        self.store[self.p.prefix+"/release"] = "full"
        with self.assertRaisesRegex(m.MetadataError, "FULL_PROFILE"):
            self.p.begin(self.plan, "provision")
        self.p.failed()
        self.assertEqual(self.store[self.p.prefix+"/release"], "full")

    def test_failure_after_partial_publication_removes_readiness(self):
        self.prepare()
        self.store[self.p.prefix+"/database-release"] = "partial"
        self.p.failed()
        self.assertNotIn(self.p.prefix+"/database-release", self.store)
        self.assertEqual(self.p.load()["status"], "failed")

    def test_destroy_empty_state_cleans_both_profiles_but_preserves_history_other_producers(self):
        self.prepare()
        self.p.publish()
        self.store[self.p.prefix+"/release"] = "full"
        self.store[self.p.prefix+"/nlb-arn"] = "old"
        self.store["/mecanica/prd/base/v1/release"] = "other-environment"
        self.p.begin({}, "destroy")
        self.p.destroyed()
        self.assertEqual(self.p.load()["status"], "destroyed")
        self.assertEqual(self.p.load()["generation"], GEN)
        self.assertIn("/mecanica/prd/base/v1/release", self.store)
        self.assertIn("/mecanica/hom/database/v1/base-access-check", self.store)
        self.assertNotIn(self.p.prefix+"/nlb-arn", self.store)

    def test_generation_mismatch_refused_before_invalidation(self):
        self.prepare()
        self.p.publish()
        with self.assertRaisesRegex(m.MetadataError, "GENERATION_MISMATCH"):
            self.p.begin({}, "provision")
        self.assertIn(self.p.prefix+"/database-release", self.store)

    def test_initial_creation_resolves_generation_only_after_apply(self):
        self.p.begin({}, "provision")
        self.assertIsNone(self.p.load()["generation"])
        self.p.prepare({"base_generation": {"value": GEN}, "database_exports": {"value": exports()}})
        self.assertEqual(self.p.load()["generation"], GEN)

    def test_code_update_reuses_unchanged_access_evidence(self):
        self.prepare()
        self.p.publish()
        with patch.dict(os.environ, GITHUB_SHA="b"*40, GITHUB_RUN_ID="124"):
            self.p.begin(self.plan, "provision")
            self.p.prepare({"base_generation": {"value": GEN}, "database_exports": {"value": exports()}})
            self.assertTrue(self.p.publish())
        release = json.loads(self.store[self.p.prefix+"/database-release"])
        self.assertEqual(release["source"]["commit"], "b"*40)

    def test_unconfirmed_invalidation_prevents_apply_boundary(self):
        with patch.object(m, "delete_parameter", side_effect=m.MetadataError("SSM_DELETE_NOT_CONFIRMED")):
            with self.assertRaisesRegex(m.MetadataError, "SSM_DELETE_NOT_CONFIRMED"):
                self.p.begin(self.plan, "provision")
        self.assertNotIn(self.p.prefix+"/database-release", self.store)

    def test_publish_write_failure_is_recovered_to_failed(self):
        self.prepare()
        def uncertain_write(name, value):
            self.store[name] = value
            if name.endswith('/database-release'):
                raise m.MetadataError('SSM_WRITE_NOT_CONFIRMED')
        with patch.object(m, 'write_parameter', side_effect=uncertain_write):
            with self.assertRaises(m.MetadataError): self.p.publish()
        self.p.failed()
        self.assertNotIn(self.p.prefix+'/database-release', self.store)
        self.assertEqual(self.p.load()['status'], 'failed')

    def test_access_policy_change_after_attestation_refused(self):
        self.prepare()
        with patch.object(m, "check_resources", return_value="changed"):
            with self.assertRaisesRegex(m.MetadataError, "DATABASE_ACCESS_CHANGED"):
                self.p.publish()

    def test_utf8_limit_and_no_cross_environment_exports(self):
        with self.assertRaisesRegex(m.MetadataError, "TOO_LARGE"):
            m.packed({"value": "á"*2200})
        m.validate_exports(exports("prd"), "prd")
        with self.assertRaises(m.MetadataError):
            m.validate_exports(exports("prd"), "hom")
        value = exports()
        value.pop("namespace")
        with self.assertRaises(m.MetadataError):
            m.validate_exports(value, "hom")

    def test_malformed_subnets_and_placeholder_sg_refused(self):
        for field, invalid in (("workload-subnet-ids", ["subnet-11111111"]*2),
                               ("init-security-group-id", "sg-placeholder"), ("namespace", "other")):
            value = exports()
            value[field] = invalid
            with self.assertRaises(m.MetadataError):
                m.validate_exports(value, "hom")


class TransportTests(unittest.TestCase):
    def test_access_denied_is_not_absence(self):
        with patch.object(m.subprocess, "run") as run:
            run.return_value.returncode = 254
            run.return_value.stderr = "(AccessDeniedException) private-data"
            with self.assertRaisesRegex(m.MetadataError, "AWS_ssm_get-parameter_FAILED"):
                m.read_parameter("/mecanica/hom/base/v1/release")

    def test_parameter_not_found_is_absence(self):
        with patch.object(m.subprocess, "run") as run:
            run.return_value.returncode = 254
            run.return_value.stderr = "(ParameterNotFound)"
            self.assertIsNone(m.read_parameter("/mecanica/hom/base/v1/release"))


class ResourceTests(unittest.TestCase):
    def setUp(self):
        self.data = exports()
        self.tags = [{"Key": k, "Value": v} for k, v in {"Project": "mecanica", "Environment": "hom", "ManagedBy": "Terraform"}.items()]
        self.bad_route = False
        self.bad_sg = False
        self.bad_az = False
        self.bad_policy = False
        def aws(*args, **kwargs):
            operation = args[1]
            if operation == 'describe-vpcs':
                return {'Vpcs': [{'State': 'available', 'Tags': self.tags}]}
            if operation == 'describe-subnets':
                return {'Subnets': [{'SubnetId': s, 'VpcId': self.data['vpc-id'], 'AvailabilityZone': 'a' if self.bad_az else str(i),
                                     'State': 'available', 'MapPublicIpOnLaunch': False, 'Tags': self.tags}
                                    for i, s in enumerate(args[3:])]}
            if operation == 'describe-route-tables':
                database = any(s in args[-1] for s in self.data['database-subnet-ids'])
                routes = [{'GatewayId': 'local', 'State': 'active'}]
                if not database or self.bad_route:
                    routes.append({'DestinationCidrBlock': '0.0.0.0/0', 'NatGatewayId': 'nat-11111111', 'State': 'active'})
                return {'RouteTables': [{'VpcId': self.data['vpc-id'], 'Routes': routes}]}
            if operation == 'describe-cluster':
                return {'cluster': {'status': 'ACTIVE', 'arn': self.data['cluster-arn'], 'resourcesVpcConfig': {
                    'vpcId': self.data['vpc-id'], 'subnetIds': self.data['workload-subnet-ids'], 'clusterSecurityGroupId': 'sg-11111111'}}}
            if operation == 'describe-network-interfaces':
                return {'NetworkInterfaces': [{'VpcId': self.data['vpc-id'], 'Groups': [{'GroupId': 'sg-33333333' if self.bad_sg else 'sg-11111111'}]}]}
            if operation == 'describe-security-groups':
                return {'SecurityGroups': [{'GroupId': sg, 'VpcId': self.data['vpc-id'], 'GroupName': 'mecanica-hom-auth', 'Tags': self.tags}
                                           for sg in ('sg-11111111', 'sg-22222222')]}
            if operation == 'describe-access-entry':
                return {'accessEntry': {'type': 'STANDARD', 'principalArn': args[-1]}}
            if operation == 'list-associated-access-policies':
                return {'associatedAccessPolicies': [] if self.bad_policy else [{'policyArn': 'arn:aws:eks::aws:cluster-access-policy/AmazonEKSEditPolicy',
                                                                                'accessScope': {'type': 'namespace', 'namespaces': ['default']}}]}
            raise AssertionError(args)
        def kubectl(*args):
            return json.dumps({'items': [{'spec': {'providerID': 'aws:///us-east-1a/i-11111111'}}]} if args[1] == 'nodes' else {'status': {'phase': 'Active'}})
        for target, callback in (('aws', aws), ('kubectl', kubectl)):
            p = patch.object(m, target, side_effect=callback)
            p.start()
            self.addCleanup(p.stop)

    def test_real_response_shapes_accept_ready_resources(self):
        self.assertEqual(len(m.check_resources(self.data, 'hom')), 64)

    def test_database_internet_route_refused(self):
        self.bad_route = True
        with self.assertRaisesRegex(m.MetadataError, 'DATABASE_NOT_ISOLATED'): m.check_resources(self.data, 'hom')

    def test_actual_node_security_group_mismatch_refused(self):
        self.bad_sg = True
        with self.assertRaisesRegex(m.MetadataError, 'NODE_SECURITY_GROUP_MISMATCH'): m.check_resources(self.data, 'hom')

    def test_single_az_refused(self):
        self.bad_az = True
        with self.assertRaisesRegex(m.MetadataError, 'SUBNET_AZS_INVALID'): m.check_resources(self.data, 'hom')

    def test_database_access_policy_required(self):
        self.bad_policy = True
        with self.assertRaisesRegex(m.MetadataError, 'DATABASE_POLICY_MISSING'): m.check_resources(self.data, 'hom')


if __name__ == "__main__":
    unittest.main()
