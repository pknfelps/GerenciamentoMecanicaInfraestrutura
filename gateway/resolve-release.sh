#!/usr/bin/env bash
set -euo pipefail

case "${TARGET_ENVIRONMENT:-}" in
  hom|prd) ;;
  *) echo 'Use hom ou prd para resolver o deploy do Gateway.' >&2; exit 1 ;;
esac

prefix="/mecanica/$TARGET_ENVIRONMENT"
function_arn="arn:aws:lambda:us-east-1:121754142617:function:mecanica-$TARGET_ENVIRONMENT-auth"

if ! metadata="$(aws ssm get-parameters --no-with-decryption --names \
  "$prefix/base/v2/vpc-id" "$prefix/api/v2/deployment" \
  "$prefix/auth/v2/openapi-key" "$prefix/auth/v2/function-version" \
  "$prefix/auth/v2/invocation-arn" "$prefix/auth/v2/api-sync-version" --output json)" ||
   ! release="$(jq -cer --arg environment "$TARGET_ENVIRONMENT" --arg function_arn "$function_arn" '
     def sha: type == "string" and test("^[0-9a-f]{40}$");
     select(.InvalidParameters == [] and (.Parameters | length == 6 and all(.[]; .Type == "String"))) |
     (.Parameters | map({key: (.Name | split("/") | last), value: .Value}) | from_entries) as $meta |
     ($meta.deployment | fromjson) as $api |
     ($meta["openapi-key"] | capture("^contracts/auth/(?<commit>[0-9a-f]{40})/openapi\\.json$").commit) as $auth |
     select($api.environment == $environment and $api.vpc == $meta["vpc-id"] and
       ($api.vpc | test("^vpc-[0-9a-f]+$")) and ($api.commit | sha) and
       ($api.imageDigest | test("^sha256:[0-9a-f]{64}$")) and
       ($meta["function-version"] | test("^[1-9][0-9]*$")) and
       $meta["api-sync-version"] == ("1:" + $meta["function-version"]) and
       $meta["invocation-arn"] == ($function_arn + ":" + $meta["function-version"])) |
     {apiCommit: $api.commit, apiDigest: $api.imageDigest, vpc: $api.vpc,
       authCommit: $auth, authInvocationArn: $meta["invocation-arn"]}
   ' <<< "$metadata" 2>/dev/null)"; then
  echo '::error::Conclua api-deploy e auth-provision no ambiente antes de atualizar o Gateway.' >&2
  exit 1
fi

printf '%s\n' "$release"
