# PredSim_BunyaInstallation

Installs PredSim (branch `linux/cleancurvev4`) and everything it needs (MATLAB
CasADi, OpenSim 4.5.2 with its Java API, opensimAD) into your own home
directory, on **UQ's Bunya HPC** or a local Ubuntu workstation.

- [Install on Bunya](#install-on-bunya) (most users)
- [Install on a local Ubuntu workstation](#install-on-a-local-ubuntu-workstation)
- [How it works](#how-it-works)
- [Benchmark findings](BENCHMARKS.md): what was measured, why single-threaded is as fast as multithreaded

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

This submits a Slurm job (16 CPUs, 32 GB, on an `epyc3` node; it takes under
an hour). Nothing heavy runs on the login node. The job:

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

The default job requests one physical core (`--cpus-per-task=2`), 16 GB and
7 days, and prefers the fastest node type (see [CPU types](#cpu-types-on-bunya)).
Override any of these on the command line, for example:

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

### CPU types on Bunya

Bunya's `general` partition has three CPU types (`epyc3`, `epyc4`, `epyc5`),
all at the same charge rate.

- **Do I need a separate install per CPU type?** No. The one install is built on
  epyc3 and runs on all three. CPU-tuned builds aren't offered: the tuned
  builds are source mode, and their earlier timings were void (Bunya
  source-mode BLAS bug, see BENCHMARKS.md).
- **Is it automatic?** Yes. Nothing to choose at install time.
- **Do I have to request a CPU type when running?** No. `run_predsim.slurm`
  *prefers* epyc4 (`--prefer=epyc4`), the fastest type for PredSim. If no
  epyc4 node is free, the job runs on another type instead of waiting.
- **Can I force one?** Yes. Give both options, because Slurm uses the
  script's `--prefer` in place of `--constraint` whenever it can:
  `sbatch --constraint=epyc4 --prefer=epyc4 ...` (or `epyc3`/`epyc5`).
  Forcing epyc4 is faster once the job starts, but it may wait longer in the queue.

Measured on the same simulation:

| Node type | Time per iteration | vs epyc4 |
|---|---|---|
| epyc4 (EPYC 9454) | 6.8 s | fastest |
| epyc3 (EPYC 7643) | 8.2 s | 1.2× slower |
| epyc5 (EPYC 9745) | 9.6 s | 1.4× slower |

### Optional: CasADi built from source

```bash
sbatch --export=ALL,CASADI_MODE=source bunya/install_predsim.slurm
```

This compiles CasADi, Ipopt and MUMPS instead of using the official CasADi
binaries. **Source stacks installed on Bunya before 3 Nov 2026 give wrong
results** (BLAS errors, diverging solves; see [BENCHMARKS.md](BENCHMARKS.md#6-multithreaded-mumps)).
Rerun this command to rebuild one. The default stays prebuilt. With the fix,
source is 16% faster on epyc3 but 7% slower on epyc4, where jobs normally run. On the Ubuntu workstation source is about 10% faster and is
the default there (see [CasADi](#casadi-prebuilt-vs-source)).

### Optional: HSL MA97 linear solver (as on Windows)

The Windows PredSim uses HSL's MA97 instead of MUMPS when CoinHSL is
installed. To do the same on Linux:

1. Request CoinHSL (free for academic use) at
   <https://licences.stfc.ac.uk/product/coin-hsl>. Download the **source**
   archive `coinhsl-<version>.tar.gz` (or the `x86_64-linux-gnu` binary) and copy it to Bunya.
2. Add it to your install (about 10 minutes):

   ```bash
   cd ~/PredSim_BunyaInstallation
   sbatch --export=ALL,PREDSIM_INSTALL_ARGS="--hsl $HOME/coinhsl-2024.05.15.tar.gz" bunya/install_predsim.slurm
   ```

PredSim then prints `Using HSL linear solver: ma97`. MA97's threads come from
`OMP_NUM_THREADS` (default 1). To go back to MUMPS without reinstalling, set
`PREDSIM_HSL_LIB=` (empty), e.g. `sbatch --export=ALL,PREDSIM_HSL_LIB= ...`.
Benchmark: see [BENCHMARKS.md](BENCHMARKS.md#hsl-ma97).

### Bunya troubleshooting

| Symptom | Fix |
|---|---|
| `no GitHub SSH access` | Step 1. |
| `install on an epyc3 node ...` | The install was submitted with another `--constraint`. Use `sbatch bunya/install_predsim.slurm` as is. |
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
- `<site>[-epyc3]_casadi-<ver>-<mode>_opensim-<ver>/` holds one stack each:
  CasADi, Ipopt/MUMPS (source mode), opensimAD, the Python venv and `env.sh`.

`~/.predsim/env.sh` points at the default stack. To remove a stack, `rm -rf`
its folder.

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

The default is set per site from benchmark results: **source on the Ubuntu
workstation** (about 10% faster, all in MUMPS) and **prebuilt on Bunya**
(7% faster on epyc4, where jobs normally run; source is 16% faster on
epyc3). To compare stacks on fixed work, submit the jobs together:

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
(`/sw/auto/rocky9a/epyc3|4|5`, with some falling back to the epyc3 builds).
Code built on a newer CPU doesn't run on an older one, so everything is
built on epyc3 (`--constraint=epyc3` in the install job). This follows the
RCC guidance in the [Bunya user guide](https://github.com/UQ-RCC/hpc-docs/blob/main/guides/Bunya-User-Guide.md#how-to-build-your-own-software).
Builds tuned for epyc4/epyc5 (`-march=znver4`) were benchmarked, but those
source-mode timings are void (see [BENCHMARKS.md](BENCHMARKS.md#4-cpu-types-on-bunya)),
so tuned builds aren't offered.

### Threads (`S.solver.N_threads`) and compiler optimisation

PredSim's `OCP/solve_NLPSOL.m` (on cleancurvev4 since 21 Oct 2026) builds the
solver with `expand = true`. That makes the solve single-threaded:
`S.solver.N_threads` has no effect, so the run job requests one physical core.

Most of each iteration is spent in the model's external function
`Subjects/<subject>/F_<subject>.so`, which opensimAD_linux compiles with no
optimisation (`-O0`; on Windows opensimAD uses `/O2`). PredSim's
`linux/run_predsim.sh` now sets `CMAKE_BUILD_TYPE=Release`, so it is compiled at
`-O3`. **Delete `F_*.so` files built before this change once**; PredSim
rebuilds them (about 3 minutes per model).

| epyc3, 80 iterations | CPUs | s / iteration | vs current | fair-share charge |
|---|---|---|---|---|
| current code, `-O0` external function | 2 | 8.4 | 1.00× | 1.00× |
| **current code, `-O3` external function** | 2 | **4.7** | **1.78× faster** | **0.56×** |
| `expand = false`, 4 threads, `-O0` | 6 | 6.5 | 1.29× faster | 2.3× |
| `expand = false`, 8 threads, `-O0` | 10 | 6.0 | 1.41× faster | 3.5× |
| `expand = false`, 16 threads, `-O0` | 18 | 4.6 | 1.85× faster | 4.9× |
| `expand = false`, 4 threads, `-O3` | 6 | 7.6 | 1.11× faster | 2.7× |

With `-O3` the current single-threaded code is as fast as 16 threads and far
cheaper, so keep `expand = true` and 2 CPUs. With `expand = false`, `-O3`
doesn't help: the time goes to CasADi evaluating the unexpanded graph around
the external function, not to the function itself.

Multithreaded MUMPS:
- **Threaded OpenBLAS** (`OPENBLAS_NUM_THREADS` = `N_threads`) made Ipopt's own time slower (2.6–2.9 s → 3.1–4.0 s per iteration).
- **MUMPS built with OpenMP** (`--mumps-openmp`, source mode) is faster: 16 threads take 3.69 s per iteration against 4.95 s for prebuilt at 2 CPUs, but at about 6× the fair-share charge, and results aren't exactly reproducible. Its first build gave wrong results (`MKL ERROR: Parameter 11 was incorrect on entry to DTRSM`). That was a Bunya source-mode BLAS bug, since fixed; details in [BENCHMARKS.md](BENCHMARKS.md#6-multithreaded-mumps).

The CPU-type comparison above was measured with `-O0` external functions.

### Known issues

- OpenBLAS 0.3.23 breaks MUMPS
  ([OpenBLAS#4005](https://github.com/OpenMathLib/OpenBLAS/issues/4005),
  [Ipopt#665](https://github.com/coin-or/Ipopt/issues/665)), so 0.3.32 is used.
