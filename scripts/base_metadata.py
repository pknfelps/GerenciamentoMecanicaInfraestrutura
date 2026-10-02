"""Base SSM protocol. AWS CLI only; never read secrets or another Terraform state."""
import argparse
import hashlib
import json
import os
import re
import subprocess
import sys
import time
import uuid
from datetime import datetime, timezone
from pathlib import Path

ACCOUNT = "121754142617"
REGION = "us-east-1"
REPOSITORY = "pknfelps/GerenciamentoMecanicaInfraestrutura"
FIELDS = ("vpc-id", "workload-subnet-ids", "database-subnet-ids", "cluster-name",
          "cluster-arn", "namespace", "api-security-group-id", "auth-security-group-id",
          "init-security-group-id")
FULL_FIELDS = ("api-service-name", "api-service-port", "nlb-arn", "nlb-dns-name",
               "nlb-listener-port", "nlb-listener-protocol", "api-integration-uri",
               "ecr-repository-url", "jwt-secret-arn", "jwt-issuer", "jwt-audience",
               "newrelic-secret-arn", "newrelic-otlp-endpoint", "otel-collector-endpoint")
ACCESS_CHECKS = ["create jobs.batch", "get jobs.batch", "list jobs.batch", "watch jobs.batch",
                 "delete jobs.batch", "get pods", "list pods", "get pods/log",
                 "create serviceaccounts", "get serviceaccounts"]


class MetadataError(Exception):
    pass


def packed(value):
    text = json.dumps(value, ensure_ascii=False, separators=(",", ":"), sort_keys=True)
    if len(text.encode("utf-8")) > 4096:
        raise MetadataError("METADATA_TOO_LARGE")
    return text


def now():
    return datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")


def require(condition, code):
    if not condition:
        raise MetadataError(code)


def aws(*args, absent=None):
    result = subprocess.run(["aws", *args, "--region", REGION, "--output", "json"],
                            capture_output=True, text=True, encoding="utf-8")
    if result.returncode:
        if absent and f"({absent})" in result.stderr:
            return None
        # CLI stderr may contain request values. Do not echo it into pipeline logs.
        raise MetadataError(f"AWS_{args[0]}_{args[1]}_FAILED")
    return json.loads(result.stdout or "{}")


def kubectl(*args):
    result = subprocess.run(["kubectl", "--request-timeout=30s", *args], capture_output=True,
                            text=True, encoding="utf-8")
    require(result.returncode == 0, "KUBERNETES_CHECK_FAILED")
    return result.stdout


def read_parameter(name):
    result = aws("ssm", "get-parameter", "--name", name, absent="ParameterNotFound")
    return None if result is None else result["Parameter"]["Value"]


def write_parameter(name, value):
    require(len(value.encode("utf-8")) <= 4096, "METADATA_TOO_LARGE")
    aws("ssm", "put-parameter", "--name", name, "--type", "String", "--tier", "Standard",
        "--data-type", "text", "--overwrite", "--value", value)
    for _ in range(6):
        if read_parameter(name) == value:
            return
        time.sleep(2)
    raise MetadataError("SSM_WRITE_NOT_CONFIRMED")


def delete_parameter(name):
    aws("ssm", "delete-parameter", "--name", name, absent="ParameterNotFound")
    for _ in range(6):
        if read_parameter(name) is None:
            return
        time.sleep(2)
    raise MetadataError("SSM_DELETE_NOT_CONFIRMED")


def validate_exports(exports, environment):
    require(set(exports) == set(FIELDS), "INVALID_EXPORT_FIELDS")
    require(re.fullmatch(r"vpc-[0-9a-f]{8,17}", exports["vpc-id"]) is not None, "INVALID_VPC")
    for field in ("workload-subnet-ids", "database-subnet-ids"):
        values = exports[field]
        require(isinstance(values, list) and len(values) == 2 and len(set(values)) == 2
                and all(isinstance(v, str) and re.fullmatch(r"subnet-[0-9a-f]{8,17}", v) for v in values),
                "INVALID_SUBNETS")
    require(not set(exports["workload-subnet-ids"]) & set(exports["database-subnet-ids"]), "SUBNET_LAYERS_OVERLAP")
    require(exports["cluster-name"] == f"mecanica-{environment}-eks", "INVALID_CLUSTER")
    require(exports["cluster-arn"] == f"arn:aws:eks:{REGION}:{ACCOUNT}:cluster/mecanica-{environment}-eks", "INVALID_CLUSTER_ARN")
    require(exports["namespace"] == "default", "INVALID_NAMESPACE")
    for field in ("api-security-group-id", "auth-security-group-id", "init-security-group-id"):
        require(isinstance(exports[field], str) and re.fullmatch(r"sg-[0-9a-f]{8,17}", exports[field]), "INVALID_SECURITY_GROUP")


def tags_match(resource, environment):
    tags = {t["Key"]: t["Value"] for t in resource.get("Tags", [])}
    return all(tags.get(k) == v for k, v in
               {"Project": "mecanica", "Environment": environment, "ManagedBy": "Terraform"}.items())


def check_resources(exports, environment):
    validate_exports(exports, environment)
    vpc = aws("ec2", "describe-vpcs", "--vpc-ids", exports["vpc-id"])["Vpcs"]
    require(len(vpc) == 1 and vpc[0]["State"] == "available" and tags_match(vpc[0], environment), "VPC_NOT_READY")
    for layer in ("workload", "database"):
        ids = exports[f"{layer}-subnet-ids"]
        subnets = aws("ec2", "describe-subnets", "--subnet-ids", *ids)["Subnets"]
        require({s["SubnetId"] for s in subnets} == set(ids) and len({s["AvailabilityZone"] for s in subnets}) == 2,
                "SUBNET_AZS_INVALID")
        for subnet in subnets:
            require(subnet["VpcId"] == exports["vpc-id"] and subnet["State"] == "available"
                    and not subnet["MapPublicIpOnLaunch"] and tags_match(subnet, environment), "SUBNET_NOT_PRIVATE")
            tables = aws("ec2", "describe-route-tables", "--filters",
                         f"Name=association.subnet-id,Values={subnet['SubnetId']}")["RouteTables"]
            require(len(tables) == 1 and tables[0]["VpcId"] == exports["vpc-id"], "ROUTE_TABLE_INVALID")
            routes = tables[0]["Routes"]
            if layer == "database":
                require(all(r.get("GatewayId") == "local" and r.get("State") == "active" for r in routes), "DATABASE_NOT_ISOLATED")
            else:
                require(not any(str(r.get("GatewayId", "")).startswith("igw-") for r in routes), "WORKLOAD_PUBLIC_ROUTE")
                require(any(r.get("DestinationCidrBlock") == "0.0.0.0/0" and r.get("NatGatewayId")
                            and r.get("State") == "active" for r in routes), "WORKLOAD_NAT_MISSING")
    cluster = aws("eks", "describe-cluster", "--name", exports["cluster-name"])["cluster"]
    require(cluster["status"] == "ACTIVE" and cluster["arn"] == exports["cluster-arn"]
            and cluster["resourcesVpcConfig"]["vpcId"] == exports["vpc-id"], "CLUSTER_NOT_READY")
    require(set(cluster["resourcesVpcConfig"]["subnetIds"]) == set(exports["workload-subnet-ids"]), "CLUSTER_SUBNETS_MISMATCH")
    node_sg = cluster["resourcesVpcConfig"]["clusterSecurityGroupId"]
    require(exports["api-security-group-id"] == node_sg == exports["init-security-group-id"], "POD_SECURITY_GROUP_MISMATCH")
    # Managed nodes use the EKS cluster SG. Verify the actual EC2 network interfaces.
    nodes = json.loads(kubectl("get", "nodes", "-o", "json"))["items"]
    require(bool(nodes), "NO_NODES")
    for node in nodes:
        instance = node["spec"]["providerID"].split("/")[-1]
        require(re.fullmatch(r"i-[0-9a-f]{8,17}", instance), "INVALID_NODE_ID")
        interfaces = aws("ec2", "describe-network-interfaces", "--filters", f"Name=attachment.instance-id,Values={instance}")["NetworkInterfaces"]
        require(bool(interfaces) and all(n["VpcId"] == exports["vpc-id"] and node_sg in {g["GroupId"] for g in n["Groups"]}
                                        for n in interfaces), "NODE_SECURITY_GROUP_MISMATCH")
    groups = aws("ec2", "describe-security-groups", "--group-ids",
                 *sorted({exports[f] for f in FIELDS if f.endswith("security-group-id")}))["SecurityGroups"]
    require(len(groups) == len({exports[f] for f in FIELDS if f.endswith("security-group-id")})
            and all(g["VpcId"] == exports["vpc-id"] for g in groups), "SECURITY_GROUP_VPC_MISMATCH")
    auth = next(g for g in groups if g["GroupId"] == exports["auth-security-group-id"])
    require(auth["GroupName"] == f"mecanica-{environment}-auth" and tags_match(auth, environment), "AUTH_SG_INVALID")
    namespace = json.loads(kubectl("get", "namespace", exports["namespace"], "-o", "json"))
    require(namespace["status"]["phase"] == "Active", "NAMESPACE_NOT_READY")
    role = f"arn:aws:iam::{ACCOUNT}:role/mecanica/pipelines/mecanica-{environment}-database-github"
    entry = aws("eks", "describe-access-entry", "--cluster-name", exports["cluster-name"], "--principal-arn", role)["accessEntry"]
    policies = aws("eks", "list-associated-access-policies", "--cluster-name", exports["cluster-name"], "--principal-arn", role)["associatedAccessPolicies"]
    require(entry["type"] == "STANDARD" and entry["principalArn"] == role, "DATABASE_ACCESS_ENTRY_INVALID")
    require(any(p["policyArn"] == "arn:aws:eks::aws:cluster-access-policy/AmazonEKSEditPolicy"
                and p["accessScope"]["type"] == "namespace" and p["accessScope"]["namespaces"] == [exports["namespace"]]
                for p in policies), "DATABASE_POLICY_MISSING")
    access = {"entry": entry, "policies": sorted(policies, key=lambda p: p["policyArn"])}
    return hashlib.sha256(packed(access).encode()).hexdigest()


class Protocol:
    def __init__(self, environment, context):
        require(environment in ("hom", "prd"), "INVALID_ENVIRONMENT")
        self.environment = environment
        self.prefix = f"/mecanica/{environment}/base/v1"
        self.context = Path(context)

    def load(self):
        value = json.loads(self.context.read_text(encoding="utf-8"))
        require(value["environment"] == self.environment and value["component"] == "base", "CONTEXT_MISMATCH")
        return value

    def save(self, value):
        self.context.write_text(packed(value), encoding="utf-8")

    def record(self, value, status, code=None):
        value.update(status=status, recordedAt=now())
        if code:
            value.update(errorCode=code, message=code)
        else:
            value.pop("errorCode", None)
            value.pop("message", None)
        write_parameter(f"{self.prefix}/attempts/{value['deploymentId']}", packed(value))
        self.save(value)

    def invalidate(self):
        for name in ("release", "database-release", "database-candidate"):
            delete_parameter(f"{self.prefix}/{name}")

    def begin(self, plan, operation):
        # Never recover a context file left by an earlier local invocation as this operation.
        self.context.unlink(missing_ok=True)
        require(os.environ.get("GITHUB_REPOSITORY") == REPOSITORY, "INVALID_REPOSITORY")
        commit = os.environ.get("GITHUB_SHA", "")
        run, attempt = os.environ.get("GITHUB_RUN_ID", ""), os.environ.get("GITHUB_RUN_ATTEMPT", "")
        require(re.fullmatch(r"[0-9a-f]{40}", commit) and run.isdigit() and attempt.isdigit(), "INVALID_SOURCE")
        full = read_parameter(f"{self.prefix}/release")
        require(operation == "destroy" or full is None, "FULL_PROFILE_REQUIRES_FULL_PUBLISHER")
        generation = None
        for resource in plan.get("resource_changes", []):
            if resource["address"] == "terraform_data.generation":
                generation = (resource["change"].get("before") or {}).get("id")
        if generation:
            uuid.UUID(generation)
        previous = read_parameter(f"{self.prefix}/database-release")
        if previous:
            old = json.loads(previous)
            require(old["environment"] == self.environment and old["accountId"] == ACCOUNT and old["region"] == REGION, "PREVIOUS_RELEASE_INVALID")
            require(operation == "destroy" or generation == old["generation"], "GENERATION_MISMATCH")
            generation = generation or old["generation"]
        value = dict(schemaVersion="1.1.0", environment=self.environment, component="base",
                     accountId=ACCOUNT, region=REGION, deploymentId=f"{run}-{attempt}-base",
                     generation=generation, source=dict(repository=REPOSITORY, commit=commit),
                     readinessProfile="database", exports={}, dependencies={}, artifacts=[], compatibility={}, verification=[])
        # Save before remote changes so failed invalidation can be diagnosed.
        self.save(value)
        self.record(value, "running")
        self.invalidate()

    def prepare(self, outputs):
        value = self.load()
        generation = outputs["base_generation"]["value"]
        uuid.UUID(generation)
        require(value["generation"] in (None, generation), "GENERATION_MISMATCH")
        exports = outputs["database_exports"]["value"]
        access_hash = check_resources(exports, self.environment)
        value.update(generation=generation, exports=exports,
                     verification=["eks-health", "private-network", "effective-security-groups", "namespace", "database-access-policy"])
        self.save(value)
        candidate = dict(schemaVersion="1.0.0", environment=self.environment, accountId=ACCOUNT,
                         region=REGION, generation=generation,
                         exports=exports, accessSha256=access_hash)
        # Invalidation may have just deleted this name. Also safe across runner restarts.
        time.sleep(30)
        write_parameter(f"{self.prefix}/database-candidate", packed(candidate))
        return candidate

    def publish(self):
        value = self.load()
        raw = read_parameter(f"{self.prefix}/database-candidate")
        require(raw is not None, "CANDIDATE_MISSING")
        candidate = json.loads(raw)
        require(candidate["generation"] == value["generation"] and candidate["exports"] == value["exports"]
                and candidate["environment"] == self.environment and candidate["accountId"] == ACCOUNT
                and candidate["region"] == REGION and candidate["schemaVersion"] == "1.0.0", "CANDIDATE_CHANGED")
        evidence_raw = read_parameter(f"/mecanica/{self.environment}/database/v1/base-access-check")
        if evidence_raw is None:
            self.record(value, "blocked", "DATABASE_ACCESS_CHECK_REQUIRED")
            return False
        evidence = json.loads(evidence_raw)
        expected = hashlib.sha256(packed(candidate).encode()).hexdigest()
        checked = datetime.fromisoformat(evidence["recordedAt"].replace("Z", "+00:00"))
        role = f"arn:aws:iam::{ACCOUNT}:role/mecanica/pipelines/mecanica-{self.environment}-database-github"
        valid = (evidence.get("schemaVersion") == "1.0.0" and evidence.get("environment") == self.environment
                 and evidence.get("generation") == value["generation"] and evidence.get("candidateSha256") == expected
                 and evidence.get("roleArn") == role and evidence.get("checks") == ACCESS_CHECKS
                 and 0 <= (datetime.now(timezone.utc) - checked).total_seconds() <= 86400)
        if not valid:
            self.record(value, "blocked", "DATABASE_ACCESS_CHECK_STALE")
            return False
        require(check_resources(value["exports"], self.environment) == candidate["accessSha256"], "DATABASE_ACCESS_CHANGED")
        require(read_parameter(f"{self.prefix}/database-candidate") == raw, "CANDIDATE_CHANGED")
        for name, item in value["exports"].items():
            write_parameter(f"{self.prefix}/{name}", packed(item) if isinstance(item, list) else str(item))
        value["verification"].append("database-role-kubernetes-access")
        self.record(value, "ready")
        write_parameter(f"{self.prefix}/database-release", packed(value))
        require(read_parameter(f"{self.prefix}/release") is None, "UNEXPECTED_FULL_RELEASE")
        return True

    def destroyed(self):
        value = self.load()
        self.invalidate()
        for field in FIELDS + FULL_FIELDS:
            delete_parameter(f"{self.prefix}/{field}")
        value["verification"] = ["terraform-state-empty", "eks-absent", "vpc-nat-eip-absent", "ssm-active-fields-absent"]
        self.record(value, "destroyed")

    def failed(self):
        if not self.context.exists():
            return
        value = self.load()
        # A pending bank check keeps the candidate available; it never exposes a release.
        if value.get("status") == "blocked":
            return
        self.invalidate()
        self.record(value, "failed", "BASE_OPERATION_FAILED")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("command", choices=("begin", "prepare", "publish", "destroyed", "failed"))
    parser.add_argument("--environment", choices=("hom", "prd"), required=True)
    parser.add_argument("--context", required=True)
    parser.add_argument("--input")
    parser.add_argument("--operation", choices=("provision", "destroy"), default="provision")
    args = parser.parse_args()
    protocol = Protocol(args.environment, args.context)
    try:
        if args.command == "begin":
            protocol.begin(json.loads(Path(args.input).read_text(encoding="utf-8-sig")), args.operation)
        elif args.command == "prepare":
            protocol.prepare(json.loads(Path(args.input).read_text(encoding="utf-8-sig")))
        elif args.command == "publish":
            if not protocol.publish():
                print("Base criada, mas acesso do banco pendente. Execute aws-oidc-check no banco com check_kubernetes=true e repita activate no mesmo commit.")
                return 3
        else:
            getattr(protocol, args.command)()
        return 0
    except (MetadataError, ValueError, KeyError, TypeError, AttributeError, StopIteration, OSError) as error:
        print(str(error) if isinstance(error, MetadataError) else "INVALID_METADATA_OR_RUNTIME", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
