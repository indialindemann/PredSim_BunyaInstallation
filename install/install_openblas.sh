#!/bin/bash
# Locate OpenBLAS and export link hints used by downstream installs.
# Expects: openblas available via spack (Ubuntu) or EBROOTOPENBLAS (Rocky/HPC).

if [ -n "${EBROOTOPENBLAS:-}" ]; then
    if [ -f "$EBROOTOPENBLAS/lib64/libopenblas.so" ]; then
        export OBLIBDIR="$EBROOTOPENBLAS/lib64"
    elif [ -f "$EBROOTOPENBLAS/lib/libopenblas.so" ]; then
        export OBLIBDIR="$EBROOTOPENBLAS/lib"
    else
        echo "ERROR: libopenblas.so not found under EBROOTOPENBLAS=$EBROOTOPENBLAS"
        return 1 2>/dev/null || exit 1
    fi
else
    export OPENBLAS_ROOT=$(spack location -i openblas@0.3.32)
    if [ -f "$OPENBLAS_ROOT/lib64/libopenblas.so" ]; then
        export OBLIBDIR="$OPENBLAS_ROOT/lib64"
    elif [ -f "$OPENBLAS_ROOT/lib/libopenblas.so" ]; then
        export OBLIBDIR="$OPENBLAS_ROOT/lib"
    else
        echo "ERROR: libopenblas.so not found under $OPENBLAS_ROOT"
        return 1 2>/dev/null || exit 1
    fi
fi

export OBLAS="$OBLIBDIR/libopenblas.so"
export LD_LIBRARY_PATH="$OBLIBDIR:${LD_LIBRARY_PATH:-}"

echo "OPENBLAS_ROOT=${OPENBLAS_ROOT:-$EBROOTOPENBLAS}"
echo "OBLIBDIR=$OBLIBDIR"
echo "OBLAS=$OBLAS"
