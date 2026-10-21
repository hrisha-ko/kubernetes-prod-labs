#!/usr/bin/env bash
# Creates kubeconfigs/<username>.kubeconfig with a client certificate signed by the cluster CA.
# Usage: ./generate-kubeconfig.sh <username> <group> <default-namespace>
set -euo pipefail
cd "$(dirname "$0")"
source ./common.sh

USER_NAME="${1:?username is required}"
GROUP="${2:?group is required}"
DEFAULT_NS="${3:-default}"

KCFG="${OUT_DIR}/${USER_NAME}.kubeconfig"
CSR_NAME="${USER_NAME}-csr"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$OUT_DIR"

# 1. Private key and certificate request (CN = user, O = group)
openssl genrsa -out "$TMP/key" 2048 2>/dev/null
openssl req -new -key "$TMP/key" -out "$TMP/csr" -subj "/CN=${USER_NAME}/O=${GROUP}"

# 2. Have the cluster sign it
k delete csr "$CSR_NAME" --ignore-not-found >/dev/null
cat <<YAML | k apply -f - >/dev/null
apiVersion: certificates.k8s.io/v1
kind: CertificateSigningRequest
metadata:
  name: ${CSR_NAME}
spec:
  request: $(base64 < "$TMP/csr" | tr -d '\n')
  signerName: kubernetes.io/kube-apiserver-client
  expirationSeconds: 31536000   # 1 year
  usages: ["client auth"]
YAML
k certificate approve "$CSR_NAME" >/dev/null
k wait csr "$CSR_NAME" --for=jsonpath='{.status.certificate}' --timeout=30s >/dev/null
k get csr "$CSR_NAME" -o jsonpath='{.status.certificate}' | base64 --decode > "$TMP/crt"
k delete csr "$CSR_NAME" >/dev/null

# 3. Build the kubeconfig (CA, certificate and key are embedded)
k config view --minify --raw --flatten -o jsonpath='{.clusters[0].cluster.certificate-authority-data}' \
  | base64 --decode > "$TMP/ca"

rm -f "$KCFG"
kc() { kubectl config --kubeconfig="$KCFG" "$@" >/dev/null; }
kc set-cluster "$CLUSTER_NAME" --server="$SERVER" --certificate-authority="$TMP/ca" --embed-certs=true
kc set-credentials "$USER_NAME" --client-certificate="$TMP/crt" --client-key="$TMP/key" --embed-certs=true
kc set-context "$USER_NAME" --cluster="$CLUSTER_NAME" --user="$USER_NAME" --namespace="$DEFAULT_NS"
kc use-context "$USER_NAME"
chmod 600 "$KCFG"

echo ">> [$USER_NAME] Done: $KCFG"
