#!/bin/bash
# SWIG fork required for CasADi MATLAB bindings.
# Exports: SWIG_CASADI_VERSION, SWIG_DIR
# Expects: GCC7_BIN (from resolve_gcc7.sh).

: "${GCC7_BIN:?GCC7_BIN must be set (run resolve_gcc7.sh first)}"

export SWIG_CASADI_VERSION="swig-3.0.11"
export SWIG_CASADI_BRANCH="matlab-customdoc"

mkdir -p "$PREDsim_INSTALL_ROOT/swig"
cd "$PREDsim_INSTALL_ROOT/swig"

echo "Removing existing swig checkout"
rm -rf swig

git clone --branch "$SWIG_CASADI_BRANCH" --depth 1 https://github.com/jaeandersson/swig.git
cd swig
wget -O pcre-8.45.tar.bz2 \
  https://downloads.sourceforge.net/project/pcre/pcre/8.45/pcre-8.45.tar.bz2

# Set compiler to be gcc7 and also overwrite and global compile flags to minimum defaults
# as GCC7 is very old and not typically compatible with newer flags
# Do this manually on each line to avaid messing with environment variables for the rest of the install
CC="$GCC7_BIN/gcc" CXX="$GCC7_BIN/g++" CFLAGS="-O2 -fPIC" CXXFLAGS="-O2 -fPIC" FFLAGS="" \
  ./autogen.sh
CC="$GCC7_BIN/gcc" CXX="$GCC7_BIN/g++" CFLAGS="-O2 -fPIC" CXXFLAGS="-O2 -fPIC" FFLAGS="" \
  Tools/pcre-build.sh
CC="$GCC7_BIN/gcc" CXX="$GCC7_BIN/g++" CFLAGS="-O2 -fPIC" CXXFLAGS="-O2 -fPIC" FFLAGS="" \
  ./configure --prefix="$HOME/deps/$SWIG_CASADI_VERSION" --with-pcre

CC="$GCC7_BIN/gcc" CXX="$GCC7_BIN/g++" CFLAGS="-O2 -fPIC" CXXFLAGS="-O2 -fPIC" FFLAGS="" \
  make -j4
CC="$GCC7_BIN/gcc" CXX="$GCC7_BIN/g++" CFLAGS="-O2 -fPIC" CXXFLAGS="-O2 -fPIC" FFLAGS="" \
  make install

export SWIG_DIR="$HOME/deps/$SWIG_CASADI_VERSION/share/swig/3.0.11"

cd "$HOME"
