## Overview

During node maintenance/upgrade operations, InfoScale CSI node pods must be evicted before application workloads.  
If an application workload is assigned a `PriorityClass` with a higher priority value than the CSI node pods, it could change the tear down order of resources during node maintenance.

**When Is This Required?**

- Preflight checks report CSI PriorityClass conflicts  
- Application workloads use a PriorityClass with a value higher than the InfoScale CSI node PriorityClass  

### Resolution Procedure:

1. **List existing PriorityClasses**
   ```bash
   oc get priorityclass
   ```

2. **Export the application PriorityClass**
   ```bash
   oc get priorityclass <application-priorityclass> -o yaml > pc.yaml
   ```

3. **Update the PriorityClass value**

   Edit the exported YAML file and reduce the `value` field so that it is less than the InfoScale CSI node PriorityClass value. For example:
   ```yaml
   value: 100000
   ```
   > **Note:** Ensure the updated value does not impact other critical workloads that rely on this PriorityClass.

4. **Apply the updated PriorityClass**
   ```bash
   oc apply -f pc.yaml --force
   ```

5. **Verify the change**
   ```bash
   oc get priorityclass <application-priorityclass>
   ```
