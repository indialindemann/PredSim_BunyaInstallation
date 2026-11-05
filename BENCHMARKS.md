# PredSim on Linux: benchmark findings

What was measured to choose the installer's defaults, and why each choice
was made. The main [README](README.md) has the short version. All results
are from November 2026.
How each bug behind these results was found and fixed is in
[bug_fixes_&_tweaking.md](bug_fixes_%26_tweaking.md).

## Summary

| Question | Answer |
|---|---|
| Biggest single speed-up? | Compiling the model's external function with optimisation: **1.8× faster** (8.4 → 4.7 s per iteration). Now the default. |
| CPU-specific flags for it? | `-march=znver3` (FMA, AVX2) makes each call 28% faster on epyc3 and epyc4, about 12% per iteration. Now the Bunya default. `-march=znver4` (AVX-512) is no better. See [section 1b](#1b-cpu-flags-for-the-external-function--marchznver3). |
| Why could Windows be faster on the same hardware? | Mostly that: opensimAD_linux compiled it at `-O0`, Windows at `/O2`. Windows may also use HSL MA97 instead of MUMPS (see [HSL](#hsl-ma97-and-ma57)). |
| HSL instead of MUMPS? | MA97, with the Ipopt settings below. Over 80 iterations MA57 was 20–38% faster per iteration, but that didn't hold on longer runs, where MA97 on 4 threads had the lowest solver time. With Ipopt's defaults no solver converged on these problems; with the default settings MA97 and MA57 both did, at the same objective. See [HSL](#hsl-ma97-and-ma57) and [Ipopt settings](#ipopt-settings). |
| CPU-tuned CasADi? | Small gain: about 3% overall in the one clean comparison. See [long runs](#long-runs-no-solution-found). |
| Threads (`S.solver.N_threads`)? | No benefit. The current code is single-threaded, and with the fix it matches 16 threads at about a ninth of the fair-share charge. |
| Multithreaded MUMPS? | Works after a fix, and 16 threads cut an iteration from 4.95 to 3.69 s. That costs about 6× the fair-share charge, and results change from run to run, so it isn't the default. See [Multithreaded MUMPS](#6-multithreaded-mumps). |
| Prebuilt or source CasADi? | Bunya: both are installed, and jobs use source on every node type so results don't follow the node. That isn't the fastest choice everywhere: with MUMPS, prebuilt was 7% faster on epyc4 and source 16% faster on epyc3 (`PREDSIM_CASADI_MODE=fastest` picks per node). Source-mode builds there were broken until 3 Nov 2026 (see [section 6](#6-multithreaded-mumps)). Ubuntu workstation: source (about 10% faster). **Prebuilt did worse on optimality at MA97's default pivoting:** none of its runs reached a solution, while most source runs on the same problem did. With tighter pivoting, both stacks reached one on both paths. See [prebuilt vs source](#prebuilt-vs-source-optimality). |
| Which Bunya CPU? | epyc4 is fastest. Jobs *prefer* it; one install runs on all types. |
| How many CPUs per job? | 2 (one physical core). More gives no speed-up. |
| Why do CPUs give different results? | MA97's OpenBLAS picks its code path by CPU, and at MA97's default pivot threshold the first factorisation is inaccurate, so rounding decides the first step. Every path tested differs, not only AVX-512, and no path is faulty. See [what changes the result](#what-changes-the-result) and [Ipopt settings](#ipopt-settings). |
| Why didn't the long runs converge? | Three Ipopt defaults don't suit these problems: MA97's pivot threshold, the objective scaling, and the adaptive barrier parameter's jumps. `linux/run_predsim.sh` now changes them by default, and every benchmark run with the new settings converged. See [Ipopt settings](#ipopt-settings). |
| How do I get the same result every time? | Bunya jobs now fix the OpenBLAS path to Haswell by default. Keep the stack, solver and threads the same as well. See [reproducible results](#reproducible-results). |

## Reproducible results

To get the same result every time, keep all of these the same:

| Keep the same | How |
|---|---|
| OpenBLAS code path | Option 1 or 2 below |
| CasADi stack | The default is source on every node type. `PREDSIM_CASADI_MODE` changes it; `fastest` makes it follow the node type again |
| Solver and threads | `PREDSIM_HSL_SOLVER`, `OMP_NUM_THREADS` and `--cpus-per-task` |
| Code and inputs | The same commit, `main.m`, solver options and starting guess, and the same muscle fit and `F_*` files in `Subjects/<subject>` |

**Option 1: force the OpenBLAS path.** `bunya/run_predsim.slurm` does this by default: it sets
`OPENBLAS_CORETYPE=Haswell` on every node type. `~/.predsim/env.sh` also uses the source stack on
every node type. Both are for matching results, not speed, so the default job already fixes them:

```bash
sbatch bunya/run_predsim.slurm
```

Outside Slurm, run `export OPENBLAS_CORETYPE=Haswell` first. The CPU must support AVX2.

**Option 2: use one CPU type.** Set both node options, and pass `auto` so OpenBLAS picks its path
by CPU:

```bash
sbatch --constraint=epyc4 --prefer=epyc4 --export=ALL,OPENBLAS_CORETYPE=auto,PREDSIM_CASADI_MODE=source bunya/run_predsim.slurm
```

Runs from before this default used the CPU's own path unless they forced one, so pass `auto` to
repeat those.

**To check it worked:**
- The job's `.out` file prints `== OpenBLAS code path:` near the top.
- Add `OPENBLAS_VERBOSE=2` to `--export`. With option 1, every `Core:` line in the log should say `Haswell`.
- Compare the runs' exit message, iteration count and objective, which should match to every printed digit.

**Limits:**
- **Tested with:** MA97 on 4 threads: epyc4 forced to Haswell matched epyc3 on its default path for whole runs, on both stacks. Over 150 iterations, epyc3, epyc4 and epyc5 forced to Haswell printed identical lines with MA97 (default and tighter pivoting), MA57 and MUMPS.
- **OpenMP MUMPS:** `--mumps-openmp` builds don't repeat, so don't use them when results must match.
- **Rerun scripts:** they keep the CPU type, stack, threads and `OPENBLAS_CORETYPE`. Older rerun scripts don't record `OPENBLAS_CORETYPE`, so add it to those by hand.
- **Thread count:** MA97 at 1, 2, 4 and 8 threads gives different results from identical inputs, so keep `OMP_NUM_THREADS` the same.
- **Convergence:** these settings make a result repeat, not converge. Convergence comes from the Ipopt options that `linux/run_predsim.sh` sets ([Ipopt settings](#ipopt-settings)).

### On Windows

This aims to match Windows machines to each other, not to Linux. **It hasn't been tested yet.**

1. Use the same commit and `main.m` on every machine. `git status` should show no changes.
2. Pick one machine as the reference and copy its whole `Subjects\<subject>` folder to the others, so they share the muscle fit and `F_*` files.
3. Start MATLAB from this file on every machine, for example `start_predsim.bat`:

```bat
@echo off
set OPENBLAS_CORETYPE=Haswell
set OMP_NUM_THREADS=8
set OPENBLAS_NUM_THREADS=1
set MKL_CBWR=AVX2
"C:\Program Files\MATLAB\R2023b\bin\matlab.exe"
```

4. Check the settings in MATLAB before running:

```matlab
getenv('OPENBLAS_CORETYPE')   % Haswell
getenv('OMP_NUM_THREADS')     % 8
version('-blas')              % should show CNR branch AVX2
```

5. Run each machine the same way, either as a desktop session or as a batch job, then compare the logs. Differences in the header and paths are expected, but the iteration lines should match:

```bat
fc /n machineA_log.txt machineB_log.txt
```

`OPENBLAS_CORETYPE` only works if the OpenBLAS in the Windows CoinHSL package picks its path at run time, which hasn't been confirmed. If the iteration lines differ from the first iteration, this may be why.

The reasons are in [bug fixes 5.7](bug_fixes_%26_tweaking.md#57-the-same-job-gives-different-results-by-cpu-type).

## Method

- **Problem:** subject `Falisse_et_al_2022_scaled75Rajagopal` (3D, 75% scaled
  Rajagopal model, sprint, curved path radius 10 000), from a fixed initial
  guess (`..._radius_10000_speed10dot1_v1.mot`).
- **Fixed work:** 80 Ipopt iterations (`max_iter = 80`), so every run does the
  same computation. Full runs use up to 5000 iterations.
- **Script:** `linux/bench/bench_predsim.m` in the PredSim `linux/cleancurvev4` branch.
  - Environment knobs: `PREDSIM_BENCH_ITERS`, `PREDSIM_BENCH_NTHREADS`, `PREDSIM_BENCH_IG`, `PREDSIM_BENCH_TAG`.
  - It prints Ipopt's timing table. `linux/bench/compare_bench.py` splits that into **CasADi evaluations** (`nlp_jac_g`, `nlp_grad_f`, …) and **Ipopt internals** (mostly the MUMPS factorisation). `linux/bench/plot_threads.py` draws the thread graphs.
- **Repeats:** at least 2 per configuration, on separate jobs (usually separate nodes). Bunya node-to-node noise is about ±5–10%. Single runs differing by less than that aren't meaningful.
- **Cost:** Bunya bills requested CPUs × wall time (and memory), so "charge" is CPUs × seconds per iteration.
- **Same path through the solve:** within one stack the 80 iterations are identical, line for line in Ipopt's log, whatever `N_threads` is, because CasADi's threading is deterministic.
  - Different MUMPS builds (prebuilt vs source: other versions, other METIS ordering) take slightly different paths through the same problem, so stacks are compared per iteration.
  - OpenMP MUMPS isn't deterministic: each run takes its own path.
- **Validity check:** runs whose log has BLAS argument errors (`MKL ERROR ... DTRSM`) are invalid. `compare_bench.py` now warns about them, and the installer's verify step fails on them.

## Where the time goes

Per iteration of the current code before the fix (epyc3, 8.4 s):

| Part | s / iteration | Share |
|---|---|---|
| `nlp_jac_g`: constraint Jacobian, almost all of it in the model's external function `F` | 5.3 | 63% |
| Other CasADi evaluations (`nlp_grad_f`, `nlp_g`, `nlp_f`) | 0.5 | 6% |
| Ipopt internals: MUMPS factorisation and solves | 2.6 | 31% |

`F` (`Subjects/<subject>/F_<subject>.so`) is C code that opensimAD generates
from the OpenSim model: algorithmic-differentiation code for the skeletal
dynamics. **OpenSim itself only runs in preprocessing** (a few seconds) and
isn't part of the per-iteration cost.

## 1. External function optimisation (`-O0` → `-O3`)

**Finding:** opensimAD_linux builds `F` with plain `make install` and no
`CMAKE_BUILD_TYPE`. CMake then passes no `-O` flag, so gcc compiles at **`-O0`**:
the compile command is only `gcc -DF_..._EXPORTS -fPIC -c foo_jac.c`. The
Windows opensimAD builds it with `cmake --build . --config RelWithDebInfo`,
which is MSVC `/O2`.

**Fix:** CMake ≥ 3.22 reads the build type from the `CMAKE_BUILD_TYPE`
environment variable. PredSim's `linux/run_predsim.sh` now exports
`CMAKE_BUILD_TYPE=Release` (`-O3 -DNDEBUG`) unless it is already set, with no
change to opensimAD or PredSim code. The environment pins cmake 3.31.6.

| epyc3, current code, 2 repeats | `nlp_jac_g` per call | s / iteration |
|---|---|---|
| `F` at `-O0` (before) | 5.30 s | 8.44 |
| `F` at `-O3` | 1.87 s | **4.73** (1.78× faster) |

**Cost:** compiling `F` takes about 170 s instead of 20 s, once per model.
PredSim reuses an existing `F_*.so`, so **files built before the change stay
unoptimised until deleted** (`rm Subjects/*/F_*.so`).

## 1b. CPU flags for the external function (`-march=znver3`)

**Question:** `-O3` alone targets generic x86-64, so `F` used no AVX or FMA
instructions at all (0 of about 470k instructions). Would CPU-specific flags help?

**Constraint:** a model's `F_<subject>.so` is one file in
`~/PredSim/Subjects/`, built by whichever job first needs it, on whatever
node that job lands on, then used by every node type. `-march=native` on an
epyc4 node would emit AVX-512 and crash on epyc3. `-march=znver3` runs on
Zen3, Zen4 and Zen5.

**Method:** three builds of the same `F`, passed to CMake as `CFLAGS` with
`CMAKE_BUILD_TYPE=Release`. Ten jobs were submitted together: the
`bench_predsim` problem, 80 iterations, 2 CPUs, 2 repeats, each node type on
the stack it uses by default. Each binary gives exactly the same trajectory on
every repeat. Different binaries take different paths, because FMA rounds
differently. That makes time per call the clean comparison; time per iteration
also depends on the path through Ipopt.

| `F` build | size | FMA instructions | AVX-512 |
|---|---|---|---|
| `-O3` (generic x86-64) | 2.13 MB | 0 | none |
| `-O3 -march=znver3` | 1.52 MB | 47,478 | none |
| `-O3 -march=znver4` | 1.46 MB | 47,479 | 586 instructions |

| Node, stack | `F` build | `nlp_jac_g` per call | evals / iter | s / iteration |
|---|---|---|---|---|
| epyc3, source | generic | 2.18 s (2.15, 2.21) | 2.81 | 5.57 (5.29, 5.84) |
| epyc3, source | **znver3** | **1.57 s** (1.64, 1.50) | **2.15** | 4.72 (5.35, 4.08) |
| epyc4, prebuilt | generic | 1.56 s (1.59, 1.53) | 1.88 | 4.21 (4.32, 4.11) |
| epyc4, prebuilt | **znver3** | **1.12 s** (1.13, 1.11) | **1.41** | **3.70** (3.72, 3.67) |
| epyc4, prebuilt | znver4 | 1.10 s (1.10, 1.09) | 1.40 | 4.08 (4.08, 4.08) |

- **znver3 cuts evaluation time by about a quarter** on both node types: `nlp_jac_g`, which calls `F`, is 28% faster. On epyc4, where Ipopt's own time was the same for both builds (2.33 vs 2.29 s), an iteration is 12% faster.
- **On epyc3 the per-iteration figure is noisy:** three of the four jobs shared one node, and Ipopt's own time ranged from 2.1 to 3.1 s between repeats. The evaluation saving (0.66 s per iteration) is the reliable number.
- **znver4 is no faster per call than znver3.** Its iterations were slower because Ipopt's own time was higher (2.68 s) on the same trajectory as znver3. That has nothing to do with `F` and wasn't investigated. Since znver4 would also need one `F` file per CPU type, it isn't used.
- **Default:** `sites/bunya.env` sets `SITE_EXTFUN_CFLAGS="-march=znver3"`. The installer writes it to `env.sh` as `PREDSIM_EXTFUN_CFLAGS`, and `run_predsim.sh` passes it to the `F` build as `CFLAGS`. The Ubuntu workstation uses `-march=native` (one machine; not benchmarked). As with `-O3`, **existing `F_*.so` files keep their old flags until deleted.**

## 2. Why single-threaded is as fast as multithreaded

PredSim's `OCP/solve_NLPSOL.m` has set `optionssol.expand = true` since
21 Oct 2026. Expanding turns the whole problem, including the
`f_coll.map(N, 'thread', N_threads)` over mesh intervals, into one flat SX
expression graph. A flat graph has no `map` left, so CasADi evaluates it on
one thread and `S.solver.N_threads` has no effect:

| expand=true, epyc3 | CPUs | s / iteration |
|---|---|---|
| `N_threads` = 4 | 6 | 8.34 |
| `N_threads` = 8 | 10 | 8.39 |
| `N_threads` = 16 | 18 | 8.21 |

With `expand = false` the `map` stays and threading works. But the
unexpanded MX graph is much more expensive to evaluate: CasADi interprets
it node by node, with a call into `F` for each mesh interval. Measured as CPU
time (`t_proc`), one `nlp_jac_g` costs **~12.5 s with `expand = false`
against ~1.9 s with `expand = true` and `-O3`**: about 6× more work. The
threads spread that extra work out but can't remove it. And with
`expand = false` the time is no longer in `F` (CPU time was 13.0 s at `-O0`
and 12.4 s at `-O3`), so the `-O3` fix barely helps:

| epyc3, 80 iterations | CPUs | s / iteration | vs current | Fair-share charge |
|---|---|---|---|---|
| current code (`expand = true`), `F` at `-O0` | 2 | 8.4 | 1.00× | 1.00× |
| **current code, `F` at `-O3`** | **2** | **4.7** | **1.78×** | **0.56×** |
| `expand = false`, 4 threads, `-O0` | 6 | 6.5 | 1.29× | 2.3× |
| `expand = false`, 8 threads, `-O0` | 10 | 6.0 | 1.41× | 3.5× |
| `expand = false`, 16 threads, `-O0` | 18 | 4.6 | 1.85× | 4.9× |
| `expand = false`, 4 threads, `-O3` | 6 | 7.6 | 1.11× | 2.7× |

The second limit is **Amdahl's law**. Ipopt's internals (about 2.6 s per
iteration, mostly MUMPS) are serial either way. Even if the Jacobian took
no time at all, an iteration would take about 2.6 s, so 16 threads can at
best roughly halve the time of the unexpanded code.

So the expanded, single-threaded solve with an optimised `F` does the least
total work, and on a cluster that bills per CPU it is by far the cheapest.
**Recommended:** keep `expand = true` and request 2 CPUs (Bunya allocates
whole cores of 2 hardware threads).

![N_threads with expand=true: no effect](docs/benchmarks/threads_expandtrue_epyc3.png)

![N_threads with expand=false, against the expand=true baseline](docs/benchmarks/threads_expandfalse_epyc3.png)

*Both graphs use `F` at `-O0`. Draw new ones with `linux/bench/plot_threads.py`.*

## 3. CPUs per job

Same code (`expand = true`, `-O0`) on epyc4 nodes:

| CPUs requested | s / iteration |
|---|---|
| 2 | 6.41 |
| 4 | 6.32 |

The difference is noise. 2 CPUs is one physical core with SMT. **Memory:**
the 3D model peaks at about 10 GB, so jobs request 16 GB.

## 4. CPU types on Bunya

`general` has epyc3 (EPYC 7643, Zen 3), epyc4 (EPYC 9454, Zen 4) and epyc5
(EPYC 9745, Zen 5c, dense cores), all at the same charge rate. Measured
with prebuilt CasADi, `F` at `-O0`, 5 CPUs, 2 repeats:

| Node type | s / iteration |
|---|---|
| epyc4 | **6.8** |
| epyc3 | 8.2 |
| epyc5 | 9.6 |

- epyc4 is about 18% faster than epyc3 and about 30% faster than epyc5. A
  single-threaded solve favours epyc4's higher per-core speed, and epyc5's
  dense cores are slower per thread.
- Only the portable epyc3 build is installed, and it runs everywhere.
- Source builds tuned for the newer CPUs (`-march=znver4`) were also tried. Their timings are **void**: every Bunya source-mode run then had the BLAS bug described in section 6.
- `run_predsim.slurm` uses `--prefer=epyc4`: epyc4 if one is free, otherwise any type. Forcing a type needs both `--constraint=X --prefer=X`, because `--prefer` replaces `--constraint` whenever it can be met.
- With `-O3` all times drop. The ranking should hold, since the work is the same, but it hasn't been re-measured.

## 5. Prebuilt vs source CasADi

| | Ubuntu workstation (i7-7700) | Bunya |
|---|---|---|
| Faster | **source**, about 10% (Ipopt internals 2.2 vs 2.9 s per iteration) | **prebuilt** on epyc4 (the preferred node type); **source** on epyc3. Both installed. |
| Why | MUMPS with METIS ordering and `-O3 -march=native`. CasADi evaluation time is identical. | — |

On Bunya the earlier source-mode timings are void because of the BLAS bug
in section 6. Fixed source build against prebuilt, with each pair submitted
together (current code, `F` at `-O3`, 2 CPUs, 2 repeats, s / iteration):

| Node type | prebuilt | source (fixed) | Ipopt internals, prebuilt / source | Faster |
|---|---|---|---|---|
| epyc4 | **4.12** (4.24, 4.00) | 4.41 (4.02, 4.79) | 2.19 / 2.27 | prebuilt, 1.07× |
| epyc3 | 5.34 (5.62, 5.05) | **4.59** (4.58, 4.59) | 2.89 / 2.11 | source, 1.16× |

- **Bunya installs both, and uses source by default:** since 5 Nov 2026 `~/.predsim/env.sh` sources the source stack on every node type, so results don't depend on where a job lands. Before that it used source on epyc3 and prebuilt elsewhere (`SITE_STACK_FASTEST_BY_ARCH` in `sites/bunya.env`), which `PREDSIM_CASADI_MODE=fastest` still does. `--prefer=epyc4` is only a preference, so many jobs run on epyc3, where source saves 14% of the time. epyc5 hasn't been measured with the fixed source build.
- **The external function is shared:** `F_<subject>.so` links only libc/libm, so both stacks use the same compiled file.
- **Contention matters:** an unpaired run of the source stack earlier, with fewer jobs on the node, gave 4.31 s against 4.95 s for prebuilt. Compare stacks with jobs submitted together.
- **Source takes a different path on epyc3 and epyc4:** its OpenBLAS picks different kernels per CPU (`DYNAMIC_ARCH`), so the rounding differs. Prebuilt took the same path on both.

The Ubuntu source stack never had the bug (no BLAS errors in any local log).
It uses spack's OpenBLAS, not the installer's pthreads build.

Neither mode needs the old SWIG fork or gcc 7. CasADi's source-release
archive ships pre-generated MATLAB wrappers (`SWIG_IMPORT=ON`).

## 6. Multithreaded MUMPS

MUMPS can use threads in two ways: through a threaded BLAS, or built with
OpenMP (ThirdParty-Mumps `--enable-openmp`, the installer's `--mumps-openmp`).

### Threaded BLAS: slower

Prebuilt stack, `expand = false`, `F` at `-O0`, `N_threads` = BLAS threads = T:

| epyc3 | T = 4 | T = 8 | T = 16 |
|---|---|---|---|
| single-threaded BLAS: s / iteration (internals) | 6.52 (2.61) | 5.98 (2.89) | 4.55 (2.59) |
| `OPENBLAS_NUM_THREADS` = T: s / iteration (internals) | 7.36 (3.08) | 6.15 (3.35) | 6.39 (4.03) |

MUMPS's dense frontal matrices are small for this sparse problem, so BLAS
threads spend more time synchronising than computing.

### OpenMP MUMPS: a Bunya build bug, then a real speed-up

The first OpenMP build gave thousands of
`Intel MKL ERROR: Parameter 11 was incorrect on entry to DTRSM` lines, a
different path from iteration 2, and runs about 10× slower that hit the 2 h
limit. The cause turned out to be **every source-mode build on Bunya, with
or without OpenMP**, not OpenMP itself:

- The ordinary source stack had the same errors in every run, and its solve diverged: in restoration at iteration 80 with objective 1.4×10⁸, against about 70 for good runs. Its verify step passed because it only checked that the iterations ran.
- **Ruled out: misrouted BLAS calls.** A dynamic-linker trace (`LD_DEBUG=bindings`) shows MUMPS's `dtrsm_` bound to OpenBLAS, not to MATLAB's MKL. The "Intel MKL" text appears only because OpenBLAS reports bad arguments through `xerbla_`, a weak symbol that MATLAB's MKL overrides.
- **What it depends on:** MUMPS linked to the installer's pthreads OpenBLAS 0.3.32 build got bad arguments in OpenBLAS's `dtrsm`. The same MUMPS linked to an **OpenMP build of the same OpenBLAS** (`USE_OPENMP=1`) is clean: install check, 8 benchmark runs, no errors, normal solves. The exact trigger inside the pthreads build wasn't isolated. It doesn't show on a small test problem, only on PredSim's.
- **Fix (installer, 3 Nov 2026):** on Bunya, source-mode MUMPS always links the OpenMP OpenBLAS, built as `libopenblasomp.so.0`.
  - The separate name keeps it apart from the pthreads `libopenblas.so.0`, which MATLAB loads through OpenSim's JNI first. Under the same name the loader would reuse the copy already loaded.
  - `--mumps-openmp` only decides whether MUMPS itself uses threads.
  - The verify step now fails on BLAS argument errors.
- **Not affected:** the prebuilt stack (Bunya's default), which bundles its own OpenBLAS, and every prebuilt result here.

Results with the fixed build. Current code (`expand = true`), `F` at `-O3`,
epyc3, all 12 jobs on one node (bun048), 2 repeats each, `OMP_NUM_THREADS` = T:

| Stack | CPUs | s / iteration | Ipopt internals | vs prebuilt | Fair-share charge |
|---|---|---|---|---|---|
| prebuilt, single-threaded (default) | 2 | 4.95 | 2.65 | 1.00× | 1.0× |
| OpenMP MUMPS, T = 1 | 2 | 5.50 | 2.93 | 0.90× | 1.1× |
| OpenMP MUMPS, T = 4 | 4 | 4.63 | 2.22 | 1.07× | 1.9× |
| OpenMP MUMPS, T = 8 | 8 | 4.47 | 2.04 | 1.11× | 3.6× |
| OpenMP MUMPS, T = 16 | 16 | 3.69 | 1.30 | 1.34× | 6.0× |

- Threads only speed up the MUMPS part (2.9 → 1.3 s). The CasADi evaluations (about 2.4 s, single-threaded) are untouched, so 16 threads give 1.34×.
- **OpenMP MUMPS isn't deterministic.** At iteration 80 the objective was 67.8, 69.3 and 69.5 for 16, 1 and 4 threads, and 153.6 in one 8-thread run. Converged results should agree, but runs can't be reproduced exactly.
- **Verdict:** only worth it when wall time matters much more than fair share. The default stays prebuilt and 2 CPUs. To use it:

  ```bash
  sbatch --export=ALL,CASADI_MODE=source,PREDSIM_INSTALL_ARGS=--mumps-openmp bunya/install_predsim.slurm
  sbatch --cpus-per-task=16 --export=ALL,OMP_NUM_THREADS=16 bunya/run_predsim.slurm
  ```

## HSL MA97 and MA57

The Windows PredSim uses Ipopt's `linear_solver = ma97` (HSL) when
`C:\CoinHSL...\bin\libhsl.dll` exists, and MUMPS otherwise. On Linux it
always used MUMPS: the check looked only for the Windows path. Now:

- **PredSim:** `solve_NLPSOL.m` takes the library from `$PREDSIM_HSL_LIB` on Linux, and the solver from `$PREDSIM_HSL_SOLVER` (default `ma97`).
- **Installer:** CoinHSL is built into each stack from `~/coinhsl-*.tar.gz` or `--hsl ARCHIVE`, and sets `PREDSIM_HSL_LIB`. It's required unless you pass `--no-hsl`.
- **CoinHSL is licensed:** download it yourself from <https://licences.stfc.ac.uk/product/coin-hsl>. It's free for academic use.
- **MATLAB's own MA57 can't be used:** `libmwma57.so` is built with 64-bit integers, and Ipopt calls it with 32-bit ones (`MA57AD ... NE has value****`).

**Method:** CoinHSL 2024.05.15 from source, with METIS. The `bench_predsim`
problem (about 149k variables), 80 iterations, the `znver3` external function,
2 repeats, 36 jobs submitted together, each node type on its default stack.
Each job had `max(2, T)` CPUs and 32 GB (peak use was about 10 GB for all).
MA97's threads come from `OMP_NUM_THREADS`. MA57 has none of its own, so its
threads come from BLAS (`OPENBLAS_NUM_THREADS`). No run had BLAS errors.

Seconds per iteration, repeats in brackets. "Solver" is Ipopt's own time
(total minus function evaluations, mostly the linear solver):

| Node, stack | Solver | Threads | s / iteration | Solver s / iter | CPU ÷ elapsed | CPUs × s / iter |
|---|---|---|---|---|---|---|
| epyc3, source | MUMPS | 1 | 4.35 (4.38, 4.31) | 2.19, 2.14 | 1.0 | 8.7 |
| | **MA57** | **1** | **3.46** (3.46, 3.47) | **1.31, 1.27** | 1.0 | **6.9** |
| | MA57 | 4 | 3.46 (3.56, 3.36) | 1.42, 1.36 | 1.2 | 13.8 |
| | MA57 | 8 | 3.84 (3.38, 4.29) | 1.32, 2.23 | 1.5 | 30.7 |
| | MA57 | 16 | 3.34 (3.13, 3.55) | 1.27, 1.51 | 2.1 | 53.4 |
| | MA97 | 1 | 4.08 (4.16, 4.00) | 1.99, 1.93 | 1.0 | 8.2 |
| | MA97 | 4 | 3.33 (3.58, 3.08) | 1.47, 1.16 | 1.3 | 13.3 |
| | MA97 | 8 | 3.58 (3.07, 4.10) | 1.03, 1.95 | 1.6 | 28.6 |
| | MA97 | 16 | 4.06 (2.96, 5.17) | 1.09, 2.42 | 2.2 | 65.0 |
| epyc4, prebuilt | MUMPS | 1 | 4.60 (3.72, 5.47) | 2.29, 3.88 | 1.0 | 9.2 |
| | **MA57** | **1** | **2.63** (2.32, 2.93) | **0.87, 1.28** | 1.0 | **5.3** |
| | MA57 | 4 | 2.42 (2.35, 2.49) | 0.94, 1.03 | 1.3 | 9.7 |
| | MA57 | 8 | 2.50 (2.68, 2.31) | 1.16, 0.89 | 1.7 | 20.0 |
| | MA57 | 16 | 2.77 (2.93, 2.62) | 1.35, 1.17 | 2.7 | 44.3 |
| | MA97 | 1 | 3.88 (2.70, 5.05) | 1.26, 2.24 | 1.0 | 7.8 |
| | MA97 | 4 | 2.27 (2.14, 2.41) | 0.75, 0.89 | 1.2 | 9.1 |
| | MA97 | 8 | 2.14 (2.17, 2.12) | 0.73, 0.71 | 1.3 | 17.1 |
| | MA97 | 16 | **2.05** (2.15, 1.95) | 0.75, 0.57 | 1.6 | 32.8 |

- **HSL is a real speed-up per iteration.** Single-threaded MA57 takes about 40% of MUMPS's solver time on epyc4 and 60% on epyc3. An iteration is about 20% faster on epyc3 (4.35 → 3.46 s) and, comparing each solver's faster repeat on epyc4, about 38% faster (3.72 → 2.32 s).
- **MA57 at 1 thread is the best value:** the lowest CPU cost per iteration on both node types.
- **MA97 is the fastest on epyc4 when given threads** (2.05 s at 16), but costs about 6× the CPU of MA57 for 11–22% less time. It needs threads to pay off: at 1 thread it is slower than MA57 on both node types.
- **Threaded BLAS doesn't help MA57.** Its solver time doesn't improve with threads. CPU use rises, so the extra threads mostly wait.
- **Scaling is limited** because function evaluations (1.4–2.2 s per iteration) are serial, whichever solver runs.
- **Noise:** several repeats differ by more than the gaps between configurations (2.70 vs 5.05 s for MA97 at 1 thread on epyc4). These jobs ran on different, busy nodes. Treat small differences as unresolved.

**80 iterations can't settle which solver is best overall.** Each solver takes a
different path. Iterates reproduce exactly between repeats, but these differ
widely at iteration 80:

| Node, stack | MUMPS | MA57, 1 thread | MA97, 1 thread |
|---|---|---|---|
| epyc3, source: objective / constraint violation | 67.2 / 2.4e+04 | 71.1 / 6.7e+03 | 127.3 / 2.8e+03 |
| epyc4, prebuilt: objective / constraint violation | 71.4 / 6.9e+03 | 73.3 / 5.7e+03 | 92.6 / 7.5e+01 |

MA97 has the lowest constraint violation at this point, but none of these runs
has converged, and that gap may not last. Time to a solution needs runs to
convergence: the [long runs](#long-runs-no-solution-found) tried this, and none
found a solution. Whether the source stack is still the
faster one on epyc3 with HSL hasn't been measured either.

### Making HSL work inside MATLAB

MATLAB's global symbols replaced HSL's calls in the source stack. MATLAB's
`libmwmetis`, `libmwma57` and `mkl.so` use 64-bit integers, and HSL uses 32-bit:

| Call from `libhsl` | Went to | Result |
|---|---|---|
| `METIS_SetDefaultOptions` | `libmwmetis` | Segfault in METIS. Its disassembly shows 64-bit writes for 40 options, which would be 320 bytes into HSL's 160-byte array. |
| `ma57gd_` (HSL's own routine) | `libmwma57` | Segfault |
| `DGEMM`, `DSWAP`, `dtpsv_` | `mkl.so` | `MKL ERROR`s, then a segfault |
| OpenMP (`GOMP_task` and others) | `libiomp5` | Restoration at iteration 1, DGEMM errors, out of memory |

The source stack alone failed because of how Ipopt loads HSL. CasADi's official
Ipopt calls `dlopen` with `RTLD_NOW | RTLD_DEEPBIND`, which makes a library
prefer its own dependencies. Upstream Ipopt 3.14 uses plain `RTLD_NOW`.

**Fix:** the source build now patches Ipopt to use `RTLD_DEEPBIND`, and `libhsl`
links METIS and OpenBLAS statically with `-Bsymbolic`. Traces with
`LD_DEBUG=bindings` on both stacks show no calls from `libhsl` into MATLAB's
libraries or MKL, and OpenMP calls going to `libgomp`.

## Long runs: no solution found

These runs were meant to measure time to a solution. **None found one**, so they
can't rank solvers or stacks by that measure.

**Method:** `main.m`'s real problem (`Falisse_et_al_2022_lightfoot_alpha0dot5`,
straight running at 9.2, from `OCP/motion_saved.mot`) at PredSim `6b532ce` or
later, which includes the touchdown bound fix `3ae6a7c`. First pass of the speed
loop only, 5000-iteration cap, `znver3` external function, 32 GB, default tolerances.
No run had BLAS errors.

**What happened in all 18 runs:** the constraint violation stalled at about
2,600–2,800 by iteration 350–490. Ipopt then entered restoration, and each run
ended at `Converged to a point of local infeasibility` or at the cap, still in
restoration. The final violation was 0.002–0.8, against a target of 10⁻⁶.

This happens with every solver and stack, which points to the problem setup rather
than the install. **The cause was found later: Ipopt's default settings.** With the
settings in [Ipopt settings](#ipopt-settings) the same problem converges. The
timings below are still useful for comparing solver time per iteration.

### By solver

One run each. Stack by node: epyc3 source, epyc4 prebuilt.

| Node | Solver | CPUs | Iterations | Hours | s / iter | Solver s / iter | Objective | Violation |
|---|---|---|---|---|---|---|---|---|
| epyc3 | MUMPS | 2 | 5000 (cap) | 7.04 | 5.07 | 3.09 | 121.6 | 0.0089 |
| | MA57 | 2 | 3104 (stopped) | 4.21 | 4.89 | 2.87 | 22.5 | 0.0037 |
| | MA97, 4 threads | 4 | 5000 (cap) | 4.30 | 3.10 | 1.14 | 107.4 | 0.0055 |
| epyc4 | MUMPS | 2 | 1886 (stopped) | 2.01 | 3.83 | 2.42 | 83.1 | 0.014 |
| | MA57 | 2 | 5000 (cap) | 5.51 | 3.96 | 2.54 | 123.2 | 0.023 |
| | MA97, 4 threads | 4 | 5000 (cap) | 2.88 | 2.07 | 0.76 | 4.0 | 0.0020 |

- **MA57's 80-iteration advantage didn't last.** Its solver time was 0.9–1.3 s per iteration over 80 iterations, but 2.5–2.9 s here, about the same as MUMPS.
- **MA97 on 4 threads had the lowest solver time** on both nodes. On epyc4 it took about half MA57's time for about the same CPU cost (8.3 against 7.9 CPU·s per iteration).
- **Caveat:** these are averages over different paths with different shares of restoration (12–76%), so they aren't a like-for-like ranking.

### By CasADi build

MA57 on 1 thread, 2 CPUs, 2 repeats, all jobs submitted together. Tuned means
CasADi, Ipopt, MUMPS and HSL built with `-O3 -march=<cpu> -mtune=<cpu> -funroll-loops`
(`znver3` on epyc3, `znver4` on epyc4). `-ffast-math` wasn't tested: it can change
results and break Ipopt's NaN checks.

| Node | Build | Iterations | Hours | s / iter | Solver s / iter | `nlp_jac_g` per call | Objective | Violation |
|---|---|---|---|---|---|---|---|---|
| epyc3 | prebuilt | 5000 (cap) | 4.95, 5.06 | 3.57, 3.64 | 1.75, 1.76 | 1.48, 1.54 s | 121.2 | 0.83 |
| | source | 3104 (stopped) | 4.09, 4.15 | 4.74, 4.81 | 2.76, 2.80 | 1.52, 1.55 s | 22.5 | 0.0037 |
| | tuned | 3104 (stopped) | **3.99, 4.01** | 4.63, 4.65 | 2.87, 2.89 | **1.43, 1.43 s** | 22.5 | 0.0037 |
| epyc4 | prebuilt | 5000 (cap) | 5.56, 5.57 | 4.00, 4.01 | 2.55, 2.56 | 1.12, 1.12 s | 123.2 | 0.023 |
| | source | 4634 (stopped) | 3.96, 4.06 | 3.07, 3.15 | 1.65, 1.72 | 1.11, 1.11 s | 131.3 | 0.0030 |
| | tuned | 5000 (cap) | 3.33, 3.18 | 2.40, 2.29 | 1.15, 1.08 | **1.08, 1.05 s** | 7.4 | 0.0042 |

- **Prebuilt vs source, compared with section 5:** that result came from MUMPS, which isn't the linear solver here. With MA57, `nlp_jac_g` takes the same time on both. Their paths differ, so their totals can't be compared, and whether the source stack still earns its place with HSL is unsettled.
- **Tuning is a small gain.** `nlp_jac_g` is about 5–7% faster per call. The one clean comparison is epyc3, where source and tuned took the same path: 4.00 against 4.12 hours, about 3%. There, faster evaluations were partly offset by solver time that was no faster.
- **epyc4's total times differ more,** but those stacks took different paths, so that isn't a speed ranking. Tuned builds aren't offered by default.
- **Runs reproduce exactly.** Repeats gave identical iteration counts and final values, and so did the earlier batch for epyc3 source and epyc4 prebuilt.

## What changes the result

A different problem from the long runs above: `main.m` and `OCP_formulation.m` from
PredSim `239530b` (half gait cycle, no touchdown bounds), with the same subject, speed,
starting guess and 5000-iteration cap. Muscle fit and `F_*.so` were byte-identical across the
ten runs where this was checked. Each row is one run. Objectives are unscaled.

| Node | Stack | Solver | OpenBLAS path | Exit | Iterations | Objective | Violation | Ipopt s |
|---|---|---|---|---|---|---|---|---|
| epyc3 | source | MUMPS | n/a | Optimal | 1687 | 80.87 | | 7703 |
| | | MA57 | Zen | Optimal | 3402 | 32.85 | | 11545 |
| | | MA97, 1 thread | Zen | Local infeasibility | 950 | 12.45 | 0.0013 | 4567 |
| | | MA97, 4 threads | Zen | Optimal | 3174 | 5.36 | | 9176 |
| | | MA97, 8 threads | Zen | Optimal | 2134 | 5.36 | | 7040 |
| | prebuilt | MA97, 4 threads | Zen | Local infeasibility | 2462 | 18.63 | 0.0013 | 8391 |
| epyc4 | source | MA57 | Cooperlake | Cap | 5000 | 110.4 | 0.16 | 12367 |
| | | MA97, 4 threads | Cooperlake | Optimal | 974 | 86.21 | | 2276 |
| | | MA97, 4 threads | Haswell (forced) | Optimal | 3174 | 5.36 | | 7814 |
| | prebuilt | MUMPS | n/a | Cap | 5000 | 132.0 | 0.043 | 23976 |
| | | MA57 | Cooperlake | Cap | 5000 | 98.2 | 0.26 | 13653 |
| | | MA97, 4 threads | Cooperlake | Cap | 5000 | 100.3 | 0.64 | 10931 |
| | | MA97, 4 threads | Haswell (forced) | Local infeasibility | 2462 | 18.63 | 0.0013 | 5969 |

Paths were logged only for the Haswell runs and epyc3 prebuilt; the others are inferred from the node type, which the 100-iteration runs confirm for epyc4. Optimal runs met the 10⁻⁶ target.

- **The CPU only mattered through the OpenBLAS path.** Forced to Haswell, epyc4 printed the same iteration lines as epyc3 for the whole run on both stacks (3175 and 2463 lines), and took 15–29% less solver time.
- **Optimal doesn't mean the same solution:** 5.36 and 86.21 both pass Ipopt's test, and they are very different gaits by cost.
- **The stack matters separately.** On the same path, source reached Optimal and prebuilt ended in local infeasibility. That's one run each on a sensitive problem. Source and prebuilt first differ at iteration 6.
- **Thread count matters separately.** epyc3 at 1, 4 and 8 threads split at iterations 26–32, even though MA97 is designed to give the same answer at any thread count. The cause isn't known; CPU allocations also differed.

### Prebuilt vs source: optimality

**At default pivoting thresholds, prebuilt CasADi did worse than source on optimality.** On this
problem, 0 of 5 prebuilt runs reached Optimal, against 6 of 8 source runs. Each count includes one run
that repeated another line for line. **With tighter pivoting, that gap closed:** both prebuilt runs
reached Optimal. Run pairs with the same solver, node and OpenBLAS path:

| Solver, path | Source | Prebuilt |
|---|---|---|
| MA97 4 threads, Cooperlake | Optimal, 86.21 | Cap, 100.3, violation 0.64 |
| MA97 4 threads, Haswell | Optimal, 5.36 | Local infeasibility, 18.63, violation 0.0013 |
| MA57, Cooperlake | Cap, 110.4, violation 0.16 | Cap, 98.2, violation 0.26 |
| MA97 4 threads, Cooperlake, tighter pivoting | Optimal, 5.64, 2193 s | Optimal, 5.36, 3502 s |
| MA97 4 threads, Haswell, tighter pivoting | Optimal, 27.66, 1723 s | Optimal, 24.54, 2412 s |

- **MA97, default pivoting:** source won both pairs. It reached Optimal where prebuilt didn't, and neither prebuilt run produced a running gait (stance 100% and 0% of the cycle).
- **MA97, tighter pivoting:** both stacks reached Optimal. Prebuilt's objective was lower on both paths, but it took more iterations and more solver time.
- **MA57:** neither run solved it. Prebuilt's objective is lower, but its violation is higher, so the objectives can't be compared directly.
- **The earlier problem points the same way:** in [the long runs](#by-casadi-build), neither stack found a solution, but prebuilt ended with the higher violation on both nodes (0.83 against 0.0037 on epyc3, 0.023 against 0.0030 on epyc4).

These are few runs on a sensitive problem, and the cause isn't known. Default stack choices haven't
changed: they're based on speed.

### OpenBLAS paths and pivoting, first 100 iterations

Source stack, MA97 on 4 threads, 100-iteration cap. The default and Haswell controls
reproduced their long runs line for line. Iteration 1:

| Run | Objective | `lg(mu)` | `lg(rg)` | Step | Ipopt s |
|---|---|---|---|---|---|
| epyc4, Prescott | 2.6694e6 | -5.2 | none | 18 | 285 |
| epyc4, Sandybridge | 2.7253e6 | 1.3 | -4.0 | 291 | 281 |
| epyc4, Haswell | 2.6236e6 | -0.2 | -4.0 | 24 | 212 |
| epyc4, SkylakeX | 2.7546e6 | 2.8 | none | 9050 | 251 |
| epyc4, Cooperlake (its default) | 2.7546e6 | 2.8 | none | 9050 | 228–230 |
| epyc5 (9745), Cooperlake (its default) | 2.7546e6 | 2.8 | none | 9050 | 409 |
| xeonsp4 (8468), SapphireRapids (its default) | 2.6510e6 | 0.3 | -4.0 | 41 | 221 |
| epyc4, `ma97_u` 1e-4, either path | 2.6204e6 | -0.3 | none | 23 | 225, 236 |
| epyc4, `ma97_u` 1e-2, either path | 2.6204e6 | -0.3 | none | 23 | 244, 249 |
| epyc4, MUMPS, for comparison | 2.6204e6 | -0.3 | none | 23 | |

- **It isn't specific to AVX-512.** Prescott, Sandybridge and Haswell differ from each other as much as from the AVX-512 paths. SkylakeX, Cooperlake and epyc4's and epyc5's defaults match for all 100 iterations.
- **Tighter pivoting removes most of the early sensitivity.** With `ma97_u` at 1e-4 or 1e-2 (default 1e-8), Cooperlake and Haswell match at iteration 1, and match epyc4 MUMPS's printed line. They first differ at iteration 45 and 59, instead of 1. At 1e-2 they were still about 1 part in a million apart at iteration 100.
- **No sign of an AVX-512 bug.** Kernel accuracy was measured later and every path is accurate ([Ipopt settings](#ipopt-settings)).
- **Cost over 100 iterations:** Ipopt time was within about 17% of the default, though these are single runs on different paths.

### Tighter pivoting, full-length runs

MA97, 4 threads, EPYC 9454 nodes, 5000-iteration cap. Tighter means `ma97_u` 1e-2 and `ma97_umax` 1e-1;
default is 1e-8 and 1e-4. Each row is one run. Restoration counts iterations marked `r` in the log.

| Stack | Path | Pivoting | Exit | Iterations | Restoration | Objective | Ipopt s |
|---|---|---|---|---|---|---|---|
| source | Cooperlake | default | Optimal | 974 | 627 | 86.21 | 2276 |
| | | tighter | Optimal | 951 | 30 | 5.64 | 2193 |
| source | Haswell | default | Optimal | 3174 | 1295 | 5.36 | 7814 |
| | | tighter | Optimal | 627 | 27 | 27.66 | 1723 |
| prebuilt | Cooperlake | default | Cap | 5000 | 4924 | 100.3 | 10931 |
| | | tighter | Optimal | 1213 | 390 | 5.36 | 3502 |
| prebuilt | Haswell | default | Local infeasibility | 2462 | 420 | 18.63 | 5969 |
| | | tighter | Optimal | 865 | 31 | 24.54 | 2412 |

- **Every tighter run reached Optimal,** with 12 to 48 times fewer restoration iterations. Total solver time fell 4% to 78%. Time per iteration was 2.31 to 2.89 s, against 2.19 to 2.46 s at default, on different nodes.
- **It doesn't make results match.** Paths still split at iteration 57 to 59 and stacks at 57 to 69, and objectives ranged from 5.36 to 27.66. Pin the path and stack as well: see [reproducible results](#reproducible-results).
- **It isn't always better.** Source on Haswell went from 5.36 to 27.66. Both Cooperlake runs ended near 5.5, and both Haswell runs ended above 24.
- **Two routes reached the same gait.** Prebuilt Cooperlake with tighter pivoting (5.361) and source Haswell at default (5.358) differ by 0.15° RMS across joint angles. 5.36 is the lowest objective seen on this problem, but that doesn't prove it's the global optimum.
- **The higher objectives mostly differ in the arms and actuator cost.** Compared with the 5.36 gait, hip, knee and ankle angles differ by 1.0° RMS for 5.64, 3.1° for 27.66 and 7.4° for 24.54, while arm coordinates differ by up to 61°. The actuator excitation term is 1290 at 5.36, 1544 at 5.64, 18448 at 24.54 and 21945 at 27.66.

**Later runs changed this picture** ([Ipopt settings](#ipopt-settings)): the exits at 24 to 86 were early stops, tighter pivoting alone needs up to 48 GB and doesn't help the current `main.m` problem, and 5.36 is the same gait as the 5.33 that the default settings now reach.

## Ipopt settings

**Short answer.** The failed and scattered long runs above were not caused by a broken
install or a faulty maths library. Three of Ipopt's default settings don't suit these
problems. With them changed, the runs converge. `linux/run_predsim.sh` now applies the
changed settings by default (PredSim `d2147e4`):

```
ma97_u=1e-2;ma97_umax=1e-1;ma97_scaling=mc64;nlp_scaling_method=none;obj_scaling_factor=1e-3;mu_max=1;dual_inf_tol=1e-3
```

Set `PREDSIM_IPOPT_OPTIONS=none` to get Ipopt's own defaults back, or give your own list
(PredSim `linux/README.md`, "Ipopt options").

**Method.** 5 to 6 Nov 2026, about 520 jobs. Two problems, both
`Falisse_et_al_2022_lightfoot_alpha0dot5` at 9.2 m/s from `OCP/motion_saved.mot`:

- **Half cycle:** `main.m` and `OCP_formulation.m` from PredSim `239530b`, as in
  [what changes the result](#what-changes-the-result).
- **Full cycle:** the current `main.m`, as in [the long runs](#long-runs-no-solution-found).

Unless stated, runs used MA97 on 4 threads and 4 CPUs on epyc3 nodes. Repeats of a setting
differ in the OpenBLAS code path (Haswell, Sandybridge, Nehalem, Prescott) and the CasADi
stack. Those are the things that changed the outcome before, so here they act as random
seeds. Runs had an Ipopt wall limit of 1.7 to 5 hours, and "Optimal" means Ipopt's
`Optimal Solution Found` with the constraint violation below 10⁻⁶. Objectives are unscaled.
Many runs shared each node, so times are about twice those of a quiet node.

### What goes wrong with Ipopt's defaults

**1. The first factorisation is inaccurate.** MA97's default pivot threshold (`ma97_u`)
is 10⁻⁸. The first matrix has 402,110 rows, 52,000 to 59,000 delayed pivots, and Jacobian
entries from 10⁻¹⁶ to 2 million. Ipopt's detailed log (`print_level 7`) at iteration 0:

| Setting, code path | What MA97 returned | Barrier parameter chosen |
|---|---|---|
| Default, Cooperlake | Refinement fails (residual ratios 0.28, 0.094, 0.017); Ipopt raises the threshold itself | 585 |
| Default, Haswell | One negative eigenvalue too many (196,056 against 196,055); Ipopt adds regularisation | 0.65 |
| `ma97_u` 10⁻², either path | Right inertia, residual ratio 10⁻⁸ to 10⁻⁷ | 0.52 |
| MA57, default | Residual ratio 1.6·10⁻⁴ | 0.49 |

So at the default threshold the first step depends on rounding, and the two code paths
start the run with barrier parameters 900 times apart. MATLAB's own sparse factorisation,
which shares no code with MA97 or OpenBLAS, shows the same thing on the same matrix: a
relative solve error of 2.8 at a threshold of 10⁻⁸, 10⁻² at 10⁻⁶, 3·10⁻⁶ at 10⁻⁴ and
6·10⁻⁸ at 10⁻². Why Ipopt's threshold is that loose, and what its fallbacks did, is in
[bug fixes 5.8](bug_fixes_%26_tweaking.md#58-the-first-factorisation-is-inaccurate-at-ipopts-default-pivot-threshold).

**2. The objective is scaled by about 10⁻⁵.** Ipopt's default scaling divides the
objective by its largest gradient entry at the starting guess. The guess is far from a
solution (objective 2.8 million, against about 5 at the optimum), so the factor is
7.3·10⁻⁶ on the half-cycle problem and 1.0·10⁻⁵ on the full-cycle one. Ipopt's
convergence test works on the scaled problem, so `tol` 10⁻⁴ is in effect about 10
unscaled. Runs passed it within 4 to 7 iterations of first becoming feasible, with an
unscaled optimality error (dual infeasibility) of 0.008 to 0.5. Rerun with only that
limit tightened (`dual_inf_tol` 10⁻³), three such runs replayed their paths exactly,
passed their old exit and carried on: 27.66 became 7.43, 86.21 became 5.64, and 24.54
reached 5.36. The "Optimal" results between 24 and 86 in the earlier tables were early
stops, not separate solutions.

**3. The adaptive barrier parameter jumps.** With `mu_strategy=adaptive` the barrier
parameter moved between 10⁻⁵ and 10³ to 10⁴ from one iteration to the next. On the
full-cycle problem the dual infeasibility then grew to 10⁹ to 10¹⁰, steps shrank to 10⁻⁴
of a full step, and every run went into restoration near iteration 400 and stayed near a
violation of 2,600. Capping the parameter (`mu_max=1`) or using the monotone strategy
removed the restoration phase completely on that problem.

**What it isn't:**

- **Not an OpenBLAS bug.** Every code path (Prescott, Core2, Nehalem, Sandybridge,
  Haswell, Zen, SkylakeX, Cooperlake) gave errors of at most 12 rounding units on dgemm,
  dsyrk, dtrsm, dtrsv, dgemv, ddot, daxpy and dger against a plain reference, sizes 1 to
  500. Haswell and Zen are bit-identical, as are SkylakeX and Cooperlake.
- **Not the inputs.** The starting guess, bounds, objective, constraints, gradient and
  Jacobian at the start hash identically across both CasADi stacks and across 4 and 8
  CPUs. The stacks differ inside Ipopt and the linear algebra, not in the problem.
- **Thread count does change MA97's result.** With the same 8 CPUs and identical
  inputs, MA97 at 1, 2, 4 and 8 threads split at iteration 26 to 31 (default threshold)
  or 59 to 73 (`ma97_u` 10⁻²). The mechanism inside MA97 wasn't isolated.

### Results by setting

"Tighter" means `ma97_u=1e-2;ma97_umax=1e-1`. Every row also has `dual_inf_tol=1e-3`.
"Scaling off" means `nlp_scaling_method=none`; "objective factor" is `obj_scaling_factor`
on top of that. Counts are runs that reached Optimal out of runs made; a run that didn't
either failed or hit its wall limit. Iterations and objectives are for the Optimal runs.

| Setting | Half cycle: Optimal | Iterations; objective | Full cycle: Optimal | Iterations; objective | Peak memory, GB |
|---|---|---|---|---|---|
| Ipopt defaults, MA97 | 0 of 6 |  | 0 of 4 |  | 13 |
| Ipopt defaults, MA57 | 0 of 8 |  | 0 of 2 |  | 24 |
| Ipopt defaults, MUMPS | 0 of 5 |  | 0 of 2 |  | 10 |
| Tighter | 13 of 15 | 883 to 2911; 5.36 to 7.43 | 0 of 6 |  | 48 |
| Tighter + MC64 | 5 of 6 | 779 to 1906; 5.36 to 7.43 | 0 of 4 |  | 10 |
| Tighter + monotone barrier | 0 of 8 |  | 4 of 4 | 1046 to 3809; 6.06 to 6.10 | 28 |
| Tighter + MC64 + `mu_max=1` | 0 of 6 |  | 6 of 6 | 448 to 622; 5.81 to 5.83 | 10 |
| Tighter + scaling off | 7 of 7 | 1361 to 1642; 5.59 | 9 of 9 | 790 to 1086; 6.75 to 6.83 | 12 |
| Tighter + MC64 + scaling off | 8 of 8 | 1330 to 1654; 5.59 | 8 of 8 | 772 to 936; 6.77 to 6.83 | 10 |
| Tighter + MC64 + scaling off + `mu_max=1` (first default, `04839db`) | 8 of 8 | 809 to 908; 5.33 | 6 of 8 | 1058 to 1940; 5.83 to 5.84 | 10 |
| The same without MC64 | 8 of 8 | 791 to 1506; 5.33 | 8 of 8 | 1075 to 1606; 5.83 to 5.84 | 25 |
| The same + objective factor 1e-5 | 3 of 4 | 589 to 909; 5.35 | 4 of 4 | 533 to 634; 5.80 to 5.81 | 10 |
| The same + objective factor 1e-4 | 7 of 7 | 530 to 611; 5.33 | 6 of 7 | 614 to 1032; 5.76 to 5.79 | 10 |
| **The same + objective factor 1e-3 (default, `d2147e4`)** | 7 of 7 | 529 to 679; 5.33 | 6 of 7 | 637 to 926; 5.78 to 5.81 | 10 |

- **Ipopt's defaults never converged,** with any linear solver, on either problem.
- **Tighter pivoting alone works on the half-cycle problem but is not safe.** It needed
  18 to 48 GB, and at 1.33 and 5 m/s 7 of 8 runs died near the end, 6 killed for memory
  at 48 GB and one with a segmentation fault inside `ma97_factor`. It didn't help the
  full-cycle problem at all.
- **MC64 scaling fixes the memory:** under 10 GB with the same thresholds.
- **Scaling off makes every run converge, on both problems,** but slowly, and on the
  full-cycle problem to a costlier gait (6.75 to 6.83).
- **`mu_max=1` then makes the result repeat.** On the half-cycle problem every such run
  ended at 5.328 to 5.331, the lowest objective seen on that problem, whichever stack,
  code path, thread count or node type it used. MA57 with the same list ended at 5.329
  and 5.332. On the full-cycle problem every finished run ended at 5.83 to 5.84, but took 1,060
  to more than 2,500 iterations and gave a left-right asymmetric gait (see below).
- **A fixed objective factor is faster and avoids that gait.** With `obj_scaling_factor`
  1e-3 the half-cycle problem took 529 to 679 iterations instead of 809 to 908, at the
  same 5.33. The full-cycle problem took 637 to 926 and ended at 5.78 to 5.81; the one
  run that didn't finish was at 5.79 when it hit a 2-hour limit on a slow node. Factor
  1e-5 was the fastest on the full-cycle problem (533 to 634 iterations) but one of four
  half-cycle runs
  stalled. Factor 1e-4 matched 1e-3 on the half-cycle problem and took 614 to 1,032
  iterations on the full-cycle one, some of them with restoration.
- **With Ipopt's scaling left on, `mu_max=1` is fast on the full-cycle problem**
  (448 to 622 iterations) but stuck in restoration on all six half-cycle runs.

**No help, or worse:** monotone barrier on the half-cycle problem (0 of 8), `mu_oracle`
`loqo`, L-BFGS history 20 or 50, SR1 updates, `expect_infeasible_problem`,
`recalc_y`, `adaptive_mu_globalization=kkt-error`, other L-BFGS start values,
`nlp_scaling_max_gradient` 1e4, `mu_max` 10, `ma97_scaling=none` (4 of 4 killed for
memory at 32 GB), and MA57 with `ma57_pivtol` 1e-2 (about 40 s per iteration). `tol`
1e-3 was no faster. `mu_max=1` with `bound_push` 0.1 and scaling off was worse than
either alone.

### Validation through the job script

The full-cycle problem, submitted with `bunya/run_predsim.slurm` and nothing but resource
flags: 2 CPUs, 1 thread, 16 GB, Haswell path and source stack unless stated. Only the
first speed of `main.m`'s loop (9.2 m/s) counts.

| Settings | Node | Exit | Iterations | Objective | Minutes | Peak GB |
|---|---|---|---|---|---|---|
| Default list (`d2147e4`) | epyc4 | Still running: objective 5.84 at iteration 409 | | | |  |
| | epyc3 | Still running: objective 14.69 at iteration 241 | | | |  |
| | epyc4 (no node flags) | Still running: objective 5.84 at iteration 408 | | | |  |
| | epyc5 | Still running: objective 13.32 at iteration 250 | | | |  |
| | epyc4, prebuilt stack | Still running: objective 5.89 at iteration 406 | | | |  |
| The same list passed as `PREDSIM_IPOPT_OPTIONS` on `04839db` | epyc4 | Optimal | 926 | 5.794 | 55 | 9.6 |
| | epyc3 | Optimal | 926 | 5.794 | 76 | 9.7 |
| First default (`04839db`) | epyc4, `OPENBLAS_CORETYPE=auto` | Optimal | 1161 | 5.832 | 71 | 9.5 |
| | epyc3, prebuilt stack | Optimal | 1318 | 5.840 | 99 | 9.6 |
| | epyc3, 4 CPUs and 4 threads | Optimal | 1845 | 5.840 | 121 | 9.7 |
| | epyc4, 4 CPUs and 4 threads | Optimal | 1845 | 5.840 | 123 | 9.9 |
| | epyc3, epyc4 (two runs), epyc5 | Still running at 5.82 after 1,840 to 2,960 iterations | | | | |
| Ipopt defaults (`PREDSIM_IPOPT_OPTIONS=none`) | epyc3 | Still running: objective 124, violation 0.7, 910 restoration iterations after 2,929 | | | | |

- **The node type no longer matters.** epyc3 and epyc4 printed the same iteration count and
  objective with the default list, and the benchmark run with the same settings matched them.
- **The first default converged but slowly:** four runs took 71 to 123 minutes and four were
  still polishing after more than 1,800 iterations.
- **Ipopt's defaults fail through the same path,** so the difference is the settings.

### Other speeds

One starting guess, both problems, 2 runs each, MA97 on 4 threads. Each cell gives the runs
that reached Optimal, their iteration counts and their objectives.

| Problem, speed | Ipopt defaults | First default (`04839db`) | Default (`d2147e4`) |
|---|---|---|---|
| Half cycle, 1.33 m/s | 2 of 2; 382, 1099; 0.292, 0.382 | 2 of 2; 2203, 2324; 0.174 | 0 of 2 (2 running) |
| Half cycle, 5 m/s | 2 of 2; 1373, 1870; 0.541, 2.177 | 2 of 2; 1133, 1308; 0.500, 0.501 | 2 of 2; 736, 986; 0.501 |
| Full cycle, 1.33 m/s | 2 of 2; 335, 531; 0.264 | 2 of 2; 1363, 1772; 0.179, 0.224 | 0 of 2 (2 running) |
| Full cycle, 5 m/s | 2 of 2; 73, 1001; 0.542, 57.734 | 1 of 2; 1893; 0.510 | 0 of 2 (2 running) |

- **Ipopt's defaults stop early here too.** Their "Optimal" exits had an unscaled
  optimality error of 0.0002 to 0.35. One 5 m/s run stopped at iteration 73 with an
  objective of 57.7, where the others reached 0.54.
- **Tighter pivoting alone:** 7 of 8 died, as above.

### The solutions are different gaits

The runs end at a handful of objectives, and they are different gaits, not one gait
reached to different accuracy. One exception: 5.36 in the earlier tables is the same
gait as 5.33 (0.6 degrees RMS apart), stopped slightly early.

| Problem | Objective | Gait |
|---|---|---|
| Half cycle | 5.33 (and 5.36) | Lowest seen. MA57 and MA97 give the identical motion |
| Half cycle | 5.59, 5.64 | Legs within 1.5 degrees RMS of the 5.33 gait; arms differ by about 21 degrees RMS |
| Half cycle | 7.43 | Legs within 2.1 degrees RMS; arms differ by 35 degrees RMS |
| Full cycle | 5.80 to 5.83 | Symmetric: both knees flex to 78 to 80 degrees in swing, both arms swing to 15 to 17 degrees |
| Full cycle | 5.76 to 5.79 | Slightly asymmetric: knees 81 to 88 and 77 to 78 degrees, arms as above |
| Full cycle | 5.83 to 5.84 | Asymmetric: knees 110 and 76 degrees, arms 50 and 10 degrees |
| Full cycle | 5.91 to 6.10 | Knees within 6 degrees of each other; arms or trunk differ |
| Full cycle | 6.75 to 6.83 | Asymmetric: knees 111 and 62 degrees, both arms to 50 degrees |

The full-cycle problem doesn't force left and right to match, so it has asymmetric
optima at almost the same cost as the symmetric one, and one slightly below it. Which
a run reaches depends on its early path, and that depends on the settings: scaling off
with no objective factor gave one of the two strongly asymmetric gaits in every one of
49 runs. The default list gave 5.808 (knees 79 and 78 degrees) in two runs and 5.78 to
5.79 (knees 84 to 85 and 77 to 78) in four. Nothing here shows which is the global
optimum, so check the gait, not only the exit message.

### Limits

- **One subject, one starting guess.** Speeds other than 9.2 m/s had 2 runs per setting.
- **Loaded nodes.** Times are from nodes shared with up to 200 of these jobs, so they
  rank settings by iterations more reliably than by minutes.
- **The full-cycle problem has a long tail.** Its objective is within 0.1% of final a
  few hundred iterations before Ipopt stops. Ipopt's "acceptable" stopping rule was
  replayed on the logs and would not have triggered, so it isn't a fix.
- **The objective factor is fixed, not derived.** 1e-3 suits objectives of order 1 to
  10 at the solution. Three values were tried, on one subject.
- **The default was chosen late.** It has fewer runs behind it than the settings it
  replaced, and its other-speed runs were still going when this was written.
- **Windows wasn't tested.** The same options can be set in `main.m` (PredSim
  `linux/README.md`).
- **Result files:** `/scratch/user/<user>/predsim-night/` on Bunya holds every run
  (`runs/<tag>/`, `specs-*.txt` for the settings, `summ.sh` for a one-line summary).
  Scratch is cleared after a period of no use.

## Reproducing

```bash
# one benchmark run (any stack env file), 80 iterations
sbatch --constraint=epyc3 --prefer=epyc3 \
  --export=ALL,PREDSIM_ENV=<stack>/env.sh,PREDSIM_SCRIPT=linux/bench/bench_predsim,PREDSIM_BENCH_ITERS=80,PREDSIM_BENCH_IG=<guess.mot> \
  bunya/run_predsim.slurm
# compare logs / draw the thread graph
python3 -I ~/PredSim/linux/bench/compare_bench.py predsim-*.out
python3 -I ~/PredSim/linux/bench/plot_threads.py out.png predsim-*.out --cpus-offset 2
```

Run concurrent jobs from a checkout whose `F_*.so` already exists, or each
job compiles its own copy at the same time.
