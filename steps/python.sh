# Python venv: casadi (same version as MATLAB's) for opensimAD's genF.py,
# numpy/scipy, and a pinned cmake used both for builds and at run time.

step_main() {
    local py; py="$(site_python)"
    log "base python: $py ($("$py" --version))"
    if ! "$PREFIX/python/bin/python" -m pip --version >/dev/null 2>&1; then
        rm -rf "$PREFIX/python"
        "$py" -m venv "$PREFIX/python"
    fi
    "$PREFIX/python/bin/python" -m pip install -q --upgrade pip setuptools wheel
    # shellcheck disable=SC2086
    "$PREFIX/python/bin/python" -m pip install -q $PY_PACKAGES
    "$PREFIX/python/bin/python" -I -c "import casadi, numpy; print('casadi', casadi.__version__, 'numpy', numpy.__version__)"
    "$PREFIX/python/bin/cmake" --version | head -1
}
