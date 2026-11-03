# OpenBLAS built from source, for sites without a usable OpenBLAS module
# (SITE_BUILD_OPENBLAS=1). On Bunya the gcc-12.3 toolchain only offers
# OpenBLAS 0.3.23, which breaks MUMPS (OpenMathLib/OpenBLAS#4005), and the
# newer modules belong to gcc 13/14 toolchains.
#
# DYNAMIC_ARCH picks optimised kernels at run time, so one build is fast on
# every node generation (Bunya mixes Zen3/Zen4/Zen5). Shared by all stacks.

STEP_SHARED=1
OPENBLAS_VERSION="0.3.32"

step_applies() { [[ "${SITE_BUILD_OPENBLAS:-0}" == 1 ]]; }

step_main() {
    local src="$OPENSIM_PREFIX/build/OpenBLAS-$OPENBLAS_VERSION" inst="$OPENSIM_PREFIX/openblas"
    fetch "https://github.com/OpenMathLib/OpenBLAS/releases/download/v$OPENBLAS_VERSION/OpenBLAS-$OPENBLAS_VERSION.tar.gz" \
          "$OPENSIM_PREFIX/build/OpenBLAS-$OPENBLAS_VERSION.tar.gz"
    rm -rf "$src"; tar -xzf "$OPENSIM_PREFIX/build/OpenBLAS-$OPENBLAS_VERSION.tar.gz" -C "$OPENSIM_PREFIX/build"
    # USE_OPENMP=0 / NUM_THREADS: pthreads build; PredSim sets OPENBLAS_NUM_THREADS.
    make -C "$src" -j"$SITE_JOBS" CC="$CC" FC="$FC" DYNAMIC_ARCH=1 TARGET=HASWELL \
        USE_OPENMP=0 NUM_THREADS=64 NO_STATIC=1 libs netlib shared >/dev/null
    make -C "$src" PREFIX="$inst" NO_STATIC=1 install >/dev/null
    [[ -f "$inst/lib/libopenblas.so.0" ]] || die "libopenblas.so.0 not installed in $inst/lib"
    log "OpenBLAS $OPENBLAS_VERSION (DYNAMIC_ARCH) in $inst/lib"
}
