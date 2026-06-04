#!/bin/bash
# Standard SWIG used by OpenSim (distinct from the CasADi fork).
# Expects: pcre2 module loaded (via predsim_install.sh).

export SWIG_VERSION="swig-4.1.1"

mkdir -p "$PREDsim_INSTALL_ROOT/swig"
cd "$PREDsim_INSTALL_ROOT/swig"

wget -nc -O swig-4.1.1.tar.gz https://prdownloads.sourceforge.net/swig/swig-4.1.1.tar.gz
tar xzf swig-4.1.1.tar.gz
cd swig-4.1.1

./configure --prefix="$HOME/deps/$SWIG_VERSION" --with-pcre
make -j4
make install

export PATH="$HOME/deps/$SWIG_VERSION/bin:$PATH"
export SWIG_DIR="$HOME/deps/$SWIG_VERSION/share/swig/4.1.1"

cd "$HOME"
