#!/bin/bash
# Resolve GCC 7.x bin directory for the CasADi SWIG fork (swig-3.0.11).
# Exports GCC7_BIN (directory containing gcc and g++).

: "${PREDsim_SYSTEM:?PREDsim_SYSTEM must be set (source detect_system.sh first)}"

if [[ "$PREDsim_SYSTEM" == bunya_hpc ]]; then
    gcc7_prefix="${PREDsim_GCC7_PREFIX:-$HOME/deps/gcc7-7.5.0}"
    GCC7_BIN="$gcc7_prefix/bin"
    if [[ ! -x "$GCC7_BIN/gcc" ]]; then
        echo "ERROR: GCC 7 not found at $GCC7_BIN/gcc (build_gcc7_toolchain should have run on Bunya)"
        return 1 2>/dev/null || exit 1
    fi
else
    # If we are on linux we are probably using spack
    GCC7_BIN="$(spack location -i gcc@7.5.0)/bin"
fi

export GCC7_BIN
echo "GCC7_BIN=$GCC7_BIN"
