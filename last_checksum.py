#!/usr/bin/env python3
import json
import sys

try:
    checksum = json.load(sys.stdin)['Labels']['build.checksum']
except Exception:
    checksum = 'N/A'

print(f'::set-env name=LAST_CHECKSUM::{checksum}')
