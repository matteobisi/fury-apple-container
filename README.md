# Apple Container and SIGHUP Distribution local lab

This repository installs a fully functional, local SIGHUP Distribution profile on Apple Container's experimental Kubernetes plugin.

> [!IMPORTANT]
> This is a personal proof of concept for local evaluation. It is not official SIGHUP Distribution documentation and is not a production or HA topology. Refer to the [official documentation](https://docs.sighup.io/) for supported installation guidance.

The current workflow was verified on 2026-11-10 with macOS 27.2 on Apple silicon, Container CLI and API server 1.7.1, the recommended Kata 4.3.1 guest kernel (`vmlinux-6.18.56-208-debug`), kubectl 1.34.1, Furyctl 0.36.1, SIGHUP Distribution v1.36.0, and Kubernetes v1.36.4.

## Prerequisites

- An Apple-silicon Mac with Container CLI and API server 1.7.1 installed.
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

The kernel script explicitly runs `container system kernel set --recommended --force`. Run it deliberately: `--force` replaces the selected default kernel. An application upgrade does not move the default kernel forward, so a host upgraded from an earlier Container release keeps the previous guest kernel until this command runs.

`create-cluster.sh` uses the current `container cluster` command set. It pins the node image to `docker.io/kindest/node:v1.36.4` so the cluster matches the Kubernetes 1.36 support in SIGHUP Distribution v1.36.0, and it passes `--shared-image-store` so cluster nodes read Apple's local image store directly. It writes an isolated kubeconfig under `.state/`, selects `sighup-local` in that file, and leaves the current context in `~/.kube/config` unchanged.

## What the profile installs

The profile follows the [SIGHUP Distribution on Minikube](https://docs.sighup.io/docs/getting-started/distro-on-minikube) local subset. It retains Apple Container's kindnet CNI and installs single HAProxy ingress, cert-manager, Loki logging, Prometheus monitoring, Tempo tracing, Forecastle, and local dynamic storage. Policy, disaster recovery, and authentication are disabled.

Apple Container does not create a default StorageClass, so `install-local-path-storage.sh` installs Rancher's local-path provisioner and marks it as default. Its storage is tied to the one local node.

The logging profile requires:

```text
fs.inotify.max_user_instances=8192
fs.inotify.max_user_watches=524288
```

`configure-node-sysctls.sh` persists and applies these SIGHUP-recommended limits in the node. The node default for `fs.inotify.max_user_instances` is 128 regardless of node size, which is below what Fluent Bit needs when it watches every container log. The deployment helper removes the two systemd-only host tailers, which cannot run in this node, then waits for all Deployment, DaemonSet, and StatefulSet rollouts to finish.

## Verification

After deployment, inspect the ready workloads and access Grafana through a port-forward:

```bash
kubectl get nodes
kubectl get deployment,daemonset,statefulset -A
kubectl get pvc -A
kubectl -n monitoring port-forward service/grafana 3000:3000
```

`http://127.0.0.1:3000/login` returned HTTP 200 in the verified workflow.

The optional registry-free development test builds an image locally and deploys it with `imagePullPolicy: Never`. No import step is needed because the cluster shares the local image store:

```bash
./scripts/deploy-local-demo.sh
kubectl -n local-demo port-forward service/local-demo 8080:80
```

## Layout

| Path | Purpose |
| --- | --- |
| `scripts/install-recommended-kernel.sh` | Explicitly installs the Container-recommended default kernel. |
| `scripts/create-cluster.sh` | Creates the native six-CPU, 16-GB Apple Container cluster on the pinned node image. |
| `scripts/configure-node-sysctls.sh` | Applies the inotify settings required by the SIGHUP logging collector. |
| `scripts/install-local-path-storage.sh` | Installs the local default StorageClass. |
| `scripts/install-furyctl.sh` | Downloads and checksum-verifies the macOS arm64 Furyctl release. |
| `scripts/deploy-sighup-distribution.sh` | Applies the profile, removes unsupported tailers, and waits for workloads. |
| `scripts/deploy-local-demo.sh` | Verifies the optional local-image development loop. |
| `scripts/destroy-cluster.sh` | Deletes the named cluster and its isolated kubeconfig. |
| `docs/verification-journal.md` | Current verified behavior and functional evidence. |
| `legacy/container-1.2.2-iptables-recovery/` | Historical workaround and evidence for the pre-1.0 kernel failure. |

## Command changes across Container releases

| Container | Change |
| --- | --- |
| 1.5.0 | Native cluster creation; `container k8s start` removed, so a stopped node is recreated, not restarted. |
| 1.6.0 | Multi-worker clusters; `--cni NONE` to skip CNI installation. |
| 1.6.1 | `container k8s` renamed to `container cluster`. |
| 1.7.1 | `load-image` removed in favour of `--shared-image-store` on create; `cluster list` shows one row per cluster with `--nodes` for the per-node view; container lifecycle commands no longer operate on cluster nodes; workers can be sized per group. |

Node-level inspection and tuning still work with `container exec`, because the 1.7.1 restriction covers lifecycle commands such as `start`, `stop`, and `delete`, not `exec`. `container start sighup-local` now reports `container with ID sighup-local not found`.

## Historical recovery

The original Container 1.2.2 workaround is preserved under `legacy/container-1.2.2-iptables-recovery/`. It documents the old `iptables-nft` node-preparation failure tracked in [apple/container#2120](https://github.com/apple/container/issues/2120). Do not use that manual kubeadm recovery for new installations.

## Teardown

Delete the full local cluster, its workloads, and the lab kubeconfig:

```bash
./scripts/destroy-cluster.sh
```
