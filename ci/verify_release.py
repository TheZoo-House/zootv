"""Verify the app and its embedded extension before publication."""

import plistlib
import sys
from pathlib import Path
from urllib.parse import urlsplit


def verify(app, version, build):
    bundles = [app, *sorted((app / 'PlugIns').glob('*.appex'))]
    expected = {'house.thezoo.ZooTV', 'house.thezoo.ZooTV.TopShelf'}
    found = set()
    servers = set()
    for bundle in bundles:
        with (bundle / 'Info.plist').open('rb') as source:
            info = plistlib.load(source)
        identifier = info['CFBundleIdentifier']
        if identifier in found:
            raise ValueError(f'Duplicate bundle: {identifier}')
        found.add(identifier)
        server = info.get('ZooTVServerURL', '')
        url = urlsplit(server)
        if url.scheme != 'https' or not url.hostname or url.username or url.password or url.query or url.fragment:
            raise ValueError('Missing or invalid TV server configuration')
        servers.add(server)
        if (info['CFBundleShortVersionString'], info['CFBundleVersion']) != (version, build):
            raise ValueError(f'{bundle}: expected {version} ({build})')
        if info.get('CFBundleSupportedPlatforms') != ['AppleTVOS']:
            raise ValueError(f'{bundle}: expected a physical tvOS build')
    if found != expected:
        raise ValueError(f'Expected app and Top Shelf: {expected}, found {found}')
    if len(servers) != 1:
        raise ValueError('App and Top Shelf use different TV server configurations')
    with (app / 'Info.plist').open('rb') as source:
        info = plistlib.load(source)
        if info.get('ITSAppUsesNonExemptEncryption') is not False:
            raise ValueError('Missing encryption compliance declaration')
        if not info.get('TVTopShelfImage', {}).get('TVTopShelfPrimaryImageWide'):
            raise ValueError('Missing required wide Top Shelf image')


if __name__ == '__main__':
    if len(sys.argv) != 4:
        sys.exit('usage: verify_release.py APP VERSION BUILD')
    verify(Path(sys.argv[1]), sys.argv[2], sys.argv[3])
