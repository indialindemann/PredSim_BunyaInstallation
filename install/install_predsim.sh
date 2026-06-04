#!/bin/bash
# PredSim repo clone and MATLAB JNI library path setup.
# Expects: OBLIBDIR (from install_openblas.sh), deps installed, MATLAB_VERSION.

: "${OBLIBDIR:?OBLIBDIR must be set (source install_openblas.sh first)}"
: "${MATLAB_VERSION:?MATLAB_VERSION must be set (via predsim_install.sh)}"

PREDSIM_GIT_BRANCH="${PREDSIM_GIT_BRANCH:-cleancurvev4}"

cd "$PREDsim_INSTALL_ROOT"
mkdir -p opensim_win
cd opensim_win
echo "Manual download time: See README instructions for OpenSim Windows geometry files."

cd "$HOME"
echo "Cloning PredSim branch: $PREDSIM_GIT_BRANCH"
git clone --recurse-submodules -b "$PREDSIM_GIT_BRANCH" git@github.com:indialindemann/PredSim.git

# MATLAB javalibrarypath is configured elsewhere — skip persistent writes here.
# mkdir -p "$HOME/.matlab/$MATLAB_VERSION"
# echo "$HOME/deps/simbody/lib" >> "$HOME/.matlab/$MATLAB_VERSION/javalibrarypath.txt"
# ...
