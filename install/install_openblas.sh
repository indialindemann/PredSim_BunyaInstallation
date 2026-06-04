#!/bin/bash
# Locate OpenBLAS and export link hints used by downstream installs.
# HPC: openblas module (EBROOTOPENBLAS), e.g. openblas/0.3.29-gcc-14.2.0
# Ubuntu: spack openblas@0.3.32 when module env is not set

if [[ -n "${EBROOTOPENBLAS:-}" ]]; then
    if [ -f "$EBROOTOPENBLAS/lib64/libopenblas.so" ]; then
        export OBLIBDIR="$EBROOTOPENBLAS/lib64"
    elif [ -f "$EBROOTOPENBLAS/lib/libopenblas.so" ]; then
        export OBLIBDIR="$EBROOTOPENBLAS/lib"
    else
        echo "ERROR: libopenblas.so not found under EBROOTOPENBLAS=$EBROOTOPENBLAS"
        return 1 2>/dev/null || exit 1
    fi
    export OPENBLAS_ROOT="$EBROOTOPENBLAS"
elif [[ "${PREDsim_SYSTEM:-}" != bunya_hpc ]] && command -v spack >/dev/null 2>&1; then
    OPENBLAS_ROOT="$(spack location -i openblas@0.3.32)"
    export OPENBLAS_ROOT
    if [ -f "$OPENBLAS_ROOT/lib64/libopenblas.so" ]; then
        export OBLIBDIR="$OPENBLAS_ROOT/lib64"
    elif [ -f "$OPENBLAS_ROOT/lib/libopenblas.so" ]; then
        export OBLIBDIR="$OPENBLAS_ROOT/lib"
    else
        echo "ERROR: libopenblas.so not found under $OPENBLAS_ROOT"
        return 1 2>/dev/null || exit 1
    fi
else
    echo "ERROR: OpenBLAS not found."
    echo "  HPC: module load openblas/0.3.29-gcc-14.2.0 before install."
    echo "  Ubuntu: load openblas module or install openblas@0.3.32 via spack."
    return 1 2>/dev/null || exit 1
fi

export OBLAS="$OBLIBDIR/libopenblas.so"
export LD_LIBRARY_PATH="$OBLIBDIR:${LD_LIBRARY_PATH:-}"

echo "OPENBLAS_ROOT=$OPENBLAS_ROOT"
echo "OBLIBDIR=$OBLIBDIR"
echo "OBLAS=$OBLAS"
