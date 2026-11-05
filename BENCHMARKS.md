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
| HSL instead of MUMPS? | Unsettled. Over 80 iterations MA57 was 20–38% faster per iteration, but that didn't hold on longer runs, where MA97 on 4 threads did best. The long runs on the current problem didn't reach a solution; on the problem from `239530b` results depend heavily on small numerical differences, so one run can't rank solvers. See [HSL](#hsl-ma97-and-ma57), [long runs](#long-runs-no-solution-found) and [what changes the result](#what-changes-the-result). |
| CPU-tuned CasADi? | Small gain: about 3% overall in the one clean comparison. See [long runs](#long-runs-no-solution-found). |
| Threads (`S.solver.N_threads`)? | No benefit. The current code is single-threaded, and with the fix it matches 16 threads at about a ninth of the fair-share charge. |
| Multithreaded MUMPS? | Works after a fix, and 16 threads cut an iteration from 4.95 to 3.69 s. That costs about 6× the fair-share charge, and results change from run to run, so it isn't the default. See [Multithreaded MUMPS](#6-multithreaded-mumps). |
| Prebuilt or source CasADi? | Bunya: both are installed and each node uses its faster one: prebuilt on epyc4 (7% faster), source on epyc3 (16% faster). Source-mode builds there were broken until 3 Nov 2026 (see [section 6](#6-multithreaded-mumps)). Ubuntu workstation: source (about 10% faster). **Prebuilt did worse on optimality at MA97's default pivoting:** none of its runs reached a solution, while most source runs on the same problem did. With tighter pivoting, both stacks reached one on both paths. See [prebuilt vs source](#prebuilt-vs-source-optimality). |
| Which Bunya CPU? | epyc4 is fastest. Jobs *prefer* it; one install runs on all types. |
| How many CPUs per job? | 2 (one physical core). More gives no speed-up. |
| Why do CPUs give different results? | MA97's OpenBLAS picks its code path by CPU, and at MA97's default pivot threshold the first step is very sensitive to that. Every path tested differs, not only AVX-512. See [what changes the result](#what-changes-the-result). |
| How do I get the same result every time? | Bunya jobs now fix the OpenBLAS path to Haswell by default. Keep the stack, solver and threads the same as well. See [reproducible results](#reproducible-results). |

## Reproducible results

To get the same result every time, keep all of these the same:

| Keep the same | How |
|---|---|
| OpenBLAS code path | Option 1 or 2 below |
| CasADi stack | Set `PREDSIM_CASADI_MODE` to `source` or `prebuilt`; otherwise the stack can change with the node type |
| Solver and threads | `PREDSIM_HSL_SOLVER`, `OMP_NUM_THREADS` and `--cpus-per-task` |
| Code and inputs | The same commit, `main.m`, solver options and starting guess, and the same muscle fit and `F_*` files in `Subjects/<subject>` |

**Option 1: force the OpenBLAS path.** `bunya/run_predsim.slurm` does this by default: it sets
`OPENBLAS_CORETYPE=Haswell` on every node type. That's for matching results, not speed. Only the
stack is left to fix:

```bash
sbatch --export=ALL,PREDSIM_CASADI_MODE=source bunya/run_predsim.slurm
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
- **Tested with:** MA97 on 4 threads. epyc4 forced to Haswell matched epyc3 on its default path for whole runs, on both stacks. Forcing Haswell on epyc3 or epyc5, and forcing it with MA57 or MUMPS, weren't tested.
- **OpenMP MUMPS:** `--mumps-openmp` builds don't repeat, so don't use them when results must match.
- **Rerun scripts:** they keep the CPU type, stack, threads and `OPENBLAS_CORETYPE`. Older rerun scripts don't record `OPENBLAS_CORETYPE`, so add it to those by hand.
- **Convergence:** these settings make a result repeat, not converge. A run that fails will fail the same way.

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

- **Bunya installs both by default:** `--prefer=epyc4` is only a preference, so many jobs run on epyc3, where source saves 14% of the time. `~/.predsim/env.sh` reads the node's CPU model at job start and sources the source stack on epyc3 and the prebuilt one elsewhere (`SITE_STACK_BY_ARCH` in `sites/bunya.env`). The cost is about 30 more minutes of install and a second check run. epyc5 keeps prebuilt until the fixed source build is measured there.
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
than the install. The cause hasn't been established. Suspects are the new touchdown
bounds, `main.m`'s relaxed tolerances being commented out, and the starting guess.

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
- **No sign of an AVX-512 bug,** but kernel accuracy wasn't measured directly.
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

**Limits:** one speed (9.2) and one starting guess on the `239530b` problem. These settings haven't been repeated, or run on epyc3 or on the current `main.m` problem, where no long run has found a solution.

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
