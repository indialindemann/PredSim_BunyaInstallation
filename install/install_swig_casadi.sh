#!/bin/bash
# SWIG fork required for CasADi MATLAB bindings.
# Exports: SWIG_CASADI_VERSION, SWIG_DIR

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

export GCC7="$(spack location -i gcc@7.5.0)/bin"

CC=$GCC7/gcc CXX=$GCC7/g++ ./autogen.sh
CC=$GCC7/gcc CXX=$GCC7/g++ Tools/pcre-build.sh
CC=$GCC7/gcc CXX=$GCC7/g++ ./configure --prefix="$HOME/deps/$SWIG_CASADI_VERSION" --with-pcre

CC=$GCC7/gcc CXX=$GCC7/g++ make -j4
CC=$GCC7/gcc CXX=$GCC7/g++ make install

export SWIG_DIR="$HOME/deps/$SWIG_CASADI_VERSION/share/swig/3.0.11"

cd "$HOME"
