#!/bin/bash

# Does NOT remove: ~/predsim_install/opensim_win

rm -rf "$HOME/deps/ipopt"
rm -rf "$HOME/deps/casadi"
rm -rf "$HOME/deps/spdlog"
rm -rf "$HOME/deps/simbody"
rm -rf "$HOME/deps/opensim-install"
rm -rf "$HOME/deps/swig-3.0.11"
rm -rf "$HOME/deps/swig-4.1.1"
rm -rf "$HOME/deps/swig-4.4.0"

rm -rf "$HOME/predsim_install/coinbrew"
rm -rf "$HOME/predsim_install/swig"
rm -rf "$HOME/predsim_install/spdlog"
rm -rf "$HOME/predsim_install/casadi_private"
rm -rf "$HOME/predsim_install/simbody"
rm -rf "$HOME/predsim_install/opensim-core"

rm -rf "$HOME/lib/blaswrap"
rm -rf "$HOME/PredSim"

rm -f "$HOME"/.matlab/*/javalibrarypath.txt