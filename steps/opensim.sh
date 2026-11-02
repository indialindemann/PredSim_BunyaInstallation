# OpenSim core (pinned tag) with Java bindings for MATLAB. Dependencies
# (Simbody, spdlog, docopt) come from OpenSim's own superbuild at the commits
# that tag pins. OpenSim is only used in PredSim preprocessing, so it is built
# with plain -O2 Release flags and system/site LAPACK; it is not speed-critical.
#
# Install RPATHs point at the install tree, so build dirs can be deleted.

STEP_SHARED=1

step_main() {
    local src="$OPENSIM_PREFIX/build/opensim-core" deps_inst="$OPENSIM_PREFIX/opensim-deps" inst="$OPENSIM_PREFIX/opensim"
    git_checkout https://github.com/opensim-org/opensim-core.git "$OPENSIM_TAG" "$src"

    # Sites that build their own OpenBLAS point Simbody's LAPACK search at it;
    # otherwise the system LAPACK is used (OpenSim is not speed-critical here).
    if [[ "${SITE_BUILD_OPENBLAS:-0}" == 1 ]]; then
        export BLA_VENDOR=OpenBLAS
        export CMAKE_PREFIX_PATH="$(dirname "$(site_blas_dir)")${CMAKE_PREFIX_PATH:+:$CMAKE_PREFIX_PATH}"
    fi
    local rp="" d
    for d in "$inst" "$deps_inst/simbody" "$deps_inst/spdlog" "$deps_inst/docopt"; do
        rp+="$d/lib;$d/lib64;"
    done
    rp+="$inst/sdk/lib"
    [[ "${SITE_BUILD_OPENBLAS:-0}" == 1 ]] && rp+=";$(site_blas_dir)"

    log "OpenSim superbuild dependencies"
    cmake -S "$src/dependencies" -B "$src/build-deps" \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX="$deps_inst" \
        -DSUPERBUILD_ezc3d=OFF \
        -DSUPERBUILD_catch2=OFF \
        -DOPENSIM_WITH_CASADI=OFF
    cmake --build "$src/build-deps" --parallel "$SITE_JOBS"

    # RHEL installs the dependencies' CMake configs under lib64, where OpenSim's
    # OPENSIM_DEPENDENCIES_DIR search does not look; point at them explicitly.
    local docopt_cfg
    docopt_cfg="$(find "$deps_inst/docopt" -name 'docopt-config.cmake' -printf '%h\n' | head -1)"
    [[ -n "$docopt_cfg" ]] || die "docopt-config.cmake not found under $deps_inst/docopt"

    log "OpenSim core $OPENSIM_TAG"
    cmake -S "$src" -B "$src/build" \
        -Ddocopt_DIR="$docopt_cfg" \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX="$inst" \
        -DCMAKE_INSTALL_RPATH="$rp" \
        -DCMAKE_BUILD_WITH_INSTALL_RPATH=OFF \
        -DOPENSIM_DEPENDENCIES_DIR="$deps_inst" \
        -DOPENSIM_WITH_CASADI=OFF \
        -DOPENSIM_C3D_PARSER=None \
        -DBUILD_JAVA_WRAPPING=ON \
        -DBUILD_PYTHON_WRAPPING=OFF \
        -DBUILD_API_EXAMPLES=OFF \
        -DBUILD_TESTING=OFF \
        -DSWIG_DIR="$OPENSIM_PREFIX/swig/share/swig/$SWIG_OPENSIM_VERSION" \
        -DSWIG_EXECUTABLE="$OPENSIM_PREFIX/swig/bin/swig" \
        -DJava_JAVAC_EXECUTABLE="$JAVA_HOME/bin/javac"
    cmake --build "$src/build" --parallel "$SITE_JOBS"
    cmake --install "$src/build"

    # OpenSim >= 4.5 installs the jar in share/java; keep the sdk/Java path that
    # PredSim's runner (and older installs) expect.
    if [[ ! -f "$inst/sdk/Java/org-opensim-modeling.jar" ]]; then
        local built_jar; built_jar="$(find "$inst" -name org-opensim-modeling.jar | head -1)"
        [[ -n "$built_jar" ]] || die "org-opensim-modeling.jar not installed"
        mkdir -p "$inst/sdk/Java"
        ln -sfn "$(realpath --relative-to="$inst/sdk/Java" "$built_jar")" "$inst/sdk/Java/org-opensim-modeling.jar"
    fi

    local jar="$inst/sdk/Java/org-opensim-modeling.jar"
    local jni; jni="$(find "$inst" -name 'libosimJavaJNI.so' | head -1)"
    [[ -f "$jar" ]] || die "OpenSim jar not installed at $jar"
    [[ -n "$jni" ]] || die "libosimJavaJNI.so not installed under $inst"
    log "jar: $jar"
    log "jni: $jni"
    env -u LD_LIBRARY_PATH ldd "$jni" | grep -E "not found|osim|SimTK|lapack|blas" || true
    if env -u LD_LIBRARY_PATH ldd "$jni" | grep -q "not found"; then
        die "libosimJavaJNI.so has unresolved dependencies without LD_LIBRARY_PATH"
    fi
}
