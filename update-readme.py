#!/usr/bin/env python3
import re

with open('.github/workflows/build.yml') as f:
    yaml = f.read()

app_images = {}
for item in re.split(r'(?m)$\n(?= +-)', re.search(r'(?ms)^(?<=# DONT-CHECKSUM-BEGIN\n).*?(?=^# DONT-CHECKSUM-END\n)', yaml).group()):
    application = re.search('(?<= - application: ).*', item).group()
    tags = re.search("(?<= tags: ')[^']*", item).group().split()
    print(application, tags)
    app_images.setdefault(application, []).append(tags)

repl = '\n'.join(
    f'## {" ".join(map(str.capitalize, app.split("-")))}\n\n'+''.join(
        '* '+', '.join(
            f'`{tag}`'
            for tag in tags
        )+'\n'
        for tags in images
    )
    for app, images in app_images.items()
)

with open('README.md', 'r+') as f:
    readme, n = re.subn(r'(?s)(?<=\n# Supported tags\n\n).*?(?=\n# |$)', repl, f.read(), count=1)
    assert n == 1
    f.seek(0)
    f.write(readme)
    f.truncate()
