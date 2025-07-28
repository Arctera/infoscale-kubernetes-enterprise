# InfoScale for Kubernetes Enterprise (IKE)

##  Overview

**IKE (InfoScale for Kubernetes Enterprise Edition)** brings enterprise-grade storage, high availability, and disaster recovery (DR) features into the Kubernetes ecosystem.

It is designed for running **stateful workloads** in Kubernetes with enterprise-grade **performance, resiliency, and manageability**.

IKE also supports **OpenShift Virtualization**, enabling unified management and high availability of both **containerized** and **virtual machine (VM)** workloads.

With OpenShift Virtualization, IKE provides:
- Shared block storage and HA for VMs similar to containers.
- Disaster recovery across clusters for VMs.
- Unified CSI-based storage for Pods and VMs.
- Monitoring and management using the same InfoScale tools.

---

##  Core Components in Kubernetes

| Component                  | Role in Kubernetes Cluster                                          |
|---------------------------|----------------------------------------------------------------------|
| **Operator**              | Manages deployment, upgrades, and configuration of InfoScale on K8s |
| **CSI Driver**            | Allows Kubernetes to manage InfoScale volumes as persistent volumes |
| **FSS (Flexible Storage Sharing)** | Lets worker nodes share their local storage with other nodes          |
| **DR Manager**            | Coordinates DR replication and failover across clusters             |
| **VVR (Volume Replicator)** | Performs async/sync volume replication for DR                    |
| **Metrics Exporter**      | Pushes InfoScale metrics to Prometheus for observability            |

---

##  Key Kubernetes-Centric Features

### 1. CSI-Based Persistent Storage
- CSI driver enables Kubernetes-native access to InfoScale-managed volumes.
- Supports `ReadWriteOnce`, `ReadWriteMany`, and multi-node access.
- Ideal for clustered apps like Oracle RAC and PostgreSQL HA.

### 2. Flexible Storage Sharing (FSS)
- Shared block storage over local disks without SAN.
- Enables low-latency, high-performance, software-defined storage pools.

### 3. App-Level High Availability (HA)
- Monitors container health and application processes.
- Supports automatic failover or container restart.

### 4. Disaster Recovery (DR) & Geo-Redundancy
- `DR Manager` enables namespace or application migration.
- Uses `VVR` for async/sync volume replication across clusters or clouds.
- Supports near-zero RPO/RTO with manual or automatic failover.

### 5. Snapshots and Cloning
- Create and manage snapshots for backup/testing.
- Volume cloning for rapid restore or parallel dev/test environments.

### 6. Prometheus Monitoring Integration
- Exposes metrics to Prometheus.
- Integrates with Grafana, Alertmanager, and enterprise monitoring.

### 7. Rolling Upgrades & Multi‑Cluster Readiness
- Zero-downtime InfoScale upgrades.
- Deployable on OpenShift, AKS, and upstream Kubernetes.

---

##  Example Use Cases

### IKE also supports virtualized workloads using OpenShift Virtualization:

- **VM Workload HA**: Automatically failover VMs managed via OpenShift Virtualization.
- **VM Storage Replication**: Use VVR to replicate VM data volumes between clusters.
- **Hybrid App Models**: Run VMs and containers in the same namespace with shared storage and DR.

| Use Case                              | Description                                                                 |
|--------------------------------------|-----------------------------------------------------------------------------|
| **Databases (PostgreSQL, Oracle)**   | Persistent, fast, and highly available block storage across worker nodes    |
| **SAP HANA in Kubernetes**           | Certified storage backend with HA and DR capabilities                       |
| **Namespace Migration/DR**           | Use DR Manager + VVR to failover a namespace to a secondary cluster         |
| **Multi-cloud Resilience**           | Replicate apps and volumes between AWS/Azure/on-prem clusters               |
| **Security-Sensitive Workloads**     | Use volume encryption and fencing for compliance and integrity              |

---

##  Certified Environments

- Red Hat OpenShift 4.x (OperatorHub Certified)
- Kubernetes (upstream) v1.23+
- Azure Red Hat OpenShift (ARO)
- Hybrid and Multi-cloud Kubernetes Clusters

---

##  Deployment Methods

- Helm Charts (Draft)
- InfoScale Operators (OpenShift-certified)
- YAML manifests (manual method)

---

##  Summary

Arctera InfoScale for Kubernetes (IKE) extends Kubernetes into an enterprise-grade platform for **storage, HA, DR**, and **observability** — optimized for critical stateful applications, **virtual machines**, and hybrid/multi-cloud environments.
