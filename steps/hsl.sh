# CoinHSL (HSL MA97 etc.) for Ipopt, from an archive the user downloads under
# the HSL licence (https://licences.stfc.ac.uk/product/coin-hsl; free for
# academic use). Runs only with --hsl ARCHIVE (or HSL_ARCHIVE=...):
#
#   coinhsl-<ver>.tar.gz                          source: built here with meson
#   CoinHSL.v<ver>.x86_64-linux-gnu-*.tar.gz      binary: relinked here
#
# Both end up as $PREFIX/hsl/lib/libhsl.so, linked against an OpenMP OpenBLAS
# (libopenblasomp, see build_openblasomp): MA97 calls BLAS from OpenMP
# threads. matlab-config then exports PREDSIM_HSL_LIB, and PredSim's
# OCP/solve_NLPSOL.m switches Ipopt to linear_solver=ma97 (as on Windows).
# Works with prebuilt and source CasADi (both Ipopts load hsllib at run time).

step_applies() { [[ -n "${HSL_ARCHIVE:-}" ]]; }

step_main() {
    [[ -f "$HSL_ARCHIVE" ]] || die "HSL archive not found: $HSL_ARCHIVE"
    local omp="$PREFIX/openblas-omp" inst="$PREFIX/hsl" src="$BUILD_ROOT/hsl-src"
    build_openblasomp "$omp"
    rm -rf "$src" "$inst"; mkdir -p "$src"
    tar -xzf "$HSL_ARCHIVE" -C "$src"
    local top; top="$(find "$src" -maxdepth 2 -name meson.build -printf '%h\n' | head -1)"
    local pe="$PREFIX/python/bin/patchelf"

    if [[ -n "$top" ]]; then
        log "CoinHSL source build ($(basename "$HSL_ARCHIVE"))"
        "$PREFIX/python/bin/pip" install -q "meson==1.5.2" "ninja==1.11.1.1"
        # Pass only the options this CoinHSL version defines.
        local opts=() o
        o="$(cat "$top"/meson_options.txt "$top"/meson.options 2>/dev/null || true)"
        has() { grep -q "option('$1'" <<< "$o"; }
        has libblas        && opts+=(-Dlibblas=openblasomp -Dlibblas_path="$omp/lib")
        has liblapack      && opts+=(-Dliblapack=openblasomp -Dliblapack_path="$omp/lib")
        local mlib mdir minc
        mlib="${SITE_METIS_LFLAGS:-}"; mdir="$(grep -oE -- '-L[^ ]+' <<< "$mlib" | head -1 | cut -c3-)"
        minc="$(grep -oE -- '-I[^ ]+' <<< "${SITE_METIS_CFLAGS:-}" | head -1 | cut -c3-)"
        if [[ -n "$mlib" ]] && has libmetis; then
            opts+=(-Dlibmetis=metis)
            [[ -n "$mdir" ]] && has libmetis_path && opts+=(-Dlibmetis_path="$mdir")
            [[ -n "$minc" ]] && has libmetis_include && opts+=(-Dlibmetis_include="$minc")
            has libmetis_version && opts+=(-Dlibmetis_version=5)
        fi
        log "meson options: ${opts[*]}"
        ( cd "$top" && CC="$CC" FC="$FC" \
            LDFLAGS="-Wl,-rpath,$omp/lib${mdir:+ -Wl,-rpath,$mdir}" \
            "$PREFIX/python/bin/meson" setup "$src/build" --prefix="$inst" --libdir=lib \
                --buildtype=release "${opts[@]}" \
          && "$PREFIX/python/bin/meson" compile -C "$src/build" -j "$SITE_JOBS" \
          && "$PREFIX/python/bin/meson" install -C "$src/build" )
        local so; so="$(find "$inst/lib" -maxdepth 1 -name 'lib*hsl*.so' ! -type l | head -1)"
        [[ -n "$so" ]] || so="$(find "$inst/lib" -maxdepth 1 -name 'lib*hsl*.so*' | head -1)"
        [[ -n "$so" ]] || die "no libcoinhsl/libhsl built in $inst/lib"
        [[ "$(basename "$so")" == libhsl.so ]] || ln -sfn "$(basename "$so")" "$inst/lib/libhsl.so"
    else
        local bin; bin="$(find "$src" -name 'libhsl.so' | head -1)"
        [[ -n "$bin" ]] || die "$HSL_ARCHIVE has neither meson.build (source) nor libhsl.so (binary)"
        log "CoinHSL binary ($(basename "$HSL_ARCHIVE"))"
        mkdir -p "$inst"; cp -a "$(dirname "$bin")" "$inst/lib"
        # Point its BLAS at the OpenMP OpenBLAS, under a name MATLAB has not
        # already loaded (OpenSim's pthreads libopenblas.so.0).
        local f n
        for f in "$inst"/lib/*.so*; do
            [[ -L "$f" ]] && continue
            for n in $(readelf -d "$f" 2>/dev/null | sed -n 's/.*NEEDED.*\[\(libopenblas[^]]*\|libblas[^]]*\|liblapack[^]]*\)\].*/\1/p'); do
                "$pe" --replace-needed "$n" libopenblasomp.so.0 "$f"
            done
            "$pe" --set-rpath "\$ORIGIN:$omp/lib" "$f"
        done
        # its own bundled BLAS copies, if any, must not be picked up instead
        rm -f "$inst"/lib/libopenblas*.so* "$inst"/lib/libblas*.so* "$inst"/lib/liblapack*.so*
    fi

    bake_rpath "$inst"/lib/*.so*
    readelf -d "$inst/lib/libhsl.so" | grep NEEDED
    local bad; bad="$(ldd_unresolved "$inst/lib/libhsl.so")"
    [[ -z "$bad" ]] || { echo "$bad"; die "libhsl.so has unresolved libraries (as MATLAB would load it)"; }
    ldd "$inst/lib/libhsl.so" | grep -q 'libopenblasomp' \
        || warn "libhsl.so does not use libopenblasomp; check its BLAS (pthreads OpenBLAS is unsafe for MA97)"
    nm -D --defined-only "$inst/lib/libhsl.so" | grep -q ' ma97_factor_d' || die "libhsl.so has no MA97 (ma97_factor_d)"
    log "CoinHSL in $inst/lib/libhsl.so"
    # env.sh must gain PREDSIM_HSL_LIB: make matlab-config rerun
    rm -f "$PREFIX/.done/matlab-config"
}
