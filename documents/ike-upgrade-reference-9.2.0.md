
## Topics

- [Overview](#overview)
- [Prerequisites](#prerequisites)
- [InfoScale Operator Upgrade](#infoscale-operator-upgrade)
- [InfoScale Cluster Version Upgrade (Software Upgrade)](#infoscale-cluster-version-upgrade-software-upgrade)
- [Combined Upgrade](#combined-upgrade)
- [Platform or OpenShift Upgrade](#platform-or-openshift-upgrade)
- [Troubleshooting](#troubleshooting)
- [Limitations](#limitations)

---

## Overview

> **Note:** Prior to upgrading InfoScale to version 9.2.0, ensure that the license secret has been created. Refer to the official *InfoScale for Kubernetes 9.2.0 Administrator's Guide* for steps.

Users can upgrade InfoScale cluster in two steps:

1. Upgrade the InfoScale Operator.
2. Upgrade the InfoScale cluster version (change the CR version).

InfoScale upgrade workflows can change with additional preparatory steps based on the source version and known issues. These workflows allow IKE to ensure upgrades without downtime for applications and virtual machines in OpenShift and OpenShift Virtualization (OCP-V) platforms.

> **Note:** Complete steps 1 and 2 before upgrading OpenShift, unless a combined upgrade is supported.

Update the CR version to match the target InfoScale release to begin the cluster upgrade.

---

## Prerequisites

- Maintain a stable and responsive platform by avoiding API server saturation, excessive thrashing, or high node resource pressure.
- Ensure enough resources are available for VM migration if you are using OpenShift Virtualization.
- Clear all errors or pending remediations flagged by the Pre-flight CLI found in `infoscale-tools-v9.2.0.tar`.

> **Note:** Verify the InfoScale support matrix before you choose your OpenShift cluster upgrade version.

Run preflight in non-interactive mode before starting the upgrade:

```bash
./preflight-cli.sh --type upgrade --target-ike <infoscale_version> --target-ocp <ocp_version> --all

# Example:
./preflight-cli.sh --type upgrade --target-ike 9.2.0 --target-ocp 4.20.22 --all
```

For installation instructions, full command reference, example output, and guidance on interpreting results, see [Preflight guide for InfoScale upgrade and fresh install](preflight-guide.md).

Additional prerequisites:

- Complete all pending rollouts and ensure all configurations are in sync.
- Resolve any existing split-brain issues in the InfoScale cluster before starting the upgrade.

> **Note:** The split-brain check is applicable only when data disk fencing is configured.

Before an OCP upgrade is executed on an OCP-V VIKE cluster, verify SCSI keys inside SDS pods:

```bash
oc exec -it infoscale-sds-21432-xxxx-xxxx -n infoscale-vtas -- bash
vxfenadm -s /dev/vx/rdmp/<dmpnodename>
```

The number of keys should match: `number of nodes × number of paths per disk`.

- Disable hard eviction settings in the kubeletconfig if system memory reservations are exceeded.

---

## InfoScale Operator Upgrade

1. Log in to the OpenShift console and navigate to the correct page:
   - **For versions below 4.20:** Go to **Operators > Installed Operators**.
   - **For versions 4.20 and above:** Go to **Ecosystem > Software Catalog**.

2. Verify that all InfoScale operators are listed on this page.

3. Click the **InfoScale SDS Operator** and select the **Subscription** tab.

4. Click **Update channel**, select **fast**, and click **Save**.

5. For the InfoScale operators, **Upgrade Available** is reported in **Status**.

6. To upgrade InfoScale, click **InfoScale SDS Operator** or **InfoScale Licensing Operator**.

7. In **Subscription**, updates that need approval are displayed next to **Upgrade Status**.

8. Review the details list. Click **Approve** to proceed with the upgrade.

> **Note:** The operator upgrade may require multiple steps (hops) depending on your current version. For example, an upgrade from version 8.0.400 must follow this path: `8.0.410 > 9.1.0 > 9.1.2`. Upgrading from 9.1.0 to 9.1.2 only requires one hop.

9. Wait until the upgrade is complete and the operator is listed in **Operators > Installed Operators**.

---

## InfoScale Cluster Version Upgrade (Software Upgrade)

To upgrade the InfoScale cluster version:

1. Verify that the kubelet configuration is applied and the rollout is complete before starting the software upgrade. Refer to the [Enabling kubelet inhibitor with systemd](#kubelet-inhibitor) section.
   - If the recommended 9.x kubelet configuration was missed during deployment, apply it before upgrading the software.

2. Apply the additional required patch if you are upgrading InfoScale from 8.x to 9.1.2.

3. Change the InfoScale cluster version to the latest version in the Custom Resource (CR).

4. Wait for step 3 to complete and then trigger the platform or OpenShift upgrade, if applicable.

### Upgrading InfoScale

> **Note:** Kubelet inhibitor configuration is a prerequisite for all VIKE releases. Ensure it is enabled before starting the software upgrade. Refer to the *Prerequisites* section of the *InfoScale for Kubernetes 9.2.0 Administrator's Guide* for steps to enable kubelet inhibitors.

#### Check if kubelet inhibitors are already applied

```bash
oc get kubeletconfigs.machineconfiguration.openshift.io -oyaml | grep -i grace
# Expected output:
#   shutdownGracePeriod: 15m
#   shutdownGracePeriodCriticalPods: 5m
```

Verify on a worker node:

```bash
ssh core@ocp-w-02.lab.ocp.lan sudo systemd-inhibit
# Expected: A kubelet entry with WHAT=shutdown and MODE=delay
```

#### Patch InfoScale cluster version to 9.2.0

```bash
oc patch infoscalecluster <cluster-name> -n <namespace> \
  --type=merge -p '{"spec":{"version":"9.2.0"}}'
```

Monitor the upgrade progress:

```bash
oc get infoscaleclusters -A
# States will cycle: Upgrading → Degraded → Healthy → Running
```

#### VM Migration Retries

During a software upgrade in environments with OCP-V workloads:

- The system automatically retries failed migrations.
- A maximum of **five total attempts** is recommended (initial attempt plus four retries).
- Setting the retry count beyond five is not recommended, as it can interfere with the OCPV controller's garbage collection process.
- If the maximum retry count is exhausted, the upgrade process pauses and the user must perform the migration manually or delete the failed migration resources.

#### Upgrade Sanity Monitoring

The upgrade sanity monitoring process serves as a protective guard during software upgrades:

- Before an older SDS pod is deleted, the system checks for any open volume references.
- The system creates intermediate "upgrade sanity" pods to perform these checks.
- In successful cases where no open volume references are detected, these pods are automatically deleted.
- If an open volume reference is found, **the upgrade is completely paused**.
- When a pause occurs, the user must identify the pod holding the volume and either delete or move that pod to allow the upgrade to resume automatically.

---

## Combined Upgrade

Combined upgrade allows users to merge a software upgrade with a platform upgrade (such as an OCP upgrade) into a **single rollout**. This is highly recommended because it minimizes worker node reboots by requiring only one rollout instead of two.

**Prerequisites:**
- Standard pre-flight requirements for any upgrade must be met.
- Only use combined upgrade if the target release matrix supports both the new InfoScale stack and the new platform's kernel version; if the target kernel is not supported, perform a software upgrade first.

### Steps to Perform a Combined Upgrade

**Step 1:** Upgrade the operator to the latest version before initiating any software or platform changes.

**Step 2:** Patch the InfoScale cluster with the `combine-upgrade` annotation:

```bash
oc patch infoscalecluster sanity-ocp416 -n infoscale-vtas \
  --type=merge -p \
  '{"metadata":{"annotations":{"infoscale.veritas.com/combine-upgrade":"enabled"}},"spec":{"version":"9.2.0"}}'
```

Monitor status:

```bash
oc get infoscaleclusters -A
# Transitions: Upgrading → OS-Upgrade-Pending
```

**Step 3:** Verify that the cluster state transitions to `OS-Upgrade-Pending`.

**Step 4:** Initiate the upgrade of all common resources (fencing and CSI) under the `infoscaleclusterset` controller. Wait until the process reaches the `OS-Upgrade-Pending` stage, then trigger the platform or OCP upgrade once you verify that **all CSI nodes have been updated**.

```bash
# Verify CSI nodes are up to date
oc get ds -n infoscale-vtas
# UP-TO-DATE count should match the number of InfoScale nodes
```

**Step 5:** Monitor the intermediate state as the SDS shifts from the old DaemonSet to the new one.

**Step 6:** Verify the final cluster state to ensure the old DaemonSet has been cleaned up and the cluster status is **Healthy**.

---

## Platform or OpenShift Upgrade

Refer to the supported platforms section for more information.

### Unsupported OCP Versions

IKE is **not supported** on the following OpenShift versions (all channels):

| OCP Version | Restriction  |
|-------------|--------------|
| 4.20.4      | All channels |
| 4.19.19     | All channels |
| 4.18.29     | All channels |

> **Note:** During an OpenShift upgrade, both the master and worker pools usually roll out at the same time. This can cause issues if your master nodes are schedulable. IKE recommends that you **do not have schedulable master nodes**. Upgrade the master pool first and wait for it to finish before starting the worker pool upgrade.

You can optionally re-run the pre-flight script to check the health of your InfoScale cluster before proceeding with the OpenShift platform upgrade.

During the upgrade, when the Machine Config Operator updates, the InfoScale cluster will show an `OS-Upgrade` status:

```bash
oc get infoscalecluster -A
# State: OS-Upgrade → Running (after OCP upgrade completes)
```

After the OpenShift upgrade finishes, make sure the InfoScale cluster shows a **Running** status before starting any other tasks.

---

## Troubleshooting

### Paused Upgrade Due to Affined and Unmanaged Workloads

If a workload is not managed by a standard Kubernetes controller, the InfoScale operator will pause the upgrade:

```
Warning UpdatePaused 23m (x89 over 41m) InfoScaleCluster
  ErrorCode=10050 ErrorMsg=Resource is not managed by controller :
  pod test/redis not managed statefulset, replicaset, daemonset on <hostname>
```

**Resolution:**
- Back up and delete resources that can be safely removed.
- Annotate the InfoScaleCluster to force the upgrade:

```bash
oc annotate infoscaleclusters infoscalecluster-dev \
  infoscale.veritas.com/forceMigrate=true
```

After the upgrade finishes, remove the annotation from the InfoScaleCluster resource.

---

### NFD Crash in OCP Upgrades from 4.19 to 4.20

If the OCP upgrade is blocked because NFD garbage collector pods are crashing with readiness failures:

**Resolution:** Delete the crashing NFD garbage collector pod. The upgrade continues automatically. The NFD is interacting with the OCP cluster operator and blocking the upgrade.

---

### Upgrades Stalled: Operators Not Progressing After Install Plan Approval

Since the InfoScale and License operators share the same operator group, they can sometimes cause inconsistencies. Typically, both operators create two separate Install Plans, but only one lists both components as "owners."

**Resolution:** When you approve the Install Plan, choose the one that shows **both** operator subscriptions in the preview section.

---

### Transient Node Drain Failures in OCP-V Upgrades

You may see the following harmless error messages while upgrading the OCP-V platform:

```
error when evicting pods/"virt-launcher-<VMNAME>" -n "<NAMESPACE>" (will retry after 5s)
```

These messages can be safely ignored. Pod disruption budgets allow more time for Virtual Machine resources to migrate during the upgrade.

---

### Resource Busy or Node Busy Error During InfoScale Upgrade

An upgrade from 8.x to 9.x can get stuck with a "Resource Busy" error if there are stale or incorrect snapshot records and tags inside the InfoScale SDS pods.

**Resolution:** Use the stale snapshot cleanup script from `infoscale-tools-v9.1.2.tar`:

```bash
# Usage:
./snapshot_cleanup.sh -n <namespace> -p <pod_name> [-g <diskgroup>] [-d]

# Options:
#   -n <namespace>  : OpenShift namespace where the pod is located (required)
#   -p <pod_name>   : Name of the InfoScale SDS pod (required)
#   -g <diskgroup>  : Specific disk group to process (optional)
#   -d              : Dry-run mode (optional)

# Example:
./snapshot_cleanup.sh -n infoscale-vtas \
  -p infoscale-sds-21432-7820e9290fa0fc26-b9phd \
  -g vrts_kube_dg-1121
```

---

### Failed VM Migrations Due to Timeouts — InfoScale Upgrade Is in a Paused State

**Causes:**
- Cluster is overloaded or insufficient bandwidth for VM migration.
- A migration policy is overriding default settings.
- Too many parallel writes causing "dirty pages."
- Migrations are simply taking too long to finish.

**Resolution:** Delete the specific `VirtualMachineMigration` resource that is in an error state. The operator will automatically retry.

To prevent recurrence:
- Set `allowAutoConverge: true` in the KubeVirt resource.
- If you see memory violation alerts, increase system-slice memory on nodes (requires a node rollout).

Recommended formula for system reservation:

```
systemReserved.memory = min( max(2G, 5% of totalRAM of node), 8Gi )
```

---

## Limitations

The following limitations apply to the current release:

- **Single-node clusters:** You cannot upgrade a single-node InfoScaleCluster. There is no other node available to host workloads during the process.
- **FSS clusters:** Upgrading clusters deployed with Flexible Storage Sharing (FSS) is not supported in this version.
