#!/usr/bin/env bash
# Shared settings for setup.sh / generate-kubeconfig.sh / verify.sh

# Admin context of the existing cluster (defaults to the current one)
KUBE_CONTEXT="${KUBE_CONTEXT:-$(kubectl config current-context)}"
# Cluster name inside the generated kubeconfig files (just a label)
CLUSTER_NAME="${CLUSTER_NAME:-k8s-mentoring}"
OUT_DIR="${OUT_DIR:-./kubeconfigs}"
export KUBE_CONTEXT CLUSTER_NAME OUT_DIR

k() { kubectl --context "$KUBE_CONTEXT" "$@"; }

SERVER="$(k config view --minify --raw -o jsonpath='{.clusters[0].cluster.server}')"
