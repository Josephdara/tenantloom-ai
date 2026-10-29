#!/usr/bin/env bash
# Releases the apply lock and writes the CI apply record, whatever happened in the earlier steps.
set -uo pipefail

out=/workspace/ci
val() { cat "$out/$1" 2>/dev/null || true; }
quoted_or_null() { if [[ -n "$1" ]]; then printf '"%s"' "$1"; else printf 'null'; fi; }

rc=0
if [[ ! -f "$out/ready" ]]; then
  outcome="PREPARE_FAILED"
  echo "Prepare failed: $(val reason)" >&2
elif [[ "$(val apply_rc)" == "0" ]]; then
  outcome="SUCCESS"
else
  outcome="APPLY_FAILED"
fi

if [[ -f "$out/ready" ]]; then
  gcloud storage rm "gs://${LOCK_BUCKET}/apply.lock" --if-generation-match="$(val lock_generation)" \
    || { echo "Could not release the apply lock." >&2; rc=1; }
fi

now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
started_at=$(val started_at)
printf '{"apply_build_id":"%s","plan_build_id":"%s","layer":"%s","state":"%s","commit_sha":"%s","pull_request":null,"plan_sha256":"%s","approver":%s,"approved_at":%s,"apply_identity":"%s","started_at":"%s","finished_at":"%s","outcome":"%s"}\n' \
  "$BUILD_ID" "$(val plan_build_id)" "$LAYER" "$STATE_PREFIX" "$COMMIT_SHA" "$(val plan_sha256)" \
  "$(quoted_or_null "$(val approver)")" "$(quoted_or_null "$(val approved_at)")" \
  "$(gcloud config get account 2>/dev/null)" "${started_at:-$now}" "$now" "$outcome" > "$out/record.json"

bq --project_id="$PROJECT_ID" insert ci_records.apply_records "$out/record.json" \
  || { echo "Could not write the CI record." >&2; rc=1; }

[[ "$outcome" == "SUCCESS" ]] || rc=1
exit "$rc"
