# Upstream SWIG for OpenSim's Java bindings (NOT the CasADi SWIG fork; CasADi
# needs no SWIG at all with its source-release archive). PCRE2 is built
# statically via SWIG's own Tools/pcre-build.sh so no pcre2 module/package is needed.

PCRE2_VERSION="10.42"

step_main() {
    local src="$BUILD_ROOT/swig-$SWIG_OPENSIM_VERSION"
    fetch "https://downloads.sourceforge.net/project/swig/swig/swig-$SWIG_OPENSIM_VERSION/swig-$SWIG_OPENSIM_VERSION.tar.gz" \
          "$BUILD_ROOT/swig-$SWIG_OPENSIM_VERSION.tar.gz"
    rm -rf "$src"; tar -xzf "$BUILD_ROOT/swig-$SWIG_OPENSIM_VERSION.tar.gz" -C "$BUILD_ROOT"
    fetch "https://github.com/PCRE2Project/pcre2/releases/download/pcre2-$PCRE2_VERSION/pcre2-$PCRE2_VERSION.tar.gz" \
          "$src/pcre2-$PCRE2_VERSION.tar.gz"
    ( cd "$src" && Tools/pcre-build.sh \
        && ./configure --prefix="$PREFIX/swig" \
        && make -j"$SITE_JOBS" && make install )
    "$PREFIX/swig/bin/swig" -version | grep -i "SWIG Version"
}
