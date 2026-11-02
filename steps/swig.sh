# Upstream SWIG for OpenSim's Java bindings (NOT the CasADi SWIG fork; CasADi
# needs no SWIG at all with its source-release archive). PCRE2 is built
# statically via SWIG's own Tools/pcre-build.sh so no pcre2 module/package is needed.

PCRE2_VERSION="10.42"

STEP_SHARED=1

step_main() {
    local src="$OPENSIM_PREFIX/build/swig-$SWIG_OPENSIM_VERSION"
    fetch "https://downloads.sourceforge.net/project/swig/swig/swig-$SWIG_OPENSIM_VERSION/swig-$SWIG_OPENSIM_VERSION.tar.gz" \
          "$OPENSIM_PREFIX/build/swig-$SWIG_OPENSIM_VERSION.tar.gz"
    rm -rf "$src"; tar -xzf "$OPENSIM_PREFIX/build/swig-$SWIG_OPENSIM_VERSION.tar.gz" -C "$OPENSIM_PREFIX/build"
    fetch "https://github.com/PCRE2Project/pcre2/releases/download/pcre2-$PCRE2_VERSION/pcre2-$PCRE2_VERSION.tar.gz" \
          "$src/pcre2-$PCRE2_VERSION.tar.gz"
    ( cd "$src" && Tools/pcre-build.sh \
        && ./configure --prefix="$OPENSIM_PREFIX/swig" \
        && make -j"$SITE_JOBS" && make install )
    "$OPENSIM_PREFIX/swig/bin/swig" -version | grep -i "SWIG Version"
}
