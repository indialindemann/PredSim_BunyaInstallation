# opensimAD recorder libraries used by PredSim/opensimAD_linux to build external
# functions. Installed once here and exposed as EBROOTOPENSIMAD, so PredSim
# never downloads from SourceForge mid-run (compute nodes may be offline).

step_main() {
    local dest="$PREFIX/opensimad"
    rm -rf "$dest"; mkdir -p "$dest"
    fetch "$OPENSIMAD_URL" "$BUILD_ROOT/opensimad-linux.tar.gz"
    file -b "$BUILD_ROOT/opensimad-linux.tar.gz" | grep -q gzip \
        || die "opensimAD download is not a gzip archive (SourceForge returned HTML?). Delete $PREDSIM_CACHE/opensimad-linux.tar.gz and retry."
    tar -xzf "$BUILD_ROOT/opensimad-linux.tar.gz" -C "$dest"
    # archive contains linux/{include,lib}
    local lib="$dest/linux/lib"
    [[ -f "$lib/libosimSimulation_recorder.so" ]] || die "unexpected opensimAD archive layout in $dest"

    # The SimTK recorder libs need libopenblas.so.0 but carry no RUNPATH, so they
    # only worked with a global LD_LIBRARY_PATH. Give them $ORIGIN and put the
    # site OpenBLAS next to them. (opensimAD runs them in a separate process,
    # not inside MATLAB, so MATLAB's MKL is not involved.)
    ln -sfn "$(site_blas_dir)/libopenblas.so.0" "$lib/libopenblas.so.0"
    local f
    for f in "$lib"/*.so*; do
        [[ -L "$f" ]] && continue
        if ! readelf -d "$f" | grep -qE "RUNPATH|RPATH"; then
            "$PREFIX/python/bin/patchelf" --set-rpath '$ORIGIN' "$f"
        fi
    done
    local bad
    for f in "$lib"/*_recorder.so; do
        bad="$(ldd_unresolved "$f")"
        [[ -z "$bad" ]] || { echo "$bad"; die "$f has unresolved libraries"; }
    done
    log "EBROOTOPENSIMAD=$dest/linux"
}
