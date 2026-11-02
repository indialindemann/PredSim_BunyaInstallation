# CasADi for MATLAB, installed flat in $PREFIX/casadi (the directory PredSim
# adds to the MATLAB path via PREDSIM_CASADI_DIR).
#
# prebuilt: official linux64-matlab2018b package. Self-contained: bundles
#           Ipopt/MUMPS and a symbol-isolated OpenBLAS/libgfortran, so MATLAB's
#           MKL needs no BLAS_VERSION/LD_PRELOAD workarounds.
# source:   casadi-source-v<ver>.zip. That archive ships the SWIG-generated
#           MATLAB/Python wrappers with SWIG_IMPORT=ON, so NO SWIG (and no
#           jaeandersson/swig fork, no gcc 7) is needed. Built with the site
#           optimisation flags against $PREFIX/ipopt.

step_main() {
    local inst="$PREFIX/casadi"
    rm -rf "$inst"
    mkdir -p "$inst"

    if [[ "$CASADI_MODE" == prebuilt ]]; then
        local zip="casadi-${CASADI_VERSION}-linux64-matlab2018b.zip"
        fetch "https://github.com/casadi/casadi/releases/download/${CASADI_VERSION}/$zip" "$BUILD_ROOT/$zip"
        extract_zip "$BUILD_ROOT/$zip" "$inst"
    else
        local zip="casadi-source-v${CASADI_VERSION}.zip" src="$BUILD_ROOT/casadi-src"
        fetch "https://github.com/casadi/casadi/releases/download/${CASADI_VERSION}/$zip" "$BUILD_ROOT/$zip"
        rm -rf "$src"; extract_zip "$BUILD_ROOT/$zip" "$src"
        grep -q 'option(SWIG_IMPORT "Import SWIG" ON)' "$src/CMakeLists.txt" \
            || die "$zip does not have SWIG_IMPORT=ON; it would need SWIG"
        PKG_CONFIG_PATH="$PREFIX/ipopt/lib/pkgconfig" cmake -S "$src" -B "$src/build" \
            -DCMAKE_BUILD_TYPE=Release \
            -DCMAKE_C_FLAGS_RELEASE="${SITE_CASADI_OPT_FLAGS:-$SITE_OPT_FLAGS} -DNDEBUG" \
            -DCMAKE_CXX_FLAGS_RELEASE="${SITE_CASADI_OPT_FLAGS:-$SITE_OPT_FLAGS} -DNDEBUG" \
            -DCMAKE_INSTALL_PREFIX="$PREFIX" \
            -DWITH_SELFCONTAINED=ON \
            -DWITH_MATLAB=ON -DMATLAB_ROOT="$MATLAB_ROOT" \
            -DWITH_PYTHON=OFF \
            -DWITH_IPOPT=ON -DWITH_BUILD_IPOPT=OFF \
            -DWITH_MUMPS=OFF -DWITH_BUILD_MUMPS=OFF \
            -DWITH_THREAD=ON -DWITH_DEEPBIND=ON \
            -DWITH_EXAMPLES=OFF -DWITH_COMMON=OFF
        cmake --build "$src/build" --parallel "$SITE_JOBS"
        # WITH_SELFCONTAINED installs into <prefix>/casadi with RPATH=$ORIGIN, so
        # ship our Ipopt/MUMPS next to it (their own RPATHs reach OpenBLAS/gfortran).
        cmake --install "$src/build"
        cp -a "$PREFIX"/ipopt/lib/libipopt.so* "$PREFIX"/ipopt/lib/libcoinmumps.so* "$inst/"
    fi

    [[ -f "$inst/casadiMEX.mexa64" && -d "$inst/+casadi" ]] || die "casadiMEX.mexa64 / +casadi missing in $inst"
    # Only the pieces PredSim uses; optional plugins (gurobi, knitro, ...) link
    # to commercial libraries that are legitimately absent.
    local f bad=0
    for f in casadiMEX.mexa64 libcasadi.so libcasadi_nlpsol_ipopt.so; do
        [[ -e "$inst/$f" ]] || continue
        if ldd "$inst/$f" | grep 'not found' | grep -vE 'libmex|libmx|libut|libeng|libMatlab'; then
            warn "$f has unresolved libraries"; bad=1
        fi
    done
    [[ $bad -eq 0 ]] || die "unresolved libraries in $inst"
    log "CasADi $CASADI_VERSION ($CASADI_MODE) installed in $inst"
}
