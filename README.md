# Apple Container and SIGHUP Distribution local lab

This repository installs a fully functional, local SIGHUP Distribution profile on Apple Container's experimental Kubernetes plugin.

> [!IMPORTANT]
> This is a personal proof of concept for local evaluation. It is not official SIGHUP Distribution documentation and is not a production or HA topology. Refer to the [official documentation](https://docs.sighup.io/) for supported installation guidance.

The current workflow was verified on 2026-09-11 with macOS 26.6.2 on Apple silicon, Container CLI and API server 1.4.1, the recommended Kata 3.32.0 guest kernel (`vmlinux-6.18.35-197-debug`), kubectl 1.34.1, Furyctl 0.35.1, and Kubernetes v1.35.5.

## Prerequisites

- An Apple-silicon Mac with Container CLI and API server 1.4.1 installed.
- `kubectl` and `curl` available on `PATH`.
- At least six CPUs and 16 GB of memory available for the cluster.
- Internet access to download the kernel, node image, Furyctl, SIGHUP artifacts, and Helm charts.

## Quick start

```bash
git clone https://github.com/matteobisi/fury-apple-container.git
cd fury-apple-container
container system start
./scripts/install-recommended-kernel.sh
./scripts/create-cluster.sh
export KUBECONFIG="$PWD/.state/sighup-local.kubeconfig"
./scripts/configure-node-sysctls.sh
./scripts/install-local-path-storage.sh
./scripts/install-furyctl.sh
export FURYCTL_BIN="$PWD/.tools/furyctl/furyctl"
./scripts/deploy-sighup-distribution.sh
```

The kernel script explicitly runs `container system kernel set --recommended --force`. Run it deliberately: `--force` replaces the selected default kernel. It prevents an installation upgraded from a pre-1.0 Container release from retaining the legacy kernel that causes native Kubernetes bootstrap to fail.

`create-cluster.sh` uses native `container k8s create` only. It writes an isolated kubeconfig under `.state/`, selects `sighup-local` in that file, and leaves the current context in `~/.kube/config` unchanged. The Container plugin also registers the cluster in the default kubeconfig; `destroy-cluster.sh` removes that plugin-managed entry when the cluster is deleted.

## What the profile installs

The profile follows the [SIGHUP Distribution on Minikube](https://docs.sighup.io/docs/getting-started/distro-on-minikube) local subset. It retains Apple Container's kindnet CNI and installs single HAProxy ingress, cert-manager, Loki logging, Prometheus monitoring, Tempo tracing, Forecastle, and local dynamic storage. Policy, disaster recovery, and authentication are disabled.

Apple Container does not create a default StorageClass, so `install-local-path-storage.sh` installs Rancher's local-path provisioner and marks it as default. Its storage is tied to the one local node.

The logging profile requires:

```text
fs.inotify.max_user_instances=8192
fs.inotify.max_user_watches=524288
```

`configure-node-sysctls.sh` persists and applies these SIGHUP-recommended limits in the node. The deployment helper removes the two systemd-only host tailers, which cannot run in this node, then waits for all Deployment, DaemonSet, and StatefulSet rollouts to finish.

## Verification

After deployment, inspect the ready workloads and access Grafana through a port-forward:

```bash
kubectl get nodes
kubectl get deployment,daemonset,statefulset -A
kubectl get pvc -A
kubectl -n monitoring port-forward service/grafana 3000:3000
```

`http://127.0.0.1:3000/login` returned HTTP 200 in the verified workflow.

The optional registry-free development test builds an image locally, imports it into the node's CRI store, and deploys it with `imagePullPolicy: Never`:

```bash
./scripts/deploy-local-demo.sh
kubectl -n local-demo port-forward service/local-demo 8080:80
```

## Layout

| Path | Purpose |
| --- | --- |
| `scripts/install-recommended-kernel.sh` | Explicitly installs the Container-recommended default kernel. |
| `scripts/create-cluster.sh` | Creates the native six-CPU, 16-GB Apple Container Kubernetes cluster. |
| `scripts/configure-node-sysctls.sh` | Applies the inotify settings required by the SIGHUP logging collector. |
| `scripts/install-local-path-storage.sh` | Installs the local default StorageClass. |
| `scripts/install-furyctl.sh` | Downloads and checksum-verifies the macOS arm64 Furyctl release. |
| `scripts/deploy-sighup-distribution.sh` | Applies the profile, removes unsupported tailers, and waits for workloads. |
| `scripts/deploy-local-demo.sh` | Verifies the optional local-image development loop. |
| `scripts/destroy-cluster.sh` | Deletes the named cluster and its isolated kubeconfig. |
| `docs/verification-journal.md` | Current verified behavior and functional evidence. |
| `legacy/container-1.2.2-iptables-recovery/` | Historical workaround and evidence for the pre-1.0 kernel failure. |

## Historical recovery

The original Container 1.2.2 workaround is preserved under `legacy/container-1.2.2-iptables-recovery/`. It documents the old `iptables-nft` node-preparation failure tracked in [apple/container#2120](https://github.com/apple/container/issues/2120). Do not use that manual kubeadm recovery for new installations.

## Teardown

Delete the full local cluster, its workloads, and the lab kubeconfig:

```bash
./scripts/destroy-cluster.sh
```
