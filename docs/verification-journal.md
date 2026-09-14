# Verification journal

## Scope

This journal records the current Apple Container 1.4.1 local Kubernetes and SIGHUP Distribution verification performed on 2026-09-11. It is a local development environment, not an HA or production topology.

## Host and tool baseline

| Component | Observed value |
| --- | --- |
| Host | macOS 26.6.2, arm64, 10 CPUs, 32 GB memory |
| Container CLI and API server | 1.4.1, release commit `9a8917ca2da5cd6ba059b9ba5ca5a74892e9bb7d` |
| Guest kernel | Kata 3.32.0, `vmlinux-6.18.35-197-debug`, kernel `6.18.35` |
| Kubernetes plugin | `container k8s` |
| kubectl client | v1.34.1 |
| Node image | `kindest/node:v1.35.5` pinned by Apple |
| Cluster allocation | 6 CPUs, 16 GB memory |
| Resulting Kubernetes version | v1.35.5 |
| Furyctl | v0.35.1 |
| SIGHUP Distribution | v1.35.1 |

## Native cluster creation

The previous `sighup-local` node and its isolated kubeconfig were removed before the test. The cluster was then created with no manual recovery:

```bash
container k8s create --name sighup-local --cpus 6 --memory 16g
```

The command completed in 33 seconds. The node was Ready, reported kernel `6.18.35`, and the native node-preparation path had installed both TCP MSS rules:

```text
-A FORWARD -p tcp -m tcp --tcp-flags SYN,RST SYN -j TCPMSS --set-mss 1220
-A OUTPUT -p tcp -m tcp --tcp-flags SYN,RST SYN -j TCPMSS --set-mss 1220
```

## Legacy-kernel regression and resolution

Before installing the recommended kernel, the host retained `vmlinux-6.12.28-153` from an installation predating Container 1.0. On Container 1.4.1, a separate native 2 CPU and 4 GB cluster creation failed with the issue #2120 signature:

```text
Error: node prep failed on sighup-iptables-141-repro: net.ipv4.ip_forward = 1
registry.k8s.io/pause:3.10.1
```

Running `container system kernel set --recommended --force` installed the recommended Kata 3.32.0 kernel. A repeated native cluster creation succeeded. The root cause and upgrade-path result were reported in [apple/container#2120](https://github.com/apple/container/issues/2120#issuecomment-5634405404).

The legacy workaround is retained in `legacy/container-1.2.2-iptables-recovery/` for historical evidence only.

## SIGHUP Distribution result

The test applied `furyctl/sighup-local.yaml` after installing Rancher's local-path provisioner and setting:

```text
fs.inotify.max_user_instances = 8192
fs.inotify.max_user_watches = 524288
```

Furyctl reported `SIGHUP Distribution installed successfully`. The wrapper removed the unsupported `systemd-common-host-tailer` and `systemd-etcd-host-tailer` DaemonSets. All remaining Deployment, DaemonSet, and StatefulSet workloads were ready. The resulting namespaces included cert-manager, forecastle, ingress-haproxy, logging, monitoring, and tracing.

All SIGHUP PVCs were Bound through the `local-path` StorageClass. This included the 150 GiB Prometheus volume, Loki and Tempo object-store volumes, and Fluentd buffers.

Grafana returned HTTP 200 through:

```bash
kubectl -n monitoring port-forward service/grafana 3000:3000
curl --fail http://127.0.0.1:3000/login
```

## Local image workflow

The optional demo image was built locally, loaded into the node's CRI store as `docker.io/library/apple-container-local-demo:0.1.0`, and deployed with `imagePullPolicy: Never`. Its ClusterIP service returned HTTP 200 through a local port-forward.

## Limits

- The Apple Kubernetes plugin remains experimental and creates one node.
- The local-path StorageClass is node-local and not a production storage design.
- The SIGHUP profile disables policy, disaster recovery, and authentication modules to match the local tutorial subset.
- Access ClusterIP services from macOS through `kubectl port-forward`.
