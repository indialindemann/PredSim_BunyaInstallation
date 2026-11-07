#!/bin/bash -l
#SBATCH --job-name=predsim
#SBATCH --partition=general
#SBATCH --prefer=epyc4
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=2
#SBATCH --mem=16G
#SBATCH --time=7-00:00:00
#SBATCH --output=predsim-%j.out
#
# Run a PredSim simulation on UQ Bunya with the stack installed by
# bunya/install_predsim.slurm.
#
#   sbatch bunya/run_predsim.slurm                     # runs ~/PredSim/main.m
#   sbatch --export=ALL,PREDSIM_SCRIPT=linux/verify/verify_stack bunya/run_predsim.slurm
#   sbatch --qos=debug --time=00:55:00 bunya/run_predsim.slurm       # quick test (debug QOS: max 1 h)
#
# Resources (benchmarked 2026-11-02, see README):
#   --prefer=epyc4     epyc4 nodes run PredSim ~18% faster than epyc3 and ~30%
#                      faster than epyc5, at the same charge rate. A preference,
#                      not a requirement: if no epyc4 node is free the job runs
#                      on another type instead of waiting. The one install works
#                      on all types, and uses the same CasADi stack (source)
#                      on each. To force a type, override BOTH options,
#                      e.g. --constraint=epyc3 --prefer=epyc3: Slurm uses
#                      --prefer in place of --constraint whenever it can be met.
#   --cpus-per-task=2  one physical core (Bunya counts 2 hardware threads per
#                      core). PredSim's solve_NLPSOL uses expand=true, so the
#                      solve is single-threaded and S.solver.N_threads has no
#                      effect; more CPUs only cost fair share. If threading is
#                      re-enabled (expand=false), use N_threads+1. With the
#                      -O3 external function (set by run_predsim.sh) the
#                      single-threaded run is as fast as 16 threads.
#   --mem=16G          the 3D models peak at ~10 GB.
#
# Environment overrides (sbatch --export=ALL,VAR=value):
#   PREDSIM_SCRIPT   repo-relative MATLAB script, no .m (default: main)
#   PREDSIM_DIR      PredSim checkout (default: ~/PredSim)
#   PREDSIM_ENV      stack env file (default: ~/.predsim/env.sh, which uses the
#                    source CasADi stack on every node type)
#   PREDSIM_CASADI_MODE  CasADi stack (default: source on every node type).
#                    prebuilt|source force one; "fastest" picks the faster stack
#                    for the node (source on epyc3, else prebuilt). Source is the
#                    default so results don't follow the node type, NOT for
#                    speed: prebuilt was about 7% faster on epyc4 with MUMPS.
#   OPENBLAS_CORETYPE    OpenBLAS code path (default: Haswell on every node type;
#                    "auto" lets OpenBLAS pick by CPU). See the note in the code below.
#   PREDSIM_RESULTS_ROOT  results folder root (default: /scratch/user/$USER/PredSimResults)
#   PREDSIM_LOG_DIR      MATLAB log folder (default: /scratch/user/$USER/predsim-logs)
#   PREDSIM_IPOPT_OPTIONS  Ipopt options as "name=value;name=value" (default: the
#                    list set in PredSim's linux/run_predsim.sh; "none" gives
#                    Ipopt's own defaults, which did not converge on the 3D
#                    sprinting problems).
#
# Where output goes (scratch by default; SCRATCH IS NOT LONG-TERM STORAGE, copy
# what you want to keep to RDM or another backed-up place):
#   Results        /scratch/user/$USER/PredSimResults/<subject>/   (PREDSIM_RESULTS_ROOT)
#   MATLAB log     /scratch/user/$USER/predsim-logs/<script>-<timestamp>.log   (PREDSIM_LOG_DIR)
#   This job's .out  predsim-<jobid>.out in the directory you submit from

set -euo pipefail

PREDSIM_DIR="${PREDSIM_DIR:-$HOME/PredSim}"
PREDSIM_ENV="${PREDSIM_ENV:-$HOME/.predsim/env.sh}"
PREDSIM_SCRIPT="${PREDSIM_SCRIPT:-main}"

[[ -f "$PREDSIM_ENV" ]] || { echo "ERROR: $PREDSIM_ENV not found; run bunya/install_predsim.slurm first" >&2; exit 1; }
[[ -x "$PREDSIM_DIR/linux/run_predsim.sh" ]] || { echo "ERROR: $PREDSIM_DIR is not a linux/cleancurvev4 checkout" >&2; exit 1; }

echo "== $(date -Is) job ${SLURM_JOB_ID:-none} on $(hostname) ($(grep -m1 'model name' /proc/cpuinfo | cut -d: -f2 | sed 's/^ //')), ${SLURM_CPUS_PER_TASK:-?} CPUs"
echo "== env: $PREDSIM_ENV -> $(readlink -f "$PREDSIM_ENV")"

# OpenBLAS code path: Haswell on every node type, unless overridden.
#
# This is NOT a performance setting. It is here so that a result doesn't depend
# on which node type the job lands on. Left alone, OpenBLAS picks its code path
# from the CPU (Zen on epyc3, Cooperlake on epyc4 and epyc5). The paths round
# differently, and with MA97 that was enough to change PredSim's result and
# whether it converged (BENCHMARKS.md, "What changes the result").
#
#   OPENBLAS_CORETYPE=auto     OpenBLAS picks by CPU, as it does without this block
#   OPENBLAS_CORETYPE=<name>   any other OpenBLAS path, e.g. Zen or Cooperlake
#
# Haswell needs AVX2, which every Bunya node type has. An empty value is treated
# as unset, because OpenBLAS would fall back to an old generic path for it.
#
# The CasADi stack is fixed for the same reason: ~/.predsim/env.sh uses the
# source stack on every node type unless PREDSIM_CASADI_MODE says otherwise.
#
# Tested: forced to Haswell, epyc3, epyc4 and epyc5 print identical iteration
# lines with MA97, MA57 and MUMPS (BENCHMARKS.md, "Reproducible results").
#
# Convergence is a separate matter: linux/run_predsim.sh in the PredSim checkout
# sets the Ipopt options that make these problems converge (PREDSIM_IPOPT_OPTIONS;
# BENCHMARKS.md, "Ipopt settings").
case "${OPENBLAS_CORETYPE:-Haswell}" in
    auto|Auto|AUTO) unset OPENBLAS_CORETYPE ;;
    *) export OPENBLAS_CORETYPE="${OPENBLAS_CORETYPE:-Haswell}" ;;
esac
echo "== OpenBLAS code path: ${OPENBLAS_CORETYPE:-auto (picked by CPU)}; CasADi stack mode: ${PREDSIM_CASADI_MODE:-site default}"

# Results and MATLAB logs go to scratch unless told otherwise: home has a 50 GB
# quota and fills quickly. Scratch is NOT long-term storage (files that go unused
# are cleared), so copy results you want to keep somewhere backed up.
# The folders are created here, so a cleared scratch is not a problem.
export PREDSIM_RESULTS_ROOT="${PREDSIM_RESULTS_ROOT:-/scratch/user/$USER/PredSimResults}"
export PREDSIM_LOG_DIR="${PREDSIM_LOG_DIR:-/scratch/user/$USER/predsim-logs}"
mkdir -p "$PREDSIM_RESULTS_ROOT" "$PREDSIM_LOG_DIR"
echo "== results: $PREDSIM_RESULTS_ROOT/<subject>/   logs: $PREDSIM_LOG_DIR"

exec "$PREDSIM_DIR/linux/run_predsim.sh" --env "$PREDSIM_ENV" --script "$PREDSIM_SCRIPT"
