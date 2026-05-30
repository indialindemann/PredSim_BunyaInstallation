#!/bin/bash
# PredSim repo clone and MATLAB JNI library path setup.
# Expects: OBLIBDIR (from install_openblas.sh), deps installed.

: "${OBLIBDIR:?OBLIBDIR must be set (source install_openblas.sh first)}"

cd "$PREDsim_INSTALL_ROOT"
mkdir -p opensim_win
cd opensim_win
echo "Manual download time: See README instructions for OpenSim Windows geometry files."

cd "$HOME"
git clone --recurse-submodules -b cleancurvev4 git@github.com:indialindemann/PredSim.git

mkdir -p "$HOME/.matlab/$MATLAB_VERSION"

echo "$HOME/deps/simbody/lib" >> "$HOME/.matlab/$MATLAB_VERSION/javalibrarypath.txt"
echo "$HOME/deps/ipopt/lib" >> "$HOME/.matlab/$MATLAB_VERSION/javalibrarypath.txt"
echo "$HOME/deps/opensim-install/lib" >> "$HOME/.matlab/$MATLAB_VERSION/javalibrarypath.txt"
echo "$HOME/deps/opensim-install/sdk/lib" >> "$HOME/.matlab/$MATLAB_VERSION/javalibrarypath.txt"
echo "$OBLIBDIR" >> "$HOME/.matlab/$MATLAB_VERSION/javalibrarypath.txt"
