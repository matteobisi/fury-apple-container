# Container 1.2.2 iptables recovery

This directory preserves the original Apple Container 1.2.2 experiment and must not be used for a current installation.

On hosts carrying the legacy `vmlinux-6.12.28-153` guest kernel, the Kubernetes plugin invoked `iptables-nft` during node preparation and failed with `Could not fetch rule set generation id: Invalid argument`. The historical `bootstrap-cluster.sh` detects only that condition, applies the two TCP MSS rules through `iptables-legacy`, and manually completes kubeadm bootstrap.

The issue is documented in [apple/container#2120](https://github.com/apple/container/issues/2120). Container 1.4.1 can create the cluster natively when it uses the recommended Kata 3.32.0 kernel. Use the repository root workflow, beginning with `scripts/install-recommended-kernel.sh`, for all new labs.

The original verification journal and the upstream inotify-sysctl patch proposal are retained here for traceability.
