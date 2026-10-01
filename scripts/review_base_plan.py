"""Review a private Terraform JSON plan; emit only addresses, actions and a fingerprint."""
import argparse
import hashlib
import json
from pathlib import Path


def review(plan):
    if plan.get("errored") or plan.get("complete") is False:
        raise ValueError("Plano incompleto ou com erro; não pode ser aplicado.")
    managed = [c for c in plan.get("resource_changes", []) if c.get("mode") == "managed"]
    # Ignore run timestamp and data-source refresh noise; keep all managed before/after,
    # unknowns, sensitivity markers, drift, outputs and selected variables in the approval.
    payload = {
        "format_version": plan.get("format_version"),
        "terraform_version": plan.get("terraform_version"),
        "variables": plan.get("variables", {}),
        "resources": sorted(managed, key=lambda c: c["address"]),
        "outputs": plan.get("output_changes", {}),
        "drift": sorted([c for c in plan.get("resource_drift", []) if c.get("mode") == "managed"], key=lambda c: c["address"]),
    }
    fingerprint = hashlib.sha256(json.dumps(payload, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode()).hexdigest()
    changes = [{"address": c["address"], "actions": c["change"]["actions"]} for c in managed if c["change"]["actions"] != ["no-op"]]
    creates_cluster = any(c.get("type") == "aws_eks_cluster" and "create" in c["change"]["actions"] for c in managed)
    for c in managed:
        if c.get("type") == "aws_eks_cluster" and "create" in c["change"]["actions"]:
            config = (c["change"].get("after") or {}).get("access_config", [])
            if len(config) != 1 or config[0].get("bootstrap_cluster_creator_admin_permissions") is not False:
                raise ValueError("Cluster novo exige bootstrap_cluster_creator_admin_permissions=false. Preserve true no hom existente; após descarte, ajuste o arquivo antes de recriar.")
    return {
        "sha256": fingerprint,
        "changes": changes,
        "has_changes": bool(changes or any(v.get("actions") != ["no-op"] for v in plan.get("output_changes", {}).values())),
        "destructive": any("delete" in c["actions"] for c in changes),
        "creates_cluster": creates_cluster,
    }


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("plan", type=Path)
    parser.add_argument("--report", required=True, type=Path)
    parser.add_argument("--expected-sha256", default="")
    args = parser.parse_args()
    result = review(json.loads(args.plan.read_text(encoding="utf-8-sig")))
    args.report.write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(result, indent=2))
    if args.expected_sha256 and result["sha256"] != args.expected_sha256.lower():
        raise SystemExit("O plano mudou desde a revisão. Inicie nova ativação e aprove o novo resumo; nenhum apply executado.")


if __name__ == "__main__":
    main()
