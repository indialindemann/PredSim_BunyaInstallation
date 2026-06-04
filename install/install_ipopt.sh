#!/bin/bash
# IPOPT via coinbrew.
# Expects: OBLIBDIR, OBLAS (from install_openblas.sh).

: "${OBLIBDIR:?OBLIBDIR must be set (source install_openblas.sh first)}"

mkdir -p "$PREDsim_INSTALL_ROOT/coinbrew"
cd "$PREDsim_INSTALL_ROOT/coinbrew"
wget -nc https://raw.githubusercontent.com/coin-or/coinbrew/master/coinbrew

chmod +x coinbrew

./coinbrew build Ipopt \
  --prefix="$HOME/deps/ipopt" \
  --no-prompt \
  --tests=none \
  --verbosity=2 \
  --enable-shared \
  --reconfigure \
  --with-blas="-L$OBLIBDIR -lopenblas" \
  --with-lapack="-L$OBLIBDIR -lopenblas"

cd "$HOME"
