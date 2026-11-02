# PredSim checkout on the Linux branch. An existing checkout is never reset or
# switched: uncommitted work is yours. We only report its state.

step_main() {
    if [[ ! -d "$PREDSIM_DIR/.git" ]]; then
        git clone --recurse-submodules -b "$PREDSIM_BRANCH" "$PREDSIM_REPO" "$PREDSIM_DIR"
    else
        local br; br="$(git -C "$PREDSIM_DIR" rev-parse --abbrev-ref HEAD)"
        log "existing checkout $PREDSIM_DIR on branch '$br' (left as is)"
        [[ "$br" == "$PREDSIM_BRANCH" ]] || warn "expected branch $PREDSIM_BRANCH; switch manually if needed"
        git -C "$PREDSIM_DIR" submodule update --init --recursive
    fi
    [[ -x "$PREDSIM_DIR/linux/run_predsim.sh" ]] \
        || die "$PREDSIM_DIR has no linux/run_predsim.sh: check out $PREDSIM_BRANCH"
}
