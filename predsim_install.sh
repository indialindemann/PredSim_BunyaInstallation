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

SCRIPT_DIR="$HOME/PredSim_BunyaInstallation"
INSTALL_SCRIPTS="$SCRIPT_DIR/install"

# shellcheck source=install/detect_system.sh
source "$INSTALL_SCRIPTS/detect_system.sh"
echo "PREDsim_SYSTEM=$PREDsim_SYSTEM"

export PREDsim_INSTALL_ROOT="${PREDsim_INSTALL_ROOT:-$HOME/predsim_install}"
export SCRIPT_DIR

run_install() {
    local name="$1"
    echo ""
    echo "===== ${name} ====="
    # shellcheck source=/dev/null
    source "$INSTALL_SCRIPTS/${name}.sh"
}

mkdir -p "$SCRIPT_DIR/logs"
mkdir -p "$PREDsim_INSTALL_ROOT" "$HOME/deps"

if [[ "$PREDsim_SYSTEM" == bunya_hpc ]]; then
    module load gcc/14.2.0
    module load cmake/3.31.3-gcccore-14.2.0
    module load openblas/0.3.29-gcc-14.2.0
    module load matlab/R2023b5
    module load java/21.0.8
    module load python/3.13.1-gcccore-14.2.0

    # EPYC 9454 (Genoa, znver4) — recommended flags for builds on this partition
    export CFLAGS="-O3 -march=znver4 -mtune=znver4 -fPIC"
    export CXXFLAGS="-O3 -march=znver4 -mtune=znver4 -fPIC"
    export FFLAGS="-O3 -march=znver4 -mtune=znver4 -fPIC"

    # matlab/R2023b5 module does not set MATLAB_VERSION
    export MATLAB_VERSION="${MATLAB_VERSION:-R2023b}"
    export PREDSIM_GIT_BRANCH="${PREDSIM_GIT_BRANCH:-cleancurvev4_ubuntu}"

else
    module load gcc/12.3.0
    module load cmake/3.26
    module load openblas/0.3.32-gcccore-12.3.0
    module load matlab/
    module load java/
    module load python/3.11

    #export CFLAGS="-O2 -march=native -mtune=native -fPIC"
    #export CXXFLAGS="-O2 -march=native -mtune=native -fPIC"
    #export FFLAGS="-O2 -march=native -mtune=native -fPIC"

    export MATLAB_VERSION=R2024b
    export PREDSIM_GIT_BRANCH="${PREDSIM_GIT_BRANCH:-cleancurvev4_ubuntu}"

fi

echo "MATLAB_VERSION=$MATLAB_VERSION"
echo "PREDSIM_GIT_BRANCH=$PREDSIM_GIT_BRANCH"
echo "CFLAGS=$CFLAGS"

cd "$HOME"

run_install install_python_env
run_install install_openblas
run_install install_ipopt

run_install install_spdlog

if [[ "$PREDsim_SYSTEM" == bunya_hpc ]]; then
    run_install build_gcc7_toolchain
fi
run_install resolve_gcc7
run_install install_swig_casadi

run_install install_casadi
run_install install_simbody

export LD_LIBRARY_PATH="$HOME/deps/ipopt/lib:${LD_LIBRARY_PATH:-}"
export PKG_CONFIG_PATH="$HOME/deps/ipopt/lib/pkgconfig:${PKG_CONFIG_PATH:-}"

if [[ "$PREDsim_SYSTEM" == bunya_hpc ]]; then
    module load pcre2/10.45-gcccore-14.2.0
else
    module load pcre2/10.42-gcccore-12.3.0
fi

run_install install_swig_opensim
run_install install_opensim
run_install install_predsim

echo ""
echo "===== PredSim installation complete (PREDsim_SYSTEM=$PREDsim_SYSTEM) ====="
