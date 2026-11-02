# Ipopt + MUMPS from source with site optimisation flags (CASADI_MODE=source).
# In prebuilt mode CasADi ships its own Ipopt/MUMPS/OpenBLAS and this is skipped.

step_applies() { [[ "$CASADI_MODE" == source ]]; }

step_main() {
    local blas; blas="$(site_blas_dir)"
    local inst="$PREFIX/ipopt" src="$BUILD_ROOT/ipopt-src"
    local gcclib; gcclib="$(dirname "$($FC -print-file-name=libgfortran.so)")"
    local rpath="-Wl,-rpath,$inst/lib -Wl,-rpath,$blas -Wl,-rpath,$gcclib"
    export CFLAGS="$SITE_OPT_FLAGS -DNDEBUG" CXXFLAGS="$SITE_OPT_FLAGS -DNDEBUG" FFLAGS="$SITE_OPT_FLAGS"
    export FCFLAGS="$FFLAGS" LDFLAGS="$rpath"
    local lapack="-L$blas -lopenblas"

    log "MUMPS (ThirdParty-Mumps $MUMPS_TP_TAG), BLAS=$blas, METIS=${SITE_METIS_LFLAGS:-none}"
    git_checkout https://github.com/coin-or-tools/ThirdParty-Mumps.git "$MUMPS_TP_TAG" "$src/mumps"
    ( cd "$src/mumps" && ./get.Mumps )
    local metis_args=()
    if [[ -n "${SITE_METIS_LFLAGS:-}" ]]; then
        metis_args=(--with-metis --with-metis-lflags="$SITE_METIS_LFLAGS" --with-metis-cflags="${SITE_METIS_CFLAGS:-}")
    else
        metis_args=(--without-metis)
    fi
    ( cd "$src/mumps" && ./configure --prefix="$inst" --disable-static \
        --with-lapack --with-lapack-lflags="$lapack" "${metis_args[@]}" \
        && make -j"$SITE_JOBS" && make install )

    log "Ipopt $IPOPT_TAG"
    git_checkout https://github.com/coin-or/Ipopt.git "$IPOPT_TAG" "$src/ipopt"
    mkdir -p "$src/ipopt/build"
    ( cd "$src/ipopt/build" && PKG_CONFIG_PATH="$inst/lib/pkgconfig" ../configure \
        --prefix="$inst" --disable-static --disable-java --without-asl --without-hsl \
        --with-lapack --with-lapack-lflags="$lapack" \
        && make -j"$SITE_JOBS" && make install )

    ldd "$inst/lib/libipopt.so" | grep -E "mumps|openblas|metis|gfortran"
    check_ldd "$inst/lib" || die "unresolved libraries in $inst/lib"
}
