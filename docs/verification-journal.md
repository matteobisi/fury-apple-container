# Verification journal

## Scope

This journal records an Apple Container 1.2.2 local Kubernetes experiment on an Apple-silicon Mac. It is a development environment, not an HA or production SIGHUP Distribution topology.

## Host and tool baseline

| Component | Observed value |
| --- | --- |
| Host | macOS 26.6.1, arm64, 10 CPUs, 32 GB memory |
| Container CLI and API server | 1.2.2, release commit `0190097` |
| Kubernetes plugin | `container k8s`, installed under `/usr/local/libexec/container/plugins/k8s` |
| kubectl client | v1.34.1 |
| Node image | `kindest/node:v1.35.5` pinned by Apple |
| Cluster allocation | 6 CPUs, 16 GB memory |
| Resulting Kubernetes version | v1.35.5 |

Apple introduced the experimental Kubernetes plugin in Container 1.2.0. It creates a single control-plane node from `kindest/node`, initializes it with kubeadm, applies kindnet, removes the control-plane taint, publishes the API server, and writes a kubeconfig.

Sources:

- [Apple Container k8s feature request](https://github.com/apple/container/issues/2043)
- [Apple Container 1.2.0 release](https://github.com/apple/container/releases/tag/1.2.0)
- [Apple Container 1.2.2 release](https://github.com/apple/container/releases/tag/1.2.2)

## Observed 1.2.2 bootstrap issue and recovery

On this host, `container k8s create --name sighup-local --cpus 6 --memory 16g` created and started the node but stopped during its node-preparation stage. The error was:

```text
Error: node prep failed on sighup-local: net.ipv4.ip_forward = 1
registry.k8s.io/pause:3.10.1
```

The node image had selected legacy iptables:

```text
/usr/sbin/iptables -> /usr/sbin/xtables-legacy-multi
```

Apple's plugin preparation script nevertheless invoked `/usr/sbin/iptables-nft` to add TCP MSS rules. That command exited with:

```text
iptables v1.8.11 (nf_tables): Could not fetch rule set generation id: Invalid argument
```

The same rules succeeded through `/usr/sbin/iptables-legacy`. `scripts/bootstrap-cluster.sh` only uses its manual kubeadm recovery when the plugin reports `node prep failed` and the `iptables-nft` probe fails. It then writes an isolated kubeconfig under `.state/`, applies the exact kindnet manifest from Apple Container 1.2.2, and waits for the node to become ready.

The recovery was verified with:

```text
NAME           STATUS   ROLES           VERSION
sighup-local   Ready    control-plane   v1.35.5
```

## Local image workflow

Apple's `container k8s load-image` saves an image from the local Container image store and imports it into the node's `containerd` `k8s.io` namespace. `scripts/deploy-local-demo.sh` builds `docker.io/library/apple-container-local-demo:0.1.0`, imports it, then deploys a workload with `imagePullPolicy: Never`. This tests the no-registry development loop.

In this test, containerd's CRI image store exposed the imported image as `docker.io/library/apple-container-local-demo:0.1.0`; kubelet rejected the equivalent bare reference with `ErrImageNeverPull`. The demo therefore uses the canonical qualified reference.

## SIGHUP Distribution prerequisites

SIGHUP's local Minikube tutorial uses a single node with six CPUs and 16 GB memory and installs a subset of the distribution with the `KFDDistribution` provider. Apple Container's cluster has no default StorageClass after kubeadm and kindnet bootstrap, whereas Minikube includes one. `scripts/install-local-path-storage.sh` installs Rancher's local-path provisioner and marks `local-path` as default before applying the SIGHUP profile.

The profile in `furyctl/sighup-local.yaml` follows the documented local subset: existing CNI, single HAProxy ingress, Loki logging, Prometheus monitoring, and no policy, disaster-recovery, or auth modules. It retains the upstream Minikube compatibility patches for systemd tailers and the control-plane certificate exporter.

## SIGHUP Distribution result

`furyctl` v0.35.1 successfully applied SIGHUP Distribution v1.35.1 to the v1.35.5 Apple Container cluster. The resulting namespaces included cert-manager, forecastle, ingress-haproxy, logging, monitoring, and tracing. The HAProxy ingress controller, Grafana, Prometheus, Loki, Tempo, MinIO, and the local demo workload were scheduled; Grafana returned HTTP 200 through:

```bash
kubectl -n monitoring port-forward service/grafana 3000:3000
```

The first apply exposed a Fluent Bit failure:

```text
[error] [/src/fluent-bit/plugins/in_tail/tail_fs_inotify.c:365 errno=24] Too many open files
```

The generic Kubernetes container nofile soft and hard limits were both `1073741816`, so process file-descriptor rlimits were not the cause. The Apple Container node instead had the default `fs.inotify.max_user_instances=128` and 65 active inotify instances before Fluent Bit began watching the complete set of container logs. SIGHUP's on-premises configuration guidance uses `fs.inotify.max_user_instances=8192` and `fs.inotify.max_user_watches=524288`.

Applying those two sysctls and restarting only `logging/infra-fluentbit` made the DaemonSet ready with zero restarts. `scripts/configure-node-sysctls.sh` applies the tuning, and `bootstrap-cluster.sh` invokes it for every bootstrap. `patches/apple-container-inotify-sysctls.patch` is a focused proposal to add the same tuning to Apple Container's node preparation. The patch is suitable for upstream discussion; the local helper is the supported lab workaround until it is accepted.

## Limits

- The Apple plugin is experimental, currently single-node, and lacks service load balancing.
- Access development services with `kubectl port-forward`; do not assume a NodePort or LoadBalancer is reachable on the macOS host.
- `container k8s write-config --kubeconfig` does not select a `current-context`. The bootstrap helper explicitly selects the named context in its isolated kubeconfig.
- The `container copy` command reported a destination but did not place a host file into this node during this test. The bootstrap helper retrieves Apple's pinned CNI manifest from the public 1.2.2 tag instead.
- The SIGHUP profile is for feature exploration. It does not meet the documented production requirements for HA nodes, storage capacity, or ingress exposure.
