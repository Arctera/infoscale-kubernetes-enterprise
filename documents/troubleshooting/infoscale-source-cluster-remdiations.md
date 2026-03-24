# Source cluster troubleshooting

## Table of Contents

- [Disk Management](#disk-management)
- [Diskgroup Management](#diskgroup-management)
- [Volume and Snapshot Operations](#volume-and-snapshot-operations)
  - [1. If Volume is DISABLED](#1-if-volume-is-disabled)
  - [2. If Volume is DETACHED](#2-if-volume-is-detached)
  - [3. If There Are Incorrect Snapshot Relationships Flagged by Preflight](#3-if-there-are-incorrect-snapshot-relationships-flagged-by-preflight)
  - [4. Pre-Upgrade Cache-Object Mirror Check](#4-pre-upgrade-cache-object-mirror-check-pre-req-for-upgrade-from-80410---9x-with-fss-diskgroup)
- [Cluster Node Status](#cluster-node-status)

## Disk Management

### 1. Identify Disks in Error

If disks are in error state, login to any SDS pod and,

Run:

```bash
oc exec -ti -n <namespace> <infoscale-sds-pod> -- bash
/opt/VRTS/bin/hacli -cmd "vxdisk list"
```

Look for disks with STATUS = error.

### 2. Verify OS and Storage Visibility

Run:

```bash
lsblk
```

If disk is not visible, fix SAN/storage/multipath issue first.

### 3. Check VxVM and Path Status

Run:

```bash
/opt/VRTS/bin/hacli -cmd "vxdisk -o alldgs list"
/opt/VRTS/bin/hacli -cmd "vxdisk path"
```

Ensure paths are available and disk is accessible.

### 4. Rescan and Refresh VxVM

Run:

```bash
/opt/VRTS/bin/hacli -cmd "vxdisk scandisks"
```

### 5. Bring Disk Online (If Accessible)

Run:

```bash
/opt/VRTS/bin/hacli -cmd "vxdisk online <diskname>"
```

### 6. If Multipath/Path Issue Is Resolved

Run:

```bash
/opt/VRTS/bin/hacli -cmd "vxdmpadm enable path=<path>"
/opt/VRTS/bin/hacli -cmd "vxdisk online <diskname>""
```

## Diskgroup Management

Note: For issues related to Diskgroup Management, please contact InfoScale support.

## Volume and Snapshot Operations

### 1. If Volume is DISABLED

A volume in DISABLED state means it is not active and cannot be accessed. To bring it back online:

Check volume status by login into any SDS pod:

```bash
oc exec -ti -n <namespace> <infoscale-sds-pod> -- bash
/opt/VRTS/bin/hacli -cmd "vxprint -g <diskgroup> -ht"
```

Start the volume:

```bash
vxvol -g <diskgroup> start <volume_name>
```

Verify the volume is now ENABLED:

```bash
/opt/VRTS/bin/hacli -cmd "vxprint -g <diskgroup> -v"
```

### 2. If Volume is DETACHED

A volume in DETACHED state means one or more plexes have been detached due to I/O errors or path issues.

Check volume and plex status by login into any SDS pod:

```bash
oc exec -ti -n <namespace> <infoscale-sds-pod> -- bash
/opt/VRTS/bin/hacli -cmd "vxprint -g <diskgroup> -ht"
```

If plex is detached then reattach the detached plex

```bash
vxplex -g <diskgroup> att <volume_name> <plex_name>
```

If plex is attached then try to start the volume

```bash
vxvol -g <diskgroup> start <volume_name>
```

Monitor resync progress:

```bash
/opt/VRTS/bin/hacli -cmd "vxtask list"
```

Verify volume state returns to ENABLED/ACTIVE:

```bash
/opt/VRTS/bin/hacli -cmd "vxprint -g <diskgroup> -v"
```

### 3. If There Are Incorrect Snapshot Relationships Flagged by Preflight

If preflight has flagged stale or incorrect snapshot relationships, clean them up using the snapshot_cleanup.sh script included in 
#### infoscale-tools-v9.1.2.tar.

Usage:

```bash
./snapshot_cleanup.sh -n <namespace> -p <pod_name> [-g <diskgroup>] [-d]
```

Options:

| Option | Description |
|---|---|
| -n <namespace> | The OpenShift namespace where the pod is located (required) |
| -p <pod_name> | The name of the InfoScale SDS pod (required) |
| -g <diskgroup> | Specific disk group to process (optional). If not specified, all disk groups will be processed |
| -d | Dry-run mode. Displays the commands that would be executed without performing any actual deletions (optional) |

Example:

```bash
./snapshot_cleanup.sh -n infoscale-vtas -p infoscale-sds-21432-7820e9290fa0fc26-b9phd -g vrts_kube_dg-1121
```

Tip: Always run with -d (dry-run) first to review what will be deleted before performing actual cleanup.

### 4. Pre-Upgrade Cache-Object Mirror Check (Pre-req for upgrade from 8.0.410 -> 9.x with FSS diskgroup)

This is not applicable for shared diskgroup.

Before upgrading, verify that the cache-object backing the snapshot volume is mirrored. If it is not mirrored, use vxassist mirror to mirror the backend volume of the cache object.

Check and mirror the existing cache-object backend:

Login to any SDs pod

```bash
oc exec -ti -n <namespace> <infoscale-sds-pod> -- bash
# Get the backend volume of the cache object for the given snapshot volume
_sc_name=`vxprint -g vrts_kube_dg-41845 snap5 | grep "^sc " | awk '{print \$2}'`
_cache_name=`vxprint -g vrts_kube_dg-41845 -F%dm_name \$_sc_name`
# Mirror the backend volume of the cache object
vxassist -g vrts_kube_dg-41845 mirror \$_cache_name
# Wait for mirroring to finish
vxtask list
```

#### Recommended Snapshot Creation Workflow (Fix for Unmirrored Cache Object)

The current VIKE snapshot creation does not honour FSS mirror attributes for the internal cache object. The following change is needed in the snapshot creation workflow to ensure the cache object backend volume is properly mirrored.

Current (broken) workflow:

```bash
# Volume is created with mirror layout (correct)
vxassist -g vrts_kube_dg-41845 make vol5 2097152 layout=mirror
# But the internal cache object created here does NOT follow the FSS mirror attribute
vxsnap -g vrts_kube_dg-41845 make source=vol5/new=snap5/cachesize=2097152
```

Recommended workflow:

```bash
# Step 1: Create the source volume
vxassist -g vrts_kube_dg-41845 make vol5 2097152
# Step 2: Create a backend volume for the cache object
# On FSS this will be mirrored across nodes by default
vxassist -g vrts_kube_dg-41845 make cache_vol_backend 2097152
# Step 3: Create the cache object using the mirrored backend volume
vxmake -g vrts_kube_dg-41845 cache snap_cache cachevolname=cache_vol_backend
# Step 4: Start the cache
vxcache -g vrts_kube_dg-41845 start snap_cache
# Step 5: Create the snapshot using the explicit cache
# The same cache object can be reused for multiple snapshots
vxsnap -g vrts_kube_dg-41845 make source=vol5/new=snap5/cache=snap_cache
```

## Cluster Node Status

Note: For issues related to Cluster Node Status, please contact InfoScale support.
