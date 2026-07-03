# Preflight guide for InfoScale upgrade and fresh install

Run preflight checks before an InfoScale upgrade or fresh installation to identify potential issues early and prevent unexpected disruption during maintenance.

---

## Downloading the preflight tool

The preflight tool is available at:  
[https://github.com/Arctera/infoscale-kubernetes-enterprise/tree/main/scripts/preflight](https://github.com/Arctera/infoscale-kubernetes-enterprise/tree/main/scripts/preflight)

Choose the option that best fits your environment.

### Option 1 — Bundled with the InfoScale tools package (recommended)

If you have the InfoScale tools package, the preflight tool is already included. Navigate directly to the preflight directory:

```
cd /infoscale-tools-v<version>/preflight
```

No additional download is needed.

### Option 2 — Download via curl or wget

Download the repository as a ZIP archive and extract only the preflight directory. No git required.

**Using curl:**

```
curl -fsSL https://github.com/Arctera/infoscale-kubernetes-enterprise/archive/refs/heads/main.zip \
  -o infoscale-ike.zip
unzip infoscale-ike.zip "infoscale-kubernetes-enterprise-main/scripts/preflight/*" -d .
mv infoscale-kubernetes-enterprise-main/scripts/preflight ./preflight
rm -rf infoscale-ike.zip infoscale-kubernetes-enterprise-main
cd preflight
chmod +x preflight-cli.sh
```

**Using wget:**

```
wget -q https://github.com/Arctera/infoscale-kubernetes-enterprise/archive/refs/heads/main.zip \
  -O infoscale-ike.zip
unzip infoscale-ike.zip "infoscale-kubernetes-enterprise-main/scripts/preflight/*" -d .
mv infoscale-kubernetes-enterprise-main/scripts/preflight ./preflight
rm -rf infoscale-ike.zip infoscale-kubernetes-enterprise-main
cd preflight
chmod +x preflight-cli.sh
```

### Option 3 — Browser download (no CLI required)

1. Go to [https://github.com/Arctera/infoscale-kubernetes-enterprise](https://github.com/Arctera/infoscale-kubernetes-enterprise)
2. Click **Code → Download ZIP**.
3. Extract the archive and navigate to `scripts/preflight/`.
4. Run `chmod +x preflight-cli.sh` to make the script executable.

### Option 4 — Air-gapped / no internet access

If the target machine has no internet access:

1. On an internet-connected machine, use Option 2 or Option 3 to obtain the `preflight/` directory.
2. Transfer it to the target machine via SCP, USB, or your internal file transfer method.

---

## Make the script executable

After downloading, ensure the script has execute permission:

```
chmod +x preflight-cli.sh
```

## Directory structure

```
preflight/
├── preflight-cli.sh
├── lib/
│   └── data/
│       └── upgrade_paths.json
└── preflight-rules/
    ├── 01-platform.sh
    ├── 02-ike-versions.sh
    ├── 03-sourceclust.sh
    └── 04-workload-sanity.sh
```

---

## Upgrade compatibility matrix

Download the latest upgrade compatibility matrix before each execution.

**Using curl:**

```
curl -fsSL \
  https://raw.githubusercontent.com/Arctera/infoscale-kubernetes-enterprise/main/data/upgrade_paths.json \
  -o ./lib/data/upgrade_paths.json
```

**Using wget:**

```
wget -q -O ./lib/data/upgrade_paths.json \
  https://raw.githubusercontent.com/Arctera/infoscale-kubernetes-enterprise/main/data/upgrade_paths.json
```

**No internet access?** Download the file from an internet-connected machine and transfer it to `lib/data/upgrade_paths.json` before running the preflight check.

---

---

## Fresh Install

Run preflight before a fresh InfoScale installation to verify the platform meets all prerequisites. Only `01-platform.sh` runs in fresh install mode — upgrade-specific rules are skipped automatically.

### Running fresh install preflight

Navigate to the preflight directory and run:

```
./preflight-cli.sh --type fresh-install --target-ike 9.2.0
```

Interactive mode is also available: run `./preflight-cli.sh` without flags and select **2) Fresh Install** when prompted.

### Example output

```
[root@bastion preflight]# ./preflight-cli.sh --type fresh-install --target-ike 9.2.0

[INFO]  ==============================================================
[INFO]   Preflight Check - Tue Jun 16 14:30:15 IST 2026
[INFO]   Installation Type : fresh-install
[INFO]   Target IKE        : 9.2.0
[INFO]  ==============================================================
[INFO]  Selected rules    : 01-platform (default for fresh-install)
[INFO]  Skipping rule (mode/selection filter): 02-ike-versions.sh
[INFO]  Skipping rule (mode/selection filter): 03-sourceclust.sh
[INFO]  Skipping rule (mode/selection filter): 04-workload-sanity.sh

-----------------------------------------------------------------------------------------------------
[Platform]
-----------------------------------------------------------------------------------------------------
[INFO]  [Platform] Current OCP version: 4.18.32
[INFO]  [Platform] Target IKE version : 9.2.0
[INFO]  [Platform] IKE version 9.2.0 is supported on current OCP 4.18.32 for fresh install
[INFO]  [Platform] All ClusterOperators are healthy and stable.
[INFO]  [Platform] Expected kubelet config is applied and rolled out.
[INFO]  [Platform] All worker nodes: NTP is synced (Leap status Normal)
[INFO]  [Platform] All expected registries are configured correctly.
[ERROR] [Platform] Detected node(s) that are both master/control-plane and worker (schedulable master):
   - master-0.example.com
   - master-1.example.com
   - master-2.example.com
[ERROR] [Platform] With masters schedulable, InfoScale workloads may co-locate with OpenShift
         control-plane components on the same node.
[ERROR] [Platform] This can cause port conflicts between InfoScale services and control-plane
         components (controller-manager).
[ERROR] [Platform] Recommendation: dedicate worker-only nodes for InfoScale, or verify InfoScale
         port ranges do not overlap with control-plane bindings before proceeding.

========== PRE-FLIGHT SUMMARY ==========
01-platform.sh : Some checks failed
========================================

All output saved to:  /infoscale-tools-v9.2.0/preflight/logs/preflight-20260616-143007/preflight.log
VxREST logs saved to: /infoscale-tools-v9.2.0/preflight/logs/preflight-20260616-143007/consolidated_vxrest_logs.log
Run log directory:    /infoscale-tools-v9.2.0/preflight/logs/preflight-20260616-143007
Run log archive:      /infoscale-tools-v9.2.0/preflight/logs/preflight-20260616-143007.zip
```

### Log save location

Logs are saved under the directory where the preflight tool is located:

| File | Contents |
| --- | --- |
| preflight.log | Full run output with all checks |
| consolidated_vxrest_logs.log | VxREST API logs collected from SDS pods |
| Run directory | Timestamps and manifests saved during the run |
| Zip archive | Compressed copy of the run directory |

To search the log for errors:

```
grep -E "\[ERROR\]|\[WARN\]" /infoscale-tools-v9.2.0/preflight/logs/preflight-YYYYMMDD-HHMMSS/preflight.log
```

### Common findings and remediation (fresh install)

All findings in fresh install mode come from `01-platform.sh`. These same platform findings apply during an upgrade too — see the upgrade section for additional upgrade-specific guidance.

| Finding | Example output | Remediation |
| --- | --- | --- |
| IKE version not supported on current OCP | `[ERROR] [Platform] IKE version 9.2.0 is NOT supported on current OCP 4.15.x for fresh install` | Upgrade OCP to a version that supports the target IKE release. Refer to the InfoScale support matrix. |
| ClusterOperator unavailable or degraded | `[ERROR] [Platform] Unavailable ClusterOperators:` followed by list, or `[ERROR] [Platform] Degraded ClusterOperators:` followed by list | Investigate: `oc get co <name>` and `oc describe co <name>`. Resolve before proceeding. |
| Kubelet inhibitor config not applied or rollout not visible on workers | `[ERROR] [Platform] Expected kubelet config is not applied.` or `[ERROR] [Platform] Kubelet config reports Success, but rollout is not visible on worker node.` | Apply the required kubelet configuration (shutdownGracePeriod: 15m, shutdownGracePeriodCriticalPods: 5m) and wait for the MachineConfig rollout to complete on all worker nodes. Refer to the Prerequisites section of the InfoScale for Kubernetes 9.2.0 Administrator's Guide. |
| NTP not synced on worker node | `[WARN] [Platform] <node>: NTP may not be synced` | Verify chrony/NTP configuration: `chronyc tracking`. Ensure the node can reach its NTP source. |
| Expected registries missing | `[WARN] [Platform] Missing expected registries:` followed by list | Configure missing registries. |
| Schedulable master nodes detected | `[ERROR] [Platform] Detected node(s) that are both master/control-plane and worker (schedulable master):` followed by list | If masters must remain schedulable, ensure master nodes are **not** included in the InfoScaleCluster CR. |

### Pre-install checklist

Before proceeding with a fresh install, confirm each item:

* Platform checks passed ([01-platform.sh](http://01-platform.sh))
* All ClusterOperators are healthy and stable
* Kubelet inhibitor config applied and rollout visible on all worker nodes
* NTP synchronized across all worker nodes
* Required image registries are accessible
* `mastersSchedulable` is set to `false` (or InfoScale workloads are confirmed not to land on master nodes)

**If all items are confirmed:** Proceed with the fresh install.  
**If any item is unresolved:** Fix those issues first, then rerun preflight.

---

---

## Upgrade

Run preflight before upgrading InfoScale to identify risks across all four rule areas.

| Rule file | What it checks |
| --- | --- |
| [01-platform.sh](http://01-platform.sh) | Cluster health, kubelet, NTP, registries |
| [02-ike-versions.sh](http://02-ike-versions.sh) | Upgrade compatibility matrix |
| [03-sourceclust.sh](http://03-sourceclust.sh) | Source InfoScale cluster health: split brain, disk/diskgroup/volume health, snapshot associations, fencing |
| [04-workload-sanity.sh](http://04-workload-sanity.sh) | Workload and PVC readiness |

### Running upgrade preflight

Navigate to the preflight directory and run:

```
./preflight-cli.sh --type upgrade --target-ike 9.2.0 --target-ocp 4.20.23 --all
```

`--all` runs all applicable rules and is recommended for a thorough pre-upgrade check.

Interactive mode is also available: run `./preflight-cli.sh` without flags and select **1) Upgrade** when prompted.

### Log save location

```
All output saved to:  /infoscale-tools-v<version>/preflight/logs/preflight-YYYYMMDD-HHMMSS/preflight.log
VxREST logs saved to: /infoscale-tools-v<version>/preflight/logs/preflight-YYYYMMDD-HHMMSS/consolidated_vxrest_logs.log
Run log directory:    /infoscale-tools-v<version>/preflight/logs/preflight-YYYYMMDD-HHMMSS
Run log archive:      /infoscale-tools-v<version>/preflight/logs/preflight-YYYYMMDD-HHMMSS.zip
```

### Checking for failures

At the end of the run, review the summary:

```
========== PRE-FLIGHT SUMMARY ==========
04-workload-sanity.sh : Some checks failed
03-sourceclust.sh     : Some checks failed
01-platform.sh        : All checks passed
02-ike-versions.sh    : All checks passed
=========================================
```

For any rule that reports **Some checks failed**, search the log:

```
grep -E "\[ERROR\]|\[WARN\]" /infoscale-tools-v9.2.0/preflight/logs/preflight-YYYYMMDD-HHMMSS/preflight.log
```

### Common findings and remediation (upgrade)

#### Platform checks (`01-platform.sh`)

The same platform findings and remediations apply during an upgrade. See the fresh install **Common findings and remediation** table above for the full list.

**Upgrade-specific note for platform findings:**

* **OCP channel:** Before initiating an OCP or combined upgrade, set the update channel to the required version:

    ```
    oc patch clusterversion version --type=merge -p '{"spec":{"channel":"stable-4.20"}}'
    ```

    Replace `stable-4.20` with the target channel (e.g., `stable-4.19`, `eus-4.18`).



#### IKE version upgrade compatibility (`02-ike-versions.sh`)

| Finding | Example output | Remediation |
| --- | --- | --- |
| IKE not supported on target OCP | `[ERROR] [IKE & OCP Upgrade Compatibility] IKE 9.2.0 is NOT supported on OCP 4.20.23` | Verify the InfoScale support matrix and select a supported OCP target version. |
| Invalid IKE upgrade path | `[ERROR] [IKE & OCP Upgrade Compatibility] Invalid IKE upgrade path: <current> -> 9.2.0` | Follow the required intermediate hops (e.g., 8.0.400 → 8.0.410 → 9.1.0 → 9.1.2). Refer to the upgrade compatibility matrix. |
| InfoScaleCluster CR not found | `[ERROR] [IKE & OCP Upgrade Compatibility] No infoscalecluster found` | Verify the InfoScaleCluster is deployed: `oc get infoscaleclusters -A`. |

#### Source cluster checks (`03-sourceclust.sh`)

| Finding | Example output | Remediation |
| --- | --- | --- |
| Split brain detected | `[ERROR] [IKE Source Cluster Health] Split brain DETECTED on disk <disk> in pod <pod>` followed by `[ERROR] [IKE Source Cluster Health] Expected <N> nodes but only <M> are registered with a known name` | Do not proceed. Verify SCSI reservations and cluster interconnect connectivity. Confirm whether this is a genuine split brain or a false positive (excluded disks lacking keys). Resolve fully before any upgrade activity. |
| SCSI key node identity unknown | `[ERROR] [IKE Source Cluster Health] Disk <disk>: <N> SCSI key(s) have Node Name reported as 'Unknown'` followed by `[ERROR] [IKE Source Cluster Health] This indicates a node identity resolution failure` | Investigate SCSI registration key ownership: `vxfenadm -s /dev/vx/rdmp/<dmpnodename>`. Resolve the node identity failure before upgrading. |
| Diskgroup not imported | `[WARN] [IKE Source Cluster Health] Diskgroup not imported in pod <pod>` | Check diskgroup status inside the SDS pod: `vxdg list`. Investigate why the diskgroup is not imported and resolve before proceeding. |
| Disk errors detected | `[ERROR] [IKE Source Cluster Health] Disk errors detected inside pod <pod> on node <node>` | Check disk status inside the SDS pod: `vxdisk -o alldgs list`. Resolve all disk errors before proceeding. |
| Volume in NEEDSYNC or not active/enabled | `[WARN] [IKE Source Cluster Health] Some volumes/snapshots in pod <pod> are in NEEDSYNC state` or `[WARN] [IKE Source Cluster Health] Some volumes in pod <pod> are not active/enabled` | Check volume status inside the SDS pod: `vxprint -g <dgname> -ht`. Resync: `vxvol -g <dgname> resync <volname>`. Wait for sync to complete: `vxtask list`. Do not proceed while sync is in progress. |
| Snapshot parent-child associations found | `[WARN] [IKE Source Cluster Health] Found snapres child volumes with snap parent snapshots in pod <pod> on node <node>` followed by `[WARN] [IKE Source Cluster Health] Diskgroup: <dg> (<N> associations)` | Review and clean up snapshots inside the SDS pod: `vxsnap -g <diskgroup_name> list`. Contact InfoScale Support if associations cannot be safely removed. |
| Fencing spec/status mismatch (shared / SCSI-3PR setup) | `[ERROR] [IKE Source Cluster Health] <ns>/<name>: fencing disks mismatch for node <node>; spec and status must match exactly in sequence` | Check fencing disk configuration: `vxfenconfig -l`. Verify the fencing disk list in the InfoScaleCluster CR spec matches the status. Resolve all mismatches before proceeding. |
| Background VxVM tasks running | `[WARN] [IKE Source Cluster Health] Background VxVM tasks detected in pod <pod>` followed by `[WARN] [IKE Source Cluster Health] Active task : <task details>` | Wait for sync tasks to complete: `vxtask list` inside the SDS pod. Do not proceed while background tasks are active. |

#### Workload sanity (`04-workload-sanity.sh`)

| Finding | Block upgrade? | When safe to proceed |
| --- | --- | --- |
| PVC not bound | Yes | After fixing the storage misconfiguration |
| Pod in unexpected Pending / CrashLoopBackOff / ContainerCreating state | Yes | After investigating and resolving the root cause |
| Job using InfoScale CSI | Yes — pauses the software upgrade | Script reports: `ERROR: Job uses InfoScale CSI-backed PVC`.  
Remove the Job, or apply the `infoscale.veritas.com/forceMigrate=true` annotation on the `InfoScaleCluster` CR. The upgrade resumes automatically once the condition is cleared. For combined upgrade, Jobs using InfoScale CSI are not a blocking check.  
**Note:** If the flagged Jobs are caused by hot-plugged disks on a running VM, see the row below — stop the VM instead of deleting the Jobs directly. |
| VM with hot-plugged disks (reported as Job using InfoScale CSI) | Yes — pauses the software upgrade; No action for combined upgrade | Kubevirt creates Job resources to manage hot-plug disk attachments. When those disks use InfoScale CSI, the script flags them as `ERROR: Job uses InfoScale CSI-backed PVC` — the same error as regular Jobs. For a software-only upgrade, **stop the VM** before proceeding. Stopping the VM removes the hot-plug attachment Jobs automatically. Do not delete the Jobs directly. For combined upgrade, no action is required. |
| **Pod using InfoScale CSI with no rescheduling path** (single-node bound pod, or pod without an owner reference) | Yes — pauses the software upgrade; No action for combined upgrade | For standard software upgrade: delete the pod, or apply the `infoscale.veritas.com/forceMigrate=true` annotation on the `InfoScaleCluster` CR. The upgrade resumes automatically once the condition is cleared. Note: pods without an owner reference are not recreated automatically after deletion. For combined upgrade, no action is required. |
| Single-node bound Deployment / ReplicaSet / StatefulSet (not using InfoScale CSI) | No — informational | The workload will be unavailable while its current node is draining if no other node satisfies its scheduling constraints. Remove the single-node binding (nodeSelector/nodeAffinity) to allow rescheduling, or ensure another suitable node exists before the upgrade begins. |
| Single-node bound Deployment / ReplicaSet / StatefulSet (using InfoScale CSI) | No — informational | The application will be unavailable while its node is being upgraded if no other node satisfies its scheduling constraints. This does not block the upgrade. If downtime is acceptable, no action is required. Otherwise, ensure another schedulable node is available before the upgrade begins. |
| Single-node bound VM using InfoScale CSI | Yes | After removing the placement constraint and validating that the VM can migrate to another node |
| HostPath-provisioned VM | Yes (OCP/combined upgrade) | After stopping the VM before the upgrade begins |
| High-priority workload (PriorityClass higher than CSI DaemonSet) | Yes | After scaling down to 0 or lowering the PriorityClass below the InfoScale CSI node priority |

### Pre-upgrade checklist

Before proceeding, confirm each item:

* No active split-brain condition
* All diskgroups, disks, and volumes are healthy
* No background VxVM sync tasks running
* Fencing spec and status are consistent (shared / SCSI-3PR setups)
* All InfoScale CSI-backed PVCs are bound
* No pods in unexpected Pending / CrashLoopBackOff / ContainerCreating state
* No Jobs using InfoScale CSI (standard upgrade) or Jobs removed/force-annotated (combined upgrade)
* VMs with hot-plugged disks stopped before upgrade (software upgrade only — Kubevirt hot-plug attachment Jobs are reported as `ERROR: Job uses InfoScale CSI-backed PVC` by the script and will pause the software upgrade; stop the VM to clear them; no action required for combined upgrade)
* No pods using InfoScale CSI that cannot be rescheduled (single-node bound or without owner reference) — deleted or force-annotated (standard upgrade); no action needed for combined upgrade
* Single-node bound Deployments/ReplicaSets/StatefulSets reviewed; another schedulable node is available if downtime is not acceptable
* No single-node bound InfoScale CSI VMs (or placement constraint removed and failover validated)
* Applications with PriorityClass higher than InfoScale CSI are scaled down to 0 or reprioritized
* HostPath-provisioned VMs stopped (OCP or combined upgrade)
* `If mastersSchedulable` please make sure masters are not included in InfoScale CR.
* OCP update channel set to the required 4.x version (for OCP or combined upgrade)

**If all items are confirmed:** Proceed with the upgrade.  
**If any critical item is unresolved:** Fix those issues first, then rerun preflight.

### Rerun after fixes

After fixing issues, run preflight again until all required rules pass:

```
./preflight-cli.sh --type upgrade --target-ike 9.2.0 --target-ocp 4.20.23 --all
```
