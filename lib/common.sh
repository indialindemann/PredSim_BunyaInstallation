#!/bin/bash
# Shared helpers for predsim-install.sh and the step scripts. Sourced, not run.

log()  { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*"; }
warn() { printf '[%s] WARNING: %s\n' "$(date +%H:%M:%S)" "$*" >&2; }
die()  { printf '[%s] ERROR: %s\n' "$(date +%H:%M:%S)" "$*" >&2; exit 1; }

need_cmd() {
    local c
    for c in "$@"; do
        command -v "$c" >/dev/null 2>&1 || die "required command not found: $c"
    done
}

# fetch URL DEST: download once into the shared cache, then copy/link to DEST.
fetch() {
    local url="$1" dest="$2"
    local cached="$PREDSIM_CACHE/$(basename "$dest")"
    mkdir -p "$PREDSIM_CACHE" "$(dirname "$dest")"
    if [[ ! -s "$cached" ]]; then
        log "download $url"
        curl -fsSL --retry 3 --retry-delay 5 -o "$cached.part" "$url" || die "download failed: $url"
        mv "$cached.part" "$cached"
    fi
    [[ "$cached" -ef "$dest" ]] || cp -f "$cached" "$dest"
}

# extract_zip ZIP DIR  (python, so no dependency on unzip)
extract_zip() {
    python3 -I - "$1" "$2" <<'EOF'
import sys, zipfile, os
z = zipfile.ZipFile(sys.argv[1])
for info in z.infolist():
    path = z.extract(info, sys.argv[2])
    mode = (info.external_attr >> 16) & 0o777
    if mode:
        os.chmod(path, mode | 0o200)
EOF
}

# git_checkout URL REF DIR: shallow clone/update DIR at a tag/branch/commit.
git_checkout() {
    local url="$1" ref="$2" dir="$3"
    if [[ ! -d "$dir/.git" ]]; then
        git init -q "$dir"
        git -C "$dir" remote add origin "$url"
    fi
    git -C "$dir" fetch -q --depth 1 origin "$ref" || die "git fetch $url $ref failed"
    # same commit already checked out: keep in-tree build dirs (incremental rebuild)
    if [[ "$(git -C "$dir" rev-parse -q --verify HEAD 2>/dev/null)" == "$(git -C "$dir" rev-parse FETCH_HEAD)" ]]; then
        return 0
    fi
    git -C "$dir" checkout -q --force FETCH_HEAD
    git -C "$dir" clean -qfdx
}

# max GLIBCXX symbol version a libstdc++ provides, e.g. 30 for GLIBCXX_3.4.30
glibcxx_level() {
    strings "$1" 2>/dev/null | grep -oE '^GLIBCXX_3\.4\.[0-9]+$' | sed 's/GLIBCXX_3\.4\.//' | sort -n | tail -1
}

# Check every ELF file under DIR resolves all its shared-library deps
# with the given LD_LIBRARY_PATH. Prints offenders; returns 1 if any.
check_ldd() {
    local dir="$1" bad=0 f missing
    while IFS= read -r -d '' f; do
        file -b "$f" | grep -q 'ELF.*shared object\|ELF.*executable' || continue
        missing="$(ldd "$f" 2>/dev/null | grep 'not found' | grep -vE 'libmex|libmx|libut|libeng|libMatlab' || true)"
        if [[ -n "$missing" ]]; then
            echo "  $f:"; echo "$missing" | sed 's/^/    /'; bad=1
        fi
    done < <(find "$dir" -type f \( -name '*.so*' -o -name '*.mexa64' \) -print0)
    return $bad
}

# ldd_unresolved FILE: print unresolved deps (or version errors) of FILE as MATLAB
# would load it: no LD_LIBRARY_PATH, plus the site's toolchain-runtime preload
# when the site declares one (site_matlab_preload_names). Empty output = OK.
ldd_unresolved() {
    local pre="" l
    if declare -F site_matlab_preload_names >/dev/null; then
        for l in $(site_matlab_preload_names); do pre+="$("$CXX" -print-file-name="$l"):"; done
    fi
    env -u LD_LIBRARY_PATH ${pre:+LD_PRELOAD="${pre%:}"} ldd "$1" 2>&1 \
        | grep -E "not found|version .* not found" | grep -vE 'libmex|libmx|libut|libeng|libMatlab' || true
}

# bake_rpath FILE...: add to each file's RUNPATH the directories of all its
# shared-library dependencies as resolved *now* (build environment, modules
# loaded), excluding system dirs. Afterwards the files load the same libraries
# in any process, e.g. MATLAB, which runs without module LD_LIBRARY_PATHs.
bake_rpath() {
    local f dirs old new
    for f in "$@"; do
        [[ -L "$f" ]] && continue
        dirs="$(ldd "$f" 2>/dev/null | awk '/=> \//{print $3}' | xargs -r -n1 dirname | xargs -r -n1 realpath \
                | grep -vE '^/(usr/)?lib(64)?(/|$)' | sort -u | paste -sd:)"
        old="$("$PREFIX/python/bin/patchelf" --print-rpath "$f" 2>/dev/null || true)"
        new="$(printf '%s' "${old:+$old:}$dirs" | tr ':' '\n' | awk 'NF && !seen[$0]++' | paste -sd:)"
        [[ -n "$new" && "$new" != "$old" ]] && "$PREFIX/python/bin/patchelf" --set-rpath "$new" "$f"
    done
    return 0
}

# build_openblas_omp DIR: OpenBLAS with USE_OPENMP=1, installed as
# libopenblas_omp.so.0 in DIR/lib (skipped if already there). OpenMP solvers
# (MUMPS --enable-openmp, HSL MA97) call BLAS from inside OpenMP parallel
# regions, which a pthreads OpenBLAS does not support (corrupted arguments,
# hangs). The _omp name keeps it distinct from the pthreads libopenblas.so.0
# that OpenSim's JNI loads into MATLAB first: the loader would otherwise reuse
# that one for every later library asking for libopenblas.so.0.
OPENBLAS_OMP_VERSION="0.3.32"
build_openblas_omp() {
    local inst="$1" ver="$OPENBLAS_OMP_VERSION"
    if [[ -f "$inst/lib/libopenblas_omp.so.0" && "$(cat "$inst/.version" 2>/dev/null)" == "$ver" ]]; then
        log "OpenMP OpenBLAS $ver already in $inst"; return 0
    fi
    local tgz="$BUILD_ROOT/OpenBLAS-$ver.tar.gz" src="$BUILD_ROOT/OpenBLAS-$ver-omp"
    fetch "https://github.com/OpenMathLib/OpenBLAS/releases/download/v$ver/OpenBLAS-$ver.tar.gz" "$tgz"
    rm -rf "$src" "$inst"; mkdir -p "$src"
    tar -xzf "$tgz" -C "$src" --strip-components=1
    log "building OpenMP OpenBLAS $ver (DYNAMIC_ARCH) -> $inst"
    make -C "$src" -j"$SITE_JOBS" CC="$CC" FC="$FC" DYNAMIC_ARCH=1 TARGET=HASWELL \
        USE_OPENMP=1 NUM_THREADS=256 LIBNAMESUFFIX=omp NO_STATIC=1 libs netlib shared >/dev/null
    make -C "$src" PREFIX="$inst" LIBNAMESUFFIX=omp NO_STATIC=1 install >/dev/null
    [[ -f "$inst/lib/libopenblas_omp.so.0" ]] || die "libopenblas_omp.so.0 not installed in $inst/lib"
    readelf -d "$inst/lib/libopenblas_omp.so.0" | grep -q 'libgomp' || die "OpenBLAS in $inst is not an OpenMP build"
    echo "$ver" > "$inst/.version"
}
