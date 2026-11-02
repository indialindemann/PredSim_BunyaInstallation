#!/bin/bash -l
#SBATCH --job-name=predsim
#SBATCH --partition=general
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=5
#SBATCH --mem=24G
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
# Resources: PredSim parallelises the collocation map over S.solver.N_threads
# threads (default 4) plus MATLAB's main thread, so cpus-per-task=5 matches
# the default; raise both together. The 3D models run within 15 GB on the
# Ubuntu workstation, so 24G leaves headroom.
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

echo "== $(date -Is) job ${SLURM_JOB_ID:-none} on $(hostname) ($(grep -m1 'model name' /proc/cpuinfo | cut -d: -f2)), ${SLURM_CPUS_PER_TASK:-?} CPUs"
exec "$PREDSIM_DIR/linux/run_predsim.sh" --env "$PREDSIM_ENV" --script "$PREDSIM_SCRIPT"
