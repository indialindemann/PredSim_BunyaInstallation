# Check the toolchain before spending an hour compiling.

step_main() {
    need_cmd git curl make tar python3 file strings "$CC" "$CXX" matlab java javac
    [[ "$CASADI_MODE" == source ]] && need_cmd "$FC"

    log "CC  = $($CC --version | head -1)"
    log "FC  = $($FC --version 2>/dev/null | head -1 || echo none)"
    log "MATLAB_ROOT = $MATLAB_ROOT"
    log "java = $(java -version 2>&1 | head -1)"
    local py; py="$(site_python)" || die "site_python failed"
    "$py" -c "import ensurepip, venv" 2>/dev/null || die "$py cannot create venvs (no ensurepip)"
    log "python = $py ($("$py" --version 2>&1))"

    # MATLAB loads its own libstdc++; anything we build that MATLAB loads (OpenSim
    # JNI, CasADi MEX/plugins in source mode, opensimAD .so) must not need newer.
    local mlib="$MATLAB_ROOT/sys/os/glnxa64/libstdc++.so.6"
    local clib; clib="$($CXX -print-file-name=libstdc++.so.6)"
    local ml cl
    ml="$(glibcxx_level "$mlib")"; cl="$(glibcxx_level "$clib")"
    log "GLIBCXX: MATLAB 3.4.$ml, compiler 3.4.$cl"
    if [[ -n "$ml" && -n "$cl" && "$cl" -gt "$ml" ]]; then
        if [[ "${SITE_ALLOW_NEWER_LIBSTDCXX:-0}" == 1 ]]; then
            warn "compiler libstdc++ (3.4.$cl) is newer than MATLAB's (3.4.$ml); $SITE preloads the toolchain's runtime into MATLAB (PREDSIM_MATLAB_LD_PRELOAD)"
        else
            die "compiler libstdc++ (3.4.$cl) is newer than MATLAB's (3.4.$ml). Use an older gcc in $SITE_FILE, or MATLAB will fail to load OpenSim/CasADi."
        fi
    fi

    local avail; avail=$(df -Pk "$(dirname "$PREFIX")" | awk 'NR==2{print int($4/1048576)}')
    log "free disk at prefix: ${avail} GB"
    [[ "$avail" -ge 15 ]] || die "need ~15 GB free for builds"

    if [[ "$PREDSIM_REPO" == git@* && ! -d "$PREDSIM_DIR/.git" ]]; then
        ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new -T git@github.com 2>&1 | grep -q "successfully authenticated" \
            || die "no GitHub SSH access (needed to clone $PREDSIM_REPO). Add this machine's SSH key to GitHub."
    fi

    # OpenBLAS: opensimAD's recorder libraries always need it; source mode also
    # links Ipopt/MUMPS against it.
    if [[ "${SITE_BUILD_OPENBLAS:-0}" == 1 ]]; then
        log "BLAS: OpenBLAS will be built (openblas step)"
    else
        site_blas_dir >/dev/null || die "site BLAS (OpenBLAS) not available"
        log "BLAS dir = $(site_blas_dir)"
    fi
    log "preflight OK"
}
