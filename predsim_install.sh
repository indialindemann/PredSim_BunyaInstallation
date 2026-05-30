#!/bin/bash -l
#SBATCH --job-name=predsim_install
#SBATCH --partition=general
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=4
#SBATCH --mem=24G
#SBATCH --time=02:00:00
#SBATCH --output=logs/%x-%j.out
#SBATCH --error=logs/%x-%j.err

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_SCRIPTS="$SCRIPT_DIR/install"

# Shared paths used by install scripts
export PREDsim_INSTALL_ROOT="${PREDsim_INSTALL_ROOT:-$HOME/predsim_install}"

run_install() {
    local name="$1"
    echo ""
    echo "===== ${name} ====="
    # shellcheck source=/dev/null
    source "$INSTALL_SCRIPTS/${name}.sh"
}

# TODO: switching based on Bunya vs Ubuntu (or other host)
module load gcc/12.3.0
module load cmake/3.26
module load openblas/0.3.32-gcccore-12.3.0 
module load matlab/
module load java/
module load python/3.11

#export CFLAGS="-O3 -march=znver4 -mtune=znver4 -fPIC"
#export CXXFLAGS="-O3 -march=znver4 -mtune=znver4 -fPIC"
#export CFLAGS="-O2 -march=native -mtune=native -fPIC"
#export CXXFLAGS="-O2 -march=native -mtune=native -fPIC"
#export FFLAGS="-O2 -march=native -mtune=native -fPIC"

cd "$HOME"
mkdir -p "$PREDsim_INSTALL_ROOT" "$HOME/deps"

run_install install_python_env
run_install install_openblas
run_install install_ipopt
run_install install_swig_casadi
run_install install_spdlog
run_install install_casadi
run_install install_simbody

module load pcre2/10.42-gcccore-12.3.0

run_install install_swig_opensim
run_install install_opensim
run_install install_predsim

echo ""
echo "===== PredSim installation complete ====="
