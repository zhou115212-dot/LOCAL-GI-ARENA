"""Small negative and positive packaging checks; no game or server required."""
from pathlib import Path
import tempfile
import unittest
import zipfile
from build import class_owners, digest, overlay, PATCH, report_tests, verified_gradle


class PackagingTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.private = self.root / 'input.jar'
        self.out = self.root / 'output.jar'
        self.owners = sorted(class_owners(PATCH))

    def write_fixture(self, skip_first=False, invalid=False, reverse=False):
        names = [p+'.class' for p in self.owners[1 if skip_first else 0:]]
        names += [self.owners[-1]+'$Inner.class', 'keys/test.pem', 'assets/table.json',
                  'other/Unreviewed.class', self.owners[0]+'Different.class']
        with zipfile.ZipFile(self.private, 'w') as z:
            for name in reversed(names) if reverse else names:
                z.writestr(name, b'bad' if invalid else b'\xca\xfe\xba\xbe'+name.encode())

    def test_patch_line_endings_and_tamper(self):
        alt = self.root / 'combat.patch'
        alt.write_bytes(PATCH.read_bytes().replace(b'\r\n', b'\n').replace(b'\n', b'\r\n'))
        self.assertEqual(class_owners(alt), set(self.owners))
        with alt.open('ab') as f:
            f.write(b'changed')
        with self.assertRaises(ValueError):
            class_owners(alt)

    def test_exact_allowlist_and_determinism(self):
        self.write_fixture()
        self.assertEqual(overlay(self.private, self.out), 34)
        with zipfile.ZipFile(self.out) as z:
            self.assertEqual(set(z.namelist()), {p+'.class' for p in self.owners} |
                             {self.owners[-1]+'$Inner.class'})
        second = self.root / 'second.jar'
        self.write_fixture(reverse=True)
        overlay(self.private, second)
        self.assertEqual(digest(self.out), digest(second))

    def test_missing_patch_fails(self):
        self.write_fixture(skip_first=True)
        with self.assertRaises(ValueError):
            overlay(self.private, self.out)

        self.assertFalse(self.out.exists())

    def test_invalid_binary_fails(self):
        self.write_fixture(invalid=True)
        with self.assertRaises(ValueError):
            overlay(self.private, self.out)

        self.assertFalse(self.out.exists())

    def test_refuses_overwrite(self):
        self.write_fixture()
        self.out.write_bytes(b'old')
        with self.assertRaises(FileExistsError):
            overlay(self.private, self.out)
        self.assertEqual(self.out.read_bytes(), b'old')

    def test_bad_gradle_checksum_fails_before_extraction(self):
        self.write_fixture()
        dest = self.root / 'tools'
        with self.assertRaises(ValueError):
            verified_gradle(self.private, dest)
        self.assertFalse(dest.exists())

    def test_empty_skipped_and_failing_suites_rejected(self):
        with self.assertRaises(ValueError):
            report_tests(self.root)
        xml = self.root / 'TEST-x.xml'
        for results in ('tests="1" failures="1"', 'tests="1" skipped="1"', 'tests="1" errors="1"'):
            xml.write_text('<testsuite '+results+'/>', encoding='utf8')
            with self.assertRaises(ValueError):
                report_tests(self.root)
        xml.write_text('<testsuite tests="3"/>', encoding='utf8')
        self.assertEqual(report_tests(self.root)['tests'], 3)


if __name__ == '__main__':
    unittest.main()
