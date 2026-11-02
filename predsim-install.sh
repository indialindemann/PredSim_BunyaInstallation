#!/bin/bash
# PredSim Linux installer.
#
#   ./predsim-install.sh [options]
#
# Options:
#   --site NAME          site config in sites/NAME.env (default: auto-detect;
#                        override with PREDSIM_SITE). Known: ubuntu-local, bunya
#   --casadi MODE        prebuilt | source (default: the site's SITE_CASADI_MODE_DEFAULT,
#                        else versions.env)
#   --prefix DIR         install prefix (default ~/predsim-deps/<stack-id>)
#   --predsim-dir DIR    PredSim checkout (default ~/PredSim)
#   --hsl ARCHIVE        also install CoinHSL from ARCHIVE (the coinhsl-*.tar.gz
#                        source or CoinHSL.*-linux-gnu*.tar.gz binary you download
#                        under the HSL licence); PredSim then uses MA97, as on
#                        Windows. Adds to an existing stack.
#   --mumps-openmp       (source mode) build MUMPS with OpenMP; stack id gets
#                        -mumpsomp. Not faster for PredSim (see BENCHMARKS.md)
#   --only STEPS         comma-separated step names to run (e.g. casadi,verify)
#   --from STEP          start at STEP, then continue
#   --force              rerun steps even if already done
#   --activate           point ~/.predsim/env.sh at this stack when done
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
MUMPS_OPENMP="${MUMPS_OPENMP:-0}"
RESTAMP=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --site)        SITE="$2"; shift 2 ;;
        --casadi)      CASADI_MODE="$2"; shift 2 ;;
        --prefix)      PREFIX="$2"; shift 2 ;;
        --predsim-dir) PREDSIM_DIR="$2"; shift 2 ;;
        --hsl)         HSL_ARCHIVE="$(realpath -e "$2")" || die "--hsl: $2 not found"; shift 2 ;;
        --mumps-openmp) MUMPS_OPENMP=1; shift ;;
        --only)        ONLY="$2"; shift 2 ;;
        --from)        FROM="$2"; shift 2 ;;
        --force)       FORCE=1; shift ;;
        --activate)    ACTIVATE=1; shift ;;
        --list)        LIST=1; shift ;;
        --restamp)     RESTAMP="$2"; shift 2 ;;
        -h|--help)     sed -n '2,30p' "$0"; exit 0 ;;
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
[[ "$CASADI_MODE" == prebuilt || "$CASADI_MODE" == source ]] || die "--casadi must be prebuilt or source"

[[ "$MUMPS_OPENMP" == 1 && "$CASADI_MODE" != source ]] && die "--mumps-openmp needs --casadi source (prebuilt CasADi ships its own MUMPS)"
MUMPS_TAG=""; [[ "$MUMPS_OPENMP" == 1 ]] && MUMPS_TAG="-mumpsomp"
STACK_ID="${SITE}${SITE_VARIANT:+-$SITE_VARIANT}_casadi-${CASADI_VERSION}-${CASADI_MODE}${MUMPS_TAG}_opensim-${OPENSIM_TAG}"
PREFIX="${PREFIX:-$HOME/predsim-deps/$STACK_ID}"
PREDSIM_CACHE="${PREDSIM_CACHE:-$HOME/predsim-deps/.cache}"
BUILD_ROOT="$PREFIX/build"
# OpenSim (+ its SWIG and Geometry) does not depend on the CasADi mode and takes
# ~1 h to build, so it lives in a prefix shared by all stacks of this site.
OPENSIM_PREFIX="${OPENSIM_PREFIX:-$HOME/predsim-deps/${SITE}_opensim-${OPENSIM_TAG}}"
export HSL_ARCHIVE MUMPS_OPENMP INSTALLER_DIR SITE SITE_FILE CASADI_MODE STACK_ID PREFIX PREDSIM_DIR PREDSIM_CACHE BUILD_ROOT OPENSIM_PREFIX

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
