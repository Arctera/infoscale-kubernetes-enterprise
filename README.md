# InfoScale Enterprise for Kubernetes
from pathlib import Path

# Define the markdown content
markdown_content = """
# Veritas InfoScale for Kubernetes Enterprise (VIKE)

## 🔍 Overview

**VIKE (Veritas InfoScale for Kubernetes Enterprise Edition)** brings Veritas’ enterprise-grade storage, high availability, and disaster recovery (DR) features into the Kubernetes ecosystem.

It is designed for running **stateful workloads** in Kubernetes with enterprise-grade **performance, resiliency, and manageability**.

---

## 🧩 Core Components in Kubernetes

| Component                  | Role in Kubernetes Cluster                                          |
|---------------------------|----------------------------------------------------------------------|
| **CSI Driver**            | Allows Kubernetes to manage InfoScale volumes as persistent volumes |
| **FSS (Flexible Storage Sharing)** | Lets worker nodes share their local storage with other nodes          |
| **VCS Agents (HA agents)** | Monitor and manage app availability (sidecar model or integrated)   |
| **DR Manager**            | Coordinates DR replication and failover across clusters             |
| **VVR (Veritas Volume Replicator)** | Performs async/sync volume replication for DR                    |
| **Operator**              | Manages deployment, upgrades, and configuration of InfoScale on K8s |
| **Metrics Exporter**      | Pushes InfoScale metrics to Prometheus for observability            |

---

## 🚀 Key Kubernetes-Centric Features

### 1. CSI-Based Persistent Storage
- CSI driver enables Kubernetes-native access to InfoScale-managed volumes.
- Supports `ReadWriteOnce`, `ReadWriteMany`, and multi-node access.
- Ideal for clustered apps like Oracle RAC and PostgreSQL HA.

### 2. Flexible Storage Sharing (FSS)
- Shared block storage over local disks without SAN.
- Enables low-latency, high-performance, software-defined storage pools.

### 3. App-Level High Availability (HA)
- Veritas Cluster Server (VCS) agents integrate with K8s probes.
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

## 🧠 Example Use Cases

| Use Case                              | Description                                                                 |
|--------------------------------------|-----------------------------------------------------------------------------|
| **Databases (PostgreSQL, Oracle)**   | Persistent, fast, and highly available block storage across worker nodes    |
| **SAP HANA in Kubernetes**           | Certified storage backend with HA and DR capabilities                       |
| **Namespace Migration/DR**           | Use DR Manager + VVR to failover a namespace to a secondary cluster         |
| **Multi-cloud Resilience**           | Replicate apps and volumes between AWS/Azure/on-prem clusters               |
| **Security-Sensitive Workloads**     | Use volume encryption and fencing for compliance and integrity              |

---

## ✅ Certified Environments

- Red Hat OpenShift 4.x (OperatorHub Certified)
- Kubernetes (upstream) v1.23+
- Azure Red Hat OpenShift (ARO)
- Hybrid and Multi-cloud Kubernetes Clusters

---

## 🔧 Deployment Methods

- Helm Charts
- Veritas Operator (OpenShift-certified)
- YAML manifests (manual method)

---

## 📌 Summary

Veritas InfoScale for Kubernetes (VIKE) extends Kubernetes into an enterprise-grade platform for **storage, HA, DR**, and **observability** — optimized for critical stateful applications and hybrid/multi-cloud environments.
"""

# Define the file path
file_path = Path("/mnt/data/VIKE_InfoScale_K8s_Readme.md")

# Write to file
file_path.write_text(markdown_content)

# Return the file path
file_path
