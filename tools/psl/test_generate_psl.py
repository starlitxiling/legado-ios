import tempfile
import unittest
from pathlib import Path

from generate_psl import PublicSuffixGenerator


class PublicSuffixGeneratorTests(unittest.TestCase):
    def test_generate_local_fixture(self):
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / "list.dat"
            output = Path(directory) / "Table.swift"
            source.write_text("// fixture\ncom\n*.ck\n!www.ck\n公司.cn\n", encoding="utf-8")
            PublicSuffixGenerator.generate(source, output)
            text = output.read_text(encoding="utf-8")
            self.assertIn("static let exact", text)
            self.assertIn("static let wildcard", text)
            self.assertIn("static let exception", text)
            self.assertIn("xn--55qx5d.cn", text)
            self.assertIn("www.ck", text)
            self.assertNotIn("*.ck", text)
            PublicSuffixGenerator.generate(source, output)
            self.assertEqual(output.read_text(encoding="utf-8"), text)


if __name__ == "__main__":
    unittest.main()
