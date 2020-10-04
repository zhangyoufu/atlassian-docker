#!/usr/bin/env python3
import json
import os
import sys

try:
    checksum = json.load(sys.stdin)['Labels']['build.checksum']
except Exception:
    checksum = 'N/A'

with open(os.environ['GITHUB_ENV'], 'a') as f:
    f.write(f'LAST_CHECKSUM={checksum}\n')
