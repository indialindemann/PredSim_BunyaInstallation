# OpenSim core (pinned tag) with Java bindings for MATLAB. Dependencies
# (Simbody, spdlog, docopt) come from OpenSim's own superbuild at the commits
# that tag pins. OpenSim is only used in PredSim preprocessing, so it is built
# with plain -O2 Release flags and system/site LAPACK; it is not speed-critical.
#
# Install RPATHs point at the install tree, so build dirs can be deleted.

step_main() {
    local src="$BUILD_ROOT/opensim-core" deps_inst="$PREFIX/opensim-deps" inst="$PREFIX/opensim"
    git_checkout https://github.com/opensim-org/opensim-core.git "$OPENSIM_TAG" "$src"

    log "OpenSim superbuild dependencies"
    cmake -S "$src/dependencies" -B "$src/build-deps" \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX="$deps_inst" \
        -DSUPERBUILD_ezc3d=OFF \
        -DSUPERBUILD_catch2=OFF \
        -DOPENSIM_WITH_CASADI=OFF \
        -DOPENSIM_WITH_TROPTER=OFF
    cmake --build "$src/build-deps" --parallel "$SITE_JOBS"

    log "OpenSim core $OPENSIM_TAG"
    cmake -S "$src" -B "$src/build" \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX="$inst" \
        -DCMAKE_INSTALL_RPATH="$inst/lib;$inst/sdk/lib;$deps_inst/simbody/lib;$deps_inst/simbody/lib64;$deps_inst/spdlog/lib;$deps_inst/docopt/lib" \
        -DCMAKE_BUILD_WITH_INSTALL_RPATH=OFF \
        -DOPENSIM_DEPENDENCIES_DIR="$deps_inst" \
        -DOPENSIM_WITH_CASADI=OFF \
        -DOPENSIM_WITH_TROPTER=OFF \
        -DOPENSIM_C3D_PARSER=None \
        -DBUILD_JAVA_WRAPPING=ON \
        -DBUILD_PYTHON_WRAPPING=OFF \
        -DBUILD_API_EXAMPLES=OFF \
        -DBUILD_TESTING=OFF \
        -DOPENSIM_INSTALL_UNIXFHS=OFF \
        -DSWIG_DIR="$PREFIX/swig/share/swig/$SWIG_OPENSIM_VERSION" \
        -DSWIG_EXECUTABLE="$PREFIX/swig/bin/swig" \
        -DJava_JAVAC_EXECUTABLE="$JAVA_HOME/bin/javac"
    cmake --build "$src/build" --parallel "$SITE_JOBS"
    cmake --install "$src/build"

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
