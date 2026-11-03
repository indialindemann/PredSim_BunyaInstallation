# OpenSim Geometry (.vtp meshes) for model visualisation, from opensim-models.
# Replaces extracting the Windows installer with 7-Zip. Set
# PREDSIM_GEOMETRY_SRC to copy from an existing folder instead (offline nodes).

STEP_SHARED=1

step_main() {
    local dest="$OPENSIM_PREFIX/opensim/Geometry"
    mkdir -p "$(dirname "$dest")"
    rm -rf "$dest"
    if [[ -n "${PREDSIM_GEOMETRY_SRC:-}" ]]; then
        [[ -d "$PREDSIM_GEOMETRY_SRC" ]] || die "PREDSIM_GEOMETRY_SRC is not a directory: $PREDSIM_GEOMETRY_SRC"
        cp -r "$PREDSIM_GEOMETRY_SRC" "$dest"
    else
        local src="$OPENSIM_PREFIX/build/opensim-models"
        rm -rf "$src"
        git clone -q --filter=blob:none --no-checkout https://github.com/opensim-org/opensim-models.git "$src"
        git -C "$src" sparse-checkout set --no-cone /Geometry
        git -C "$src" checkout -q "$OPENSIM_MODELS_REF"
        cp -r "$src/Geometry" "$dest"
    fi
    log "$(find "$dest" -name '*.vtp' | wc -l) geometry files in $dest"
}
