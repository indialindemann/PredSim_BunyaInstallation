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
#                      on all types. To force a type, override BOTH options,
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
#   PREDSIM_ENV      stack env file (default: ~/.predsim/env.sh)
#
# MATLAB output: ~/PredSim/logs/<script>-<timestamp>.log (and this job's .out).
# Results: ~/PredSimResults/<subject>/

set -euo pipefail

PREDSIM_DIR="${PREDSIM_DIR:-$HOME/PredSim}"
PREDSIM_ENV="${PREDSIM_ENV:-$HOME/.predsim/env.sh}"
PREDSIM_SCRIPT="${PREDSIM_SCRIPT:-main}"

[[ -f "$PREDSIM_ENV" ]] || { echo "ERROR: $PREDSIM_ENV not found; run bunya/install_predsim.slurm first" >&2; exit 1; }
[[ -x "$PREDSIM_DIR/linux/run_predsim.sh" ]] || { echo "ERROR: $PREDSIM_DIR is not a linux/cleancurvev4 checkout" >&2; exit 1; }

echo "== $(date -Is) job ${SLURM_JOB_ID:-none} on $(hostname) ($(grep -m1 'model name' /proc/cpuinfo | cut -d: -f2 | sed 's/^ //')), ${SLURM_CPUS_PER_TASK:-?} CPUs"
echo "== env: $PREDSIM_ENV -> $(readlink -f "$PREDSIM_ENV")"
exec "$PREDSIM_DIR/linux/run_predsim.sh" --env "$PREDSIM_ENV" --script "$PREDSIM_SCRIPT"
