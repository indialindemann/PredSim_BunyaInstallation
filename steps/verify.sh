# Verify the stack: library resolution, then PredSim's linux/verify/verify_stack.m
# (CasADi+Ipopt in MATLAB, OpenSim Java API, short end-to-end PredSim run).
# Always runs. PREDSIM_VERIFY_ITERS caps the PredSim run (default 80).

step_main() {
    log "library resolution (no LD_LIBRARY_PATH)"
    local jni; jni="$(find "$OPENSIM_PREFIX/opensim" -name libosimJavaJNI.so | head -1)"
    local f bad
    for f in "$jni" "$PREFIX/casadi/libcasadi_nlpsol_ipopt.so" "$PREFIX/casadi/casadiMEX.mexa64"; do
        bad="$(ldd_unresolved "$f")"
        [[ -z "$bad" ]] || { echo "$bad"; die "$f has unresolved libraries (as MATLAB would load it)"; }
    done
    log "  OK"

    log "MATLAB end-to-end check (log: $PREFIX/logs/verify-matlab.log)"
    "$PREDSIM_DIR/linux/run_predsim.sh" --env "$PREFIX/env.sh" \
        --script linux/verify/verify_stack --log "$PREFIX/logs/verify-matlab.log" >/dev/null 2>&1 \
        || { tail -40 "$PREFIX/logs/verify-matlab.log"; die "MATLAB verification failed"; }
    grep -q "VERIFY PASSED" "$PREFIX/logs/verify-matlab.log" || die "verification did not report success"
    # BLAS argument errors mean a broken linear solver even when the run
    # "succeeds" (seen with a pthreads OpenBLAS on Bunya: the solve diverged).
    local nerr; nerr="$(grep -cE 'MKL ERROR|On entry to [A-Z]+ parameter' "$PREFIX/logs/verify-matlab.log" || true)"
    [[ "$nerr" == 0 ]] || { grep -m3 -E 'MKL ERROR|On entry to' "$PREFIX/logs/verify-matlab.log"; die "BLAS reported $nerr argument errors during the PredSim run: the stack's linear solver is broken"; }
    grep -E "^\[verify|EXIT:|differ|match" "$PREFIX/logs/verify-matlab.log" || true
    log "verify OK"
}
