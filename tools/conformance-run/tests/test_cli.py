import json
from pathlib import Path
import subprocess
import tempfile
import unittest


PACKAGE = Path(__file__).resolve().parents[1]
REPOSITORY = PACKAGE.parents[1]


class ConformanceCLITests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        subprocess.run(["rtk", "proxy", "swift", "build", "--package-path", str(PACKAGE), "--disable-sandbox"], check=True)
        result = subprocess.run(["rtk", "proxy", "swift", "build", "--package-path", str(PACKAGE), "--show-bin-path"], check=True, capture_output=True, text=True)
        cls.binary = Path(result.stdout.strip()) / "conformance-run"

    def setUp(self) -> None:
        temporary = tempfile.TemporaryDirectory(prefix="conformance-cli-")
        self.addCleanup(temporary.cleanup)
        self.directory = Path(temporary.name)
        fixture = REPOSITORY / "Tests/Conformance/fixtures/synthetic/synthetic-empty.json"
        self.valid = self.directory / "valid.json"
        self.valid.write_text(json.dumps(json.loads(fixture.read_text())[:1]))

    def run_cli(self, *paths: Path) -> subprocess.CompletedProcess:
        return subprocess.run(["rtk", "proxy", str(self.binary), *map(str, paths)], capture_output=True, text=True, cwd=self.directory)

    def test_valid_case_succeeds(self) -> None:
        result = self.run_cli(self.valid)
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertIn("TOTAL 1 / 1 / 100.00%", result.stdout)

    def test_non_case_only_fails(self) -> None:
        path = self.directory / "non-case.json"
        path.write_text("{}")
        result = self.run_cli(path)
        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertIn("TOTAL 0 / 0 / N/A", result.stdout)

    def test_empty_case_array_fails(self) -> None:
        path = self.directory / "empty.json"
        path.write_text("[]")
        result = self.run_cli(path)
        self.assertNotEqual(result.returncode, 0, result.stdout)

    def test_empty_directory_fails(self) -> None:
        path = self.directory / "empty"
        path.mkdir()
        result = self.run_cli(path)
        self.assertNotEqual(result.returncode, 0, result.stdout)

    def test_explicit_invalid_file_with_valid_case_fails(self) -> None:
        path = self.directory / "invalid.json"
        path.write_text('[{"id":"broken"}]')
        result = self.run_cli(self.valid, path)
        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertIn("errors=1", result.stdout)

    def test_directory_auxiliary_fixture_is_skipped(self) -> None:
        (self.directory / "auxiliary.json").write_text("{}")
        result = self.run_cli(self.directory)
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertIn("non_case_files=1", result.stdout)

    def test_default_corpus_keeps_unsupported_failures(self) -> None:
        result = self.run_cli()
        self.assertEqual(result.returncode, 1, result.stdout)
        self.assertIn("TOTAL 134 / 142", result.stdout)
        self.assertIn("unsupported=8 errors=0", result.stdout)


def main() -> None:
    unittest.main(verbosity=2)


if __name__ == "__main__":
    main()
