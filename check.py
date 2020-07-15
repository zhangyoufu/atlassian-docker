#!/usr/bin/env python3
import json
import re
import requests
import typing

class Version(typing.NamedTuple):
    major: int
    minor: int
    patch: int
    suffix_series: int
    suffix_number: int
    string: str

    def __str__(self):
        return self.string

    def __repr__(self):
        return str(self)

    @classmethod
    def from_string(self, s):
        m = re.fullmatch(r'(\d+)\.(\d+)(?:\.(\d+))?(?:-([A-Za-z]+)(\d+))?', s)
        assert m, s
        major, minor, patch, suffix_series, suffix_number = m.groups()
        major = int(major)
        minor = int(minor)
        patch = int(patch) if patch else 0
        suffix_series = suffix_series_lut[suffix_series]
        suffix_number = int(suffix_number) if suffix_number else 0
        return Version(major, minor, patch, suffix_series, suffix_number, s)

session = requests.Session()

def query_download(channel, application, *, filter_func=None):
    rsp = session.get(f'https://my.atlassian.com/download/feeds/{channel}/{application}.json', allow_redirects=False)
    assert rsp.status_code == 200, f'{rsp.status_code} {rsp.reason}'
    body = rsp.text
    assert body.startswith('downloads(') and body.endswith(')')
    data = json.loads(body[10:-1])
    assert isinstance(data, list)
    if filter_func is not None:
        data = list(filter(filter_func, data))
    return data

def filter_general(item):
    return item['description'].endswith(f'(TAR.GZ Archive)')

def filter_jira_eap(item):
    return bool(re.fullmatch(r'Jira Software .* \(TAR.GZ Archive\)', item['description']))

def main():
    global suffix_series_lut
    matrix = []

    for application in ['jira-software', 'confluence']:
        print(f'Processing {application}')
        suffix_series_lut = {
            'jira-software': {'EAP': -2, 'RC': -1, None: 0},
            'confluence': {'m': -3, 'beta': -2, 'rc': -1, None: 0},
        }[application]
        minimum = Version.from_string({
            'jira-software': '8.9.0',
            'confluence': '7.4.0',
        }[application])

        latest = {}
        for channel in ['archived', 'current', 'eap']:
            print(f'Querying {channel} channel...')
            _application = application
            filter_func = filter_general
            if application == 'jira-software' and channel == 'eap':
                _application = 'jira' # mixing Jira Core/Software/Servicedesk
                filter_func = filter_jira_eap
            for item in query_download(channel, _application, filter_func=filter_func):
                version = item['version']
                if int(version.split('.', 1)[0]) < minimum.major:
                    continue
                print(f'Got version {version}')
                version = Version.from_string(version)
                if version < minimum:
                    continue

                latest_version, latest_item = latest.setdefault(version.major, {}).setdefault(version.minor, (version, item))
                if latest_version is version:
                    continue
                if version > latest_version:
                    latest[version.major][version.minor] = (version, item)

        for major in sorted(latest.keys(), reverse=True):
            first = True
            for minor in sorted(latest[major].keys(), reverse=True):
                _, item = latest[major][minor]
                tags = [item['version'], f'{major}.{minor}']
                if first and item['type'] == 'Binary':
                    first = False
                    tags.append(f'{major}')

                # sanity check
                assert item['zipUrl'].startswith('https://')
                assert re.fullmatch(r'[0-9a-f]{32}', item['md5'])

                matrix.append(f'''\
        - application: {application}
          version: {item['version']!r}
          url: {item['zipUrl']!r}
          md5: {item['md5']!r}
          tags: {' '.join(tags)!r}''')

    with open('.github/workflows/build.yml', 'r+') as f:
        data, n = re.subn(r'(?ms)(?<=^# DONT-CHECKSUM-BEGIN\n).*?(?=\n^# DONT-CHECKSUM-END\n)', '\n'.join(matrix), f.read(), count=1)
        assert n == 1
        f.seek(0)
        f.write(data)
        f.truncate()

if __name__ == '__main__':
    main()
