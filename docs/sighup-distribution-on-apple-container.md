---
title: SIGHUP Distribution on Apple Container
sidebar_position: 1
---

# SIGHUP Distribution on Apple Container 1.4.1

This guide installs the SIGHUP Distribution local profile on a native Apple Container Kubernetes cluster. It was verified on 2026-09-11 with Container 1.4.1, the recommended Kata 3.32.0 guest kernel, Kubernetes v1.35.5, and Furyctl v0.35.1.

It is a local evaluation environment, not a production or HA deployment. Apple Container's Kubernetes plugin is experimental and creates one node.

## Prerequisites

- macOS on Apple silicon
- Apple Container CLI and API server 1.4.1
- `kubectl` and `curl`
- Six available CPUs and 16 GB of memory
- Internet access for the kernel, node image, Furyctl, SIGHUP artifacts, and Helm charts

## Prepare the guest kernel

Run this command deliberately before creating a new cluster:

```bash
./scripts/install-recommended-kernel.sh
```

It executes `container system kernel set --recommended --force`. The force option replaces the selected default kernel, which is required to replace a legacy pre-1.0 kernel retained during a Container upgrade. Do not run it when a deliberately selected custom default kernel must be preserved.

## Create the native cluster

```bash
./scripts/create-cluster.sh
export KUBECONFIG="$PWD/.state/sighup-local.kubeconfig"
kubectl get nodes
```

The script creates `sighup-local` with six CPUs and 16 GB of memory through `container k8s create`. It does not use manual kubeadm bootstrap, CNI installation, or iptables rule recovery. It also writes and selects an isolated lab kubeconfig under `.state/`.

## Configure storage and logging limits

Apple Container does not provide a default StorageClass. Install the single-node local-path provisioner:

```bash
./scripts/install-local-path-storage.sh
kubectl get storageclass
```

SIGHUP's Fluent Bit deployment also needs the following node limits:

```bash
./scripts/configure-node-sysctls.sh
```

The helper persists and applies `fs.inotify.max_user_instances=8192` and `fs.inotify.max_user_watches=524288`.

## Apply SIGHUP Distribution

```bash
./scripts/install-furyctl.sh
export FURYCTL_BIN="$PWD/.tools/furyctl/furyctl"
./scripts/deploy-sighup-distribution.sh
```

The local `KFDDistribution` profile retains the existing kindnet CNI and installs HAProxy ingress, cert-manager, Loki, Prometheus, Tempo, Forecastle, and local storage. Policy, disaster recovery, and authentication are disabled. The deployment helper removes two systemd-only host tailers unsupported by the Apple Container node and waits for the remaining workloads to become ready.

## Verify the environment

```bash
kubectl get deployment,daemonset,statefulset -A
kubectl get pvc -A
kubectl -n monitoring port-forward service/grafana 3000:3000
```

In the verified run, all distribution workloads were ready, all distribution PVCs were bound through `local-path`, and `http://127.0.0.1:3000/login` returned HTTP 200.

## Historical recovery

The Container 1.2.2 `iptables-nft` recovery is archived under `legacy/container-1.2.2-iptables-recovery/`. It records the old-kernel behavior reported in [apple/container#2120](https://github.com/apple/container/issues/2120). Do not use it for a current installation.
