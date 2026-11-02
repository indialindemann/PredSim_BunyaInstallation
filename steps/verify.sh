# Verify the stack: library resolution, then PredSim's linux/verify/verify_stack.m
# (CasADi+Ipopt in MATLAB, OpenSim Java API, short end-to-end PredSim run).
# Always runs. PREDSIM_VERIFY_ITERS caps the PredSim run (default 80).

step_main() {
    log "library resolution (no LD_LIBRARY_PATH)"
    local jni; jni="$(find "$OPENSIM_PREFIX/opensim" -name libosimJavaJNI.so | head -1)"
    env -u LD_LIBRARY_PATH ldd "$jni" | grep -q "not found" && die "OpenSim JNI has unresolved libraries"
    env -u LD_LIBRARY_PATH ldd "$PREFIX/casadi/libcasadi_nlpsol_ipopt.so" | grep -q "not found" \
        && die "CasADi Ipopt plugin has unresolved libraries"
    log "  OK"

    log "MATLAB end-to-end check (log: $PREFIX/logs/verify-matlab.log)"
    "$PREDSIM_DIR/linux/run_predsim.sh" --env "$PREFIX/env.sh" \
        --script linux/verify/verify_stack --log "$PREFIX/logs/verify-matlab.log" >/dev/null 2>&1 \
        || { tail -40 "$PREFIX/logs/verify-matlab.log"; die "MATLAB verification failed"; }
    grep -q "VERIFY PASSED" "$PREFIX/logs/verify-matlab.log" || die "verification did not report success"
    grep -E "^\[verify|EXIT:|differ|match" "$PREFIX/logs/verify-matlab.log" || true
    log "verify OK"
}
