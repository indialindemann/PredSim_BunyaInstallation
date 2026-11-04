# PredSim on Linux: bug fixes and tweaking

Every non-obvious bug, fix and performance tweak found while getting PredSim
running on Linux and on UQ's Bunya cluster. For each one: what went wrong, how
it was found, and the exact fix. All of this work was done in November 2026.

The full timing tables are in [BENCHMARKS.md](BENCHMARKS.md). This report
covers how the problems were found and fixed.

**Commit labels:** `installer` is this repo, branch `linux`. `PredSim` is
`indialindemann/PredSim`, branch `linux/cleancurvev4`.

## Contents

- [Quick index](#quick-index)
- [Part 1: Compiler flags and speed](#part-1-compiler-flags-and-speed)
- [Part 2: Linking to MATLAB](#part-2-linking-to-matlab)
- [Part 3: Building and installing](#part-3-building-and-installing)
- [Part 4: PredSim code on Linux](#part-4-predsim-code-on-linux)
- [Part 5: Benchmarking mistakes and pitfalls](#part-5-benchmarking-mistakes-and-pitfalls)
- [Reference: settings used](#reference-settings-used)
- [Reference: debugging commands](#reference-debugging-commands)
- [Still open](#still-open)

## Quick index

| # | Symptom | Cause | Fix |
|---|---|---|---|
| [1.1](#11-external-function-compiled-at--o0) | Linux far slower than expected | External function built at `-O0` | `CMAKE_BUILD_TYPE=Release` |
| [1.2](#12-no-cpu-specific-instructions-in-the-external-function) | No AVX or FMA in the function | `-O3` targets generic x86-64 | `-march=znver3` on Bunya |
| [1.3](#13-threads-had-no-effect) | `N_threads` does nothing | `expand = true` is single-threaded | Keep it, and request 2 CPUs |
| [1.4](#14-neither-casadi-build-is-fastest-everywhere) | No single best CasADi build | Differs by CPU type | Install both, choose per node |
| [2.1](#21-matlab-rejects-newer-c-libraries) | `GLIBCXX` errors in MATLAB | MATLAB bundles an old `libstdc++` | Compiler choice or preload |
| [2.3](#23-libraries-only-worked-with-ld_library_path) | Libraries not found in MATLAB | Dependencies relied on `LD_LIBRARY_PATH` | RPATHs, `bake_rpath` |
| [2.5](#25-mkl-error-parameter-11--on-entry-to-dtrsm) | `MKL ERROR ... DTRSM`, diverging solves | Bunya pthreads OpenBLAS with MUMPS | Link the OpenMP OpenBLAS |
| [2.7](#27-matlab-taking-over-hsls-calls) | Segfaults with HSL, source stack only | MATLAB's symbols replacing HSL's | `RTLD_DEEPBIND`, static link, `-Bsymbolic` |
| [3.3](#33-module-python-hid-the-venvs-python) | `genF.py` can't import casadi | Module python shadows the venv | Load modules before setting `PATH` |
| [3.5](#35-coinhsl-can-silently-build-without-metis) | HSL could lose METIS unnoticed | Missing `metis.h` links a dummy | Install fails if METIS is absent |
| [5.1](#51-the-install-check-passed-on-a-broken-stack) | Broken stack passed its check | Check only tested that it ran | Fail on BLAS errors |
| [5.2](#52-timings-skewed-by-node-load) | Comparisons changed between runs | Busy shared nodes | Submit paired jobs together |

## Part 1: Compiler flags and speed

### 1.1 External function compiled at `-O0`

**Symptom.** Windows looked faster than Linux on similar hardware, with no
explanation from CasADi or Ipopt.

**How it was found.** Ipopt's timing table showed `nlp_jac_g` taking about
60–65% of each iteration. That call spends its time in the model's external
function, `Subjects/<subject>/F_<subject>.so`, so I compared how each platform
builds that file:

| Platform | Build command | Optimisation |
|---|---|---|
| Windows (`opensimAD`) | `cmake --build . --config RelWithDebInfo` | MSVC `/O2` |
| Linux (`opensimAD_linux`) | `make install`, no build type | **None** |

Reproducing the Linux compile showed the actual command had no `-O` flag:

```
gcc -DF_..._EXPORTS -fPIC -c foo_jac.c
```

**Fix.** CMake 3.22 and later read the build type from an environment variable,
so no opensimAD code had to change. `linux/run_predsim.sh` now has:

```bash
export CMAKE_BUILD_TYPE="${CMAKE_BUILD_TYPE:-Release}"   # -O3 -DNDEBUG
```

**Result (epyc3, 2 repeats).**

| | `nlp_jac_g` per call | s / iteration |
|---|---|---|
| `-O0` | 5.30 s | 8.44 |
| `-O3` | 1.87 s | **4.73** (1.78× faster) |

- **Cost:** compiling takes about 170 s rather than 20 s, once per model.
- **Catch:** PredSim reuses an existing `F_*.so`, so older files stay slow until deleted.
- **Commit:** PredSim `68a2904`.

### 1.2 No CPU-specific instructions in the external function

**Question.** You asked whether the function is tuned for the CPU it runs on. It
wasn't. Disassembling the `-O3` build showed no `ymm` or `zmm` registers and no
FMA in about 470k instructions.

**The constraint.** One `F_<subject>.so` is shared by every node, and it's built
by whichever job first needs it. `-march=native` on an epyc4 node would emit
AVX-512, which would crash with an illegal instruction on epyc3. `-march=znver3`
runs on Zen3, Zen4 and Zen5.

**How it was tested.** CMake reads `CFLAGS` from the environment on first
configure. Three builds of the same function, paired on each node type:

| Build | Size | FMA instructions | AVX-512 instructions |
|---|---|---|---|
| `-O3` | 2.13 MB | 0 | 0 |
| `-O3 -march=znver3` | 1.52 MB | 47,478 | 0 |
| `-O3 -march=znver4` | 1.46 MB | 47,479 | 586 |

**Result.** `znver3` made `nlp_jac_g` 28% faster per call on epyc3 and epyc4. An
iteration on epyc4 went from 4.21 to 3.70 s. `znver4` was no faster per call.

**Fix.**

```bash
# sites/bunya.env
SITE_EXTFUN_CFLAGS="-march=znver3"
# written to env.sh as PREDSIM_EXTFUN_CFLAGS, then in linux/run_predsim.sh:
export CFLAGS="${CFLAGS:+$CFLAGS }$PREDSIM_EXTFUN_CFLAGS"
```

The local workstation uses `-march=native`, since it's one machine. That setting
wasn't benchmarked.

**Side effect.** FMA rounds differently, so each build takes a slightly different
solver path. Compare builds by time per call, not by the iterate at a given
iteration.

**Commits:** installer `6d6bf47`, PredSim `83fca05`.

### 1.3 Threads had no effect

**Symptom.** Raising `S.solver.N_threads` on Bunya changed nothing:

| `N_threads` | CPUs | s / iteration |
|---|---|---|
| 4 | 6 | 8.34 |
| 8 | 10 | 8.39 |
| 16 | 18 | 8.21 |

**How it was found.** The flat result looked wrong, so I searched the history of
`OCP/solve_NLPSOL.m`. Commit `b04b660` on cleancurvev4 had set
`optionssol.expand = true`, which makes the solve single-threaded. A scratch copy
with `expand = false` used 68.2 s of CPU in 18.3 s of elapsed time at 4 threads,
confirming threading only works in that mode.

**Why single-threaded still wins.** `expand = false` scales (1.85× at 16 threads),
but its evaluations are slow: about 12.5 s of CPU per `nlp_jac_g` against 1.9 s
expanded. After the `-O3` fix, single-threaded on 2 CPUs (4.7 s) matches 16
threads, at about a ninth of the fair-share charge.

**Fix.** No code change. `run_predsim.slurm` requests `--cpus-per-task=2`.

### 1.4 Neither CasADi build is fastest everywhere

**Finding (paired, s / iteration).**

| Node | Prebuilt | Source |
|---|---|---|
| epyc4 | **4.12** | 4.41 |
| epyc3 | 5.34 | **4.59** |

**The complication.** `--prefer=epyc4` is only a preference, so jobs can land on
either type, and code paths recorded at install must work on both.

**Fix.** `--casadi both` installs both stacks. `~/.predsim/env.sh` becomes a small
selector that reads the CPU model at job start:

```bash
# sites/bunya.env
SITE_CASADI_MODE_DEFAULT="both"
SITE_STACK_BY_ARCH="epyc3=source *=prebuilt"
```

The file is replaced with `mv`, not written in place. Writing to the old path
would have followed its symlink and overwritten a stack's `env.sh`.

**Commit:** installer `895c314`.

### 1.5 Forcing a node type needs two options

**Symptom.** `sbatch --constraint=epyc3 bunya/run_predsim.slurm` still ran on epyc4.

**How it was found.** Test jobs on Bunya. The script's `#SBATCH --prefer=epyc4`
replaces `--constraint` whenever it can be met.

**Fix.** Pass both: `--constraint=epyc3 --prefer=epyc3`. Documented in the README
and the script. **Commit:** installer `87852d4`.

## Part 2: Linking to MATLAB

MATLAB loads its own copies of many common libraries, and that causes most of the
bugs below. A library that works in a terminal can fail or misbehave inside
MATLAB. The first rule that came out of this: **test libraries the way MATLAB
loads them**.

### 2.1 MATLAB rejects newer C++ libraries

**Symptom.** Loading fails with `GLIBCXX_3.4.xx not found`.

**Cause.** MATLAB uses its bundled `libstdc++`, which limits how new a compiler's
output can be:

| Machine | MATLAB's limit | Compiler available | Result |
|---|---|---|---|
| Ubuntu workstation (R2024b) | `GLIBCXX_3.4.30` | gcc 13 needs 3.4.32; gcc 12.3 needs 3.4.30 | Use gcc 12.3 |
| Bunya (R2023b) | `GLIBCXX_3.4.28` | Every gcc module is newer (gcc 12.3 needs 3.4.30) | Preload the newer runtime |

**Fix on Bunya.** Preload the toolchain's runtime into the MATLAB process only.
`libstdc++` is backward compatible, so MATLAB itself still works.

```bash
# env.sh, computed per node so it uses that node's own module tree
export PREDSIM_MATLAB_LD_PRELOAD="$(for l in libstdc++.so.6 libgcc_s.so.1; do \
    printf '%s:' "$(g++ -print-file-name=$l)"; done | sed 's/:$//')"
# linux/run_predsim.sh applies it to MATLAB alone
MATLAB_ENV=(env "LD_PRELOAD=$PREDSIM_MATLAB_LD_PRELOAD${LD_PRELOAD:+:$LD_PRELOAD}")
```

The installer's preflight step checks this rule before compiling anything.

**Commits:** installer `577b227`, `dd85b23`; PredSim `cfc2099`.

### 2.2 Fortran code needs the newer `libgfortran`

**Cause.** Source-built MUMPS and CoinHSL are compiled by gcc 12, so they need its
`libgfortran`. MATLAB's own copy is older.

**Fix.** Add `libgfortran.so.5` and `libquadmath.so.0` to the preload for source
stacks. This initially missed HSL on the prebuilt stack. I spotted that while
reading the build files, before the first HSL run, and extended it:

```bash
if [[ "${CASADI_MODE:-}" == source || -f "${PREFIX:-}/hsl/lib/libhsl.so" ]]; then
    libs+=" libgfortran.so.5 libquadmath.so.0"
fi
```

**Commit:** installer `b287588`.

### 2.3 Libraries only worked with `LD_LIBRARY_PATH`

**Symptom.** The original install built a long `LD_LIBRARY_PATH` by hand, and
deleting build folders broke OpenSim in MATLAB. On Bunya, a job failed with
`libcoinmumps` unable to find `libmetis.so`, leaving the jobs that depended on it
stuck at `DependencyNeverSatisfied`.

**How it was found.** The stuck dependency led to the failed install log. Checking
`ldd` with no `LD_LIBRARY_PATH` showed the missing library. The cause is that
libtool silently drops `-Wl,-rpath` for libraries outside its own search paths, so
a build can look fine while the module is loaded and then fail in MATLAB, which
runs without the module's environment.

**Fix.** Two helpers in `lib/common.sh`:

- **`bake_rpath FILE...`** records each dependency's resolved folder in the file's RUNPATH using `patchelf`, excluding system folders.
- **`ldd_unresolved FILE`** checks a library as MATLAB would load it, with no `LD_LIBRARY_PATH` and with the site's preload applied. The preload matters: on Bunya the system `libstdc++` is older than gcc 12's, so a plain `ldd` gave false errors.

```bash
env -u LD_LIBRARY_PATH LD_PRELOAD="$pre" ldd "$1" | grep -E "not found|version .* not found"
```

Env files no longer set `LD_LIBRARY_PATH` at all.

**Commits:** installer `9a1f213`, `1fe7f8a`.

### 2.4 Smaller library-path problems

| Problem | Effect | Fix | Commit |
|---|---|---|---|
| opensimAD's SimTK recorder libraries have no RUNPATH | Need `libopenblas.so.0` from a global path | `patchelf --set-rpath '$ORIGIN'`, and link OpenBLAS beside them | `997d07b` |
| `javalibrarypath.txt` was appended to with `>>` on each install | Duplicate and stale entries; it's shared by all stacks, so a run could load another stack's OpenSim library | `run_predsim.sh` rewrites it from `PREDSIM_JAVA_LIBRARY_PATH` when it differs, and backs up the original once | `f3b3b76` (PredSim) |
| CasADi's self-contained mode sets RPATH to `$ORIGIN` only | Couldn't find Ipopt | Copy `libipopt.so*` and `libcoinmumps.so*` next to CasADi | `997d07b` |
| A rebuilt Ipopt left an old copy next to CasADi | Changes wouldn't take effect | The `ipopt` step removes the `casadi` step's done-marker | `ae036de` |

### 2.5 `MKL ERROR: Parameter 11 ... on entry to DTRSM`

This took three attempts to explain, and my first two explanations were wrong.

**Symptom.** Source-built MUMPS on Bunya printed thousands of these errors. The
solve then diverged: objective about 1.4×10⁸ at iteration 80, against about 70 for
good runs, and some runs were 10× slower.

**Wrong explanation 1: OpenMP.** The errors first appeared in an OpenMP MUMPS test,
so I blamed calling a pthreads OpenBLAS from OpenMP threads. I shipped a fix and
documented that cause. But the ordinary source stack, with no OpenMP, had the same
errors. They had gone unnoticed because the check still passed
([5.1](#51-the-install-check-passed-on-a-broken-stack)).

**Wrong explanation 2: calls going to MKL.** The message says "Intel MKL", so the
obvious guess was MUMPS calling MATLAB's MKL.

**How that was ruled out.** A dynamic-linker trace in the real process:

```bash
LD_BIND_NOW=1 LD_DEBUG=bindings LD_DEBUG_OUTPUT=trace run_predsim.sh ...
grep -h "dtrsm_" trace* | grep coinmumps
```

MUMPS's `dtrsm_` was bound to OpenBLAS. The text says "MKL" because OpenBLAS
reports bad arguments through `xerbla_`, a weak symbol that MATLAB's MKL overrides.
The error came from OpenBLAS, printed by MKL's handler.

**What the evidence does show.**

| MUMPS linked to | Result |
|---|---|
| Installer's pthreads OpenBLAS 0.3.32 | Errors, with or without OpenMP |
| OpenMP build of the same OpenBLAS | Clean: check run plus 8 benchmark runs |
| Spack OpenBLAS (local Ubuntu) | Clean |
| Prebuilt CasADi's bundled OpenBLAS | Clean |

**The exact trigger inside the pthreads build was never isolated.** It doesn't
appear on a small test problem, only on PredSim's. The fix is based on what was
tested, not a full explanation.

**Fix.** Bunya's source-mode MUMPS links the OpenMP build:

```bash
make DYNAMIC_ARCH=1 TARGET=HASWELL USE_OPENMP=1 NUM_THREADS=256 LIBNAMESUFFIX=omp libs netlib shared
```

**Commit:** installer `ae036de`.

### 2.6 Same library name means the same library

**Problem.** MATLAB loads OpenSim's JNI library first, which brings in the pthreads
`libopenblas.so.0`. The loader reuses a library already loaded under the same
name, so a second OpenBLAS with that name would never load.

**Fix.** `LIBNAMESUFFIX=omp` gives the OpenMP build its own name. My first version
assumed `libopenblas_omp.so.0`, and the install stopped because the real name is
`libopenblasomp.so.0`, with no underscore. **Commit:** installer `1a2d603`.

### 2.7 MATLAB taking over HSL's calls

This was the hardest bug, and each fix exposed the next failure. It only affected
the source stack.

**The underlying problem.** MATLAB has already loaded its own METIS, MA57, BLAS
and OpenMP libraries. MATLAB's use 64-bit integers where they matter, and HSL uses
32-bit. If the linker sends an HSL call to MATLAB's copy, the arguments are
misread.

**How it was found.** Each round used MATLAB's crash stack trace, then
`LD_DEBUG=bindings` to record where each of HSL's calls actually went.

| Round | Evidence | Call went to | Result | Fix tried |
|---|---|---|---|---|
| 1 | `metis5_adapter → METIS_NodeND → libmetis__MMDOrder` | `METIS_SetDefaultOptions` → MATLAB's `libmwmetis` | Segfault in METIS | Static METIS, `-Bsymbolic` |
| 1 | `ma57ad_ → ma57gd_` in `libmwma57.so` | HSL's own `ma57gd_` → MATLAB's | Segfault in MA57 | Same |
| 2 | `DSWAP` and `dtpsv_` in `mkl.so`; `MKL ERROR: Parameter 13 ... DGEMM` | HSL's BLAS → MATLAB's MKL | Segfault, 6.3 million errors in one MA57 run | Static OpenBLAS |
| 3 | `GOMP_task` in `libiomp5.so`; `DGEMM parameter number 4` | HSL's OpenMP → MATLAB's Intel runtime | MA97 restoration at iteration 1, out of memory | `RTLD_DEEPBIND` |

**Round 1 detail.** `METIS_NodeND` went to the correct library while
`METIS_SetDefaultOptions` went to MATLAB's. That happens because MATLAB exports
`METIS_SetDefaultOptions` under the standard name but renames its node-ordering
routines (`METIS5_NodeND`, `METIS4_NodeND`). The disassembly showed the difference:

```
MATLAB:  mov $0xffffffffffffffff,%rsi     (64-bit -1)
Module:  mov $0xffffffff,%esi             (32-bit -1)
```

With 40 options, that's 320 bytes written into HSL's 160-byte array. This overrun
is inferred from the disassembly and the crash, not directly observed.

**The real cause: one flag.** Every failure was on the source stack, so I compared
how each Ipopt calls `dlopen`:

```bash
objdump -d --no-show-raw-insn libipopt.so.3 | grep -B6 'dlopen@plt' | grep esi
```

| Ipopt | Flags | Meaning |
|---|---|---|
| CasADi's official build | `0xa` | `RTLD_NOW \| RTLD_DEEPBIND` |
| Upstream 3.14, built by the source stack | `0x2` | `RTLD_NOW` |

`RTLD_DEEPBIND` makes a loaded library prefer its own dependencies over global
symbols.

**Final fix: all of these together.**

```bash
# steps/ipopt.sh: same load flags as CasADi's official build
sed -i 's/dlopen(libname.c_str(), RTLD_NOW)/dlopen(libname.c_str(), RTLD_NOW | RTLD_DEEPBIND)/' \
    src/Common/IpLibraryLoader.cpp

# steps/hsl.sh: METIS and OpenBLAS inside libhsl, own symbols bound to itself
meson setup ... -Dprefer_static=true
LDFLAGS="-Wl,-Bsymbolic ..."
```

`build_openblasomp` also had to start producing a static `libopenblasomp.a`
(removing `NO_STATIC=1`). The static linking probably isn't needed now that
`RTLD_DEEPBIND` is in place, though that wasn't tested on its own. I kept it as extra protection, and because the passing
probes tested that build.

**How the fix was checked.** Every HSL call was traced on both stacks and both
solvers:

| Check | Result on both stacks |
|---|---|
| Crashes or MKL errors | None |
| HSL calls recorded | 137 (MA97), 135 (MA57) |
| Calls into MATLAB or MKL | **0** |
| OpenMP calls | All to `libgomp` |
| Check run | Passed |

Calls inside `libhsl`, such as BLAS now, don't appear in a trace, so that part
relies on the library having no BLAS dependency.

**Commits:** installer `734f12f`, `b0f5507`, `fd58344`.

### 2.8 MATLAB's own MA57 can't be used

**Idea.** MATLAB ships `libmwma57.so`, which might have allowed testing before the
licence arrived.

**Test.** Pointing Ipopt's `hsllib` at it failed: `MA57AD ... NE has value****`.
It's built with 64-bit integers, and Ipopt uses 32-bit ones. The same mismatch
later caused [2.7](#27-matlab-taking-over-hsls-calls).

## Part 3: Building and installing

### 3.1 CasADi needed a difficult SWIG fork

**Problem.** The original install compiled CasADi from a private 3.7.1 source,
which needed SWIG 3.0.11, which needed gcc 7. It was the longest and most fragile
step, and its version differed from Windows.

**Finding.** CasADi's `casadi-source-v<ver>.zip` already contains the generated
wrappers and builds with `SWIG_IMPORT=ON`, so **neither build mode needs SWIG**.
The official prebuilt zip also works in MATLAB.

**Fix.** CasADi 3.8.2 either way, with a guard in `steps/casadi.sh` so a future
archive can't silently need SWIG again:

```bash
grep -q 'option(SWIG_IMPORT "Import SWIG" ON)' "$src/CMakeLists.txt" || die ...
cmake ... -DWITH_SELFCONTAINED=ON -DWITH_MATLAB=ON -DWITH_IPOPT=ON \
    -DWITH_BUILD_IPOPT=OFF -DWITH_THREAD=ON -DWITH_DEEPBIND=ON
```

`WITH_DEEPBIND` applies to how CasADi loads its own plugins. It doesn't change how
Ipopt loads HSL, which is why [2.7](#27-matlab-taking-over-hsls-calls) still
happened.

**Related fix.** Self-contained mode installed into `casadi/casadi/` rather than
`casadi/`, so the install prefix is now the stack folder (`997d07b`).

### 3.2 Bunya's module trees differ by CPU

**Problem.** `module load` resolves to `/sw/auto/rocky9a/epyc3|4|5/`. Paths recorded
at install time have to work everywhere, and code built for a newer CPU can crash
with `SIGILL` on an older one.

**Fix.** The install runs on epyc3 (`#SBATCH --constraint=epyc3`), with
`-march=znver3`. Preflight fails on other node types. At run time `module load`
still uses each node's own tree, which is why the preload path is computed per
node ([2.1](#21-matlab-rejects-newer-c-libraries)).

**A false failure along the way.** gcc 12.3 on epyc5 falls back to the epyc3 tree,
which my check rejected. It now accepts the node's tree or epyc3 (`82d6a75`).

### 3.3 Module python hid the venv's python

**Symptom.** On Bunya, opensimAD's `genF.py` couldn't `import casadi`.

**Cause.** `env.sh` set the venv's `PATH` and then ran `module load python`, which
put the module's python ahead of the venv's.

**Fix.** Load modules first, then set `PATH`, and check it when writing `env.sh`:

```bash
( source "$PREFIX/env.sh" >/dev/null 2>&1; [[ "$(command -v python)" == "$PREFIX/python/bin/python" ]] ) || die ...
```

The python module also stays in the run environment, because the venv links its
`libpython`. **Commits:** installer `c10a3dd`, `dd85b23`.

### 3.4 Other build problems

| Problem | How it showed up | Fix | Commit |
|---|---|---|---|
| RHEL puts docopt's CMake config in `lib64/cmake`, which OpenSim doesn't search | OpenSim configure failed on Bunya | Find the file, pass `-Ddocopt_DIR` | `846415a` |
| `ssh -T git@github.com` always exits 1 | Preflight reported no GitHub access | Check the message, not the exit code | `dd85b23` |
| OpenBLAS 0.3.23 has a broken `?gemmt` ([#4005](https://github.com/OpenMathLib/OpenBLAS/issues/4005), fixed in 0.3.24) | Known upstream; Bunya's gcc-12.3 module is 0.3.23 and lacks the patch | Build 0.3.32 | `577b227` |
| OpenSim and Simbody cloned from unpinned `master` | Each install could differ | Pin OpenSim 4.5.2 and its dependencies | `9d7194d` |
| opensimAD libraries downloaded from SourceForge mid-run | Failed downloads left an HTML file behind; compute nodes may be offline | Install once, set `EBROOTOPENSIMAD` | `9d7194d` |
| System python 3.12 lacks `ensurepip` on the workstation | Venv creation failed | Use spack's python 3.11 | `997d07b` |
| A stack-ID assignment using `$([[ ]] && echo)` returned false | Installer exited under `set -e` | Rewrote it as an `if`-style assignment | during `7ae37e0` |
| Editing a comment in a site file made every step look stale, including the hour-long OpenSim build | Input hashes include the site file | `--restamp` marks finished steps current | `997d07b` |

The OpenBLAS 0.3.23 bug was not reproduced on Bunya. The evidence is the upstream
issue plus the module's patch list.

### 3.5 CoinHSL can silently build without METIS

**How it was found.** Reading CoinHSL's `metis/meson.build` before the first real
build. If `metis.h` isn't found, it uses `dummy_metis.f90`, with only a warning at
most. MA57 and MA97 would then lose METIS ordering, which would have quietly
skewed the benchmark.

**Fix.** `steps/hsl.sh` fails unless `libhsl.so` contains the real `METIS_NodeND`,
along with `dgemm_`, `ma97_factor_d` and `ma57ad_`. The HSL tip about making sure
METIS is compiled in is covered by this check. HSL is also built with the same
`SITE_OPT_FLAGS` as the source stack's MUMPS, so the comparison is fair.

**Commit:** installer `b287588`.

### 3.6 `grep -q` with `pipefail` gives false failures

**Symptom.** The install failed with "libhsl.so has no static METIS", yet `nm`
clearly showed `METIS_NodeND`.

**Cause.** `nm ... | grep -q X` under `set -o pipefail`. `grep -q` exits at its
first match, `nm` then gets `SIGPIPE`, and the pipeline reports failure. The small
library's output fitted in the pipe buffer, which hid this until static linking
made the library 25 MB.

**Fix.** `grep X >/dev/null` reads all the input. **Commit:** installer `4faae78`.

## Part 4: PredSim code on Linux

| Problem | How it showed up | Fix | Commit |
|---|---|---|---|
| Windows-only CasADi and results paths in `main.m` | `motion file path ... does not exist` | `platformPaths.m`: Windows paths unchanged on Windows, mapped on Linux | `f3b3b76` |
| `solve_NLPSOL.m` looked only for `libhsl.dll` | Linux could never use HSL | `platformPaths('hsllib', ...)` reads `$PREDSIM_HSL_LIB` | `caabdda` |
| `setenv('PATH', [hsl_bin ';' getenv('PATH')])` ran on Linux | A `C:\` path merged into `PATH`'s first entry | Run it only on Windows | `caabdda` |
| `ma97` was hard-coded | MA57 couldn't be tested | `$PREDSIM_HSL_SOLVER`, default `ma97` | `808328f` |
| `run()` changes to the script's folder | `platformPaths` not found | `run_linux_predsim.m` adds the repo root to the path | `f3b3b76` |
| Upstream's reference test settings no longer fit cleancurvev4 (`S.bounds.points`) | The check run failed, though the install was fine | `verify_stack.m` sets up like `main.m` | `df9f718` |

### Rerun scripts

Each Slurm job now writes `<result>_rerun.slurm`, which requests the same hardware
and settings (PredSim `be2c8eb`). Two details came up:

- **`epyc4` isn't an exact spec.** That feature covers 9124, 9534, 9454 and 9654P nodes, so the script pins the model too: `--constraint=epyc4&9454`.
- **A bash quirk.** `${features//,/&}` printed `epyc4,9454`, because bash 5.2 treats `&` in a replacement as the matched text. A local test with a fake `scontrol`, fed real Bunya output, caught it before any job ran. It now uses `sed`.

**How it was checked.** A real 1-iteration job ran through the default Slurm script and landed on an EPYC 9454 node, then its saved script was submitted as a new job. The rerun got the same CPU model, stack and solver, and reproduced the iterate at iteration 1 (objective `1.5291937`, violation `1.83e+04`). It also landed on the same node (bun126), although only the CPU model was required.

## Part 5: Benchmarking mistakes and pitfalls

### 5.1 The install check passed on a broken stack

**Problem.** The source stack with the DTRSM errors passed its check, because the
check only confirmed that the iterations ran. Timings from those runs looked real
and were used to conclude that prebuilt was as fast or faster.

**Fix.**
- `steps/verify.sh` fails on any `MKL ERROR` or `On entry to X parameter` line.
- `compare_bench.py` counts those lines and warns that the run is invalid.
- All Bunya source-mode timings from before the fix were marked void, including the "tuned builds are slower" result, which has not been re-measured.

**Commits:** installer `ae036de`, PredSim `d65f507`.

### 5.2 Timings skewed by node load

**Problem.** Bunya's nodes are shared. An unpaired run gave 4.31 s against prebuilt's
4.95 s, but paired on the same terms, it was 4.59 against 5.34 on epyc3, and
reversed on epyc4. Repeats can differ by nearly 2× (MA97 at 1 thread on epyc4: 2.70
and 5.05 s).

**What I do now.**
- Submit everything being compared together, and run at least 2 repeats.
- Report the repeats, not just the mean.
- Split time into function evaluations and Ipopt's own time. Evaluations don't depend on the linear solver, so a slow `nlp_jac_g` flags a busy node.

The local workstation was similar. An apparent 27% `nlp_jac_g` slowdown led me to
test `OPENBLAS_NUM_THREADS` and `-march=native`, but the timing there was noisy
enough that only repeated runs could rank stacks.

### 5.3 Different builds take different paths

**Finding.** Each build reproduces its own trajectory exactly on every repeat,
except OpenMP MUMPS. Different builds and CPUs diverge through rounding. At 80
iterations, MA97's constraint violation on epyc4 was about 75, against about 5,700
for MA57.

**What this means.** Time per iteration can't say which solver reaches a solution
first. That's what the convergence runs are for.

### 5.4 My setup mistakes in the `-march` benchmark

Each of these wasted a round of jobs, and each left a safeguard behind.

| Mistake | How it was caught | Lesson |
|---|---|---|
| Warm-start path resolved relative to the scratch copy | Both builds failed within a minute | Pass `PREDSIM_BENCH_IG` explicitly |
| Scratch copies predated `CMAKE_BUILD_TYPE`, so the `-march` builds were `-O0` | The "tuned" files were 2.3× larger with no FMA | Inspect binaries before trusting timings |
| Check job treated `(%rbp)` references as a sign of `-O0` | It failed good builds: AVX code realigns the stack and uses the frame pointer at `-O3` too | Test what you care about: size and FMA |
| Generic jobs had no dependency, so they ran before the others | `squeue` showed them running | Make everything wait for the same gate |

### 5.5 A probe that reported nothing

**Mistake.** My first full binding report searched for `libhsl.so` before stripping
directory paths, so it matched nothing, and the script deleted the traces. An empty
report looked just like a clean one.

**Fix.** The report now prints the number of calls recorded, and the gate requires
it to be above zero. The gate also checks for crashes, MKL errors, calls into
MATLAB, and OpenMP going to `libgomp`. Before relying on it I tested it on old
results: prebuilt passed and the broken source runs failed.

### 5.6 Smaller lessons

- **`DependencyNeverSatisfied`:** with `afterok`, a failed job leaves dependants pending forever. Use `--kill-on-invalid-dep=yes`.
- **Failed installs left `env.sh` as a link to prebuilt,** because the per-CPU selector is only written once both stacks succeed. It's a safe fallback, but it meant my warning about epyc3 crashes was wrong for a while.
- **Threaded BLAS doesn't help:** MUMPS's internals went from 2.6–2.9 s to 3.1–4.0 s, and MA57's solver time didn't improve. Dense blocks in this problem are too small.
- **OpenMP MUMPS isn't reproducible:** the objective at iteration 80 varied from 67.8 to 153.6.

## Reference: settings used

### Compiler and linker flags

| Target | Flags | Where |
|---|---|---|
| External function, Bunya | `-O3 -DNDEBUG -march=znver3` | `CMAKE_BUILD_TYPE`, `PREDSIM_EXTFUN_CFLAGS` |
| External function, workstation | `-O3 -DNDEBUG -march=native` | Same |
| Source MUMPS, Ipopt, CasADi, Bunya | `-O3 -march=znver3 -mtune=znver3 -fPIC` | `SITE_OPT_FLAGS` |
| CoinHSL | `SITE_OPT_FLAGS`, `-Wl,-Bsymbolic`, `-Dprefer_static=true`, `--buildtype=release` | `steps/hsl.sh` |
| OpenBLAS (pthreads) | `DYNAMIC_ARCH` | `steps/openblas.sh` |
| OpenBLAS (OpenMP) | `DYNAMIC_ARCH=1 TARGET=HASWELL USE_OPENMP=1 NUM_THREADS=256 LIBNAMESUFFIX=omp` | `lib/common.sh` |
| Ipopt source patch | `dlopen(..., RTLD_NOW \| RTLD_DEEPBIND)` | `steps/ipopt.sh` |

### Environment variables

| Variable | Purpose | Set by |
|---|---|---|
| `PREDSIM_MATLAB_LD_PRELOAD` | Newer runtime libraries, MATLAB only | `env.sh` |
| `PREDSIM_JAVA_LIBRARY_PATH` | Folder for OpenSim's JNI library | `env.sh` |
| `PREDSIM_CASADI_DIR` | CasADi for this stack | `env.sh` |
| `PREDSIM_HSL_LIB` | HSL library. Set but empty means MUMPS | `env.sh`, or you |
| `PREDSIM_HSL_SOLVER` | `ma97` or `ma57` | You |
| `PREDSIM_CASADI_MODE` | Force `prebuilt` or `source` | You |
| `PREDSIM_EXTFUN_CFLAGS` | External function CPU flags | `env.sh` |
| `CMAKE_BUILD_TYPE` | `Release` by default | `run_predsim.sh` |
| `CFLAGS` | Passes the CPU flags to CMake | `run_predsim.sh` |
| `OMP_NUM_THREADS` | MA97 and OpenMP threads, default 1 | `env.sh`, or you |
| `OPENBLAS_NUM_THREADS` | BLAS threads, default 1 | `env.sh`, or you |
| `EBROOTOPENSIMAD` | opensimAD libraries, no download | `env.sh` |
| `PREDSIM_RERUN_SCRIPT` | Rerun script to copy beside results | `run_predsim.sh` |

`LD_LIBRARY_PATH` is deliberately not used.

## Reference: debugging commands

```bash
# Where do a library's calls really go, inside MATLAB?
LD_DEBUG=bindings LD_DEBUG_OUTPUT=trace linux/run_predsim.sh ...
sed -E 's/^ *[0-9]+: *//; s#/[^ ]*/##g' trace* | grep '^binding file libhsl.so' | sort -u

# Will it load the way MATLAB loads it? (Add the site's LD_PRELOAD on Bunya.)
env -u LD_LIBRARY_PATH ldd libhsl.so

# How does Ipopt load HSL? 0x2 = RTLD_NOW, 0xa = adds RTLD_DEEPBIND
objdump -d --no-show-raw-insn libipopt.so.3 | grep -B6 'dlopen@plt' | grep esi

# What did the compiler actually produce?
objdump -d F_model.so | grep -cE 'vfn?m(add|sub)'    # FMA
objdump -d F_model.so | grep -c '%zmm'               # AVX-512

# What does a library contain and need?
nm -D --defined-only libhsl.so | grep -E ' (dgemm_|METIS_NodeND)$'
readelf -d libhsl.so | grep -E 'NEEDED|RUNPATH|SYMBOLIC'

# Which CPU is the node, exactly?
scontrol show node <node> | grep ActiveFeatures
```

## Still open

- **The pthreads OpenBLAS trigger** ([2.5](#25-mkl-error-parameter-11--on-entry-to-dtrsm)) was avoided, not explained.
- **`znver4`'s slower iterations:** Ipopt's own time was higher (2.68 against 2.29 s) on the same trajectory. Not investigated.
- **CPU-tuned stacks:** the earlier result is void and hasn't been re-measured.
- **Source vs prebuilt on epyc3 with HSL:** the selector's choice was measured with MUMPS only.
- **Time to a solution by solver:** convergence runs are in progress, on `main.m`'s real problem.
- **HSL scaling options:** not tested yet.
- **Possible upstream reports:** suggesting `RTLD_DEEPBIND` to Ipopt, and MATLAB's unrenamed `METIS_SetDefaultOptions` to MathWorks. Not filed.
