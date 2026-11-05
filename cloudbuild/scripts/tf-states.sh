#!/bin/sh
# Plans or applies every Terraform state: the platform root first, then one tenant state per tenants/<id>.yaml.
set -eu

mode="${1:?usage: tf-states.sh pr-plan|plan|apply}"
bucket="${STATE_BUCKET:?STATE_BUCKET is required}"
plans="${PLANS_DIR:-/workspace/plans}"

case "$mode" in
  pr-plan | plan | apply) ;;
  *) echo "unknown mode: $mode" >&2; exit 2 ;;
esac

states() {
  echo platform
  [ -d terraform/tenant ] || return 0
  for f in tenants/*.yaml; do
    [ -e "$f" ] || continue
    id=$(basename "$f" .yaml)
    if ! echo "$id" | grep -Eq '^[a-z][a-z0-9]{2,14}$'; then
      echo "invalid tenant ID: $id" >&2
      return 1
    fi
    echo "tenant/$id"
  done
}

list=$(states)

plan_name() {
  case "$1" in
    platform) echo platform ;;
    tenant/*) echo "tenant-${1#tenant/}" ;;
  esac
}

if [ "$mode" = apply ]; then
  for state in $list; do
    if [ ! -f "$plans/$(plan_name "$state").tfplan" ]; then
      echo "no saved plan for $state; nothing applied" >&2
      exit 1
    fi
  done
fi

for state in $list; do
  case "$state" in
    platform)
      dir=terraform
      prefix=platform
      vars=""
      ;;
    tenant/*)
      id="${state#tenant/}"
      dir=terraform/tenant
      prefix="tenants/$id"
      vars="-var=tenant=$id"
      if [ -f terraform/platform.auto.tfvars.json ]; then
        cp terraform/platform.auto.tfvars.json "$dir/"
      fi
      ;;
  esac

  name=$(plan_name "$state")
  echo "== $state"
  terraform -chdir="$dir" init -input=false -reconfigure -backend-config="bucket=$bucket" -backend-config="prefix=$prefix"

  case "$mode" in
    pr-plan)
      terraform -chdir="$dir" validate
      terraform -chdir="$dir" plan -input=false -lock=false $vars
      ;;
    plan)
      mkdir -p "$plans"
      terraform -chdir="$dir" plan -input=false $vars -out="$plans/$name.tfplan"
      ;;
    apply)
      terraform -chdir="$dir" apply -input=false "$plans/$name.tfplan"
      ;;
  esac
done
