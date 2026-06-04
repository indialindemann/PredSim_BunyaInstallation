#!/bin/bash

[[ -f /etc/hostname ]] || { echo "ERROR: /etc/hostname not found"; return 1 2>/dev/null || exit 1; }
host="$(tr -d '[:space:]' < /etc/hostname)"
if [[ "$host" == bun* ]]; then
    export PREDsim_SYSTEM="bunya_hpc"
else         # assume its one of the home ubuntu servers
    export PREDsim_SYSTEM="linux"
fi
