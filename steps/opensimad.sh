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
    [[ -f "$dest/linux/lib/libosimSimulation_recorder.so" ]] || die "unexpected opensimAD archive layout in $dest"
    log "EBROOTOPENSIMAD=$dest/linux"
}
