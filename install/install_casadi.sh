#!/bin/bash
# CasADi with IPOPT, Python, and MATLAB bindings.
# Expects: active Python venv, SWIG_CASADI_VERSION, SWIG_DIR, ipopt installed.

: "${SWIG_CASADI_VERSION:?SWIG_CASADI_VERSION must be set (source install_swig_casadi.sh first)}"
: "${SWIG_DIR:?SWIG_DIR must be set (source install_swig_casadi.sh first)}"

python -m pip install --upgrade pip setuptools wheel
python -m pip install numpy scipy

export LD_LIBRARY_PATH="$HOME/deps/ipopt/lib:${LD_LIBRARY_PATH:-}"
export PKG_CONFIG_PATH="$HOME/deps/ipopt/lib/pkgconfig:${PKG_CONFIG_PATH:-}"

CASADI_VERSION="3.7.1"
CASADI_INSTALL="$HOME/deps/casadi"
PYTHON_EXEC="$(which python)"
PYTHON_SITE="$(python -c 'import site; print(site.getsitepackages()[0])')"

cd "$PREDsim_INSTALL_ROOT"
rm -rf "$PREDsim_INSTALL_ROOT/casadi_private"
git clone --branch "$CASADI_VERSION" --depth 1 git@github.com:indialindemann/casadi_private.git

cd "$PREDsim_INSTALL_ROOT/casadi_private"
rm -rf build
mkdir build
cd build

PATH="$HOME/deps/$SWIG_CASADI_VERSION/bin:$PATH" cmake .. \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="$CASADI_INSTALL" \
    -DPYTHON_PREFIX="$CASADI_INSTALL" \
    \
    -DWITH_IPOPT=ON \
    -DWITH_BUILD_IPOPT=OFF \
    -DIPOPT_ROOT_DIR="$HOME/deps/ipopt" \
    \
    -DWITH_MUMPS=OFF \
    -DWITH_BUILD_MUMPS=OFF \
    \
    -DWITH_LAPACK=ON \
    -DWITH_BUILD_LAPACK=OFF \
    -DWITH_OPENBLAS=ON \
    \
    -DWITH_PYTHON=ON \
    -DWITH_PYTHON3=ON \
    \
    -DWITH_MATLAB=ON \
    -DWITH_DEEPBIND=ON \
    \
    -DSWIG_EXECUTABLE="$HOME/deps/$SWIG_CASADI_VERSION/bin/swig" \
    -DSWIG_DIR="$SWIG_DIR" \
    \
    -DWITH_THREAD=ON \
    -DWITH_COMMON=OFF \
    -DWITH_EXAMPLES=OFF \
    -DWITH_DOCUMENTATION=OFF \
    \
    -DPython_EXECUTABLE="$PYTHON_EXEC" \
    -DPython3_EXECUTABLE="$PYTHON_EXEC"

PATH="$HOME/deps/$SWIG_CASADI_VERSION/bin:$PATH" cmake --build . --parallel 4
PATH="$HOME/deps/$SWIG_CASADI_VERSION/bin:$PATH" cmake --install .

echo "$CASADI_INSTALL" > "$PYTHON_SITE/casadi-local.pth"

export LD_LIBRARY_PATH="$CASADI_INSTALL:$CASADI_INSTALL/lib:$HOME/deps/ipopt/lib:${LD_LIBRARY_PATH:-}"

python -c "import casadi; print(casadi.__version__); print(casadi.__file__)"

cd "$HOME"
