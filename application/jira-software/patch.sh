#!/bin/sh
set -eux
SCRIPT_DIR=$(dirname -- $0)
patch -p1 <${SCRIPT_DIR}/patch.diff
