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
