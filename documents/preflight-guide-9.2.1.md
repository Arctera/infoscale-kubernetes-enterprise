# Preflight guide for InfoScale upgrade and fresh install

The Pre-flight CLI validates that an OpenShift cluster is ready for an InfoScale Kubernetes Enterprise (IKE) upgrade or fresh install. It runs a set of rule scripts (platform, IKE versions, source-cluster, workload sanity) and reports a pass/fail summary plus detailed logs.

## Topics

- [Prerequisites](#prerequisites)
- [Downloading the Pre-flight CLI](#downloading-the-pre-flight-cli)
- [Command reference](#command-reference)
- [Rules](#rules)
- [Running the CLI](#running-the-cli)
- [Example output](#example-output)
- [Logs and artifacts](#logs-and-artifacts)
- [Interpreting results](#interpreting-results)

---

## Prerequisites

Run the CLI from a host that can reach the OpenShift cluster (for example, the bastion) with a logged-in `oc`/`kubectl` context.

- **Bash** — the script must run in a Bash shell. If you use a different shell, switch to Bash.
- **jq** — required for parsing the upgrade matrix and cluster data.
- **oc** or **kubectl** — with an active session to the target cluster.
- **curl** or **wget** — optional; used to refresh the upgrade matrix (`upgrade_paths.json`) from GitHub. If neither is present, the bundled local matrix is used.
- **git** — to download the CLI (see below), or use the ZIP option if git is unavailable.

The CLI checks its own dependencies at startup and exits early if a required tool is missing.

---

## Downloading the Pre-flight CLI

The Pre-flight CLI is distributed from the InfoScale Kubernetes Enterprise repository (branch `IKE-9.2.1`, path `scripts/preflight-9.2.1/`). This is a **private repository** in the `Arctera` GitHub org, so you need repository access.

**Option A — clone the branch (SSH, works out of the box with repo access):**

```bash
git clone -b IKE-9.2.1 git@github.com:Arctera/infoscale-kubernetes-enterprise.git
cd infoscale-kubernetes-enterprise/scripts/preflight-9.2.1
chmod +x preflight-cli.sh
```

**Option B — sparse checkout (download only the preflight folder):**

```bash
git clone --depth 1 --filter=blob:none --sparse -b IKE-9.2.1 \
  git@github.com:Arctera/infoscale-kubernetes-enterprise.git
cd infoscale-kubernetes-enterprise
git sparse-checkout set scripts/preflight-9.2.1
cd scripts/preflight-9.2.1
chmod +x preflight-cli.sh
```

**Option C — download as a ZIP (no git; requires a token for the private repo):**

```bash
curl -L -H "Authorization: token <YOUR_PAT>" -o preflight-9.2.1.zip \
  https://github.com/Arctera/infoscale-kubernetes-enterprise/archive/refs/heads/IKE-9.2.1.zip
unzip preflight-9.2.1.zip
cd infoscale-kubernetes-enterprise-IKE-9.2.1/scripts/preflight-9.2.1
chmod +x preflight-cli.sh
```

> **Note:** The HTTPS clone form (`https://github.com/Arctera/...`) prompts for credentials or a Personal Access Token (PAT) because the repository is private. The SSH form is recommended if your key already has access.

The downloaded folder contains:

```
preflight-9.2.1/
├── preflight-cli.sh          # entry point
├── lib/                      # helper libraries + data/ (upgrade_paths.json, document_links.json)
└── preflight-rules/          # rule scripts (01-platform, 02-ike-versions, 03-sourceclust, 04-workload-sanity)
```

---

## Command reference

```
Usage: ./preflight-cli.sh [OPTIONS]

OPTIONS:
  --type <type>            Type of operation: 'upgrade' or 'fresh-install' (default: upgrade)
                           If omitted, an interactive prompt is shown.
  --target-ike <version>   Target IKE version (required for both modes; prompts if omitted)
  --target-ocp <version>   Target OCP version (optional, upgrade mode only)
  --rule, --rules <list>   Run only selected rule(s), comma-separated.
                           Accepts rule name(s) (with or without .sh) and/or rule number(s).
                           If omitted and stdin is interactive, a prompt is shown.
  --all                    Run all applicable rules (skips the interactive rule prompt)
  -h, --help               Show help
```

Notes:
- On startup the CLI refreshes `upgrade_paths.json` from GitHub (falls back to the bundled local copy if the download fails or the schema check fails).
- Optional environment variables: `WRITE_RESULTS_TSV=true` and `WRITE_RESULTS_JSON=true` write machine-readable result files into the run log directory.

---

## Rules

| # | Rule | Description | Runs in |
|---|------|-------------|---------|
| 1 | `01-platform` | Platform readiness: machine-config/kubelet-config status, NTP sync, master-schedulable check, allowed image registries, etc. | upgrade + fresh-install |
| 2 | `02-ike-versions` | Validates the source→target IKE version path against the upgrade matrix. | upgrade |
| 3 | `03-sourceclust` | Source InfoScale cluster health (state, split-brain, stale snapshots, etc.). | upgrade |
| 4 | `04-workload-sanity` | Workload readiness for a no-downtime rollout (managed/affined workloads, PDBs, etc.). | upgrade |

**Mode behavior:**
- **`upgrade`** runs all four rules by default (or the subset you pass via `--rule`).
- **`fresh-install`** runs only `01-platform` and ignores `--rule`/`--rules`/`--all`.

---

## Running the CLI

**Upgrade (non-interactive, all rules):**

```bash
./preflight-cli.sh --type upgrade --target-ike 9.2.1 --target-ocp 4.20.22 --all
```

**Fresh install (only platform checks; always needs the target IKE version):**

```bash
./preflight-cli.sh --type fresh-install --target-ike 9.2.1
```

**Run specific rules by name or number:**

```bash
./preflight-cli.sh --type upgrade --target-ike 9.2.1 --rule 01-platform,03-sourceclust
./preflight-cli.sh --type upgrade --target-ike 9.2.1 --rule 1,3
```

**Interactive mode (prompts for type, versions, and rules):**

```bash
./preflight-cli.sh
```

> **Version note:** `--target-ike` is the InfoScale version you are moving to. Use the value that matches your target release and support matrix. The download branch/folder is named `IKE-9.2.1` / `preflight-9.2.1`; make sure the `--target-ike` you pass is a valid version in the upgrade matrix (the CLI lists valid versions if you pass an invalid one).

---

## Example output

```text
==============================================================
 Preflight Check - <timestamp>
 Installation Type : upgrade
 Target OCP        : 4.20.22
 Target Infoscale  : 9.2.1
==============================================================
...
========== PRE-FLIGHT SUMMARY ==========
04-workload-sanity.sh : All checks passed
03-sourceclust.sh : All checks passed
01-platform.sh : All checks passed
02-ike-versions.sh : All checks passed
========================================
[INFO]  All output saved to: .../logs/preflight-20260317-095735/preflight.log
```

---

## Logs and artifacts

Each run writes into a timestamped directory under `preflight-9.2.1/logs/`:

```
logs/preflight-YYYYMMDD-HHMMSS/
├── preflight.log                    # full stdout/stderr of the run
├── consolidated_vxrest_logs.log     # collected VxREST logs
├── check-results.tsv                # only if WRITE_RESULTS_TSV=true
└── check-results.json               # only if WRITE_RESULTS_JSON=true
```

At the end of the run the directory is archived (`.zip` if `zip` is available, otherwise `.tar.gz`). The final log lines print the exact paths of the log file, the run log directory, and the archive — attach the archive when raising a support case.

---

## Interpreting results

- **All rules `PASS`** → the cluster is ready; proceed with the operator upgrade / software upgrade / fresh install.
- **Any rule `FAIL`** → open `preflight.log` in the run directory, find the failing check, and remediate before proceeding. Re-run the CLI until all applicable rules pass.
- **Config phase failure** → the run aborts early (before executing checks). Fix the reported configuration issue and re-run.
- **Warnings** (for example, "allowed registries" empty, or matrix refresh skipped) do not stop the run but should be reviewed — some indicate a real gap, others are benign for unrestricted clusters.

Re-running preflight before the OpenShift/platform upgrade (optional) is recommended to re-confirm cluster health.
