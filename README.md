# PredSim_BunyaInstallation

Installs PredSim (branch `linux/cleancurvev4`) and everything it needs (MATLAB
CasADi, OpenSim 4.5.2 with its Java API, opensimAD) into your own home
directory, on **UQ's Bunya HPC** or a local Ubuntu workstation.

- [Install on Bunya](#install-on-bunya) (most users)
- [Install on a local Ubuntu workstation](#install-on-a-local-ubuntu-workstation)
- [How it works](#how-it-works)

---

## Install on Bunya

### 1. One-time prerequisite: a GitHub SSH key on Bunya

The install clones the PredSim repository over SSH, so Bunya needs a GitHub
key with access to `indialindemann/PredSim`. On a Bunya login node:

```bash
ssh -T git@github.com     # "Hi <you>! You've successfully authenticated" -> skip to step 2
```

If that fails, create a key and add it to your GitHub account
(*GitHub → Settings → SSH and GPG keys → New SSH key*), then ask for access
to the PredSim repository:

```bash
ssh-keygen -t ed25519 -C "$USER@bunya"      # accept the defaults
cat ~/.ssh/id_ed25519.pub                   # paste this into GitHub
```

### 2. Install (one command)

On a Bunya login node:

```bash
git clone git@github.com:indialindemann/PredSim_BunyaInstallation.git ~/PredSim_BunyaInstallation && cd ~/PredSim_BunyaInstallation && sbatch bunya/install_predsim.slurm
```

This submits a Slurm job (16 CPUs, 32 GB, up to 4 h, on an `epyc3` node).
Nothing heavy runs on the login node. The job:

1. builds OpenBLAS, SWIG and OpenSim 4.5.2, and installs CasADi, opensimAD and a Python venv into `~/predsim-deps/`,
2. clones PredSim (`linux/cleancurvev4`) to `~/PredSim`, unless that folder already exists,
3. writes `~/.predsim/env.sh`, the one file a simulation needs,
4. runs a check that finishes with a short PredSim simulation.

If your default Slurm account isn't the one to charge, add `--account=a_xxxx` after `sbatch`.

### 3. Check it worked

```bash
squeue --me                                           # job still running?
tail -f ~/PredSim_BunyaInstallation/predsim-install-<jobid>.out
```

The last lines should be `verify OK` and `done.`. If a step failed, the
`.out` file names the step and its log, e.g.
`~/predsim-deps/<stack>/logs/opensim.log`. Fix the cause and resubmit.
Finished steps are skipped:

```bash
cd ~/PredSim_BunyaInstallation && sbatch bunya/install_predsim.slurm
```

### 4. Run a simulation

Edit `~/PredSim/main.m` as usual, then:

```bash
sbatch ~/PredSim_BunyaInstallation/bunya/run_predsim.slurm
```

| What | Where |
|---|---|
| Job output | `predsim-<jobid>.out` in the directory you submitted from |
| MATLAB / IPOPT log | `~/PredSim/logs/main-<timestamp>.log` |
| Results | `~/PredSimResults/<subject>/` |

The default job requests 5 CPUs, 24 GB and 7 days. That matches PredSim's
default `S.solver.N_threads = 4` plus MATLAB's own thread. Override on the
command line, for example:

```bash
sbatch --time=2-00:00:00 --mem=32G ~/PredSim_BunyaInstallation/bunya/run_predsim.slurm
sbatch --qos=debug --time=00:55:00 ~/PredSim_BunyaInstallation/bunya/run_predsim.slurm     # quick test, starts fast, max 1 h
sbatch --export=ALL,PREDSIM_SCRIPT=myOtherMain ~/PredSim_BunyaInstallation/bunya/run_predsim.slurm
```

For a quick test, set `S.solver.max_iter` to a few tens in `main.m` first.
At the default 5000 iterations a run takes hours.

### 5. Updating

```bash
cd ~/PredSim_BunyaInstallation && git pull && sbatch bunya/install_predsim.slurm   # installer / dependencies
cd ~/PredSim && git pull                                                            # PredSim code
```

### Optional: stacks tuned for newer CPUs

Bunya's `general` partition mixes three AMD generations: `epyc3` (Zen3),
`epyc4` (Zen4) and `epyc5` (Zen5). The default install targets epyc3, which
runs on all of them. You can also build stacks tuned for the newer CPUs:

```bash
cd ~/PredSim_BunyaInstallation && bunya/install_all_arches.sh   # epyc3, then epyc4 + epyc5 after it
```

`run_predsim.slurm` then automatically uses the tuned stack on whichever node
type a job lands on. To pick a node type, add `--constraint=epyc4` (or
`epyc3`/`epyc5`) to `sbatch`.

### Optional: CasADi built from source

```bash
sbatch --export=ALL,CASADI_MODE=source bunya/install_predsim.slurm
```

This compiles CasADi, Ipopt and MUMPS for the node's CPU instead of using
the official CasADi binaries (see [CasADi](#casadi-prebuilt-vs-source)).

### Bunya troubleshooting

| Symptom | Fix |
|---|---|
| `no GitHub SSH access` | Step 1. |
| `shared step ... must be built first ...` | You started a tuned (`--constraint=epyc4/5`) install before the default one. Run `sbatch bunya/install_predsim.slurm` first. |
| Job stays `PD` (pending) | Normal when the cluster is busy. `squeue --me --start` shows the estimated start time. |
| `verify` failed | See `~/predsim-deps/<stack>/logs/verify-matlab.log`. |

---

## Install on a local Ubuntu workstation

Requirements: MATLAB R2024b at `/usr/local/MATLAB/R2024b`, gcc 12.3 at
`/opt/gcc-12.3.0`, apt `libmetis-dev`, a JDK (Temurin 21) and spack
`openblas@0.3.32` and `python@3.11.15`. See `sites/ubuntu-local.env` to
change these.

```bash
git clone git@github.com:indialindemann/PredSim_BunyaInstallation.git
cd PredSim_BunyaInstallation
./predsim-install.sh --site ubuntu-local --list     # what will run / is done
./predsim-install.sh --site ubuntu-local            # install
~/PredSim/linux/run_predsim.sh                      # run main.m
nohup ~/PredSim/linux/run_predsim.sh > /dev/null 2>&1 &   # long run in the background; log in ~/PredSim/logs/
```

The local MATLAB R2024b's libstdc++ stops at GLIBCXX_3.4.30. gcc 12 matches
it; Ubuntu's own gcc 13 would not.

---

## How it works

Everything is installed under `~/predsim-deps/`:

- `<site>_opensim-<ver>/` is shared by all stacks of a site: OpenSim, its
  Geometry, SWIG, and on Bunya OpenBLAS.
- `<site>[-<cpu>]_casadi-<ver>-<mode>_opensim-<ver>/` holds one stack each:
  CasADi, Ipopt/MUMPS (source mode), opensimAD, the Python venv and `env.sh`.

`~/.predsim/env.sh` points at the default stack (`env-<cpu>.sh` for tuned
Bunya stacks). To remove a stack, `rm -rf` its folder.

Each step logs to `<stack>/logs/<step>.log` and records a hash of its inputs.
Re-running only redoes steps whose script, `versions.env` or site file
changed. `--force` redoes a step anyway; `--restamp` marks finished steps as
current after a comment-only edit.

### `predsim-install.sh` options

| | |
|---|---|
| `--site bunya\|ubuntu-local` | machine config in `sites/` (the Bunya job script always passes `bunya`) |
| `--casadi prebuilt\|source` | see below |
| `--only casadi,verify` / `--from opensim` | run part of the install |
| `--list` | show steps and their state |
| `--activate` | point `~/.predsim/env.sh` at this stack |
| `--prefix DIR`, `--predsim-dir DIR` | change locations |
| `PREDSIM_VERIFY_ITERS=N` | iteration cap of the check run (default 80) |
| `PREDSIM_GEOMETRY_SRC=DIR` | copy OpenSim Geometry from a local folder instead of git |

### Steps

| Step | What |
|---|---|
| `preflight` | tools present; compiler libstdc++ vs MATLAB's (see below); disk; GitHub SSH |
| `python` | venv with `casadi==<CASADI_VERSION>` (for opensimAD's `genF.py`), numpy, scipy, pinned `cmake`, `patchelf` |
| `openblas` | Bunya: OpenBLAS 0.3.32 with `DYNAMIC_ARCH` (the gcc-12 module family only has 0.3.23, which breaks MUMPS) |
| `ipopt` | source mode only: MUMPS (METIS ordering) + Ipopt, optimised for the CPU |
| `casadi` | official prebuilt zip, or a build from `casadi-source-v<ver>.zip` |
| `swig` | upstream SWIG 4.1.1 for OpenSim's Java bindings |
| `opensim` | opensim-core `4.5.2` + its pinned Simbody/spdlog/docopt, Java bindings, install RPATHs |
| `geometry` | OpenSim Geometry from opensim-models (no Windows installer / 7-Zip) |
| `opensimad` | opensimAD recorder libraries, downloaded once (PredSim used to fetch them mid-run) |
| `predsim` | clone `linux/cleancurvev4` if absent; an existing checkout is never touched |
| `matlab-config` | writes `<stack>/env.sh` |
| `verify` | library checks, then `PredSim/linux/verify/verify_stack.m`: CasADi+Ipopt, OpenSim, a short PredSim run |

### CasADi: prebuilt vs source

CasADi's MATLAB interface is generated with a patched SWIG fork, and building
that fork is what used to need gcc 7. CasADi's source-release archive
(`casadi-source-v<ver>.zip`) already contains the generated wrappers and
builds with `SWIG_IMPORT=ON`, so **neither mode needs SWIG**.

- `prebuilt` is self-contained. It bundles Ipopt/MUMPS and a symbol-isolated OpenBLAS/libgfortran, so MATLAB keeps its MKL.
- `source` compiles CasADi, Ipopt and MUMPS (with METIS) for the CPU.

The default is set in `versions.env` from benchmark results. To compare stacks
on fixed work:

```bash
PREDSIM_BENCH_ITERS=80 ~/PredSim/linux/run_predsim.sh --env <stackA>/env.sh --script linux/bench/bench_predsim
PREDSIM_BENCH_ITERS=80 ~/PredSim/linux/run_predsim.sh --env <stackB>/env.sh --script linux/bench/bench_predsim
python3 -I ~/PredSim/linux/bench/compare_bench.py ~/PredSim/logs/bench_predsim-*.log
```

### MATLAB and the C++ runtime

MATLAB ships its own `libstdc++`. Libraries built with a newer gcc fail to
load in MATLAB unless the newer runtime is used instead.

- **Ubuntu (R2024b):** the toolchain (gcc 12) matches MATLAB, so nothing is needed.
- **Bunya (R2023b, GLIBCXX_3.4.28):** every gcc module is newer, so
  `run_predsim.sh` preloads the toolchain's `libstdc++`/`libgcc_s` into the
  MATLAB process only (`PREDSIM_MATLAB_LD_PRELOAD`). `libstdc++` is backward
  compatible, so MATLAB itself is unaffected.

### Bunya CPU generations

Bunya's modules are built separately for each CPU generation
(`/sw/auto/rocky9a/epyc3|4|5`). Code built on a newer CPU doesn't run on an
older one, so the shared parts and the default stack are built on epyc3
(`--constraint=epyc3` in the job script). This follows the RCC guidance in
the [Bunya user guide](https://github.com/UQ-RCC/hpc-docs/blob/main/guides/Bunya-User-Guide.md#how-to-build-your-own-software).
gcc 12 has no `znver5` target, so epyc5 stacks use `znver4`.

### Known issues

- OpenBLAS 0.3.23 breaks MUMPS
  ([OpenBLAS#4005](https://github.com/OpenMathLib/OpenBLAS/issues/4005),
  [Ipopt#665](https://github.com/coin-or/Ipopt/issues/665)), so 0.3.32 is used.
