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
    # MUMPS_OPENMP=1 (or SITE_MUMPS_OPENMP=1): build MUMPS with OpenMP, so its
    # factorisation uses OMP_NUM_THREADS threads (BLAS threads come from
    # OPENBLAS_NUM_THREADS either way). Off by default.
    local omp_args=(--disable-openmp)
    [[ "${MUMPS_OPENMP:-${SITE_MUMPS_OPENMP:-0}}" == 1 ]] && omp_args=(--enable-openmp)
    log "MUMPS OpenMP: ${omp_args[*]}"
    local metis_args=()
    if [[ -n "${SITE_METIS_LFLAGS:-}" ]]; then
        metis_args=(--with-metis --with-metis-lflags="$SITE_METIS_LFLAGS" --with-metis-cflags="${SITE_METIS_CFLAGS:-}")
    else
        metis_args=(--without-metis)
    fi
    ( cd "$src/mumps" && ./configure --prefix="$inst" --disable-static \
        --with-lapack --with-lapack-lflags="$lapack" "${metis_args[@]}" "${omp_args[@]}" \
        && make -j"$SITE_JOBS" && make install )

    log "Ipopt $IPOPT_TAG"
    git_checkout https://github.com/coin-or/Ipopt.git "$IPOPT_TAG" "$src/ipopt"
    mkdir -p "$src/ipopt/build"
    ( cd "$src/ipopt/build" && PKG_CONFIG_PATH="$inst/lib/pkgconfig" ../configure \
        --prefix="$inst" --disable-static --disable-java --without-asl --without-hsl \
        --with-lapack --with-lapack-lflags="$lapack" \
        && make -j"$SITE_JOBS" && make install )

    # libtool drops -Wl,-rpath for module libraries (e.g. METIS on Bunya); bake
    # the resolved dependency dirs in so MATLAB (no module env) finds them too.
    bake_rpath "$inst"/lib/libcoinmumps.so.* "$inst"/lib/libipopt.so.*
    ldd "$inst/lib/libipopt.so" | grep -E "mumps|openblas|metis|gfortran"
    local f bad
    for f in "$inst"/lib/libcoinmumps.so "$inst"/lib/libipopt.so; do
        bad="$(ldd_unresolved "$f")"
        [[ -z "$bad" ]] || { echo "$bad"; die "$f has unresolved libraries (as MATLAB would load it)"; }
    done
    check_ldd "$inst/lib" || die "unresolved libraries in $inst/lib"
}
