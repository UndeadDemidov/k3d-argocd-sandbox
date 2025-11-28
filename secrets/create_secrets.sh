#!/bin/bash

log() {
	echo "$(date '+%y-%m-%d %H:%M:%S') | INF | $*" >&2
}

err() {
	echo "$(date '+%y-%m-%d %H:%M:%S') | ERR | $*" >&2
}

die() {
	err "$@"
	exit 1
}

add_labels_to_secret() {
  local labels=$1
  local secret_name=$2
  
  if [[ -n "$labels" && "$labels" != "null" ]]; then
    log "Adding labels to secret $secret_name";
    LABELS=$labels yq eval '.spec.template.metadata.labels = env(LABELS)' -i sealed_secret.json
  fi
}

process_secret() {
  local PRJ_DIR=$1
  local SS_PUB_KEY=$2
  local secret_name=$3

  local json=$(yq eval -o json '.' config.yaml)
  local namespace=$(echo $json | jq -r '.namespace')
  local path=$(echo $json | jq -r '.path')

  resources_json="[]"
  for secret in $(echo $json | jq -r '.secrets[].name'); do
    local item=$(yq eval -o json ".secrets[] | select(.name==\"$secret\")" config.yaml)
    local name=$(echo $item | jq -r '.name')
    local type=$(echo $item | jq -r '.type')

    local source=$(echo $item | jq -r '.source')
    local vault="vault/$source"

    local labels=$(echo $item | jq -r '.labels // empty')

    case "$type" in
      "env")
        if [[ ! (-f $vault) ]]; then die "File $vault does not exists."; fi

        log "Create env secret $name in resources.yaml";
        kubectl create secret generic $name --dry-run=client --from-env-file=$vault -n $namespace -o yaml \
        | kubeseal --cert $SS_PUB_KEY -f /dev/stdin > sealed_secret.json
        
        add_labels_to_secret "$labels" "$name"
        
        resources_json=$(echo $resources_json | jq --slurpfile f sealed_secret.json '. += $f')
        ;;
      "file")
        if [[ ! (-f $vault) ]]; then die "File $vault does not exists."; fi

        log "Create file secret $name in resources.yaml";
        kubectl create secret generic $name --dry-run=client --from-file=${source}=$vault -n $namespace -o yaml \
        | kubeseal --cert $SS_PUB_KEY -f /dev/stdin > sealed_secret.json
        
        add_labels_to_secret "$labels" "$name"
        
        resources_json=$(echo $resources_json | jq --slurpfile f sealed_secret.json '. += $f')
        ;;
      "dockerjsonconfig")
        if [[ ! (-f $vault) ]]; then die "File $vault does not exists."; fi

        log "Create dockerjsonconfig secret $name in resources.yaml";
        kubectl create secret generic $name --dry-run=client --from-file=.dockerconfigjson=$vault --type=kubernetes.io/dockerconfigjson -n $namespace -o yaml \
        | kubeseal --cert $SS_PUB_KEY -f /dev/stdin > sealed_secret.json
        
        add_labels_to_secret "$labels" "$name"
        
        resources_json=$(echo $resources_json | jq --slurpfile f sealed_secret.json '. += $f')
        ;;
      "files")
        log "Create files secret $name in resources.yaml";
        # gen one secret from set of files
        local sources=$(echo $item | jq -r '.sources[]')
        local kubectl_cmd="kubectl create secret generic $name --dry-run=client"
        
        # Add each file to the secret
        for source in $sources; do
          local vault_file="vault/$source"
          if [[ ! (-f $vault_file) ]]; then die "File $vault_file does not exists."; fi

          # Extract filename from path to use as key name (Kubernetes keys cannot contain slashes)
          local key_name=$(basename "$source")
          kubectl_cmd="$kubectl_cmd --from-file=$key_name=$vault_file"
        done
        
        # Create sealed secret
        eval "$kubectl_cmd -n $namespace -o yaml" \
        | kubeseal --cert $SS_PUB_KEY -f /dev/stdin > sealed_secret.json
        
        add_labels_to_secret "$labels" "$name"

        resources_json=$(echo $resources_json | jq --slurpfile f sealed_secret.json '. += $f')
        ;;
      *)
        die "illegal secret type: $type"
        ;;
    esac
  done
  
  # Check if any secrets were created
  if [[ $(echo $resources_json | jq 'length') -eq 0 ]]; then 
    die "No secrets were created!"; 
  fi

  echo $resources_json | yq eval -P '{"extraDeploy": .}' > resources.yaml

  log "Create ArgoCD manifest.yaml"
  cp -f "$PRJ_DIR/manifest.yaml" ./manifest.yaml
  sed -i '' "s|RELEASE_NAME|$secret_name|g" manifest.yaml
  sed -i '' "s|KUBE_NAMESPACE|$namespace|g" manifest.yaml

  log "Inject SealedSecret resources.yaml in ArgoCD manifest.yaml"
  cat resources.yaml | sed -r 's|^|        |' >> manifest.yaml

  mkdir -p "$(dirname "$(dirname "$PRJ_DIR")/$path")"
  cp -f manifest.yaml "$(dirname "$PRJ_DIR")/$path"

  log "Remove resources.yaml and manifest.yaml"
  rm -f sealed_secret.json resources.yaml manifest.yaml
}

process_cluster() {
  local PRJ_DIR=$1;
  local FQDN=$2;
  local SS_PUB_KEY="${PRJ_DIR}/${FQDN}/ss-pub-key.pem";

  for entry in $(find . -type f -name config.yaml | xargs -I {} dirname {} | sed 's/\.\///'); do
    # Continue if no changes for the secret
    # if [[ -z "$(git --no-pager diff --name-only HEAD HEAD~1 -- ${entry})" ]]; then continue; fi
    secret_name=$(echo "$entry" | awk '{split($0,a,"/"); print a[1]}');
    log "Processing secret $secret_name";
    cd $secret_name
      process_secret $PRJ_DIR $SS_PUB_KEY $secret_name
    cd - > /dev/null
  done
}

set -o pipefail
# shopt -s lastpipe

PRJ_DIR=$(pwd)
for cluster in $(ls -1d */); do
  # Continue if no changes for whole cluster
  # if [[ -z "$(git --no-pager diff --name-only HEAD HEAD~1 -- ${cluster})" ]]; then continue; fi
  FQDN=${cluster%/} # remove trailing slash

  log "======== PROCESSING CLUSTER $FQDN ========"
  cd $cluster
    process_cluster $PRJ_DIR $FQDN # make it uppercase
  cd $PRJ_DIR
done
