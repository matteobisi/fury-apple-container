---
title: SIGHUP Distribution on Apple Container
sidebar_position: 1
---

# SIGHUP Distribution on Apple Container

Apple Container 1.2.0 introduced an experimental `container k8s` plugin for a local, single-node Kubernetes cluster. This guide installs the SIGHUP Distribution local profile over that cluster on an Apple-silicon Mac.

The workflow was verified with Container 1.2.2, Kubernetes v1.35.5, SIGHUP Distribution v1.35.1, and Furyctl v0.35.1. It is for local evaluation only. It is not an HA or production deployment.

## What the profile installs

The profile follows the [SIGHUP Distribution on Minikube](https://docs.sighup.io/docs/getting-started/distro-on-minikube) tutorial, replacing Minikube with Apple Container's kubeadm-based cluster. It keeps the existing kindnet CNI and deploys single HAProxy ingress, cert-manager, Loki logging, Prometheus monitoring, Tempo tracing, and Forecastle. Policy, disaster recovery, and authentication are disabled.

Apple Container currently creates one control-plane node. Allocate the six CPUs and 16 GB of memory used by the SIGHUP local tutorial. The full SIGHUP production topology has materially different HA, node, and storage requirements.

## Prerequisites

- macOS on Apple silicon
- Apple Container 1.2.2, with `container system status` reporting `running`
- kubectl
- Internet access to pull Container, Kubernetes, SIGHUP, and Helm artifacts

Obtain the lab artifacts repository and work from its root:

```bash
cd fury-apple-container
```

## Create the Apple Container cluster

```bash
./scripts/bootstrap-cluster.sh
export KUBECONFIG="$PWD/.state/sighup-local.kubeconfig"
kubectl get nodes
```

The expected result is one Ready `sighup-local` control-plane node on Kubernetes v1.35.5.

The helper retains an isolated kubeconfig rather than changing the context in `~/.kube/config`.

### Fluent Bit inotify tuning

SIGHUP's logging collector watches the node's container log files. Apple Container's node default for `fs.inotify.max_user_instances` is 128, which was exhausted while Fluent Bit initialized and appeared as `Too many open files`.

The bootstrap helper applies the SIGHUP on-premises tuning:

```text
fs.inotify.max_user_instances=8192
fs.inotify.max_user_watches=524288
```

To apply it again after manually changing or restarting the node:

```bash
./scripts/configure-node-sysctls.sh
kubectl -n logging rollout restart daemonset/infra-fluentbit
kubectl -n logging rollout status daemonset/infra-fluentbit
```

### Container 1.2.2 bootstrap recovery

On the tested host, Apple Container 1.2.2 created the node but stopped during preparation because it invoked `iptables-nft` in a `kindest/node` image configured for legacy iptables. This is tracked in [apple/container#2120](https://github.com/apple/container/issues/2120). The helper detects only that specific `node prep failed` condition, installs the equivalent legacy TCP MSS rules, runs kubeadm, applies Apple's pinned kindnet manifest, and waits for readiness.

If cluster creation fails for another reason, the helper exits and leaves the error visible. Do not treat the recovery path as a general workaround. Once a future Apple Container release resolves #2120 and that release has been verified here, the native `container k8s create` command will be sufficient to create the cluster and this recovery should be removed.

## Install local dynamic storage

Apple's kubeadm bootstrap does not install a default StorageClass. SIGHUP Distribution validates that one exists, so install Rancher's local-path provisioner:

```bash
./scripts/install-local-path-storage.sh
kubectl get storageclass
```

The expected result includes `local-path (default)`. Its storage is local to the single node and is appropriate only for this lab.

## Install Furyctl and apply SIGHUP Distribution

The helper downloads the Furyctl 0.35.1 macOS arm64 archive and verifies its published SHA-256 checksum before extracting it under `.tools/`.

```bash
./scripts/install-furyctl.sh
export FURYCTL_BIN="$PWD/.tools/furyctl/furyctl"
./scripts/deploy-sighup-distribution.sh
```

`furyctl/sighup-local.yaml` is a `KFDDistribution` configuration. It uses the kubeconfig from `KUBECONFIG`, which means Furyctl installs the distribution over the existing Apple Container cluster rather than creating Kubernetes nodes itself.

Verify the primary components:

```bash
kubectl get namespaces
kubectl get pods -A
kubectl -n monitoring port-forward service/grafana 3000:3000
```

Open `http://127.0.0.1:3000/login` while the port-forward process is running.

## Verified result

Furyctl completed successfully and the tested cluster scheduled the SIGHUP namespaces, HAProxy ingress, Grafana, Prometheus, Loki, Tempo, MinIO, Forecastle, and Fluent Bit. Grafana returned HTTP 200 through the local port-forward.

The inotify tuning is a local Apple Container node configuration, not a SIGHUP Distribution production recommendation. The installation is a useful, fully running integration experiment, but it remains a single-node, experimental local environment rather than a production topology.

## Teardown

Delete the full local cluster and its workloads:

```bash
./scripts/destroy-cluster.sh
```

The helper deletes only the named Apple Container cluster. Remove `.state/` manually if the isolated kubeconfig is no longer needed.
