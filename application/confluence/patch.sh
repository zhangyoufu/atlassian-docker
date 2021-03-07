#!/bin/bash
set -eux
SCRIPT_DIR=$(dirname -- $0)

[[ ${VERSION} =~ ([0-9]+)\.([0-9]+) ]]
MAJOR_VERSION=${BASH_REMATCH[1]}
MINOR_VERSION=${BASH_REMATCH[2]}

patch --verbose --fuzz=0 --strip=1 <${SCRIPT_DIR}/patch-common.diff
if (( MAJOR_VERSION > 7 || MAJOR_VERSION == 7 && MINOR_VERSION < 12 )); then
	patch --verbose --fuzz=0 --strip=1 <${SCRIPT_DIR}/patch-pre-7.12.diff
else
	patch --verbose --fuzz=0 --strip=1 <${SCRIPT_DIR}/patch-post-7.12.diff
fi
