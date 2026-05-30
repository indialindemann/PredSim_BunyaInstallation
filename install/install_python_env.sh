#!/bin/bash
# Python virtual environment for PredSim dependencies.
# Expects: python module loaded (via predsim_install.sh).

PYVER=$(python -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}.{sys.version_info.micro}")')
VENV="$HOME/deps/python-${PYVER}"

if [ ! -d "$VENV" ]; then
    python -m venv "$VENV"
fi

source "$VENV/bin/activate"
