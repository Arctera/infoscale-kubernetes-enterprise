# InfoScale Kubernetes Enterprise (IKE) Upgrade Guide

## Table of Contents

- [Overview](#overview)
- [Pre-requisites](#pre-requisites)
- [InfoScale Operator Upgrade](#infoscale-operator-upgrade)
- [InfoScale Preflight Checks](#infoscale-preflight-checks)
- [InfoScale Cluster Version Upgrade (Soft Upgrade)](#infoscale-cluster-version-upgrade-soft-upgrade)
- [Moving from 8.x to 9.x](#moving-from-8x-to-9x)
  - [Option 1: Only Workers are Schedulable](#option-1-only-workers-are-schedulable)
  - [Option 2: Both Workers and Masters are Schedulable](#option-2-both-workers-and-masters-are-schedulable)
- [Source Version: 8.0.4x](#source-version-804x)
- [Source Version: 9.x](#source-version-9x)
- [Supported Platform Upgrades and Exceptions](#supported-platform-upgrades-and-exceptions)
- [Troubleshooting](#troubleshooting)
  - [Paused Upgrade](#paused-upgrade)
- [References and Artefacts](#references-and-artefacts)

---

## Overview

This page outlines the workflows for IKE upgrades and end-to-end upgrades, where users can upgrade OpenShift and the InfoScale cluster in two steps:

1. **InfoScale Operator upgrade**
2. **InfoScale cluster version upgrade** (CR Version change)

Based on the source version and observed known issues, InfoScale upgrade workflows can change with additional preparatory steps. With these workflows, IKE ensures upgrades without downtime of deployed applications and Virtual machines in OpenShift and OpenShift Virtualisation platforms.

> **Note:** Steps 1 and 2 should be completed before upgrading OpenShift, unless marked for combined upgrade where CR version and OCP upgrades are done simultaneously. (Combined upgrade is not under the scope of this page)

---

## Pre-requisites

1. The platform should remain stable and responsive, without entering into high-latency states caused by API server saturation, excessive thrashing or surges in node resource pressure
2. Enough resources are available for VM migration if using OCP-V
3. Pre-flight CLI should not flag any errors or there should not be any pending remediations
4. There should be no pending rollouts. All configurations should be in sync

---

## InfoScale Operator Upgrade

InfoScale operator can be upgraded with published operator in customer environment. In-house clusters require the latest catalog source to be deployed, which can be picked as per the build manifests. Make sure you applied/edited the corresponding catsrc for InfoScale Operator catalog image as per the latest build.

Please refer to the artefacts for yaml references if you are planning to prepare source cluster itself for upgrade.

There can be multiple hops involved for operator upgrade depending on deployed operator version. For example, **8.0.400 operator** will go through:

- `8.0.410` → `9.1.0` → `9.1.2`

> **Important:** If source version is 8.x, change the channel of subscription resource to `fast`, otherwise operator upgrade won't be visible in web console.

### Example: Operator Upgrade Progress

**Towards 8.0.410:**

```shell
oc get csv -n infoscale-vtas
```

```
NAME                                  DISPLAY                                       VERSION   REPLACES                                PHASE
cert-manager-operator.v1.18.0         cert-manager Operator for Red Hat OpenShift   1.18.0    cert-manager-operator.v1.17.0           Succeeded
infoscale-licensing-operator.v9.1.0   InfoScale™ Licensing Operator                 9.1.0     infoscale-licensing-operator.v8.0.410   Succeeded
infoscale-sds-operator.v8.0.400       InfoScale™ SDS Operator                       8.0.400   infoscale-sds-operator.v8.0.330         Replacing
infoscale-sds-operator.v8.0.410       InfoScale™ SDS Operator                       8.0.410   infoscale-sds-operator.v8.0.400         Installing
```

**Next hop towards 9.1.0:**

```shell
oc get csv -n infoscale-vtas -w
```

```
NAME                                  DISPLAY                                       VERSION   REPLACES                                PHASE
cert-manager-operator.v1.18.0         cert-manager Operator for Red Hat OpenShift   1.18.0    cert-manager-operator.v1.17.0           Succeeded
infoscale-licensing-operator.v9.1.0   InfoScale™ Licensing Operator                 9.1.0     infoscale-licensing-operator.v8.0.410   Succeeded
infoscale-sds-operator.v8.0.410       InfoScale™ SDS Operator                       8.0.410   infoscale-sds-operator.v8.0.400         Replacing
infoscale-sds-operator.v9.1.0         InfoScale™ SDS Operator                       9.1.0     infoscale-sds-operator.v8.0.410         Installing
```

**Final hop to 9.1.2:**

```shell
oc get csv -n infoscale-vtas -w
```

```
NAME                                  DISPLAY                                       VERSION   REPLACES                                PHASE
cert-manager-operator.v1.18.0         cert-manager Operator for Red Hat OpenShift   1.18.0    cert-manager-operator.v1.17.0           Succeeded
infoscale-licensing-operator.v9.1.0   InfoScale™ Licensing Operator                 9.1.0     infoscale-licensing-operator.v8.0.410   Succeeded
infoscale-sds-operator.v9.1.2         InfoScale™ SDS Operator                       9.1.2     infoscale-sds-operator.v9.1.0           Succeeded
```

---

## InfoScale Preflight Checks

InfoScale IKE advises running preflight CLI once the operator is upgraded. It should flag if there are any discrepancies found in current cluster. User should remediate and apply the missing configuration as prompted, then proceed for upgrades.

> **Note:** Preflight CLI will be part of release tar artefacts (`infoscale-tools.tar`).

---

## InfoScale Cluster Version Upgrade (Soft Upgrade)

Based on the source version, please apply the given steps and go through the verification where required. All the files and required resources can be found in the [References and Artefacts](#references-and-artefacts) section.

### Summary

| Source Version | Steps Required |
|----------------|----------------|
| **8.x to 9.x** | Additional kubelet configuration steps required |
| **9.0.x to 9.0.y** | Standard upgrade procedure |

**For 9.x upgrades:**
1. Change InfoScale Cluster version to latest
2. Wait for upgrade to finish and InfoScale cluster to reflect back to Running
3. Trigger platform/OCP upgrade

---

## Moving from 8.x to 9.x

To configure SDS pod lifecycle hooks, additional kubelet configuration should be applied with this major InfoScale version change. To minimize restarts caused by this configuration, we suggest pausing the schedulable machine config pools for some time.

> **Warning:** Please make sure you unpause the same as per the instruction. This will cause forced rollout if not followed correctly.

> **Note:** Same steps are applicable even for 9.x if you missed this pre-deployment requirement or preflight CLI flagged the same.

### Check if Kubelet Configuration is Needed

Pause all schedulable MCPs. Only worker pool in standard OCP configuration.
*(Consider marking the same for master if it is schedulable and part of InfoScale Cluster)*

```shell
oc get kubeletconfigs.machineconfiguration.openshift.io
# Should be empty OR without following params

oc get kubeletconfigs.machineconfiguration.openshift.io -oyaml | grep -i grace
#      shutdownGracePeriod: 15m
#      shutdownGracePeriodCriticalPods: 5m
```

If present, check whether it's rolled out:

```shell
# Replace with the correct node; it should show kubelet inhibitor
ssh core@ocp-w-02.lab.ocp.lan sudo systemd-inhibit
```

Expected output:
```
WHO            UID USER PID  COMM           WHAT     WHY                                        MODE
NetworkManager 0   root 1486 NetworkManager sleep    NetworkManager needs to turn off networks  delay
kubelet        0   root 3112 kubelet        shutdown Kubelet needs time to handle node shutdown delay
```

If kubelet inhibitor is not present, proceed with the given configuration.

---

### Option 1: Only Workers are Schedulable

```shell
# Label the worker MCP
# Use common label if masters are schedulable:
# oc label mcp worker machineconfiguration.openshift.io/domain=sched

oc label mcp worker machineconfiguration.openshift.io/role=worker
```

```
machineconfigpool.machineconfiguration.openshift.io/worker labeled
```

```shell
# Pause the worker MCP
oc patch mcp worker --type=merge -p '{"spec":{"paused":true}}'
```

```
machineconfigpool.machineconfiguration.openshift.io/worker patched
```

```shell
# Verify pause status
oc get mcp worker -oyaml | grep pause
```

```
  paused: true
```

```shell
# Apply systemd config for worker
oc apply -f https://raw.githubusercontent.com/Arctera/infoscale-kubernetes-enterprise/main/config/sysd/99-worker-sysd.yaml
```

```
machineconfig.machineconfiguration.openshift.io/99-worker-sysd-conf-override created
```

```shell
# Apply kubelet config for worker
oc apply -f https://raw.githubusercontent.com/Arctera/infoscale-kubernetes-enterprise/main/config/kubelet/kubelet-config.yaml
```

```
kubeletconfig.machineconfiguration.openshift.io/custom-kubelet-config created
```

**Verify the kubelet config:**

```shell
oc describe kubeletconfigs.machineconfiguration.openshift.io custom-kubelet-config
```

```yaml
Name:         custom-kubelet-config
Namespace:
Labels:       <none>
Annotations:  machineconfiguration.openshift.io/mc-name-suffix:
API Version:  machineconfiguration.openshift.io/v1
Kind:         KubeletConfig
Metadata:
  Creation Timestamp:  2026-01-16T13:15:00Z
  Finalizers:
    99-worker-generated-kubelet
  Generation:        1
  Resource Version:  19382539
  UID:               940d4930-c19d-4e8e-98f1-99d0fb65e2cd
Spec:
  Kubelet Config:
    Shutdown Grace Period:                15m
    Shutdown Grace Period Critical Pods:  5m
  Machine Config Pool Selector:
    Match Labels:
      machineconfiguration.openshift.io/role:  worker   # Can change as per label
Status:
  Conditions:
    Last Transition Time:  2026-01-16T13:15:00Z
    Message:               Success
    Status:                True
    Type:                  Success
Events:                    <none>
```

---

### Option 2: Both Workers and Masters are Schedulable

Follow this if both workers and masters are schedulable and ANY master node is part of InfoScale.

```shell
# Label both MCPs
oc label mcp worker machineconfiguration.openshift.io/domain=sched
oc label mcp master machineconfiguration.openshift.io/domain=sched

# Pause both MCPs
oc patch mcp worker --type=merge -p '{"spec":{"paused":true}}'
oc patch mcp master --type=merge -p '{"spec":{"paused":true}}'
```

```
machineconfigpool.machineconfiguration.openshift.io/worker patched
machineconfigpool.machineconfiguration.openshift.io/master patched
```

```shell
# Apply common systemd config
oc apply -f https://raw.githubusercontent.com/Arctera/infoscale-kubernetes-enterprise/main/config/sysd/99-common-sysd.yaml

# Apply common kubelet config
oc apply -f https://raw.githubusercontent.com/Arctera/infoscale-kubernetes-enterprise/main/config/kubelet/common-kubelet-config.yaml
```

> **Important:** Machine config operator will rollout this config only when user unpauses (sets `pause=false`). **Do not do this step right away.** Follow the next instructions.

---

## Source Version: 8.0.4x

> **Note:** At this stage, respective machine config pool(s) are still paused.

### Step 1: Apply Required Patch

```shell
# Download patch infoscale-patch-8.0.4x.tar.gz from SORT
tar xvzf infoscale-patch-8.0.4x.tar.gz
cd infoscale-patch-8.0.4x

# Apply the patch
./apply-cluster-patch.sh infoscalecluster-dev
```

**Expected output:**

```
[INFO] Using CLI: oc
[INFO] Locating InfoScaleCluster: infoscalecluster-dev
[INFO] Cluster namespace: infoscale-vtas
[INFO] Discovering pods for cluster infoscalecluster-dev
[INFO] Found pods:
  - infoscale-sds-1230-1eb7816cdb4bd7f3-9dlmv
  - infoscale-sds-1230-1eb7816cdb4bd7f3-fjpwt
  - infoscale-sds-1230-1eb7816cdb4bd7f3-vt2nj
  - infoscale-sds-1230-1eb7816cdb4bd7f3-w9ls8
[INFO] Collecting files from patch directory: /opt/infoscale-patch-8.0.4x
[INFO] Processing pod: infoscale-sds-1230-1eb7816cdb4bd7f3-9dlmv
[INFO]   -> /usr/sbin/vxassist
[INFO]   -> /etc/systemd/system/pod-prestop.service
Created symlink /etc/systemd/system/multi-user.target.wants/pod-prestop.service → /etc/systemd/system/pod-prestop.service.
[INFO]   -> /sbin/vss-util
[INFO]   -> /sbin/vss-stop
...
[INFO] Patch applied successfully to cluster: infoscalecluster-dev
```

### Step 2: Patch InfoScaleCluster Version to 9.1.2

```shell
oc patch infoscalecluster infoscalecluster-dev -n infoscale-vtas --type=merge -p '{"spec":{"version":"9.1.2"}}'
```

```
infoscalecluster.infoscale.veritas.com/infoscalecluster-dev patched
```

**Wait for cluster to be in Running state:**

```shell
oc get po -n infoscale-vtas
```

```
NAME                                            READY   STATUS        RESTARTS      AGE
infoscale-csi-controller-569fb9fc4-k6ddn        5/5     Running       1 (51s ago)   57s
infoscale-csi-node-c85tf                        2/2     Running       0             27s
infoscale-csi-node-cpwrt                        2/2     Terminating   0             3d5h
infoscale-csi-node-gsx5d                        2/2     Running       0             3d5h
infoscale-csi-node-xfgjn                        2/2     Running       0             3d5h
infoscale-fencing-controller-5b86c59dfd-f7ptw   1/1     Running       0             3d5h
infoscale-fencing-enabler-6mx7d                 1/1     Running       0             3d5h
infoscale-fencing-enabler-j8zgw                 1/1     Running       0             3d5h
infoscale-fencing-enabler-qrxtw                 1/1     Running       0             3d5h
infoscale-fencing-enabler-tjcbk                 1/1     Running       0             3d5h
infoscale-licensing-operator-7bb6cb7d48-5hz5b   1/1     Running       0             3d14h
infoscale-sds-1230-1eb7816cdb4bd7f3-drhlq       1/1     Running       0             3d5h
infoscale-sds-1230-1eb7816cdb4bd7f3-fzdzl       1/1     Running       0             3d5h
infoscale-sds-1230-1eb7816cdb4bd7f3-gf62d       1/1     Running       0             3d5h
infoscale-sds-1230-1eb7816cdb4bd7f3-hq6b9       1/1     Running       0             3d5h
infoscale-sds-operator-66c66c6ccf-wfzv4         1/1     Running       0             2m49s
infoscale-toolset-1230-6bc76b6b96-64flx         1/1     Running       0             3d5h
infoscale-toolset-1230-6bc76b6b96-87jrp         1/1     Running       0             3d5h
infoscale-toolset-1230-6bc76b6b96-mggxs         1/1     Running       0             3d5h
infoscale-toolset-1230-6d9f474779-nwb26         0/1     Running       0             32s
```

```shell
oc get infoscaleclusters -A
```

```
NAMESPACE        NAME                   VERSION   CLUSTERID   STATE       DISKGROUPS          STATUS    AGE
infoscale-vtas   infoscalecluster-dev   8.0.400   1230        Upgrading   vrts_kube_dg-1230   Healthy   3d5h
```

### Step 3: Wait for Completion of Software Upgrade

At this stage, changes will roll out first for CSI, fencing, Toolset, then for SDS.

> **Note:** Cluster will fluctuate between Degraded and Running state, since one node is going out of cluster and joining again. This will take some time depending on workload running on system.

```
NAMESPACE        NAME                   VERSION   CLUSTERID   STATE       DISKGROUPS          STATUS     AGE
infoscale-vtas   infoscalecluster-dev   8.0.400   1230        Upgrading   vrts_kube_dg-1230   Degraded   38m
infoscale-vtas   infoscalecluster-dev   8.0.400   1230        Upgrading   vrts_kube_dg-1230   Healthy    39m
infoscale-vtas   infoscalecluster-dev   9.1.2     1230        Running     vrts_kube_dg-1230   Healthy    39m
```

### Step 4: Enable the Paused Pools (Sequentially if Applicable)

Preferably enable/unpause the masters first if schedulable. Wait for complete rollout and then do the same with worker pool.

> **Warning:** Enabling both simultaneously does not guarantee application availability.

```shell
oc patch mcp worker --type=merge -p '{"spec":{"paused":false}}'
```

```
machineconfigpool.machineconfiguration.openshift.io/worker patched
```

**Monitor node status:**

```shell
watch oc get no
```

```
NAME                      STATUS                     ROLES                  AGE   VERSION
ocp348-m1.test.int        Ready                      control-plane,master   41d   v1.30.7
ocp348-m2.test.int        Ready                      control-plane,master   41d   v1.30.7
ocp348-m3.test.int        Ready                      control-plane,master   41d   v1.30.7
ocp348-w01.test.int       Ready                      worker                 41d   v1.30.7
ocp348-w02.test.int       Ready                      worker                 41d   v1.30.7
ocp348-w03.test.int       Ready                      worker                 41d   v1.30.7
ocp348-w04.test.int       Ready,SchedulingDisabled   worker                 41d   v1.30.7
```

### Step 5: Wait for Rollout and InfoScaleCluster to be Ready

> **Tip:** If a node is taking too long and showing state `NotReady,SchedulingDisabled`, try resetting the node.

```shell
oc get infoscaleclusters -Aw
```

```
NAMESPACE        NAME                   VERSION   CLUSTERID   STATE     DISKGROUPS          STATUS     AGE
infoscale-vtas   infoscalecluster-dev   9.1.2     1230        Running   vrts_kube_dg-1230   Degraded   117m
infoscale-vtas   infoscalecluster-dev   9.1.2     1230        Running   vrts_kube_dg-1230   Healthy    121m
```

### Step 6: Trigger the Platform/OCP Upgrade

```shell
oc get clusterversions.config.openshift.io
```

```
NAME      VERSION   AVAILABLE   PROGRESSING   SINCE   STATUS
version   4.17.10   True        False         14d     Cluster version is 4.17.10
```

**During upgrade:**

```
NAME      VERSION   AVAILABLE   PROGRESSING   SINCE   STATUS
version   4.17.10   True        True          65s     Working towards 4.17.46: 112 of 903 done (12% complete), waiting on etcd, kube-apiserver
```

**After completion:**

```shell
oc get clusterversions.config.openshift.io version
```

```
NAME      VERSION   AVAILABLE   PROGRESSING   SINCE   STATUS
version   4.17.46   True        False         74m     Cluster version is 4.17.46
```

```shell
oc get mcp
```

```
NAME     CONFIG                                             UPDATED   UPDATING   DEGRADED   MACHINECOUNT   READYMACHINECOUNT   UPDATEDMACHINECOUNT   DEGRADEDMACHINECOUNT   AGE
master   rendered-master-0b87433eaa1c30ee47db01e64f1caa2f   True      False      False      3              3                   3                     0                      41d
worker   rendered-worker-db5dd169fbc14286c9c4aab0c9ac2418   True      False      False      4              4                   4                     0                      41d
```

---

## Source Version: 9.x

If user is on 9.x (which can be 9.1.0 only), desired upgrade version would be 9.1.2.

There can be 2 cases here:

1. **You followed all required pre-requisites** including the kubelet configuration
2. **If not yet done:** Preflight will suggest you to complete it first. Unpause the required MCPs and let it rollout.

### Standard Upgrade Procedure

1. Upgrade the operator to latest version
2. Change the InfoScaleCluster spec to the latest version - `9.1.2`
3. Wait for completion
4. Do the OpenShift Upgrade

---

## Supported Platform Upgrades and Exceptions

### Unsupported OpenShift Versions

| Version | Channel |
|---------|---------|
| 4.20.4 | All |
| 4.19.19 | All |
| 4.18.29 | Only in candidate channels |
| 4.17.44 | All |
| 4.16.53 | Only in candidate channels |

> **Important:** During OCP upgrade, in full cluster upgrade, both pools (masters and workers) rollout in parallel, which will be problematic if masters are schedulable.
>
> **IKE recommends:** Do not make masters schedulable. If masters are schedulable, choose master upgrade first and on completion choose worker pool upgrade.

---

## Troubleshooting

### Paused Upgrade

If any workload is not owned by ANY of standard Kubernetes controllers, InfoScale operator will pause the upgrade with the following events:

```
Warning  UpdatePaused  23m (x89 over 41m)   InfoScaleCluster  ErrorCode=10050 ErrorMsg=Resource is not managed by controller : pod test/redis not managed statefulset, replicaset, daemonset on volqalnx984
Warning  UpdatePaused  14m (x4 over 15m)    InfoScaleCluster  to resume upgrade with forced migration of such workloads, annotate InfoScaleCluster with infoscale.veritas.com/forceMigrate=true
```

### Suggested Actions

Admin should handle such workloads. For example:

- Simple fleet of pods
- Pods owned by any operators which are not reconciling them on another node

**Options:**
1. Take backup and cleanup such resources if possible
2. If there's no impact even if such resources are down, annotate the InfoScaleCluster for forceful upgrade

**Force upgrade command:**

```shell
oc annotate infoscaleclusters infoscalecluster-dev infoscale.veritas.com/forceMigrate=true
```

```
infoscalecluster.infoscale.veritas.com/infoscalecluster-dev annotated
```

---

## References and Artefacts

### Configuration Files

| Resource | URL |
|----------|-----|
| Worker Systemd Config | https://raw.githubusercontent.com/Arctera/infoscale-kubernetes-enterprise/main/config/sysd/99-worker-sysd.yaml |
| Common Systemd Config | https://raw.githubusercontent.com/Arctera/infoscale-kubernetes-enterprise/main/config/sysd/99-common-sysd.yaml |
| Worker Kubelet Config | https://raw.githubusercontent.com/Arctera/infoscale-kubernetes-enterprise/main/config/kubelet/kubelet-config.yaml |
| Common Kubelet Config | https://raw.githubusercontent.com/Arctera/infoscale-kubernetes-enterprise/main/config/kubelet/common-kubelet-config.yaml |

### Patches and Tools

| Resource | Source |
|----------|--------|
| `infoscale-patch-8.0.4x.tar.gz` | Download from [SORT](https://sort.veritas.com) |
| `infoscale-tools.tar` (includes Preflight CLI) | Part of release artefacts |

### Related Documentation

- [InfoScale Kubernetes Enterprise Documentation](https://github.com/Arctera/infoscale-kubernetes-enterprise)
- [OpenShift Machine Config Operator](https://docs.openshift.com/container-platform/latest/post_installation_configuration/machine-configuration-tasks.html)
- [Kubelet Configuration Reference](https://kubernetes.io/docs/reference/config-api/kubelet-config.v1beta1/)

### Version Compatibility Matrix

| InfoScale Version | Supported OCP Versions | Notes |
|-------------------|------------------------|-------|
| 8.0.400 | 4.14.x - 4.16.x | Requires patch before upgrade |
| 8.0.410 | 4.14.x - 4.17.x | Intermediate upgrade version |
| 9.1.0 | 4.14.x - 4.18.x | Requires kubelet configuration |
| 9.1.2 | 4.14.x - 4.20.x | Latest supported version |

