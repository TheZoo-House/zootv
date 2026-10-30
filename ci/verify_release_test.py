import plistlib
import tempfile
import unittest
from pathlib import Path

from verify_release import verify


class ReleaseBundleTest(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.app = Path(self.directory.name) / 'ZooTV.app'
        self.shelf = self.app / 'PlugIns' / 'ZooTVTopShelf.appex'
        for path, identifier in [(self.app, 'house.thezoo.ZooTV'),
                                 (self.shelf, 'house.thezoo.ZooTV.TopShelf')]:
            path.mkdir(parents=True, exist_ok=True)
            self.write(path, CFBundleIdentifier=identifier, CFBundleShortVersionString='0.1.0',
                       CFBundleVersion='4', CFBundleSupportedPlatforms=['AppleTVOS'],
                       ZooTVServerURL='https://tv.example.test',
                       TVTopShelfImage={'TVTopShelfPrimaryImageWide': 'TopShelfWide'},
                       ITSAppUsesNonExemptEncryption=False)

    def write(self, path, **changes):
        plist = path / 'Info.plist'
        info = plistlib.loads(plist.read_bytes()) if plist.exists() else {}
        plist.write_bytes(plistlib.dumps(info | changes))

    def test_accepts_matching_device_app_and_extension(self):
        verify(self.app, '0.1.0', '4')

    def test_rejects_missing_extension(self):
        (self.shelf / 'Info.plist').unlink()
        self.shelf.rmdir()
        with self.assertRaisesRegex(ValueError, 'app and Top Shelf'):
            verify(self.app, '0.1.0', '4')

    def test_rejects_stale_extension_version(self):
        self.write(self.shelf, CFBundleVersion='1')
        with self.assertRaisesRegex(ValueError, 'expected 0.1.0'):
            verify(self.app, '0.1.0', '4')

    def test_rejects_simulator_artifact(self):
        self.write(self.app, CFBundleSupportedPlatforms=['AppleTVSimulator'])
        with self.assertRaisesRegex(ValueError, 'physical tvOS'):
            verify(self.app, '0.1.0', '4')

    def test_rejects_wrong_extension(self):
        self.write(self.shelf, CFBundleIdentifier='house.thezoo.other')
        with self.assertRaisesRegex(ValueError, 'app and Top Shelf'):
            verify(self.app, '0.1.0', '4')

    def test_rejects_missing_compliance(self):
        plist = self.app / 'Info.plist'
        info = plistlib.loads(plist.read_bytes())
        del info['ITSAppUsesNonExemptEncryption']
        plist.write_bytes(plistlib.dumps(info))
        with self.assertRaisesRegex(ValueError, 'encryption'):
            verify(self.app, '0.1.0', '4')

    def test_rejects_missing_server_configuration(self):
        self.write(self.app, ZooTVServerURL='')
        with self.assertRaisesRegex(ValueError, 'server configuration'):
            verify(self.app, '0.1.0', '4')

    def test_rejects_different_extension_server(self):
        self.write(self.shelf, ZooTVServerURL='https://other.example.test')
        with self.assertRaisesRegex(ValueError, 'different TV server'):
            verify(self.app, '0.1.0', '4')

    def test_rejects_missing_wide_top_shelf_image(self):
        self.write(self.app, TVTopShelfImage={})
        with self.assertRaisesRegex(ValueError, 'wide Top Shelf'):
            verify(self.app, '0.1.0', '4')
