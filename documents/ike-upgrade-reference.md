# InfoScale Kubernetes Enterprise (IKE) Upgrade Guide
# Upgrade Reference

## Table of Contents

- [Overview](#overview)
- [Pre-requisites](#pre-requisites)
- [InfoScale Operator upgrade](#infoscale-operator-upgrade)
- [InfoScale Cluster version upgrade (Software upgrade)](#infoscale-cluster-version-upgrade-software-upgrade)
  - [Upgrading to InfoScale](#upgrading-to-infoscale)
- [Platform/OpenShift upgrade](#platformopenshift-upgrade)
- [Troubleshooting](#troubleshooting)
- [Limitations](#limitations)

## Overview

This page outlines the workflows for IKE upgrades and end-to-end upgrades, where users can upgrade OpenShift and the InfoScale cluster in two steps

- InfoScale Operator upgrade

- InfoScale cluster version upgrade (CR Version change)

Based on the source version and observed known issues; InfoScale upgrade workflows can change with additional preparatory steps. With these workflows, IKE ensuring upgrades without downtime of deployed applications and Virtual machines in OpenShift and OpenShift Virtualisation platform. Also; 1 and 2 should be completed before upgrading OpenShift; unless marked for combined upgrade where, CR version and OCP upgrades done simultaneously. (combined upgrade is not under the scope of this page)

## Pre-requisites

1. The platform should remain stable and responsive, without entering into high-latency states caused by API server saturation, excessive thrashing or surges in node resource pressure

2. Enough resources are available for VM migration if using OCP-V, please follow Red Hat OpenShift documentation for this.

3. Pre-flight CLI should not flag any errors or there should not be any pending remediations, 
   this script is part of infoscale-tools-v9.1.2.tar 

    Note: Please check InfoScale support matrix before finalizing OpenShift cluster version for upgrade

    ```bash

    Before running the script, ensure that you have Bash installed on your system.

    - Bash: This script is intended to be run in a Bash shell. If you're using a different shell, consider switching to Bash. Also ,make sure jq is installed since script uses it.

    ```bash
    ./preflight-cli.sh --target-ike <infoscale_version> --target-ocp <ocp_version>

    e.g.

    ./preflight-cli.sh --target-ike 9.1.2 --target-ocp 4.19.x
    ========== PRE-FLIGHT SUMMARY ==========
    04-workload-sanity.sh : All checks passed
    03-sourceclust.sh : All checks passed
    01-platform.sh : All checks passed
    02-ike-versions.sh : All checks passed
    ========================================
    [INFO]  All output saved to: /opt/Preflight/preflight/logs/preflight-20260317-095735/preflight.log
    ```

4. There should be no pending rollouts. All configurations should be in sync, all the worker pools should be healthy.

5. If No existing split brain should be seen in deployed InfoScale cluster before triggering upgrades

    Before OCP upgrade is executed on the OCP-V VIKE cluster please execute following following commands inside SDS pods

    ```bash
    #oc exec -it infoscale-sds-21432-xxxx-xxxx  -n infoscale-vtas -- bash
    #vxfenadm -s /dev/vx/rdmp/<dmpnodename>
    ```

    No of keys should match the number of nodes X no of paths for each disk.

    e.g if no of nodes is 5 and each disk has 2 path then you should see 10 disks

    ```text
    [root@ocptest-01 /]# vxfenadm -s /dev/vx/rdmp/emc0_346f
    Reading SCSI Registration Keys...
    Device Name: /dev/vx/rdmp/emc0_346f
    Total Number Of Keys: 10
    key[0]:
            [Numeric Format]:   65,80,71,82,48,48,49,57
            [Character Format]: APGR0019
            [Node Format]: Cluster ID: unknown  Node ID: 0   Node Name: ocptest-01.test.int
    key[1]:
            [Numeric Format]:   65,80,71,82,48,48,49,57
            [Character Format]: APGR0019
            [Node Format]: Cluster ID: unknown  Node ID: 0   Node Name: ocptest-01.test.int
    key[2]:
            [Numeric Format]:   67,80,71,82,48,48,49,57
            [Character Format]: CPGR0019
            [Node Format]: Cluster ID: unknown  Node ID: 2   Node Name: ocptest-02.test.int
    key[3]:
            [Numeric Format]:   67,80,71,82,48,48,49,57
            [Character Format]: CPGR0019
            [Node Format]: Cluster ID: unknown  Node ID: 2   Node Name: ocptest-02.test.int
    key[4]:
            [Numeric Format]:   68,80,71,82,48,48,49,57
            [Character Format]: DPGR0019
            [Node Format]: Cluster ID: unknown  Node ID: 3   Node Name: ocptest-03.test.int
    key[5]:
            [Numeric Format]:   68,80,71,82,48,48,49,57
            [Character Format]: DPGR0019
            [Node Format]: Cluster ID: unknown  Node ID: 3   Node Name: ocptest-03.test.int
    key[6]:
            [Numeric Format]:   69,80,71,82,48,48,49,57
            [Character Format]: EPGR0019
            [Node Format]: Cluster ID: unknown  Node ID: 4   Node Name: ocptest-04.test.int
    key[7]:
            [Numeric Format]:   69,80,71,82,48,48,49,57
            [Character Format]: EPGR0019
            [Node Format]: Cluster ID: unknown  Node ID: 4   Node Name: ocptest-04.test.int
    key[8]:
            [Numeric Format]:   66,80,71,82,48,48,49,57
            [Character Format]: BPGR0019
            [Node Format]: Cluster ID: unknown  Node ID: 1   Node Name: ocptest-05.test.int
    key[9]:
            [Numeric Format]:   66,80,71,82,48,48,49,57
            [Character Format]: BPGR0019
            [Node Format]: Cluster ID: unknown  Node ID: 1   Node Name: ocptest-05.test.int
    ```

6. With kubeleconfig; no hard eviction should be set if system memory reservations exceeds.

## InfoScale Operator upgrade

1. Connect to OpenShift console.
2. Navigate based on OCP version:
   - OCP < 4.20: `Operator -> Installed Operators`
   - OCP >= 4.20: `Ecosystem -> Software Catalog`
3. Confirm InfoScale operators are listed.
4. Open **InfoScale SDS Operator** -> **Subscription**.
5. Click **Update channel**, select `fast`, then save.
6. Approve pending upgrades in install plans.
7. Wait until upgraded in **Operators -> Installed Operators**.

Notes:
- Multiple hops can be required depending on deployed operator version.
- Example: `8.0.400 -> 8.0.410 -> 9.1.0 -> 9.1.2`
- For `9.1.0 -> 9.1.2`, only one hop is required.

## InfoScale Cluster version upgrade (Software upgrade)

-  Make sure kubelet configuration is applied and configuration rollout is done before software upgrade.

- If recommended kubelet configuration is missed during deployment of 9.x then that needs to be applied before software upgrade.

- Addtional patch is required to apply if upgrading InfoScale from 8.x to 9.1.2

- Change InfoScale Cluster version to latest.

- Trigger platform / OCP upgrade (If applicable)

### Upgrading to InfoScale

Important:

- Upgrading InfoScale from 8.x to 9.x (or to 9.1.2) requires an additional kubelet configuration to enable SDS pod lifecycle hooks. To minimize disruption during the configuration rollout, the schedulable MachineConfig pools must be paused before applying the configuration and unpaused only as instructed in the steps below. Unpausing out of order will trigger an immediate forced rollout.

- If the kubelet configuration was not applied during the initial deployment of InfoScale 9.x, complete the steps below before upgrading to 9.1.2. The preflight CLI will flag this condition if it was missed.

```bash
oc get kubeletconfigs.machineconfiguration.openshift.io
is empty OR without following params

# oc get kubeletconfigs.machineconfiguration.openshift.io -oyaml | grep -i grace
      shutdownGracePeriod: 15m
      shutdownGracePeriodCriticalPods: 5m

And if its present, check whether it's rolled out
It should show kubelet inhibitor(replace the correct node below), if it's not present proceed with given configuration.

# ssh core@ocp-w-02.lab.ocp.lan sudo systemd-inhibit
WHO            UID USER PID  COMM           WHAT     WHY                        MODE
NetworkManager 0   root 1486 NetworkManager sleep    NetworkManager needs to turn off networks  delay
kubelet        0   root 3112 kubelet        shutdown Kubelet needs time to handle node shutdown delay

Above output confirms that kubelet inhibitor is already active on a node (if present, steps A & B give below can be skipped)
```
#### A. Kubeletconfig - Follow if workers and masters both are schedulable

```bash
# Label the MCP

oc label mcp worker machineconfiguration.openshift.io/domain=sched
oc label mcp master machineconfiguration.openshift.io/domain=sched

# Pause both MCPs
oc patch mcp worker --type=merge -p '{"spec":{"paused":true}}'
machineconfigpool.machineconfiguration.openshift.io/worker patched

oc patch mcp master --type=merge -p '{"spec":{"paused":true}}'
machineconfigpool.machineconfiguration.openshift.io/master patched

# Apply common systemd config
oc apply -f https://raw.githubusercontent.com/Arctera/infoscale-kubernetes-enterprise/main/config/sysd/99-common-sysd.yaml

# Apply common kubelet config
oc apply -f https://raw.githubusercontent.com/Arctera/infoscale-kubernetes-enterprise/main/config/kubelet/common-kubelet-config.yaml

# Should show success as -
oc describe kubeletconfigs.machineconfiguration.openshift.io custom-kubelet-config
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
      machineconfiguration.openshift.io/role:  worker   <<< can change as per label
Status:
  Conditions:
    Last Transition Time:  2026-01-16T13:15:00Z
    Message:               Success
    Status:                True
    Type:                  Success
Events:                    <none>
```
#### B. Kubeletconfig - Follow if only - workers are schedulable

```bash
# kubelet config should have the same label present in this case.
oc label mcp worker machineconfiguration.openshift.io/role=worker
machineconfigpool.machineconfiguration.openshift.io/worker labeled

oc patch mcp worker --type=merge -p '{"spec":{"paused":true}}'
machineconfigpool.machineconfiguration.openshift.io/worker patched

oc get mcp worker -oyaml  | grep pause
  paused: true
  
# Apply systemd config

oc apply -f https://raw.githubusercontent.com/Arctera/infoscale-kubernetes-enterprise/main/config/sysd/99-worker-sysd.yaml
machineconfig.machineconfiguration.openshift.io/99-worker-sysd-conf-override created

# Apply kubelet config for worker
oc apply -f https://raw.githubusercontent.com/Arctera/infoscale-kubernetes-enterprise/main/config/kubelet/kubelet-config.yaml
kubeletconfig.machineconfiguration.openshift.io/custom-kubelet-config created
```


Machine config operator will rollout this config only when user unpause / mark pause=false. 

#### Important : Please do not unpause right away. follow the next instructions(At this stage respective machine config pool/ pools are still paused.)

#### If the source InfoScale version is 8.0.4x, you must apply the required patch before proceeding, 

```bash
# Download patch infoscale-patch-8.0.4x.tar.gz from SORT
tar xvzf infoscale-patch-8.0.4x.tar.gz
cd infoscale-patch-8.0.4x
# Apply the patch
./apply-cluster-patch.sh infoscalecluster-dev
# Apply
./apply-cluster-patch.sh infoscalecluster-dev
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
Created symlink /etc/systemd/system/multi-user.target.wants/pod-prestop.service -> /etc/systemd/system/pod-prestop.service.
[INFO]   -> /sbin/vss-util
[INFO]   -> /sbin/vss-stop
[INFO] Processing pod: infoscale-sds-1230-1eb7816cdb4bd7f3-fjpwt
[INFO]   -> /usr/sbin/vxassist
[INFO]   -> /etc/systemd/system/pod-prestop.service
Created symlink /etc/systemd/system/multi-user.target.wants/pod-prestop.service -> /etc/systemd/system/pod-prestop.service.
[INFO]   -> /sbin/vss-util
[INFO]   -> /sbin/vss-stop
[INFO] Processing pod: infoscale-sds-1230-1eb7816cdb4bd7f3-vt2nj
[INFO]   -> /usr/sbin/vxassist
[INFO]   -> /etc/systemd/system/pod-prestop.service
Created symlink /etc/systemd/system/multi-user.target.wants/pod-prestop.service -> /etc/systemd/system/pod-prestop.service.
[INFO]   -> /sbin/vss-util
[INFO]   -> /sbin/vss-stop
[INFO] Processing pod: infoscale-sds-1230-1eb7816cdb4bd7f3-w9ls8
[INFO]   -> /usr/sbin/vxassist
[INFO]   -> /etc/systemd/system/pod-prestop.service
Created symlink /etc/systemd/system/multi-user.target.wants/pod-prestop.service -> /etc/systemd/system/pod-prestop.service.
[INFO]   -> /sbin/vss-util
[INFO]   -> /sbin/vss-stop
[INFO] Patch applied successfully to cluster: infoscalecluster-dev
```

#### Patch InfoScaleCluster version to 9.1.2

with this step, we are triggering software upgrade of InfoScaleCluster

```bash
oc patch infoscalecluster <cluster-name>  -n <namespace>  --type=merge  -p '{"spec":{"version":"9.1.2"}}'
infoscalecluster.infoscale.veritas.com/<namespace> patched
```

Wait for cluster to be in running state and rollout to be complete

```bash
# oc get po -n infoscale-vtas
NAME                                            READY   STATUS        RESTARTS      AGE
infoscale-csi-controller-569fb9fc4-k6ddn        5/5     Running       1 (51s ago)   57s
infoscale-csi-node-c85tf                        2/2     Running       0              27s
infoscale-csi-node-cpwrt                        2/2     Terminating   0              3d5h
infoscale-csi-node-gsx5d                        2/2     Running       0              3d5h
infoscale-csi-node-xfgjn                        2/2     Running       0              3d5h
infoscale-fencing-controller-5b86c59dfd-f7ptw   1/1     Running       0              3d5h
infoscale-fencing-enabler-6mx7d                 1/1     Running       0              3d5h
infoscale-fencing-enabler-j8zgw                 1/1     Running       0              3d5h
infoscale-fencing-enabler-qrxtw                 1/1     Running       0              3d5h
infoscale-fencing-enabler-tjcbk                 1/1     Running       0              3d5h
infoscale-licensing-operator-7bb6cb7d48-5hz5b   1/1     Running       0              3d5h
infoscale-sds-1230-1eb7816cdb4bd7f3-drhlq       1/1     Running       0              3d14h
infoscale-sds-1230-1eb7816cdb4bd7f3-fzdzl       1/1     Running       0              3d5h
infoscale-sds-1230-1eb7816cdb4bd7f3-gf62d       1/1     Running       0              3d5h
infoscale-sds-1230-1eb7816cdb4bd7f3-hq6b9       1/1     Running       0              3d5h
infoscale-sds-operator-66c66c6ccf-wfzv4         1/1     Running       0              3d5h
infoscale-toolset-1230-6bc76b6b96-64flx         1/1     Running       0              2m49s
infoscale-toolset-1230-6bc76b6b96-87jrp         1/1     Running       0              3d5h
infoscale-toolset-1230-6bc76b6b96-mggxs         1/1     Running       0              3d5h
infoscale-toolset-1230-6d9f474779-nwb26         0/1     Running       0              32s
---
# oc get infoscaleclusters -A
NAMESPACE        NAME                   VERSION   CLUSTERID   STATE       DISKGROUPS          STATUS    AGE
infoscale-vtas   infoscalecluster-dev   8.0.400   1230        Upgrading   vrts_kube_dg-1230   Healthy   3d5h
```

#### Wait for completion of software upgrade

At this stage, you will see the changes rolled out first for CSI, fencing, Toolset etc then for SDS cluster will fluctuate between degraded and running state, since one node is going out of cluster and joining again. it will take some time depending on workload running on system

```text
infoscale-vtas   infoscalecluster-dev   8.0.400   1230        Upgrading   vrts_kube_dg-1230   Degraded   38m
infoscale-vtas   infoscalecluster-dev   8.0.400   1230        Upgrading   vrts_kube_dg-1230   Healthy    39m
infoscale-vtas   infoscalecluster-dev   9.1.2     1230        Running     vrts_kube_dg-1230   Healthy    39m
```

#### Enable the paused pools - Sequentially if applicable (If it was paused during kubelet config) if not then do not need to follow this step.

Here, preferably enable / unpause the masters first if schedulable. wait for complete rollout and then do the same with worker pool. Please note that enabling both; does not guarantee applications availability

```bash
oc patch mcp worker --type=merge -p '{"spec":{"paused":false}}'
machineconfigpool.machineconfiguration.openshift.io/worker patched
---
Every 2.0s: oc get no

ocp348-ba1: Tue Jan 20 15:42:12 2026
NAME                      STATUS                     ROLES                  AGE   VERSION
ocp348-m1.test.int        Ready                      control-plane,master   41d   v1.30.7
ocp348-m2.test.int        Ready                      control-plane,master   41d   v1.30.7
ocp348-m3.test.int        Ready                      control-plane,master   41d   v1.30.7
ocp348-w01.test.int       Ready                      worker                 41d   v1.30.7
ocp348-w02.test.int       Ready                      worker                 41d   v1.30.7
ocp348-w03.test.int       Ready                      worker                 41d   v1.30.7
ocp348-w04.test.int       Ready,SchedulingDisabled   worker                 41d   v1.30.7
```

#### Wait for rollout and InfoScaleCluster to be in ready state

if node is taking too long and showing state - NotReady,SchedulingDisabled try resetting the node

```bash
# oc get infoscaleclusters -Aw
NAMESPACE        NAME                   VERSION   CLUSTERID   STATE     DISKGROUPS          STATUS     AGE
infoscale-vtas   infoscalecluster-dev   9.1.2     1230        Running   vrts_kube_dg-1230   Degraded   117m
infoscale-vtas   infoscalecluster-dev   9.1.2     1230        Running   vrts_kube_dg-1230   Healthy    121m
```

## Platform/OpenShift upgrade

For Supported platform refer to section (Give link to section System Requirements -> Supported platforms from release doc)

Below are some exceptions , IKE will not be supported on below OpenShift versions.

| OCP Version | Restriction |
|---|---|
| 4.20.4 | All channels |
| 4.19.19 | All channels |
| 4.18.29 | All channels |
| 4.17.44 | All channels |
| 4.16.53 | All channels |

Note: While performing OCP upgrade, its important know that in full cluster upgrade, both pools i.e. masters and workers rollout in parallel, which will be problem if masters are schedulable.

Hence IKE discourage having masters schedulable. Here user can choose master upgrade first and on completion choose next worker pool upgrade.

Please re-run pre-flight script (Optional) to check InfoScale health status

Proceed with the OpenShift/Platform upgrade as necessary.

During OpenShift upgrade, when machine config operator is getting updated InfoScale cluster will be in OS-Upgrade state as shown below,

```bash
#oc get infoscalecluster -A
NAMESPACE        NAME            VERSION   CLUSTERID   STATE        DISKGROUPS           STATUS     AGE
infoscale-vtas   sanity-ocp416   9.1.2     21432       OS-Upgrade   vrts_kube_dg-21432   Degraded   2d1h
```

Once OpenShift upgrade is successful make sure InfoScale cluster is in “Running” state before performing any operations.

```bash
# oc get infoscalecluster -A
NAMESPACE        NAME            VERSION   CLUSTERID   STATE     DISKGROUPS           STATUS    AGE
infoscale-vtas   sanity-ocp416   9.1.2     21432       Running   vrts_kube_dg-21432   Healthy   2d1h
```

## Troubleshooting

### 1. Paused Upgrade due affined and unmanaged workloads

if any workload which is not owned by ANY of standard kubernetes controllers InfoScale operator will pause the upgrade with following events -

```text
Warning  UpdatePaused  23m (x89 over 41m)   InfoScaleCluster  ErrorCode=10050 ErrorMsg=Resource is not managed by controller : pod test/redis not managed statefulset, replicaset, daemonset on ocptest-01
Warning  UpdatePaused  14m (x4 over 15m)    InfoScaleCluster  to resume upgrade with forced migration of such workloads, annotate InfoScaleCluster with infoscale.veritas.com/forceMigrate=true
```

suggested action in above case -

Admin should handle such workloads, for example simple fleet of pods, pods owned by any operators which are not reconciling them on another node etc

Either take backup and cleanup such resources if possible

If there’s no impact even if such resources are down, annotate the InfoScaleCluster to forceful upgrade as shown earlier in events for example -

```bash
oc annotate infoscaleclusters infoscalecluster-dev infoscale.veritas.com/forceMigrate=true
infoscalecluster.infoscale.veritas.com/infoscalecluster-dev annotated
```

Once the upgrade completed with force option, admin can remove this annotation from InfoScaleCluster resource

### 2. NFD Crash in OCP upgrades from 4.19 -> 4.20

OCP upgrades had been blocked with NFD garbage collector pods were crashing because of some readiness failure as seen below

```text
NAME                                      READY   STATUS    RESTARTS          AGE
nfd-controller-manager-658cccddf9-w9l54   1/1     Running   0                 2d16h
nfd-gc-6b7549bfc4-llv5w                   0/1     Running   1 (35s ago)       75s <<< continesouly restarting
nfd-gc-fbbd48975-g2bw5                    1/1     Running   0                 2d16h
nfd-master-5bb757c8d4-hmdm6               0/1     Running   777 (2m33s ago)   2d16h
nfd-master-7c585f4bf-tswdp                1/1     Running   0                 2d16h
nfd-worker-629wr                          1/1     Running   2 (2d16h ago)     2d16h
nfd-worker-86hd9                          1/1     Running   2 (2d20h ago)     2d21h
. . .
58s         Normal    Pulled             pod/nfd-gc-6b7549bfc4-llv5w       Successfully pulled image "registry.redhat.io/openshift4/ose-node-feature-discovery-rhel9@sha256:5459499aedd2ebd0245d79d6dfed353c5a24c12d54bc97cbc2cecfe2489b792e" in 3.513s (3.513s including waiting). Image size: 617600938 bytes.
32s         Warning   Unhealthy          pod/nfd-gc-6b7549bfc4-llv5w       Liveness probe failed: Get "http://10.128.3.19:8080/healthz": dial tcp 10.128.3.19:8080: connect: connection refused
27s         Warning   Unhealthy          pod/nfd-gc-6b7549bfc4-llv5w       Readiness probe failed: Get "http://10.128.3.19:8080/healthz": dial tcp 10.128.3.19:8080: connect: connection refused
27s         Warning   ProbeError         pod/nfd-gc-6b7549bfc4-llv5w       Readiness probe error: Get "http://10.128.3.19:8080/healthz": dial tcp 10.128.3.19:8080: connect: connection refused...
22s         Warning   ProbeError         pod/nfd-gc-6b7549bfc4-llv5w       Liveness probe error: Get "http://10.128.3.19:8080/healthz": dial tcp 10.128.3.19:8080: connect: connection refused...
22s         Normal    Killing            pod/nfd-gc-6b7549bfc4-llv5w       Container nfd-gc failed liveness probe, will be restarted
22s         Normal    Pulling            pod/nfd-gc-6b7549bfc4-llv5w       Pulling image "registry.redhat.io/openshift4/ose-node-feature-discovery-rhel9@sha256:5459499aedd2ebd0245d79d6dfed353c5a24c12d54bc97cbc2cecfe2489b792e"
18s         Normal    Pulled             pod/nfd-gc-6b7549bfc4-llv5w       Successfully pulled image "registry.redhat.io/openshift4/ose-node-feature-discovery-rhel9@sha256:5459499aedd2ebd0245d79d6dfed353c5a24c12d54bc97cbc2cecfe2489b792e" in 3.457s (3.457s including waiting). Image size: 617600938 bytes.
18s         Normal    Started            pod/nfd-gc-6b7549bfc4-llv5w       Started container nfd-gc
18s         Normal    Created            pod/nfd-gc-6b7549bfc4-llv5w       Created container: nfd-gc
```

Upgrade progressed post deletion of corresponding NFD gc pod. Looks like NFD interacting with OCP cluster operator and blocking further upgrade progress. Below are the exact minor versions where this issue was seen

```json
{
  "completionTime": "2026-02-06T13:02:05Z",
  "image": "quay.io/openshift-release-dev/ocp-release@sha256:91606a5f04331ed3293f71034d4f480e38645560534805fe5a821e6b64a3f203",
  "startedTime": "2026-02-06T11:38:41Z",
  "state": "Completed",
  "verified": true,
  "version": "4.20.8"
},
{
  "completionTime": "2026-02-06T06:25:59Z",
  "image": "quay.io/openshift-release-dev/ocp-release@sha256:7c2001c24aa550aa228cd2d0fc0b5d9ac6656cd4267cd7c156ec758d0687758e",
  "startedTime": "2026-02-06T05:03:33Z",
  "state": "Completed",
  "verified": true,
  "version": "4.19.21"
}
```

### 3. Operators are not upgrading even after Install plan approval is completed

Since InfoScale operator has the dependency on License operator; both of these share the same operator group; resulting into such inconsistencies. Typically both operators create 2 install plans, only one of it has both sub components listed in owners. When user approves install plan, select the one which shows both of the operators sub in preview section

### 4. Transient node drain failures in OCP-V upgrades

User can observe following harmless error messages / alerts while upgrading OpenShift virtuliazation platform

```text
error when evicting pods/"virt-launcher-<VMNAME>" -n "<NAMESPACE>" (will retry after 5s):
```

related details can be found in this RedHat knowledge base - https://access.redhat.com/solutions/7067725

related articles states that these messages can safely be ignored; as these pod disruption budges can expanded runtime for migration of VirtualMachine resources

### 5. Resource busy/Node busy error during InfoScale upgrade

Upgrade from 8.x to 9.x gets stuck with Resource Busy if there stale / incorrect snapshot relationships and tags are present inside InfoScale SDS pods, because of this SDS operator repeatedly see “node busy” or in-progress volume/snapshot sync.

If pre-flight CLI reports such snapshots delete those using below stale snapshot cleanup script, this script is part of infoscale-tools-v9.1.2.tar

```bash
Usage:
./snapshot_cleanup.sh -n <namespace> -p <pod_name> [-g <diskgroup>] [-d]

Options:
-n <namespace>: The OpenShift namespace where the pod is located (required).
-p <pod_name>: The name of the InfoScale SDS pod (required).
Usage:
./snapshot_cleanup.sh -n <namespace> -p <pod_name> [-g <diskgroup>] [-d]
Options:
-n <namespace>: The OpenShift namespace where the pod is located (required).
-p <pod_name>: The name of the InfoScale SDS pod (required).
-g <diskgroup>: Specific disk group to process (optional). If not specified, all disk groups will be processed.
-d: Dry-run mode. Displays the commands that would be executed without performing any actual deletions (optional).
Example:
./snapshot_cleanup.sh -n infoscale-vtas -p infoscale-sds-21432-7820e9290fa0fc26-b9phd -g vrts_kube_dg-1121
-g <diskgroup>: Specific disk group to process (optional). If not specified, all disk groups will be processed.
-d: Dry-run mode. Displays the commands that would be executed without performing any actual deletions (optional).

Example:
./snapshot_cleanup.sh -n infoscale-vtas -p infoscale-sds-21432-7820e9290fa0fc26-b9phd -g vrts_kube_dg-1121
```

### 6. Failed VM migrations due to timeouts - InfoScale upgrade is in paused state

This can be observed in InfoScaleCluster upgrade if,

- There’s contention in cluster, resource heaviness and not enough bandwidth is set for VM migration
- Some migration policy overriding the default bandwidth and limiting the group of VMs for migration from source node to others
- Too many parallel writes, constantly dirtying out the pages which are not getting flushed properly
- Migrations taking too long to complete

In Any of such cases; InfoScale operator currently wait for user to take action and remediate the VirtualMachineMigration resource which is in error state. if errored because of timed out as shown below -

```bash
# oc describe vmim  infoscale-fio-vm-1-114880f98092cdab -n prod
Name:         infoscale-fio-vm-1-114880f98092cdab
Namespace:    prod
Labels:       kubevirt.io/vmi-name=fio-vm-1
Annotations:  kubevirt.io/latest-observed-api-version: v1
              kubevirt.io/storage-observed-api-version: v1
API Version:  kubevirt.io/v1
Kind:         VirtualMachineInstanceMigration
Metadata:
  Creation Timestamp:  2026-03-12T13:17:59Z
  Generation:          1
  Resource Version:    4628614
  UID:                 6b39e1cc-2e8f-4d44-a644-e559319185d4
Spec:
  Vmi Name:  fio-vm-1
Status:
  Migration State:
    Abort Status:    Succeeded
    Completed:       true
    End Timestamp:   2026-03-12T13:18:15Z
    Failed:          true
    Failure Reason:  Live migration is not completed after #Num seconds and has been aborted <<<
    Migration Configuration:
      Allow Auto Converge:                    true
      Allow Post Copy:                        false
    . . .
# oc describe infoscaleclusters -n infoscale-vtas kubeburner  | grep Pause
  Warning  UpdatePaused  164m (x7 over 168m)  InfoScaleCluster  migration instance infoscale-fio-vm-8-c74edd9fa2a14506 is failed in prod, upgrade is waiting for its completion; user intervention required
  Warning  UpdatePaused  164m (x7 over 168m)  InfoScaleCluster  migration instance infoscale-fio-vm-5-24c5edc43025ba88 is failed in prod, upgrade is waiting for its completion; user intervention required
  . . .
```

To remediate such timeouts; user can simply delete the corresponding virtual machine migration, operator will re-try the same again and proceed with the upgrade.

To avoid hitting this again, we suggest following configuration changes -

-  Set allowAutoConverge: true in kubevirt resource, if set as false

-  If memory violations alerts are also seen in web console, related to system memory reservation exceeds certain limit, you can optionally increase system slice
   memory on schedulable nodes, keep in mind that this configuration requires rollout.
 
   Details can be found here; in 2 point -
   https://docs.redhat.com/en/documentation/openshift_container_platform/4.20/html/nodes/working-with-nodes#nodes-nodes-managing-about_nodes-nodes-managing
     
   Though above page sets very less memory, broad suggestion is to have -
   systemReserved.memory     = min( max(2G, 5% of totalRAM of node), 8Gi )
   This is upto cluster admin to decide this reservation; based upon surge, bandwidth and node management constraints.

## Limitations

Following are the upgrade constraints that should be considered for current release

- Single node InfoScaleCluster resource is not upgradable in any storage configurations; for obvious reasons as there’s no other compute to move the workload
- Cluster deployed with Flexible storage sharing configuration (FSS); upgrade of such cluster is not supported
