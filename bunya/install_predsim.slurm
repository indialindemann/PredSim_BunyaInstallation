#!/bin/bash -l
#SBATCH --job-name=predsim-install
#SBATCH --partition=general
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=16
#SBATCH --mem=32G
#SBATCH --time=02:00:00
#SBATCH --output=predsim-install-%j.out
#SBATCH --constraint=epyc3
#
# Install the PredSim Linux stack for the submitting user on UQ Bunya.
#
#   cd ~/PredSim_BunyaInstallation
#   sbatch bunya/install_predsim.slurm                       # default (versions.env)
#   sbatch --export=ALL,CASADI_MODE=source bunya/install_predsim.slurm
#   sbatch --account=a_xxxx bunya/install_predsim.slurm      # if your default account differs
#
# Everything goes to ~/predsim-deps/ (OpenSim + OpenBLAS shared in
# ~/predsim-deps/bunya_opensim-<ver>, each CasADi mode in its own stack dir),
# PredSim is cloned to ~/PredSim (branch linux/cleancurvev4) if absent, and
# ~/.predsim/env.sh is pointed at the new stack. Under 1 h on 16 cores (about
# half of it the final check run); re-running only redoes what changed.
# Progress: tail -f predsim-install-<jobid>.out
#
# Runs on a Zen3 (epyc3) node on purpose: Bunya's modules are built per CPU
# generation, and Zen3 builds also run on the Zen4/Zen5 nodes, so this one
# install works on every node type.
#
# Needs: GitHub SSH key on Bunya with access to indialindemann/PredSim.

set -euo pipefail

# Slurm runs a copy of this script from its spool dir, so locate the repo
# from the submit directory (or PREDSIM_INSTALLER_DIR).
INSTALLER_DIR="${PREDSIM_INSTALLER_DIR:-${SLURM_SUBMIT_DIR:-$PWD}}"
if [[ ! -x "$INSTALLER_DIR/predsim-install.sh" ]]; then
    INSTALLER_DIR="$HOME/PredSim_BunyaInstallation"
fi
[[ -x "$INSTALLER_DIR/predsim-install.sh" ]] || {
    echo "ERROR: predsim-install.sh not found. Submit from the PredSim_BunyaInstallation directory." >&2
    exit 1
}

echo "== $(date -Is) job ${SLURM_JOB_ID:-none} on $(hostname) ($(grep -m1 'model name' /proc/cpuinfo | cut -d: -f2))"
echo "== installer: $INSTALLER_DIR @ $(git -C "$INSTALLER_DIR" rev-parse --short HEAD 2>/dev/null || echo '?')"

export SITE_JOBS="${SLURM_CPUS_PER_TASK:-4}"
args=(--site bunya --activate)
[[ -n "${CASADI_MODE:-}" ]] && args+=(--casadi "$CASADI_MODE")

"$INSTALLER_DIR/predsim-install.sh" "${args[@]}" ${PREDSIM_INSTALL_ARGS:-}

echo "== $(date -Is) done. Submit a simulation with:"
echo "   sbatch $INSTALLER_DIR/bunya/run_predsim.slurm"
