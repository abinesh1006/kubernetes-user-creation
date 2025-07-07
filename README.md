Here’s the complete **`README.md`** file in Markdown format:

---

````markdown
# 🚀 Kubernetes User Provisioning Script (`kube.sh`)

This script automates the creation of a Kubernetes user with fine-grained access to specific namespaces using client certificates and RBAC.

---

## 📌 Features

- Creates a user identity using a **client certificate** and generates a **kubeconfig** file.
- Grants access to specific namespaces:
  - `read` → creates a custom Role with read-only permissions.
  - `write` → binds to the built-in `edit` ClusterRole.
- Automatically enforces **read-only access** for any namespace that starts with `prod`.
- Optionally includes permissions to list all namespaces (if enabled in the script).

---

## ✅ Prerequisites

- Access to a Kubernetes cluster as an **admin**.
- `kubectl`, `openssl`, and `bash` installed locally.

---

## ⚙️ How to Execute

```bash
chmod +x kube.sh
./kube.sh <username> <namespace1>:<read|write> <namespace2>:<read|write> ...
````

### Example:

```bash
./kube.sh alice dev:write qa:read prod-db:write
```

> 🔒 Even though `prod-db:write` is passed, the script will enforce **read-only access** because the namespace starts with `prod`.

---

## 📁 Files Generated

| File                         | Description                                 |
| ---------------------------- | ------------------------------------------- |
| `<username>.key`             | Private key for the user                    |
| `<username>.csr`             | Certificate Signing Request                 |
| `<username>.crt`             | Signed certificate issued by Kubernetes     |
| `<username>-kubeconfig.yaml` | Kubeconfig file to authenticate as the user |

---

## 🔐 How to Access the Cluster

Once the kubeconfig is created, export it and start using `kubectl`:

```bash
export KUBECONFIG=$PWD/<username>-kubeconfig.yaml
kubectl get pods -n dev
```

---

## 👤 Who Can Execute This Script?

This script must be executed by someone with **cluster-admin** privileges:

* Able to create and approve CertificateSigningRequests
* Able to create Roles, RoleBindings, ClusterRoleBindings
* Able to manage all relevant namespaces

---

## 📌 Notes

* Namespaces will be created if they don’t already exist.
* You may securely send the generated kubeconfig file to the user.
* You can revoke access later by deleting:

  * The user's RoleBindings
  * The signed certificate
  * The kubeconfig file

---

## 📦 Optional Enhancements

* Zip the generated files for delivery:

  ```bash
  zip alice-kubeconfig.zip alice.*
  ```
* Audit access by reviewing RoleBindings:

  ```bash
  kubectl get rolebindings --all-namespaces | grep <username>
  ```

---
