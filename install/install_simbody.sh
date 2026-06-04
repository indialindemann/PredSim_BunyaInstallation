#!/bin/bash
# Simbody multibody dynamics library.
# Expects: OBLAS or OBLIBDIR (from install_openblas.sh).

: "${OBLIBDIR:?OBLIBDIR must be set (source install_openblas.sh first)}"

BLAS_LIB="${OBLAS:-$OBLIBDIR/libopenblas.so}"

cd "$PREDsim_INSTALL_ROOT"
git clone https://github.com/simbody/simbody.git simbody --depth 1

SIMBODY_SRC="${SIMBODY_SRC:-$PREDsim_INSTALL_ROOT/simbody}"
INSTALL_PREFIX="${INSTALL_PREFIX:-$HOME/deps/simbody}"
BUILD_DIR="${BUILD_DIR:-$SIMBODY_SRC/build}"
mkdir -p "$BUILD_DIR"

cmake -S "$SIMBODY_SRC" -B "$BUILD_DIR" \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_PREFIX="$INSTALL_PREFIX" \
  -DBUILD_SHARED_LIBS=ON \
  -DBUILD_TESTING=OFF \
  -DBUILD_EXAMPLES=OFF \
  -DSIMBODY_USE_OPENMP=ON \
  -DBLAS_LIBRARIES="$BLAS_LIB" \
  -DLAPACK_LIBRARIES="$BLAS_LIB"

cmake --build "$BUILD_DIR" --parallel 4
cmake --install "$BUILD_DIR"

# On Bunya, CMake installs shared libs to lib64; downstream scripts expect lib.
if [[ ! -e "$INSTALL_PREFIX/lib" ]] && [[ -d "$INSTALL_PREFIX/lib64" ]]; then
    ln -sfn lib64 "$INSTALL_PREFIX/lib"
fi

cd "$HOME"
