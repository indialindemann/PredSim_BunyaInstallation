#!/bin/bash
# spdlog shared library (bundled fmt).

mkdir -p "$PREDsim_INSTALL_ROOT/spdlog"
cd "$PREDsim_INSTALL_ROOT/spdlog"
wget -nc -O spdlog-1.15.3.tar.gz https://github.com/gabime/spdlog/archive/refs/tags/v1.15.3.tar.gz
tar xzf spdlog-1.15.3.tar.gz
cd spdlog-1.15.3
rm -rf build && mkdir build && cd build

cmake .. \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_PREFIX="$HOME/deps/spdlog" \
  -DSPDLOG_BUILD_SHARED=ON \
  -DSPDLOG_FMT_EXTERNAL=OFF \
  -DCMAKE_POSITION_INDEPENDENT_CODE=ON

cmake --build . --parallel 4
cmake --install .

cd "$HOME"
