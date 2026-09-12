import importlib.util
import json
from pathlib import Path
import tempfile
import unittest


SPEC = importlib.util.spec_from_file_location(
    "analyze_sources", Path(__file__).with_name("analyze_sources.py")
)
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class AnalyzeSourcesTest(unittest.TestCase):
    def test_stream_and_duplicate_union(self):
        with tempfile.TemporaryDirectory(dir=Path(__file__).parent) as directory:
            root = Path(directory)
            (root / "one.json").write_text(json.dumps([
                {"bookSourceUrl": "synthetic-a", "jsLib": "java.a();"},
                {"bookSourceUrl": "synthetic-a", "jsLib": "java.b();"},
                {"bookSourceUrl": "synthetic-b", "ruleContent": {"content": "@js:java.a();"}},
            ]), encoding="utf-8")
            analyzer = MODULE.AnalyzeSources(root, {"a", "b"})
            analyzer.run()
            self.assertEqual(analyzer.total, 3)
            self.assertEqual(len(analyzer.sources), 2)
            self.assertEqual(analyzer.covered({"a"}), 1)
            self.assertEqual(analyzer.covered({"a", "b"}), 2)
            self.assertIn("累计覆盖率", analyzer.report([], "2000-01-01", "fixture"))

    def test_lexical_exclusions_and_features(self):
        code = MODULE.AnalyzeSources.mask('"java.fake(); x.length()"; /* Packages.foo */ java.real(); x.length();')
        self.assertNotIn("fake", code)
        self.assertNotIn("Packages", code)
        self.assertIn("java.real", code)
        self.assertIsNone(MODULE.AnalyzeSources.features["E4X 后代运算"].search("...items; 1.2;"))

    def test_options_and_nested_javascript(self):
        analyzer = MODULE.AnalyzeSources(Path("."), {"a", "b"})
        strings = [("searchUrl", 'relative, {"method":"POST","js":"java.a();","headers":{"x":"y"}}')]
        snippets, keys = analyzer.extract(strings)
        self.assertIn("method", keys)
        self.assertNotIn("x", keys)
        self.assertTrue(any("java.a()" in item for item in snippets))

    def test_rule_interpolation_is_not_e4x(self):
        analyzer = MODULE.AnalyzeSources(Path("."), set())
        snippets, _ = analyzer.extract([("ruleContent.content", "<js>result = {{$..text}}; String(result)</js>")])
        self.assertFalse(any(MODULE.AnalyzeSources.features["E4X 后代运算"].search(item) for item in snippets))
        self.assertFalse(any(MODULE.AnalyzeSources.features["E4X XML 字面量"].search(item) for item in snippets))

    def test_loose_options_keep_only_top_level_keys(self):
        self.assertEqual(MODULE.AnalyzeSources.loose_option_keys("{method:'POST',headers:{nested:'value'},body:{{key}}}"), {"method", "headers", "body"})

    def test_nested_url_objects_are_not_options(self):
        analyzer = MODULE.AnalyzeSources(Path("."), set())
        snippets, keys = analyzer.extract([("searchUrl", 'relative, {"body":[{"x":1},{"timeout":9,"js":"java.fake();"}]}')])
        self.assertEqual(keys, {"body"})
        self.assertFalse(any("java.fake" in item for item in snippets))
        snippets, keys = analyzer.extract([("searchUrl", 'relative, {"body":{"js":"@js:java.fake();"},"js":"java.real();"}, {"timeout":9}')])
        self.assertEqual(keys, {"body", "js"})
        self.assertEqual(snippets, ["java.real();"])

    def test_javascript_object_argument_is_not_url_options(self):
        analyzer = MODULE.AnalyzeSources(Path("."), set())
        code = '@js:java.get(key, {"headers":{}}); java.put(key,result);'
        snippets, keys = analyzer.extract([("ruleContent.content", code)])
        self.assertEqual(keys, set())
        self.assertTrue(any("java.put" in item for item in snippets))

    def test_new_and_unknown_option_keys(self):
        analyzer = MODULE.AnalyzeSources(Path("."), set())
        for name in ("origin", "resolveIp", "serverID", "webViewDelayTime"):
            with self.subTest(name=name):
                self.assertIn(name, analyzer.option_names)
                _, keys = analyzer.extract([("searchUrl", 'relative, {' + json.dumps(name) + ':1}')])
                self.assertEqual(keys, {name})
        _, keys = analyzer.extract([("searchUrl", 'relative, {"custom-option":1}')])
        self.assertEqual(keys, {"custom-option"})
        analyzer.sources = {"synthetic": {"methods": set(), "rules": set(), "features": set(), "options": keys, "variables": set()}}
        self.assertIn("未知选项键", analyzer.report([], "2000-01-01", "fixture"))

    def test_public_host_vocabulary(self):
        with tempfile.TemporaryDirectory(dir=Path(__file__).parent) as directory:
            root = Path(directory)
            paths = {
                "help/JsExtensions.kt": "interface JsExtensions {\n fun ajax() {}\n private fun hidden() {}\n}",
                "help/JsEncodeUtils.kt": "interface JsEncodeUtils {\n fun encode() {}\n}",
                "model/analyzeRule/AnalyzeRule.kt": "class AnalyzeRule {\n public fun getString() {}\n fun put() {}\n internal fun internalOnly() {}\n class Nested {\n fun nestedOnly() {}\n }\n}",
                "model/analyzeRule/AnalyzeUrl.kt": "class AnalyzeUrl {\n override fun get() {}\n suspend fun request() {}\n private\n fun privateMultiline() {}\n}",
                "data/entities/BaseSource.kt": 'private object Helper {\n fun run() {}\n}\ninterface BaseSource {\n fun getLoginInfo() {}\n // fun commented() {}\n val text = "fun fake() {}"\n}',
            }
            for relative, content in paths.items():
                path = root / relative
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text(content, encoding="utf-8")
            legacy, base, expanded = MODULE.AnalyzeSources.load_vocabulary(root / "help")
            self.assertEqual(legacy, {"ajax", "hidden", "encode"})
            self.assertEqual(base, {"ajax", "encode"})
            self.assertEqual(expanded, {"ajax", "encode", "getString", "put", "get", "request", "getLoginInfo"})


if __name__ == "__main__":
    unittest.main()
