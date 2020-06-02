#!/usr/bin/env python3
import re

with open('.github/workflows/build.yml') as f:
    yaml = f.read()

repl = '\n'.join(
    '* '+', '.join(
        f'`{item}`'
        for item in m.group().split()
    )
    for m in re.finditer(r"(?<= tags: ')[^']*", yaml)
)

with open('README.md', 'r+') as f:
    readme, n = re.subn(r'(?s)(?<=# Supported tags\n\n).*?(?=\n\n#|$)', repl, f.read(), count=1)
    assert n == 1
    f.seek(0)
    f.write(readme)
    f.truncate()
