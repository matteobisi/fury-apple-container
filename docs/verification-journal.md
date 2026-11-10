# Verification journal

## Scope

This journal records the current Apple Container 1.7.1 local Kubernetes and SIGHUP Distribution verification performed on 2026-11-10. It is a local development environment, not an HA or production topology.

## Host and tool baseline

| Component | Observed value |
| --- | --- |
| Host | macOS 27.2, arm64, 10 CPUs, 32 GB memory |
| Container CLI and API server | 1.7.1, release commit `a15b460` |
| Guest kernel | Kata 4.3.1, `vmlinux-6.18.56-208-debug`, kernel `6.18.56` |
| Kubernetes command set | `container cluster` |
| kubectl client | v1.34.1 |
| Node image | `docker.io/kindest/node:v1.36.4`, pinned explicitly |
| Cluster allocation | 6 CPUs, 16 GB memory |
| Resulting Kubernetes version | v1.36.4, containerd 2.3.4 |
| Furyctl | v0.36.1 |
| SIGHUP Distribution | v1.36.0 |

## Kernel retention across the 1.5.0 to 1.7.1 upgrade

The host had been set to the Container 1.5.0 recommended kernel. Before any change for this verification, the effective default was still the old one:

```text
$ readlink "$HOME/Library/Application Support/com.apple.container/kernels/default.kernel-arm64"
.../kernels/vmlinux-6.18.35-197-debug
```

The `kernels/` directory held `vmlinux-6.12.28-153` and `vmlinux-6.18.35-197-debug` only. The 1.7.1 recommended kernel, Kata 4.3.1 `vmlinux-6.18.56-208-debug`, was not on disk, and a node created in that state reported `6.18.35`.

The explicit remediation moved the default forward:

```bash
container system kernel set --recommended --force
```

The command downloaded Kata 4.3.1 and created `vmlinux-6.18.56-208-debug` plus a new `default.kernel-arm64` symlink. A node created afterwards reported `6.18.56`.

This is the same upgrade behaviour documented for Container 1.5.0: an application upgrade does not move the selected guest kernel forward. The remediation is unchanged; only the recommended kernel version moved.

## Native cluster creation

The pre-existing `sighup-local` node from the Container 1.5.0 lab appeared in `container list` but not in `container cluster list`, so it was removed with `container delete`. The cluster was then created with a pinned node image, the shared image store, and no manual recovery:

```bash
container cluster create \
  --name sighup-local \
  --cpus 6 \
  --memory 16g \
  --node-image docker.io/kindest/node:v1.36.4 \
  --shared-image-store
```

The command completed in 40 seconds and wrote the kubeconfig to `~/.kube/config`. The node reported Kubernetes v1.36.4, kernel `6.18.56`, and containerd 2.3.4.

`container cluster ls` returned one row for the cluster. `container cluster ls --nodes` returned the per-node view with the dual `control-plane,worker` role:

```text
CLUSTER       NODE          ROLE                  STATE    CPUS  MEMORY  ADDR          PORTS
sighup-local  sighup-local  control-plane,worker  running  6     16 GB   192.168.64.5  6445->6443
```

### Stale kubeconfig

The `.state/sighup-local.kubeconfig` left by the Container 1.5.0 lab still pointed at the deleted cluster's certificate authority, so `kubectl` failed with `x509: certificate signed by unknown authority`. Rewriting it resolved the problem:

```bash
container cluster write-config --name sighup-local --kubeconfig "$PWD/.state/sighup-local.kubeconfig"
kubectl config use-context sighup-local
```

### Lifecycle commands on cluster nodes

Cluster nodes are excluded from container lifecycle commands as of 1.7.1:

```text
$ container start sighup-local
Error: container with ID sighup-local not found
```

Node-level `container exec` still works, which the sysctl helper depends on.

### Multi-worker clusters

A two-node cluster was created to verify worker support and per-group sizing:

```bash
container cluster create --name workers-test --cpus 2 --memory 4g --workers count=1,cpus=2,memory=4g
```

Both nodes reached the running state, the worker received its own address, and the cluster listing reported two nodes. The test cluster was deleted afterwards.

## SIGHUP Distribution result

The test applied `furyctl/sighup-local.yaml` with Furyctl 0.36.1 after installing Rancher's local-path provisioner v0.0.37 and setting:

```text
fs.inotify.max_user_instances = 8192
fs.inotify.max_user_watches = 524288
```

The node default before tuning was `fs.inotify.max_user_instances = 128` and `fs.inotify.max_user_watches = 130278`. The watches value scales with node memory, but the instances limit does not, so the tuning remains necessary.

Furyctl reported `SIGHUP Distribution installed successfully`. The wrapper removed the unsupported `systemd-common-host-tailer` and `systemd-etcd-host-tailer` DaemonSets. All 58 pods across the cert-manager, forecastle, ingress-haproxy, local-path-storage, logging, monitoring, and tracing namespaces were running with no restarts.

All 16 SIGHUP PVCs were Bound through the default `local-path` StorageClass, including the Prometheus database volume, the Loki and Tempo object-store volumes, and the Fluentd buffers.

## Access and local image checks

| Check | Command | Result |
| --- | --- | --- |
| Grafana | `kubectl -n monitoring port-forward service/grafana 3000:3000` | `http://127.0.0.1:3000/login` returned HTTP 200 |
| Forecastle | `kubectl -n forecastle port-forward service/forecastle 18081:80` | `http://127.0.0.1:18081/` returned HTTP 200 |
| Local image | `./scripts/deploy-local-demo.sh` | Pod Ready, `imagePullPolicy: Never`, no registry access |
| Local service | `kubectl -n local-demo port-forward service/local-demo 18080:80` | Returned HTTP 200 with the expected page |

The shared image store removed the import step that earlier releases required. A locally built image is usable from a cluster node as soon as it exists in Apple's image store. The fully qualified name requirement also disappeared: a bare `shortname-demo:dev` reference with `imagePullPolicy: IfNotPresent` started successfully, where earlier releases rejected the equivalent bare name with `ErrImageNeverPull`.

## Limits

- The Apple Kubernetes plugin remains experimental.
- The local-path StorageClass is node-local and not a production storage design.
- The SIGHUP profile disables policy, disaster recovery, and authentication modules to match the local tutorial subset.
- Access ClusterIP services from macOS through `kubectl port-forward`; the plugin still publishes only the API endpoint.
- A stopped cluster cannot be restarted in place. There is no `container cluster start`.
- The kubectl client on the test host is v1.34.1 against a v1.36.4 server, which exceeds the supported version skew. Upgrade the client before relying on version-sensitive output.
