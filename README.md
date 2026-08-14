# Apple Container and SIGHUP Distribution local lab

This directory contains the reproducible material behind the Apple Container Kubernetes walkthrough and the SIGHUP Distribution local-lab experiment.

> [!IMPORTANT]
> This repository is a personal proof of concept created while testing the newest Apple Container Kubernetes plugin. It is not official SIGHUP Distribution documentation. For installation guidance, supported configurations, and all SIGHUP Distribution needs, refer to the [official documentation](https://docs.sighup.io/).

The lab was verified on 2026-08-13 with macOS 26.6.1 on Apple silicon, Container CLI 1.2.2, Container API server 1.2.2, kubectl 1.34.1, and a Kubernetes v1.35.5 node created from Apple Container's pinned `kindest/node` image.

## Prerequisites

- An Apple-silicon Mac with Container CLI and API server 1.2.2 installed.
- `kubectl`, `jq`, and `curl` available on `PATH`.
- At least six CPUs and 16 GB of memory available for the cluster.

## Layout

| Path | Purpose |
| --- | --- |
| `scripts/bootstrap-cluster.sh` | Creates and configures a six-CPU, 16-GB Apple Container Kubernetes cluster. |
| `scripts/configure-node-sysctls.sh` | Applies the inotify settings required by the SIGHUP logging collector. |
| `scripts/install-local-path-storage.sh` | Installs a default dynamic StorageClass required by the SIGHUP local profile. |
| `scripts/deploy-local-demo.sh` | Builds a local image, imports it into the cluster, and deploys it without a registry. |
| `scripts/install-furyctl.sh` | Downloads and verifies the macOS arm64 Furyctl release used by the local profile. |
| `scripts/deploy-sighup-distribution.sh` | Applies the profile and removes systemd-only logging tailers unsupported by the node. |
| `scripts/destroy-cluster.sh` | Deletes the named Apple Container cluster. |
| `manifests/` | The registry-free demo workload. |
| `furyctl/` | SIGHUP Distribution profile and deployment wrapper. |
| `docs/verification-journal.md` | Commands, observed behavior, constraints, and results. |

## Quick start: cluster and local demo

```bash
git clone https://github.com/matteobisi/fury-apple-container.git
cd fury-apple-container
container system start
./scripts/bootstrap-cluster.sh
export KUBECONFIG="$PWD/.state/sighup-local.kubeconfig"
./scripts/install-local-path-storage.sh
./scripts/deploy-local-demo.sh
kubectl -n local-demo port-forward service/local-demo 8080:80
```

In another terminal, open `http://127.0.0.1:8080`.

> [!IMPORTANT]
> The lab keeps its kubeconfig at `.state/sighup-local.kubeconfig` and does not change `~/.kube/config`. Before running any `kubectl` command in a new shell, work from the repository root and set:
>
> ```bash
> cd fury-apple-container
> export KUBECONFIG="$PWD/.state/sighup-local.kubeconfig"
> ```

The Apple `k8s` plugin is experimental. Read the verification journal before relying on this lab: Container 1.2.2 has a reproducible `iptables-nft` bootstrap failure on this host, tracked in [apple/container#2120](https://github.com/apple/container/issues/2120). The bootstrap script contains a narrow, temporary recovery path for that condition, applies the required inotify tuning, and otherwise exits on failures. Once Apple resolves the issue in a release verified by this lab, the native `container k8s create` command will create the cluster without the recovery path.

## SIGHUP Distribution profile

Continue from the repository root after completing the cluster setup:

```bash
export KUBECONFIG="$PWD/.state/sighup-local.kubeconfig"
./scripts/install-furyctl.sh
export FURYCTL_BIN="$PWD/.tools/furyctl/furyctl"
./scripts/deploy-sighup-distribution.sh
```

The profile is intentionally a local demonstration, not a production topology. It installs the distribution over the existing single-node cluster through the `KFDDistribution` provider. On the verified Container 1.2.2 lab, Furyctl finished successfully and all deployed workloads, including Fluent Bit, became ready after the documented inotify tuning. The verification journal records the tested control plane, DNS, local-image, storage, logging, and Grafana access paths, along with the current restart limitation of the manual recovery.
