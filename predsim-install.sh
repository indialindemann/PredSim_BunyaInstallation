#!/bin/bash
# PredSim Linux installer.
#
#   ./predsim-install.sh [options]
#
# Options:
#   --site NAME          site config in sites/NAME.env (default: auto-detect;
#                        override with PREDSIM_SITE). Known: ubuntu-local, bunya
#   --casadi MODE        prebuilt | source | both (default: the site's
#                        SITE_CASADI_MODE_DEFAULT, else versions.env). 'both'
#                        installs the two stacks and makes ~/.predsim/env.sh
#                        pick one by the site's SITE_STACK_BY_ARCH (Bunya: source
#                        on every node type, so results don't follow the node)
#   --prefix DIR         install prefix (default ~/predsim-deps/<stack-id>)
#   --predsim-dir DIR    PredSim checkout (default ~/PredSim)
#   --hsl ARCHIVE        install CoinHSL from ARCHIVE (the coinhsl-*.tar.gz source
#                        you download under the HSL licence). Without this option
#                        the newest ~/coinhsl-*.tar.gz is used, and the install
#                        fails if there is none. PredSim then uses MA97, as on
#                        Windows.
#   --no-hsl             skip CoinHSL and use MUMPS. A later run without this
#                        option installs CoinHSL, and future runs use it.
#   --mumps-openmp       (source mode) build MUMPS with OpenMP; stack id gets
#                        -mumpsomp. Not faster for PredSim (see BENCHMARKS.md)
#   --only STEPS         comma-separated step names to run (e.g. casadi,verify)
#   --from STEP          start at STEP, then continue
#   --force              rerun steps even if already done
#   --activate           point ~/.predsim/env.sh at this stack when done
#   --selector-only      with 'both': rewrite ~/.predsim/env.sh from the site
#                        config and exit; builds and checks nothing
#   --list               list steps and their state, then exit
#   --restamp STEPS      mark already-completed steps (state 'stale') as current
#                        without re-running them, e.g. after a comment-only edit
#   -h, --help
#
# Each step logs to <prefix>/logs/<step>.log and writes a done-marker
# containing a hash of its inputs, so re-running only redoes steps whose
# script, versions or site config changed.
set -euo pipefail

INSTALLER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$INSTALLER_DIR/lib/common.sh"
# shellcheck source=versions.env
source "$INSTALLER_DIR/versions.env"

ORIG_ARGS=("$@")
SITE="${PREDSIM_SITE:-}"
CASADI_MODE="${CASADI_MODE:-}"   # --casadi / env; else site default, else versions.env
PREFIX=""
PREDSIM_DIR="${PREDSIM_DIR:-$HOME/PredSim}"
ONLY=""
FROM=""
FORCE=0
ACTIVATE=0
LIST=0
HSL_ARCHIVE="${HSL_ARCHIVE:-}"
NO_HSL=0
MUMPS_OPENMP="${MUMPS_OPENMP:-0}"
RESTAMP=""
SELECTOR_ONLY=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --site)        SITE="$2"; shift 2 ;;
        --casadi)      CASADI_MODE="$2"; shift 2 ;;
        --prefix)      PREFIX="$2"; shift 2 ;;
        --predsim-dir) PREDSIM_DIR="$2"; shift 2 ;;
        --hsl)         HSL_ARCHIVE="$(realpath -e "$2")" || die "--hsl: $2 not found"; shift 2 ;;
        --no-hsl)      NO_HSL=1; shift ;;
        --mumps-openmp) MUMPS_OPENMP=1; shift ;;
        --only)        ONLY="$2"; shift 2 ;;
        --from)        FROM="$2"; shift 2 ;;
        --force)       FORCE=1; shift ;;
        --activate)    ACTIVATE=1; shift ;;
        --list)        LIST=1; shift ;;
        --selector-only) SELECTOR_ONLY=1; shift ;;
        --restamp)     RESTAMP="$2"; shift 2 ;;
        -h|--help)     sed -n '2,36p' "$0"; exit 0 ;;
        *) die "unknown option: $1 (see --help)" ;;
    esac
done

if [[ -z "$SITE" ]]; then
    case "$(hostname -s)" in
        bun*) SITE=bunya ;;
        *)    SITE=ubuntu-local ;;
    esac
fi
SITE_FILE="$INSTALLER_DIR/sites/$SITE.env"
[[ -f "$SITE_FILE" ]] || die "no site config: $SITE_FILE"
# shellcheck source=/dev/null
source "$SITE_FILE"

CASADI_MODE="${CASADI_MODE:-${SITE_CASADI_MODE_DEFAULT:-$CASADI_MODE_DEFAULT}}"
[[ "$CASADI_MODE" == prebuilt || "$CASADI_MODE" == source || "$CASADI_MODE" == both ]] \
    || die "--casadi must be prebuilt, source or both"

[[ "$MUMPS_OPENMP" == 1 && "$CASADI_MODE" != source ]] && die "--mumps-openmp needs --casadi source (prebuilt CasADi ships its own MUMPS)"
MUMPS_TAG=""; [[ "$MUMPS_OPENMP" == 1 ]] && MUMPS_TAG="-mumpsomp"
stack_id() { echo "${SITE}${SITE_VARIANT:+-$SITE_VARIANT}_casadi-${CASADI_VERSION}-$1${MUMPS_TAG}_opensim-${OPENSIM_TAG}"; }

# ~/.predsim/env.sh for 'both': sources one stack, chosen by the site's
# SITE_STACK_BY_ARCH for the CPU type of whichever node it runs on.
# PREDSIM_CASADI_MODE=fastest uses SITE_STACK_FASTEST_BY_ARCH instead.
write_selector() {
    local f="$HOME/.predsim/env.sh" tmp map="${SITE_STACK_BY_ARCH:-*=$CASADI_MODE_DEFAULT}" pair
    local fast="${SITE_STACK_FASTEST_BY_ARCH:-$map}"
    mkdir -p "$HOME/.predsim"
    tmp="$(mktemp "$f.XXXXXX")"
    {
        echo "# PredSim stack selector, generated by PredSim_BunyaInstallation/predsim-install.sh"
        echo "# ($(date -I)). Default stack by CPU type for site $SITE: $map."
        echo "# PREDSIM_CASADI_MODE=fastest picks the faster stack per CPU type: $fast"
        echo "# (see BENCHMARKS.md). Force one: PREDSIM_CASADI_MODE=prebuilt|source,"
        echo "# or run_predsim.sh --env <stack>/env.sh"
        if declare -F site_arch >/dev/null; then declare -f site_arch; else echo 'site_arch() { echo any; }'; fi
        echo '_predsim_mode="${PREDSIM_CASADI_MODE:-}"'
        echo 'if [[ "$_predsim_mode" == fastest ]]; then'
        echo '    case "$(site_arch)" in'
        for pair in $fast; do echo "        ${pair%%=*}) _predsim_mode=${pair#*=} ;;"; done
        echo '    esac'
        echo 'elif [[ -z "$_predsim_mode" ]]; then'
        echo '    case "$(site_arch)" in'
        for pair in $map; do echo "        ${pair%%=*}) _predsim_mode=${pair#*=} ;;"; done
        echo '    esac'
        echo 'fi'
        echo 'case "$_predsim_mode" in'
        echo "    prebuilt) _predsim_env=\"$HOME/predsim-deps/$(stack_id prebuilt)/env.sh\" ;;"
        echo "    source)   _predsim_env=\"$HOME/predsim-deps/$(stack_id source)/env.sh\" ;;"
        echo '    *) echo "PredSim: no stack for PREDSIM_CASADI_MODE=$_predsim_mode (prebuilt|source|fastest)" >&2; return 1 ;;'
        echo 'esac'
        echo '[[ -f "$_predsim_env" ]] || { echo "PredSim: $_predsim_env missing; rerun the installer" >&2; return 1; }'
        echo 'unset _predsim_mode'
        echo '# shellcheck source=/dev/null'
        echo 'source "$_predsim_env"'
    } > "$tmp"
    mv -f "$tmp" "$f"    # replaces a symlink rather than writing through it
    log "activated: ~/.predsim/env.sh picks the stack by CPU type ($map; fastest: $fast)"
}

if [[ $SELECTOR_ONLY -eq 1 ]]; then
    [[ "$CASADI_MODE" == both ]] || die "--selector-only needs --casadi both (or a site whose default is both)"
    for m in prebuilt source; do
        [[ -f "$HOME/predsim-deps/$(stack_id "$m")/env.sh" ]] || die "stack $(stack_id "$m") isn't installed"
    done
    write_selector
    cat "$HOME/.predsim/env.sh"
    exit 0
fi

# CoinHSL is required unless --no-hsl. Fail here, before an hour of compiling,
# when a stack still needs it and there is no archive to build it from.
if [[ "$NO_HSL" == 1 ]]; then
    [[ -z "$HSL_ARCHIVE" ]] || die "--hsl and --no-hsl can't be used together"
else
    if [[ -z "$HSL_ARCHIVE" ]]; then
        HSL_ARCHIVE="$(compgen -G "$HOME/coinhsl-*.tar.gz" | sort -V | tail -1 || true)"
    fi
    hsl_missing=""
    if [[ "$CASADI_MODE" == both ]]; then hsl_modes="prebuilt source"; else hsl_modes="$CASADI_MODE"; fi
    for m in $hsl_modes; do
        d="${PREFIX:-$HOME/predsim-deps/$(stack_id "$m")}"
        [[ -f "$d/hsl/lib/libhsl.so" ]] || hsl_missing=1
    done
    if [[ -n "$hsl_missing" && -z "$HSL_ARCHIVE" && $LIST -eq 0 && -z "$RESTAMP" ]]; then
        die "CoinHSL source not found: expected ~/coinhsl-<version>.tar.gz, or pass --hsl ARCHIVE.
       Download it under the HSL licence (see 'Get the CoinHSL solver' in README.md):
       https://licences.stfc.ac.uk/product/coin-hsl
       To install without it and use the slower MUMPS solver, pass --no-hsl
       (on Bunya: sbatch bunya/install_predsim.slurm --no-hsl)."
    fi
fi
export HSL_ARCHIVE NO_HSL

if [[ "$CASADI_MODE" == both ]]; then
    [[ -z "$PREFIX" ]] || die "--prefix needs a single --casadi mode"
    had_env=0; [[ -e "$HOME/.predsim/env.sh" ]] && had_env=1
    for m in prebuilt source; do
        log "======== CasADi mode: $m"
        "$INSTALLER_DIR/predsim-install.sh" "${ORIG_ARGS[@]}" --site "$SITE" --casadi "$m"
    done
    [[ $LIST -eq 1 || -n "$RESTAMP" ]] && exit 0
    if [[ $ACTIVATE -eq 1 || $had_env -eq 0 ]]; then
        write_selector
    fi
    cat "$HOME/.predsim/env.sh"
    exit 0
fi

STACK_ID="$(stack_id "$CASADI_MODE")"
PREFIX="${PREFIX:-$HOME/predsim-deps/$STACK_ID}"
PREDSIM_CACHE="${PREDSIM_CACHE:-$HOME/predsim-deps/.cache}"
BUILD_ROOT="$PREFIX/build"
# OpenSim (+ its SWIG and Geometry) does not depend on the CasADi mode and takes
# ~1 h to build, so it lives in a prefix shared by all stacks of this site.
OPENSIM_PREFIX="${OPENSIM_PREFIX:-$HOME/predsim-deps/${SITE}_opensim-${OPENSIM_TAG}}"
export MUMPS_OPENMP INSTALLER_DIR SITE SITE_FILE CASADI_MODE STACK_ID PREFIX PREDSIM_DIR PREDSIM_CACHE BUILD_ROOT OPENSIM_PREFIX

# Ordered steps; a step script may define step_applies() to opt out.
STEPS=(preflight python openblas ipopt casadi hsl swig opensim geometry opensimad predsim matlab-config verify)

step_file() { echo "$INSTALLER_DIR/steps/$1.sh"; }

# Steps whose script sets STEP_SHARED=1 install into $OPENSIM_PREFIX and keep
# their done-marker there, so every CasADi mode reuses one OpenSim build.
step_shared() { ( source "$(step_file "$1")"; [[ "${STEP_SHARED:-0}" == 1 ]] ); }
step_marker() {
    if step_shared "$1"; then echo "$OPENSIM_PREFIX/.done/$1"; else echo "$PREFIX/.done/$1"; fi
}

step_hash() {
    local key="$CASADI_MODE $PREFIX"
    step_shared "$1" && key="$OPENSIM_PREFIX"
    cat "$(step_file "$1")" "$INSTALLER_DIR/versions.env" "$SITE_FILE" \
        <(echo "$key") | sha1sum | cut -c1-12
}

step_state() {
    local s="$1" marker; marker="$(step_marker "$1")"
    if ! ( source "$(step_file "$s")"; ! declare -F step_applies >/dev/null || step_applies ); then
        echo skip
    elif [[ -f "$marker" && "$(cat "$marker")" == "$(step_hash "$s")" ]]; then
        echo done
    elif [[ -f "$marker" ]]; then
        echo stale
    else
        echo todo
    fi
}

if [[ -n "$RESTAMP" ]]; then
    IFS=, read -r -a rs <<< "$RESTAMP"
    for s in "${rs[@]}"; do
        [[ "$(step_state "$s")" == stale ]] || die "$s is not 'stale' (only completed steps can be restamped)"
        step_hash "$s" > "$(step_marker "$s")"
        echo "restamped $s"
    done
    exit 0
fi

if [[ $LIST -eq 1 ]]; then
    echo "site=$SITE  casadi=$CASADI_MODE  prefix=$PREFIX"
    echo "shared opensim prefix=$OPENSIM_PREFIX"
    for s in "${STEPS[@]}"; do printf '  %-14s %s\n' "$s" "$(step_state "$s")"; done
    exit 0
fi

mkdir -p "$PREFIX/logs" "$PREFIX/.done" "$BUILD_ROOT" "$PREDSIM_CACHE" "$OPENSIM_PREFIX/.done" "$OPENSIM_PREFIX/build"
log "PredSim install: site=$SITE ($SITE_DESC)"
log "stack=$STACK_ID"
log "prefix=$PREFIX"
log "opensim prefix (shared)=$OPENSIM_PREFIX"

# env.sh must follow the HSL choice when it changes on an already installed stack.
if [[ -f "$PREFIX/env.sh" && -f "$PREFIX/hsl/lib/libhsl.so" ]]; then
    env_has_hsl=0; grep -q 'PREDSIM_HSL_LIB=' "$PREFIX/env.sh" && env_has_hsl=1
    if [[ "$env_has_hsl" == "$NO_HSL" ]]; then rm -f "$PREFIX/.done/matlab-config"; fi
fi

started=0
[[ -z "$FROM" ]] && started=1
for s in "${STEPS[@]}"; do
    [[ "$s" == "$FROM" ]] && started=1
    [[ $started -eq 1 ]] || continue
    if [[ -n "$ONLY" && ",$ONLY," != *",$s,"* ]]; then continue; fi
    [[ -f "$(step_file "$s")" ]] || die "missing step script: $(step_file "$s")"

    state="$(step_state "$s")"
    if [[ "$state" == skip ]]; then log "-- $s: not needed for this config"; continue; fi
    if [[ "$state" == done && $FORCE -eq 0 && "$s" != verify ]]; then log "-- $s: already done"; continue; fi

    if step_shared "$s" && declare -F site_can_build_shared >/dev/null && ! site_can_build_shared; then
        die "shared step '$s' ($state) can only be built on this site's portable node type; on Bunya: sbatch bunya/install_predsim.slurm (runs on epyc3)"
    fi
    log "== $s (log: $PREFIX/logs/$s.log)"
    set +e
    (
        set -euo pipefail
        site_toolchain
        export PATH="$PREFIX/python/bin:$PATH"   # pinned cmake from the venv
        # shellcheck source=/dev/null
        source "$(step_file "$s")"
        step_main
    ) > >(tee "$PREFIX/logs/$s.log") 2>&1
    rc=$?
    set -e
    wait
    [[ $rc -eq 0 ]] || die "step '$s' failed (exit $rc); see $PREFIX/logs/$s.log"
    step_hash "$s" > "$(step_marker "$s")"
done

if [[ $ACTIVATE -eq 1 ]]; then
    mkdir -p "$HOME/.predsim"
    ln -sfn "$PREFIX/env.sh" "$HOME/.predsim/env.sh"
    log "activated: ~/.predsim/env.sh -> $PREFIX/env.sh"
elif [[ ! -e "$HOME/.predsim/env.sh" && -f "$PREFIX/env.sh" ]]; then
    mkdir -p "$HOME/.predsim"
    ln -sfn "$PREFIX/env.sh" "$HOME/.predsim/env.sh"
    log "no active stack yet; activated this one"
fi
log "done. Run PredSim with: $PREDSIM_DIR/linux/run_predsim.sh --env $PREFIX/env.sh"
