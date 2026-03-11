### Deleting Applied Kubelet Configuration

If any worker node is showing an inhibitor present **OR** a kubelet config resource is present – clean it up.

#### Example

```bash
ssh core@<worker-node> systemd-inhibit
```

**Output:**
```
WHO            UID USER PID  COMM           WHAT     WHY                                        MODE
NetworkManager 0   root 1270 NetworkManager sleep    NetworkManager needs to turn off networks  delay
kubelet        0   root 2596 kubelet        shutdown Kubelet needs time to handle node shutdown delay
2 inhibitors listed.
```

```bash
oc get kubeletconfigs.machineconfiguration.openshift.io -A
```

**Output:**
```
NAME                    AGE
custom-kubelet-config   92m
```

---

#### Cleanup Steps

> **Note:** Make sure your respective MCPs (worker OR worker + masters) are paused before applying the steps below.

1. **Pause worker MCP:**
   ```bash
   oc patch mcp worker --type=merge -p '{"spec":{"paused":true}}'
   ```

2. **Delete sysd config:**
   ```bash
   oc delete -f https://raw.githubusercontent.com/Arctera/infoscale-kubernetes-enterprise/main/config/sysd/99-worker-sysd.yaml
   ```

3. **Delete kubelet config:**
   ```bash
   oc delete -f https://raw.githubusercontent.com/Arctera/infoscale-kubernetes-enterprise/main/config/kubelet/kubelet-config.yaml
   ```

4. **Resume worker MCP:**
   ```bash
   oc patch mcp worker --type=merge -p '{"spec":{"paused":false}}'
   ```
