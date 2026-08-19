# Kubelet Shutdown Hook Configuration

Before fresh installation of InfoScale 9.2.0, ensure kubelet shutdown grace settings are configured and rolled out.

To enable kubelet's graceful shutdown inhibitor on nodes, users must apply two configurations in the following order:

1. **systemd change with machine config** — Extends `InhibitDelayMaxSec` so systemd honors kubelet's shutdown inhibitor for the full grace period.
2. **Kubelet Configuration shutdown grace periods** — Defines how long kubelet will wait for regular and critical pods during shutdown.

Both configurations trigger MCP updates and node reboots, so they should be applied deliberately.

---

## 1) Verify KubeletConfig

```shell
oc get kubeletconfigs.machineconfiguration.openshift.io
oc get kubeletconfigs.machineconfiguration.openshift.io -oyaml | grep -i grace
```

**Required values:**

- `shutdownGracePeriod`: 15m
- `shutdownGracePeriodCriticalPods`: 5m

If missing, apply configuration using the matching flow below.

---

## 2) If above kubeletconfig exists, verify rollout on nodes

```shell
ssh core@<worker-node> sudo systemd-inhibit
WHO            UID USER PID  COMM           WHAT     WHY                                        MODE
NetworkManager 0   root 3339 NetworkManager sleep    NetworkManager needs to turn off networks  delay
kubelet        0   root 5476 kubelet        shutdown Kubelet needs time to handle node shutdown delay
```

**Expected kubelet line:**

- COMM: `kubelet`
- WHAT: `shutdown`
- MODE: `delay`

If kubelet inhibitor is present, config is already effective — the process below can be skipped.

---

## Config A: Worker and Master are schedulable

```shell
oc label mcp worker machineconfiguration.openshift.io/domain=sched
oc label mcp master machineconfiguration.openshift.io/domain=sched
oc patch mcp worker --type=merge -p '{"spec":{"paused":true}}'
oc patch mcp master --type=merge -p '{"spec":{"paused":true}}'
oc apply -f https://raw.githubusercontent.com/Arctera/infoscale-kubernetes-enterprise/main/config/sysd/99-common-sysd.yaml
oc apply -f https://raw.githubusercontent.com/Arctera/infoscale-kubernetes-enterprise/main/config/kubelet/common-kubelet-config.yaml
oc describe kubeletconfigs.machineconfiguration.openshift.io custom-kubelet-config
```

**Success criteria:**

- Type: `Success`
- Status: `True`
- Grace values show `15m` and `5m`

**Unpause MCPs paused in this flow:**

```shell
oc patch mcp worker --type=merge -p '{"spec":{"paused":false}}'
oc patch mcp master --type=merge -p '{"spec":{"paused":false}}'
```

---

## Config B: Only Worker is schedulable

```shell
oc label mcp worker machineconfiguration.openshift.io/role=worker
oc patch mcp worker --type=merge -p '{"spec":{"paused":true}}'
oc get mcp worker -oyaml | grep pause
oc apply -f https://raw.githubusercontent.com/Arctera/infoscale-kubernetes-enterprise/main/config/sysd/99-worker-sysd.yaml
oc apply -f https://raw.githubusercontent.com/Arctera/infoscale-kubernetes-enterprise/main/config/kubelet/kubelet-config.yaml
```

**Unpause MCPs paused in this flow:**

```shell
oc patch mcp worker --type=merge -p '{"spec":{"paused":false}}'
```

---

## Final Validation (before install — check this on all nodes)

```shell
oc get kubeletconfigs.machineconfiguration.openshift.io -oyaml | grep -i 'shutdownGracePeriod\|shutdownGracePeriodCriticalPods'
oc get mcp
ssh core@<worker-node> sudo systemd-inhibit
WHO            UID USER PID  COMM           WHAT     WHY                                        MODE
NetworkManager 0   root 3339 NetworkManager sleep    NetworkManager needs to turn off networks  delay
kubelet        0   root 5476 kubelet        shutdown Kubelet needs time to handle node shutdown delay
```

**Re-check:**

```shell
oc get mcp
```

> **Note:** Do not unpause out of order; it triggers immediate rollout.
