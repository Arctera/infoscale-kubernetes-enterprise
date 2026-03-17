# Upgrade Reference

## Table of Contents

1. [Overview](#overview)
2. [Pre-requisites](#pre-requisites)
   - [Run the Pre-flight CLI](#run-the-pre-flight-cli)
   - [Stale Snapshot Cleanup (8.x → 9.x only)](#stale-snapshot-cleanup-8x--9x-only)
   - [SCSI Key Validation (OCP-V VIKE only)](#scsi-reservation-key-validation-ocp-v-vike-only)
   - [Cluster Health Checks](#cluster-health-checks)
3. [InfoScale Operator Upgrade](#infoscale-operator-upgrade)
4. [InfoScale Cluster Version Upgrade](#infoscale-cluster-version-upgrade)
   - [Kubelet Configuration Decision Guide](#kubelet-configuration-decision-guide)
   - [Option A – Workers Only](#option-a--workers-only-are-schedulable)
   - [Option B – Workers + Masters](#option-b--workers-and-masters-are-schedulable-and-any-master-is-part-of-infoscale)
   - [Patch for 8.0.4x Sources](#apply-the-required-patch-for-source-version-804x)
   - [Trigger the Cluster Upgrade](#trigger-the-cluster-upgrade)
   - [Unpause Machine Config Pools](#unpause-machine-config-pools)
5. [Platform / OCP Upgrade](#platform--ocp-upgrade)
6. [Supported Versions and Exceptions](#supported-versions-and-exceptions)
7. [Troubleshooting](#troubleshooting)

---

## Overview

This page describes the **three-phase upgrade sequence** for InfoScale on OpenShift:

| Phase | Action | Must complete before |
|-------|--------|----------------------|
| **1** | InfoScale Operator upgrade | Phase 2 |
| **2** | InfoScale cluster version upgrade (CR version change) | Phase 3 |
| **3** | OpenShift (OCP) platform upgrade | — |

> [!IMPORTANT]
> Complete Phases 1 and 2 **before** upgrading OpenShift, unless the upgrade is explicitly a *combined upgrade* (simultaneous CR version + OCP upgrade). Combined upgrades are outside the scope of this document.

Depending on the source version and any known issues, additional preparatory steps may be required before Phase 1. These are described in the [Pre-requisites](#pre-requisites) section below.

---

## Pre-requisites

Verify each of the following before starting any upgrade phase:

- [ ] The platform is stable and responsive — no API server saturation, excessive thrashing, or node resource pressure.
- [ ] Sufficient resources are available for VM migration if using OCP-V. See [Red Hat OpenShift documentation](https://docs.redhat.com) for sizing guidance.
- [ ] The InfoScale support matrix has been reviewed for the target OCP version.
- [ ] No pending rollouts. All configurations are in sync and all worker pools are healthy.
- [ ] No split-brain conditions exist in the deployed InfoScale cluster.
- [ ] The pre-flight CLI reports no errors and no pending remediations (see below).

### Run the Pre-flight CLI

The pre-flight CLI is included in `infoscale-tools-v9.1.2.tar`. Run it and resolve **all** reported issues before proceeding.

```bash
./preflight-cli.sh --target-ike <infoscale_version> --target-ocp <ocp_version>
```

Example:

```bash
./preflight-cli.sh --target-ike 9.1.0 --target-ocp 4.19.x
```

### Stale Snapshot Cleanup (8.x → 9.x only)

> [!WARNING]
> Upgrades from 8.x to 9.x can get stuck with `Resource Busy` if stale snapshot relationships or tags are present inside SDS pods. This causes the SDS operator to repeatedly report `node busy` or an in-progress volume/snapshot sync.

If the pre-flight CLI reports stale snapshots, clean them up **before proceeding**:

```bash
./snapshot_cleanup.sh
```

> Script is included in `infoscale-tools-v9.1.2.tar`.

### SCSI Reservation Key Validation (OCP-V VIKE only)

> [!NOTE]
> This check applies only to OCP-V VIKE clusters. Skip if you are not running OpenShift Virtualization.

Before triggering an OCP upgrade, verify SCSI registration key counts from inside an SDS pod:

```bash
oc exec -it infoscale-sds-21432-xxxx-xxxx -n infoscale-vtas -- bash
vxfenadm -s /dev/vx/rdmp/<dmpnodename>
```

**Expected key count:**  `number_of_nodes × paths_per_disk`

> Example: 5 nodes × 2 paths = **10 keys**

<details>
<summary>Example output (5-node cluster, 2 paths per disk)</summary>

```text
Device Name: /dev/vx/rdmp/emc0_346f
Total Number Of Keys: 10
key[0]:
        [Character Format]: APGR0019
        [Node Format]: Cluster ID: unknown  Node ID: 0   Node Name: ocptest-01.test.int
key[1]:
        [Character Format]: APGR0019
        [Node Format]: Cluster ID: unknown  Node ID: 0   Node Name: ocptest-01.test.int
key[2]:
        [Character Format]: CPGR0019
        [Node Format]: Cluster ID: unknown  Node ID: 2   Node Name: ocptest-02.test.int
key[3]:
        [Character Format]: CPGR0019
        [Node Format]: Cluster ID: unknown  Node ID: 2   Node Name: ocptest-02.test.int
key[4]:
        [Character Format]: DPGR0019
        [Node Format]: Cluster ID: unknown  Node ID: 3   Node Name: ocptest-03.test.int
key[5]:
        [Character Format]: DPGR0019
        [Node Format]: Cluster ID: unknown  Node ID: 3   Node Name: ocptest-03.test.int
key[6]:
        [Character Format]: EPGR0019
        [Node Format]: Cluster ID: unknown  Node ID: 4   Node Name: ocptest-04.test.int
key[7]:
        [Character Format]: EPGR0019
        [Node Format]: Cluster ID: unknown  Node ID: 4   Node Name: ocptest-04.test.int
key[8]:
        [Character Format]: BPGR0019
        [Node Format]: Cluster ID: unknown  Node ID: 1   Node Name: ocptest-05.test.int
key[9]:
        [Character Format]: BPGR0019
        [Node Format]: Cluster ID: unknown  Node ID: 1   Node Name: ocptest-05.test.int
```

</details>

### Cluster Health Checks

Run both commands and confirm the expected outputs before proceeding.

**1. Cluster state must be `Running`:**

```bash
oc get infoscalecluster -A
```

```text
NAMESPACE     NAME                      VERSION   CLUSTERID   STATE     DISKGROUPS           STATUS    AGE
<namespace>   <infoscale-cluster-name>  8.0.400   21432       Running   vrts_kube_dg-21432   Healthy   90m
```

**2. Cluster health must be `Healthy`:**

```bash
oc get infoscaleclusters.infoscale.veritas.com <infoscale-cluster-name> \
  -n <namespace> -ojsonpath='{.status.clusterState}{"\n"}'
```

Expected output: `Healthy`

> [!WARNING]
> Do not proceed if the cluster is in `Degraded` or any non-`Healthy` state. Investigate and resolve the root cause first.

---

## InfoScale Operator Upgrade

1. Open the OpenShift web console.

2. Navigate to the Operators page:
   - OCP **below 4.20** → `Operators → Installed Operators`
   - OCP **4.20 and above** → `Ecosystem → Software Catalog`

3. Confirm all InfoScale operators are listed.

4. Click **InfoScale SDS Operator** → **Subscription** tab.

5. Click **Update channel**, select **`fast`**, and save.

6. When the **Upgrade Available** status appears, click either **InfoScale SDS Operator** or **InfoScale Licensing Operator**.

7. In **Subscription**, review the pending update that requires approval.

8. Click **Approve** to proceed.

9. Wait for the upgrade to complete and verify the new version appears under **Installed Operators**.

> [!NOTE]
> **Multi-hop upgrades:** Depending on the starting version, the operator may upgrade in multiple steps. For example:
> - `8.0.400` → `8.0.410` → `9.1.0` → `9.1.2`
> - `9.1.0` → `9.1.2` (single hop)
>
> Repeat the approval step for each hop until the target version is reached.

---

## InfoScale Cluster Version Upgrade

**Upgrade steps at a glance:**

1. Verify or apply kubelet configuration (see decision guide below)
2. Apply patch, if upgrading from 8.0.4x
3. Patch the InfoScaleCluster version to the target
4. Wait for upgrade to complete
5. Unpause machine config pools (if paused in step 1)
6. Trigger OCP upgrade (separate phase)

### Kubelet Configuration Decision Guide

SDS pod lifecycle hooks require specific kubelet shutdown parameters. Use the flow below to determine what — if anything — you need to do.

**Step 1 — Check if parameters are already present:**

```bash
oc get kubeletconfigs.machineconfiguration.openshift.io -oyaml | grep -i grace
```

If you see both lines below, the config exists:

```text
shutdownGracePeriod: 15m
shutdownGracePeriodCriticalPods: 5m
```

**Step 2 — If the config exists, verify it is rolled out** (replace node name with an actual worker):

```bash
ssh core@<worker-node> sudo systemd-inhibit
```

If the output includes a `kubelet shutdown` inhibitor entry like this, the config is active and **you can skip to [Apply the Required Patch](#apply-the-required-patch-for-source-version-804x)**:

```text
WHO     COMM     WHAT      WHY                                        MODE
kubelet kubelet  shutdown  Kubelet needs time to handle node shutdown delay
```

**Step 3 — If the config is missing or not rolled out**, follow the option that matches your cluster topology:

| Scenario | Follow |
|----------|--------|
| Only worker nodes are schedulable | [Option A](#option-a--workers-only-are-schedulable) |
| Both workers **and** masters are schedulable, and any master is part of InfoScale | [Option B](#option-b--workers-and-masters-are-schedulable-and-any-master-is-part-of-infoscale) |

> [!WARNING]
> Do not unpause the machine config pools immediately after applying the configuration. The MCO will roll out changes only when you explicitly unpause. Follow the instructions at [Unpause Machine Config Pools](#unpause-machine-config-pools) at the correct stage.

---

### Option A – Workers Only Are Schedulable

**1. Label and pause the worker MCP:**

```bash
oc label mcp worker machineconfiguration.openshift.io/role=worker
oc patch mcp worker --type=merge -p '{"spec":{"paused":true}}'
```

Verify the pool is paused:

```bash
oc get mcp worker -oyaml | grep paused
# Expected: paused: true
```

**2. Apply systemd and kubelet configuration:**

```bash
oc apply -f https://raw.githubusercontent.com/Arctera/infoscale-kubernetes-enterprise/main/config/sysd/99-worker-sysd.yaml
oc apply -f https://raw.githubusercontent.com/Arctera/infoscale-kubernetes-enterprise/main/config/kubelet/kubelet-config.yaml
```

**3. Confirm the kubelet config was accepted successfully:**

```bash
oc describe kubeletconfigs.machineconfiguration.openshift.io custom-kubelet-config
```

Look for `Status: True` and `Type: Success` at the bottom of the output:

```text
Status:
  Conditions:
    Message:  Success
    Status:   True
    Type:     Success
```

The worker MCP remains **paused** at this point. Continue to [Apply the Required Patch](#apply-the-required-patch-for-source-version-804x).

---

### Option B – Workers and Masters Are Schedulable and Any Master Is Part of InfoScale

**1. Label and pause both MCPs:**

```bash
oc label mcp worker machineconfiguration.openshift.io/domain=sched
oc label mcp master machineconfiguration.openshift.io/domain=sched

oc patch mcp worker --type=merge -p '{"spec":{"paused":true}}'
oc patch mcp master --type=merge -p '{"spec":{"paused":true}}'
```

**2. Apply the common systemd and kubelet configuration:**

```bash
oc apply -f https://raw.githubusercontent.com/Arctera/infoscale-kubernetes-enterprise/main/config/sysd/99-common-sysd.yaml
oc apply -f https://raw.githubusercontent.com/Arctera/infoscale-kubernetes-enterprise/main/config/kubelet/common-kubelet-config.yaml
```

Both MCPs remain **paused** at this point. Continue to [Apply the Required Patch](#apply-the-required-patch-for-source-version-804x).

---

### Apply the Required Patch for Source Version 8.0.4x

> [!NOTE]
> This step is only required when upgrading **from 8.0.4x**. Skip if your source version is 9.x.

Download `infoscale-patch-8.0.4x.tar.gz` from SORT, then run:

```bash
tar xvzf infoscale-patch-8.0.4x.tar.gz
cd infoscale-patch-8.0.4x
./apply-cluster-patch.sh infoscalecluster-dev
```

A successful run ends with:

```text
[INFO] Patch applied successfully to cluster: infoscalecluster-dev
```

<details>
<summary>Full example output</summary>

```text
[INFO] Using CLI: oc
[INFO] Locating InfoScaleCluster: infoscalecluster-dev
[INFO] Cluster namespace: infoscale-vtas
[INFO] Discovering pods for cluster infoscalecluster-dev
[INFO] Found pods:
  - infoscale-sds-1230-1eb7816cdb4bd7f3-9dlmv
  - infoscale-sds-1230-1eb7816cdb4bd7f3-fjpwt
  - infoscale-sds-1230-1eb7816cdb4bd7f3-vt2nj
  - infoscale-sds-1230-1eb7816cdb4bd7f3-w9ls8
[INFO] Processing pod: infoscale-sds-1230-1eb7816cdb4bd7f3-9dlmv
[INFO]   -> /usr/sbin/vxassist
[INFO]   -> /etc/systemd/system/pod-prestop.service
Created symlink /etc/systemd/system/multi-user.target.wants/pod-prestop.service -> /etc/systemd/system/pod-prestop.service.
[INFO]   -> /sbin/vss-util
[INFO]   -> /sbin/vss-stop
... (repeated for each pod)
[INFO] Patch applied successfully to cluster: infoscalecluster-dev
```

</details>

---

### Trigger the Cluster Upgrade

**1. Patch the InfoScaleCluster version:**

```bash
oc patch infoscalecluster <cluster-name> -n <namespace> \
  --type=merge -p '{"spec":{"version":"9.1.2"}}'
```

Expected output:

```text
infoscalecluster.infoscale.veritas.com/<cluster-name> patched
```

**2. Monitor pod rollout** — CSI, fencing, and toolset components roll out first, then SDS:

```bash
oc get po -n infoscale-vtas -w
```

**3. Monitor cluster status** — the cluster will oscillate between `Degraded` and `Running` as nodes leave and rejoin one at a time. This is expected behavior.

```bash
oc get infoscaleclusters -A -w
```

Example progression:

```text
NAMESPACE        NAME                   VERSION   STATE       STATUS     AGE
infoscale-vtas   infoscalecluster-dev   8.0.400   Upgrading   Healthy    3d5h
infoscale-vtas   infoscalecluster-dev   8.0.400   Upgrading   Degraded   38m   ← node cycling (normal)
infoscale-vtas   infoscalecluster-dev   8.0.400   Upgrading   Healthy    39m
infoscale-vtas   infoscalecluster-dev   9.1.2     Running     Healthy    39m   ← upgrade complete
```

Wait until `VERSION` shows `9.1.2`, `STATE` shows `Running`, and `STATUS` shows `Healthy` before continuing.

---

### Unpause Machine Config Pools

> [!NOTE]
> Only follow this step if you paused MCPs in [Option A](#option-a--workers-only-are-schedulable) or [Option B](#option-b--workers-and-masters-are-schedulable-and-any-master-is-part-of-infoscale). If you did not pause any pools, skip this section.

> [!WARNING]
> If you paused both masters and workers (Option B), **unpause masters first** and wait for full rollout before unpausing workers. Unpausing both pools at the same time does not guarantee application availability.

**Unpause workers** (or masters first if Option B):

```bash
oc patch mcp worker --type=merge -p '{"spec":{"paused":false}}'
```

Monitor node rollout:

```bash
oc get no -w
```

A node being reconfigured will temporarily show `Ready,SchedulingDisabled`. Wait until all nodes return to `Ready`.

```text
NAME                 STATUS                     ROLES                  AGE   VERSION
ocp348-w04.test.int  Ready,SchedulingDisabled   worker                 41d   v1.30.7   ← rolling
ocp348-w04.test.int  Ready                      worker                 41d   v1.30.7   ← done
```

> If a node stays in `NotReady,SchedulingDisabled` for an extended period, try resetting that node.

Confirm InfoScaleCluster returns to `Healthy` after the rollout:

```bash
oc get infoscaleclusters -Aw
```

```text
NAMESPACE        NAME                   VERSION   STATE     STATUS     AGE
infoscale-vtas   infoscalecluster-dev   9.1.2     Running   Degraded   117m   ← transitioning
infoscale-vtas   infoscalecluster-dev   9.1.2     Running   Healthy    121m   ← done
```

---

## Platform / OCP Upgrade

Trigger the OCP upgrade only after both Phases 1 and 2 above are complete.

> [!NOTE]
> During a full cluster upgrade, master and worker MCPs roll out **in parallel**. This is a risk if masters are schedulable. IKE recommends upgrading masters first, then workers, to maintain application availability.

Check current version before starting:

```bash
oc get clusterversions.config.openshift.io
```

```text
NAME      VERSION   AVAILABLE   PROGRESSING   STATUS
version   4.17.10   True        False         Cluster version is 4.17.10
```

Monitor during upgrade:

```text
NAME      VERSION   AVAILABLE   PROGRESSING   STATUS
version   4.17.10   True        True          Working towards 4.17.46: 112 of 903 done (12%)...
```

Verify completion:

```bash
oc get clusterversions.config.openshift.io version
oc get mcp
```

```text
NAME      VERSION   AVAILABLE   PROGRESSING   STATUS
version   4.17.46   True        False         Cluster version is 4.17.46

NAME     UPDATED   UPDATING   DEGRADED   MACHINECOUNT   READYMACHINECOUNT
master   True      False      False      3              3
worker   True      False      False      4              4
```

---

## Supported Versions and Exceptions

### Unsupported OCP Versions

The following OCP versions must **not** be used as upgrade targets:

| OCP Version | Channel restriction |
|-------------|-------------------|
| `4.20.4` | All channels |
| `4.19.19` | All channels |
| `4.18.29` | Candidate channel only |
| `4.17.44` | All channels |
| `4.16.53` | Candidate channel only |

---

## Troubleshooting

### 1. Upgrade Paused — Unmanaged Workloads

**Symptom:** The InfoScale operator pauses the upgrade with events like:

```text
Warning  UpdatePaused  InfoScaleCluster  ErrorCode=10050
  ErrorMsg=Resource is not managed by controller: pod test/redis
  not managed by statefulset, replicaset, or daemonset on volqalnx984

Warning  UpdatePaused  InfoScaleCluster
  to resume, annotate InfoScaleCluster with infoscale.veritas.com/forceMigrate=true
```

**Why this happens:** Any pod not owned by a standard Kubernetes controller (Deployment, StatefulSet, DaemonSet, ReplicaSet) blocks the upgrade, because the operator cannot safely migrate it.

**Resolution options:**

1. **Preferred:** Identify the workload and either delete it, migrate it manually, or ensure its owner is reconciling it across nodes.
2. **If downtime is acceptable for that workload:** Force migration by annotating the cluster:

```bash
oc annotate infoscaleclusters infoscalecluster-dev \
  infoscale.veritas.com/forceMigrate=true
```

After the upgrade completes, remove the annotation:

```bash
oc annotate infoscaleclusters infoscalecluster-dev \
  infoscale.veritas.com/forceMigrate-
```

---

### 2. NFD Crash Blocking OCP Upgrade (4.19 → 4.20)

**Symptom:** NFD garbage collector pods crash-loop during OCP upgrades:

```text
nfd-gc-6b7549bfc4-llv5w   0/1   Running   1 (35s ago)   75s
```

Events on the pod show repeated liveness/readiness probe failures against port `8080`.

**Resolution:** Delete the crashing `nfd-gc` pod. It will be recreated and the upgrade will resume:

```bash
oc delete pod <nfd-gc-pod-name> -n openshift-nfd
```

**Affected versions where this was observed:**

| OCP Version | State |
|-------------|-------|
| `4.19.21` | Completed after pod deletion |
| `4.20.8` | Completed after pod deletion |

<details>
<summary>Full event log example</summary>

```text
Warning  Unhealthy  pod/nfd-gc-6b7549bfc4-llv5w
  Liveness probe failed: Get "http://10.128.3.19:8080/healthz": connection refused
Warning  Unhealthy  pod/nfd-gc-6b7549bfc4-llv5w
  Readiness probe failed: Get "http://10.128.3.19:8080/healthz": connection refused
Normal   Killing    pod/nfd-gc-6b7549bfc4-llv5w
  Container nfd-gc failed liveness probe, will be restarted
```

</details>

---

### 3. Operators Not Upgrading After Install Plan Approval

**Why this happens:** InfoScale SDS Operator and InfoScale Licensing Operator share the same operator group. Each creates two install plans, but only one of those plans lists both operators as owners.

**Resolution:** When approving an install plan, always select the plan that shows **both** operators in the preview panel. Approving the wrong plan stalls one of the operators.

---

### 4. Transient Node Drain Errors During OCP-V Upgrades

**Symptom:** Messages like the following appear during OpenShift Virtualization cluster upgrades:

```text
error when evicting pods/"virt-launcher-<VMNAME>" -n "<NAMESPACE>"
(will retry after 5s)
```

**These messages are safe to ignore.** Pod Disruption Budgets intentionally allow VM migration to take longer, and the eviction will succeed once the migration completes.

See [Red Hat KB 7067725](https://access.redhat.com/solutions/7067725) for details.

---

### 5. VM Migration Timeouts Pausing the InfoScale Upgrade

**Symptom:** The InfoScale upgrade stalls because one or more `VirtualMachineInstanceMigration` resources are in a failed/timed-out state:

```bash
oc describe infoscaleclusters -n infoscale-vtas <cluster-name> | grep -A2 UpdatePaused
```

```text
Warning  UpdatePaused  InfoScaleCluster
  migration instance infoscale-fio-vm-8-c74edd9fa2a14506 is failed in prod,
  upgrade is waiting for its completion; user intervention required
```

**Common causes:**

- Cluster resource contention or insufficient migration bandwidth
- A migration policy that limits bandwidth for certain VMs
- Excessive dirty-page churn preventing memory convergence
- VMs with very large memory footprint

**Resolution:** Delete the failed migration resource. The InfoScale operator will automatically retry it:

```bash
oc get vmim -n <namespace>
oc delete vmim <failed-migration-name> -n <namespace>
```

Confirm the migration name from the event, for example:

```bash
oc describe vmim infoscale-fio-vm-1-114880f98092cdab -n prod
```

Look for:
```text
Failure Reason: Live migration is not completed after #Num seconds and has been aborted
```

**To prevent recurrence:**

1. Ensure `allowAutoConverge: true` is set in the `kubevirt` resource:

   ```bash
   oc get kubevirt -n kubevirt-hyperconverged -oyaml | grep autoConverge
   ```

2. If memory pressure alerts appear in the web console, consider increasing `systemReserved.memory` on schedulable nodes. See the [OCP nodes documentation](https://docs.redhat.com/en/documentation/openshift_container_platform/4.20/html/nodes/working-with-nodes#nodes-nodes-managing-about_nodes-nodes-managing) for guidance.

   Recommended formula:

   ```
   systemReserved.memory = min( max(2Gi, 5% of node RAM), 8Gi )
   ```

   Final value should be chosen by the cluster administrator based on observed surge patterns and bandwidth constraints.
