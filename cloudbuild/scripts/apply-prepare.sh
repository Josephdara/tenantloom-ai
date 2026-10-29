#!/usr/bin/env bash
# Checks approval, waits for the matching plan build, takes the apply lock, and verifies the saved plan.
set -euo pipefail

out=/workspace/ci
lock="gs://${LOCK_BUCKET}/apply.lock"
mkdir -p "$out"
date -u +%Y-%m-%dT%H:%M:%SZ > "$out/started_at"

fail() {
  echo "$1" | tee "$out/reason" >&2
  exit 1
}

read -r decision approver approved_at < <(gcloud builds describe "$BUILD_ID" --region="$REGION" \
  --format='value(approval.result.decision,approval.result.approverAccount,approval.result.approvalTime)') || true
[[ "${decision:-}" == "APPROVED" ]] || fail "Build ${BUILD_ID} is not approved."
echo "$approver" > "$out/approver"
echo "$approved_at" > "$out/approved_at"

deadline=$((SECONDS + 900))
while :; do
  plan_id="" plan_status=""
  read -r plan_id plan_status < <(gcloud builds list --region="$REGION" \
    --filter="buildTriggerId=${PLAN_TRIGGER_ID} AND substitutions.COMMIT_SHA=${COMMIT_SHA}" \
    --sort-by=~createTime --limit=1 --format='value(id,status)') || true
  case "$plan_status" in
    SUCCESS) break ;;
    ""|PENDING|QUEUED|WORKING) ;;
    *) fail "Plan build ${plan_id} for ${COMMIT_SHA} ended with ${plan_status}." ;;
  esac
  (( SECONDS < deadline )) || fail "No successful plan build for ${COMMIT_SHA}."
  echo "Waiting for the plan build of ${COMMIT_SHA}."
  sleep 30
done
echo "$plan_id" > "$out/plan_build_id"

printf '{"build_id":"%s","layer":"%s","state":"%s","commit":"%s"}\n' \
  "$BUILD_ID" "$LAYER" "$STATE_PREFIX" "$COMMIT_SHA" > "$out/lock.json"
while ! err=$(gcloud storage cp "$out/lock.json" "$lock" --if-generation-match=0 2>&1); do
  [[ "$err" == *412* ]] || fail "Could not create the apply lock: ${err}"
  echo "Apply lock is held by another build; waiting."
  sleep 30
done
generation=$(gcloud storage objects describe "$lock" --format='value(generation)')
echo "$generation" > "$out/lock_generation"

release() {
  gcloud storage rm "$lock" --if-generation-match="$generation" || true
}
trap release EXIT

src="gs://${PLAN_BUCKET}/${LAYER}/${plan_id}"
gcloud storage cp "${src}/tfplan" "${src}/tfplan.sha256" "$out/"
(cd "$out" && sha256sum -c tfplan.sha256) || fail "Saved plan ${plan_id} does not match its hash."
cut -d' ' -f1 "$out/tfplan.sha256" > "$out/plan_sha256"

current=$(gcloud storage objects describe "$lock" --format='value(generation)') || fail "The apply lock disappeared."
[[ "$current" == "$generation" ]] || fail "The apply lock was replaced by another holder."

touch "$out/ready"
trap - EXIT
