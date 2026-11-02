#!/bin/bash
# Submit the portable epyc3 install, then stacks tuned for epyc4 and epyc5 that
# start only after it succeeds (they reuse its shared OpenSim/OpenBLAS build).
#
#   cd ~/PredSim_BunyaInstallation && bunya/install_all_arches.sh [extra sbatch args]
#   CASADI_MODE=source bunya/install_all_arches.sh
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
exp="ALL${CASADI_MODE:+,CASADI_MODE=$CASADI_MODE}"
j3=$(sbatch --parsable --export="$exp" --constraint=epyc3 "$@" bunya/install_predsim.slurm)
echo "epyc3 (portable, default): job $j3"
for a in epyc4 epyc5; do
    j=$(sbatch --parsable --export="$exp" --constraint=$a --dependency=afterok:"$j3" "$@" bunya/install_predsim.slurm)
    echo "$a (tuned):              job $j (after $j3)"
done
