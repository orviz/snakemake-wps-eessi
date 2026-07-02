# WPS Compilation Workflow over EESSI with Snakemake

This repository provides a **Snakemake** workflow designed to compile the **WRF Pre-processing System (WPS)** directly on top of the **EESSI** (European Environment for Scientific Software Installations) shared stack via CVMFS.

By leveraging the optimized MPI/NetCDF/WRF stack pre-built by EESSI, this workflow eliminates the need to compile the core WRF model from scratch. Instead, it natively automates the local download and tracking of required GRIB2 libraries (Jasper), clones the official WPS repository, and triggers target-specific compilation steps with comprehensive **physical file-based checkpoint tracking**.

---

## Environment Architecture

This project relies on **Pixi** to deploy an isolated, project-confined execution environment containing Python 3, Snakemake 8+, and the Snakemake native Slurm cluster submission plugins.

### 1. Install Pixi (One-time setup per user)
If Pixi is not yet available on your cluster login node, run the following standalone script:
```bash
curl -fsSL https://pixi.sh/install.sh | sh
source ~/.bashrc
```

### 2. Clone this repository

Clone this project into your scratch or home space inside the cluster:

```bash
git clone https://github.com/orviz/snakemake-wps-eessi
cd snakemake-wps-eessi
```

### 3. Workspace Initialization
Navigate to this repository root directory and instruct Pixi to fetch and lock the execution dependencies:
```bash
pixi install
```

---

## Repository Layout

This workflow complies with the **Snakemake Workflow Standard**, separating workflow source logic from local system credentials using an automated template abstraction layer:

```text
snakemake-wps-eessi/
├── .gitignore               # Excludes logs, build temporaries, and custom profiles
├── README.md                # This infrastructure deployment guide
├── pixi.toml                # Project task and software package configuration
├── config/
│   ├── config.yaml          # Target WPS version and CVMFS system paths
│   ├── README.md            # Slurm cluster credential discovery guide
│   └── profiles/
│       └── template_slurm/  # Base template configuration for any HPC cluster
│           └── config.yaml
└── workflow/
    └── Snakefile            # Granular rule execution dependency graph (DAG)
    └── audit_eessi.sh       # EESSI + EasyBuild: audits EESSI environment to decide whether compile from official EB config & patches (EESSI_OFFICIAL) or local (FALLBACK_LOCAL)
```

---

## Workflow explanation
### Step 1: EESSI environment audit (`workflow/audit_eessi.sh`)
- If status is `EESSI_OFFICIAL`: EasyBuild uses native recipe (WPS-4.6.0-foss-2024a-dmpar.eb).
- If status is `FALLBACK_LOCAL`: EasyBuild uses local configuration file and (if any) associated patches (from `./config`).

## Execution & Deployment Guide (**OLD**)

### 1. Match your Target EESSI Mount Paths
Open `config/config.yaml` and verify that the CVMFS initialization path and targeted WRF folder match the architecture of your specific HPC cluster:
```yaml
# config/config.yaml
wps_version: "v4.6.0"
wps_configure_option: "3" # Option for Linux x86_64, foss toolchain (GRIB2 enabled)
install_root: "/home/user/sw" # Destination path for the local Jasper installation
eessi_init_script: "/cvmfs/software.eessi.io/versions/2025.06/init/bash"
eessi_wrf_module: "WRF/4.6.1-foss-2024a-dmpar"
eessi_wrf_dir: "/cvmfs/software.eessi.io/versions/2025.06/software/linux/x86_64/intel/cascadelake/software/WRF/4.6.1-foss-2024a-dmpar/WRFV4.6.1"
```

### 2. Instantiate Your Private Cluster Profile
To prevent Git from tracking or uploading your private resource usage accounts, copy the cluster profile template folder into a custom deployment tag (e.g., `altamira_cluster`):
```bash
cp -r config/profiles/template_slurm config/profiles/altamira_cluster
```
*Note: Any custom profile folder underneath `config/profiles/` except `template_slurm` is automatically blacklisted by the `.gitignore` rule.*

Open `config/profiles/altamira_cluster/config.yaml` and modify the `<YOUR_SLURM_PARTITION>` and `<YOUR_SLURM_ACCOUNT>` fields using the discovery guidelines outlined in `config/README.md`.

### 3. Run a Dry-Run Graph Check
Simulate the workflow layout on your login node to guarantee Slurm parameters are parsed correctly:
```bash
pixi run dry-run config/profiles/altamira_cluster
```

### 4. Submit to Production Compute Queues

*   **To orchestrate individual step submission through your Slurm scheduling daemon:**
    ```bash
    pixi run run-slurm config/profiles/altamira_cluster
    ```
*   **To compile locally if working within a pre-allocated interactive resource node (`salloc` space):**
    ```bash
    pixi run run-local --cores 8
    ```

---

## Compilation Stages

Snakemake will construct a Direct Acyclic Graph (DAG) split into 4 decoupled rule targets:

1.  **`install_jasper`**: Downloads, configures, and isolates a static `libjasper.a` library build in your user space.
2.  **`clone_wps`**: Clones and checks out the specific tag reference of the official UCAR WPS codebase.
3.  **`configure_wps`**: sources EESSI CVMFS sub-shells on-the-fly, matches variables with the static WRF libraries, and outputs a valid `configure.wps` target file.
4.  **`compile_wps`**: Safely locks the maximum memory allocation bugs of underlying linear algebra dependencies (`export OPENBLAS_NUM_THREADS=1`) and compiles the definitive target binaries: `geogrid.exe`, `ungrib.exe`, and `metgrid.exe`.
