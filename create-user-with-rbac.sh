
#!/bin/bash

# ------------------------------------------------------------------------------
# Script Name : create-user-with-rbac.sh
# Description : Creates a Kubernetes user with namespace-scoped access.
# 
# How it works:
# 1. Accepts a username and list of namespace:access pairs (e.g. dev:write qa:read).
# 2. Namespaces starting with 'prod' are always granted read-only access.
# 3. Generates a private key and a CSR, submits it to the Kubernetes API, and approves it.
# 4. Extracts the signed certificate and creates a kubeconfig file for the user.
# 5. For each namespace:
#    - If access is 'read', creates a Role with read-only rules and binds the user.
#    - If access is 'write', binds the user to the built-in 'edit' ClusterRole.
# 6. Optionally grants ClusterRole access to 'get' and 'list' all namespaces.
# Output : A kubeconfig file named <username>-kubeconfig.yaml usable via KUBECONFIG env.
# ------------------------------------------------------------------------------


# ------------------------------------------------------------------------------
# Script Name: create-user-with-rbac.sh
# Description : Creates a Kubernetes user with namespace-specific access.
# Usage       : ./create-user-with-rbac.sh <username> <namespace1>:<read|write> <namespace2>:<read|write> ...
# Behavior    : - Auto-generates key, CSR, approves certificate, and creates kubeconfig.
#              - For namespaces starting with 'prod', access is always 'read'.
#              - 'read' access uses a custom Role, 'write' uses built-in ClusterRole=edit.
#              - Optionally grants permission to list namespaces if desired.
# Output      : A kubeconfig file named <username>-kubeconfig.yaml
# ---------------------------------------------------------------------

set -e

USERNAME=$1
shift

if [[ -z "$USERNAME" || $# -eq 0 ]]; then
  echo "Usage: $0 <username> <namespace1>:<read|write> [namespace2:access] ..."
  exit 1
fi

# =============================
# Generate Key, CSR, and Cert
# =============================
CSR_NAME="${USERNAME}-csr"
KEY_FILE="${USERNAME}.key"
CSR_FILE="${USERNAME}.csr"
CRT_FILE="${USERNAME}.crt"
KUBECONFIG_FILE="${USERNAME}-kubeconfig.yaml"

echo "Generating key and CSR for user '$USERNAME'..."
openssl genrsa -out "$KEY_FILE" 2048
openssl req -new -key "$KEY_FILE" -out "$CSR_FILE" -subj "/CN=${USERNAME}"
CSR_BASE64=$(base64 -w0 < "$CSR_FILE")

cat <<EOF > "${CSR_NAME}.yaml"
apiVersion: certificates.k8s.io/v1
kind: CertificateSigningRequest
metadata:
  name: ${CSR_NAME}
spec:
  request: ${CSR_BASE64}
  signerName: kubernetes.io/kube-apiserver-client
  usages:
  - client auth
EOF

kubectl delete csr "$CSR_NAME" --ignore-not-found
kubectl apply -f "${CSR_NAME}.yaml"
sleep 2
kubectl certificate approve "${CSR_NAME}"

CERT=$(kubectl get csr "$CSR_NAME" -o jsonpath='{.status.certificate}')
echo "$CERT" | base64 -d > "$CRT_FILE"

CLUSTER_NAME=$(kubectl config current-context)
CLUSTER_SERVER=$(kubectl config view -o jsonpath="{.clusters[?(@.name==\"$CLUSTER_NAME\")].cluster.server}")
CA_DATA=$(kubectl config view --raw -o jsonpath="{.clusters[?(@.name==\"$CLUSTER_NAME\")].cluster.certificate-authority-data}")

CLIENT_CERT=$(base64 -w0 < "$CRT_FILE")
CLIENT_KEY=$(base64 -w0 < "$KEY_FILE")

# Create Kubeconfig
cat <<EOF > "$KUBECONFIG_FILE"
apiVersion: v1
kind: Config
clusters:
- name: kubernetes
  cluster:
    certificate-authority-data: ${CA_DATA}
    server: ${CLUSTER_SERVER}
contexts:
- name: ${USERNAME}@kubernetes
  context:
    cluster: kubernetes
    user: ${USERNAME}
current-context: ${USERNAME}@kubernetes
users:
- name: ${USERNAME}
  user:
    client-certificate-data: ${CLIENT_CERT}
    client-key-data: ${CLIENT_KEY}
EOF

echo "Kubeconfig  written to: $KUBECONFIG_FILE"

# Namespace Role Assignments
for ns_access in "$@"; do
  ns="${ns_access%%:*}"
  access="${ns_access##*:}"
  # Force read-only if namespace starts with "prod"
  if [[ "$ns" == prod* ]]; then
    access="read"
  fi
  echo "Setting $access access for $USERNAME in namespace $ns"
  kubectl create namespace "$ns" --dry-run=client -o yaml | kubectl apply -f -
  if [[ "$access" == "read" ]]; then
    cat <<EOF | kubectl apply -n "$ns" -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: readonly-role
rules:
- apiGroups: [""]
  resources: ["pods", "pods/log", "services", "endpoints", "configmaps", "secrets", "events"]
  verbs: ["get", "list", "watch"]
- apiGroups: ["apps"]
  resources: ["deployments", "replicasets", "statefulsets"]
  verbs: ["get", "list", "watch"]
- apiGroups: ["batch"]
  resources: ["jobs", "cronjobs"]
  verbs: ["get", "list", "watch"]
- apiGroups: ["networking.k8s.io"]
  resources: ["ingresses", "networkpolicies"]
  verbs: ["get", "list", "watch"]
- apiGroups: ["metrics.k8s.io"]
  resources: ["pods", "nodes"]
  verbs: ["get", "list", "watch"]
EOF

    kubectl create rolebinding "${USERNAME}-readonly-binding" \
      --namespace="$ns" \
      --role=readonly-role \
      --user="$USERNAME" \
      --dry-run=client -o yaml | kubectl apply -f -
  else
    kubectl create rolebinding "${USERNAME}-edit-binding" \
      --namespace="$ns" \
      --clusterrole=edit \
      --user="$USERNAME" \
      --dry-run=client -o yaml | kubectl apply -f -
  fi
done

# Global Namespace Reader Role
echo "Granting '$USERNAME' permission to list namespaces..."

cat <<EOF | kubectl apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: ${USERNAME}-namespace-reader
rules:
- apiGroups: [""]
  resources: ["namespaces"]
  verbs: ["get", "list"]
EOF

cat <<EOF | kubectl apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: ${USERNAME}-namespace-reader-binding
subjects:
- kind: User
  name: ${USERNAME}
  apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: ClusterRole
  name: ${USERNAME}-namespace-reader
  apiGroup: rbac.authorization.k8s.io
EOF

echo ""
echo "Done. Export successfull!"
