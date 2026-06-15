#!/bin/bash
# Build GCC 7.5.0 for the CasADi SWIG fork (Bunya only).
# Downloads under $PREDsim_INSTALL_ROOT/gcc7, installs to $HOME/deps/gcc7-7.5.0.
# Skips if the install prefix already has gcc.

GCC7_VERSION="7.5.0"
GCC7_PREFIX="${PREDsim_GCC7_PREFIX:-$HOME/deps/gcc7-$GCC7_VERSION}"
GCC7_DIR="${PREDsim_INSTALL_ROOT:-$HOME/predsim_install}/gcc7"
GCC7_SRC="$GCC7_DIR/gcc-$GCC7_VERSION"
GCC7_BUILD="$GCC7_SRC/build"
GCC7_TARBALL="gcc-$GCC7_VERSION.tar.xz"
GCC7_URL="https://ftp.gnu.org/gnu/gcc/gcc-$GCC7_VERSION/$GCC7_TARBALL"

if [[ -x "$GCC7_PREFIX/bin/gcc" ]]; then
    echo "GCC 7 already present at $GCC7_PREFIX — skipping build."
    "$GCC7_PREFIX/bin/gcc" --version | head -1
    return 0 2>/dev/null || exit 0
fi

echo "Building GCC $GCC7_VERSION into $GCC7_PREFIX"

mkdir -p "$GCC7_DIR"
cd "$GCC7_DIR"

if [[ ! -f "$GCC7_TARBALL" ]]; then
    wget -nc "$GCC7_URL"
fi

if [[ ! -d "$GCC7_SRC" ]]; then
    tar xf "$GCC7_TARBALL"
fi

cd "$GCC7_SRC"
CFLAGS="-O2 -fPIC" CXXFLAGS="-O2 -fPIC" FFLAGS="" ./contrib/download_prerequisites

rm -rf "$GCC7_BUILD"
mkdir -p "$GCC7_BUILD"
cd "$GCC7_BUILD"

# Override global compile flags (e.g. -march=znver4 from predsim_install.sh) — GCC 7 cannot use them.
CFLAGS="-O2 -fPIC" CXXFLAGS="-O2 -fPIC" FFLAGS="" \
  ../configure \
    --prefix="$GCC7_PREFIX" \
    --enable-languages=c,c++ \
    --disable-multilib \
    --disable-bootstrap

CFLAGS="-O2 -fPIC" CXXFLAGS="-O2 -fPIC" FFLAGS="" make -j4
CFLAGS="-O2 -fPIC" CXXFLAGS="-O2 -fPIC" FFLAGS="" make install

echo "GCC 7 installed to $GCC7_PREFIX"
"$GCC7_PREFIX/bin/gcc" --version | head -1
