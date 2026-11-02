# PredSim_BunyaInstallation

Installs PredSim (branch `linux/cleancurvev4`) and its dependencies on Linux,
either on a local Ubuntu workstation or on UQ's Bunya HPC. Machine
differences live in `sites/*.env`; the steps are identical everywhere.

## Quick start

```bash
git clone -b linux git@github.com:indialindemann/PredSim_BunyaInstallation.git
cd PredSim_BunyaInstallation
./predsim-install.sh --list          # what will run, and what's already done
./predsim-install.sh                 # install (site auto-detected)
~/PredSim/linux/run_predsim.sh       # run PredSim (main.m)
```

Everything is installed under `~/predsim-deps/<stack-id>/`, for example
`~/predsim-deps/ubuntu-local_casadi-3.8.2-prebuilt_opensim-4.5.2/`. The stack id
comes from the site and versions, so different builds sit side by side.
`~/.predsim/env.sh` points at the active one (`--activate` switches it).
To remove a stack, `rm -rf` its folder.

Re-running is cheap: each step records a hash of its inputs and only re-runs
when its script, `versions.env` or the site file changed (`--force` to redo).
Logs: `~/predsim-deps/<stack-id>/logs/<step>.log`.

## Options

| | |
|---|---|
| `--site ubuntu-local\|bunya` | override auto-detection (hostname `bun*` = Bunya) |
| `--casadi prebuilt\|source` | CasADi from the official binary package, or compiled here with `-O3 -march=native` against our own Ipopt/MUMPS (see *CasADi* below) |
| `--only casadi,verify` / `--from opensim` | run part of the install |
| `--prefix DIR`, `--predsim-dir DIR` | change locations |
| `PREDSIM_VERIFY_ITERS=N` | iteration cap of the verification run (default 80) |
| `PREDSIM_GEOMETRY_SRC=DIR` | copy OpenSim Geometry from a local folder instead of git |

## Steps

| Step | What |
|---|---|
| `preflight` | tools present; **compiler's libstdc++ not newer than MATLAB's** (otherwise MATLAB can't load OpenSim/CasADi without `LD_PRELOAD` hacks); disk; GitHub SSH |
| `python` | venv with `casadi==<CASADI_VERSION>` (opensimAD's `genF.py`), numpy, scipy, pinned `cmake` |
| `ipopt` | source mode only: MUMPS (METIS ordering) + Ipopt, site optimisation flags, site OpenBLAS |
| `casadi` | prebuilt zip, or `casadi-source-v<ver>.zip` build |
| `swig` | upstream SWIG 4.1.1 for OpenSim's Java bindings (PCRE2 built in) |
| `opensim` | opensim-core `4.5.2` + its pinned Simbody/spdlog/docopt, Java bindings, install RPATHs |
| `geometry` | OpenSim Geometry from opensim-models (no Windows installer / 7-Zip) |
| `opensimad` | opensimAD recorder libraries, downloaded once (PredSim used to fetch them mid-run) |
| `predsim` | clone `linux/cleancurvev4` if absent; an existing checkout is never touched |
| `matlab-config` | writes `<prefix>/env.sh`, the only thing a run needs |
| `verify` | `ldd` checks, then `PredSim/linux/verify/verify_stack.m`: CasADi+Ipopt, OpenSim, short end-to-end PredSim run |

## CasADi: prebuilt vs source

CasADi's MATLAB interface is generated with a patched SWIG fork. Building
that fork is what used to need gcc 7. **CasADi's source-release archive
(`casadi-source-v<ver>.zip`) already contains the generated wrappers and
builds with `SWIG_IMPORT=ON`, so neither mode needs SWIG at all.**

- `prebuilt` is self-contained: it bundles Ipopt/MUMPS and a symbol-isolated
  OpenBLAS/libgfortran, so MATLAB keeps its MKL and needs no
  `BLAS_VERSION`/`LD_PRELOAD` workarounds.
- `source` compiles CasADi, Ipopt and MUMPS for this CPU (`SITE_OPT_FLAGS`).

The default is set in `versions.env` from benchmark results; see
`PredSim/linux/bench/`. To compare builds yourself:

```bash
PREDSIM_BENCH_ITERS=80 ~/PredSim/linux/run_predsim.sh --env <stackA>/env.sh --script linux/bench/bench_predsim
PREDSIM_BENCH_ITERS=80 ~/PredSim/linux/run_predsim.sh --env <stackB>/env.sh --script linux/bench/bench_predsim
python3 -I ~/PredSim/linux/bench/compare_bench.py ~/PredSim/logs/bench_predsim-*.log
```

## Sites

### ubuntu-local
Ubuntu 24.04, MATLAB R2024b (`/usr/local/MATLAB/R2024b`), gcc 12.3 in
`/opt/gcc-12.3.0`. MATLAB R2024b's libstdc++ stops at GLIBCXX_3.4.30, and
Ubuntu's gcc 13 would exceed it. Needs apt `libmetis-dev`, a JDK (Temurin 21)
and, for source mode, spack `openblas@0.3.32`.

### bunya
To do: `sites/bunya.env`.

## Known issues
- OpenBLAS 0.3.23 breaks MUMPS ([OpenBLAS#4005](https://github.com/OpenMathLib/OpenBLAS/issues/4005),
  [Ipopt#665](https://github.com/coin-or/Ipopt/issues/665)); sites use 0.3.32.
