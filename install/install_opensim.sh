#!/bin/bash
# OpenSim-core with Java bindings.
# Expects: simbody, ipopt, spdlog, OBLAS (from prior install scripts).

: "${OBLAS:?OBLAS must be set (source install_openblas.sh first)}"

cd "$PREDsim_INSTALL_ROOT"

git clone https://github.com/opensim-org/opensim-core.git --depth 1
cd opensim-core
mkdir -p build
cd build

export PKG_CONFIG_PATH="$HOME/deps/ipopt/lib/pkgconfig:${PKG_CONFIG_PATH:-}"
export LD_LIBRARY_PATH="$HOME/deps/simbody/lib:$HOME/deps/ipopt/lib:$HOME/deps/spdlog/lib:${LD_LIBRARY_PATH:-}"

cmake .. \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_PREFIX="$HOME/deps/opensim-install" \
  -DBUILD_JAVA_WRAPPING=ON \
  -DBUILD_PYTHON_WRAPPING=OFF \
  -DBUILD_TESTING=OFF \
  -DSUPERLU=OFF \
  -DSIMBODY_HOME="$HOME/deps/simbody" \
  -DCMAKE_PREFIX_PATH="$HOME/deps/spdlog;$HOME/deps/simbody;$HOME/deps/ipopt" \
  -DCMAKE_FIND_PACKAGE_PREFER_CONFIG=TRUE \
  -DCMAKE_FIND_USE_PACKAGE_REGISTRY=OFF \
  -DCMAKE_FIND_USE_SYSTEM_PACKAGE_REGISTRY=OFF \
  -DBLA_VENDOR=OpenBLAS \
  -DBLAS_LIBRARIES="$OBLAS" \
  -DLAPACK_LIBRARIES="$OBLAS" \
  -DOPENSIM_WITH_CASADI=OFF

cmake --build . --parallel 4
cmake --install .

# On Bunya, CMake installs shared libs to lib64; downstream scripts expect lib.
_prefix="$HOME/deps/opensim-install"
if [[ ! -e "$_prefix/lib" ]] && [[ -d "$_prefix/lib64" ]]; then
    ln -sfn lib64 "$_prefix/lib"
fi

mkdir -p "$HOME/deps/opensim-install/sdk/Java"
mkdir -p "$HOME/deps/opensim-install/sdk/lib"

cp -v "$PREDsim_INSTALL_ROOT/opensim-core/build/Bindings/Java/src/org-opensim-modeling.jar" \
      "$HOME/deps/opensim-install/sdk/Java/"

cp -v "$PREDsim_INSTALL_ROOT/opensim-core/build/libosimJavaJNI.so" \
      "$HOME/deps/opensim-install/sdk/lib/"

export LD_LIBRARY_PATH="$HOME/deps/opensim-install/sdk/lib:$HOME/deps/opensim-install/lib:$HOME/deps/simbody/lib:$HOME/deps/ipopt/lib:${LD_LIBRARY_PATH:-}"

cd "$HOME"
