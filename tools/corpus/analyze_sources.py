#!/usr/bin/env python3
"""离线统计书源宿主依赖，只用标准库，不执行 JS、不联网。

以 bookSourceUrl 原值去重，同键各版本的特性取并集；空键逐条独立计数。
逐对象流式读取顶层 JSON 数组，不保存书源内容。每特性每去重键最多计一次。
规则标记扫描业务规则字符串（排除名称、说明等元数据）；XPath 的 / 前缀
仅检查 rule* 字段，排除 //域名及 URL 字段。规则标记是文本出现率，可能包含
JS 中的同形运算符。JS 从 jsLib/loginCheckJs、<js>、@js:/@webjs:、{{ }}、
URL JSON 选项 js/webJs/bodyJs 提取；额外识别未标记的 java 方法调用字符串。
每个业务字符串只解析逗号后的第一个选项对象，嵌套对象不另作选项或 JS；
未知顶层选项键单列计数。词表取五个 Kotlin 宿主类型的直接公开成员方法，
排除 private/internal/protected、嵌套类型成员和 companion 扩展函数。
屏蔽 JS 字符串、注释和可识别的正则字面量后统计直接 java.method( 调用、
特性与标识符。模板字符串内插值、动态调用、别名、eval 字符串不展开。
注入变量是标识符出现数，不做作用域或接收者类型推导。WebView JS 混合计入，
因而是保守的迁移工作量估计，并不证明这些调用在 JSC 宿主上下文执行。
覆盖分母为至少有一个直接 java 方法调用的去重源，含词表外方法；排序候选为
Kotlin 词表与观测到的直接调用名并集，词表外名须另核查契约。只有完整
依赖集合包含于前 N 个已实现方法才算覆盖。排序按源数降序，同频按方法名；
80%/95% 是此排序最短前缀，不是任意子集的全局最优最小化。
Rhino 特性是词法候选，E4X 与 length() 尤其不能据文本证明运行时类型。
示例只输出匹配结构并将非保留标识符和字面量匿名化，不输出原始上下文。
"""

import argparse
from collections import Counter
import csv
from datetime import date
import hashlib
import json
from pathlib import Path
import re


class AnalyzeSources:
    variables = "java cookie cache source book result baseUrl chapter chapters title src nextChapterUrl page key speakText speakSpeed infoMap".split()
    option_names = set("method charset headers body webView js retry type webJs bodyJs timeout followRedirects dnsIp origin resolveIp serverID webViewDelayTime".split())
    features = {
        "E4X XML 字面量": re.compile(r"(?:^|[=(:,;{]|\breturn)\s*(?:<[A-Za-z_][\w:.-]*(?:\s[^<>\n]*?)?\s*/?>|<>)(?=[\s\S]*?(?:</|/>))"),
        "E4X 属性访问": re.compile(r"\.\s*@\s*[A-Za-z_$][\w$]*"),
        "E4X 后代运算": re.compile(r"(?<=[\w$)\]])\s*(?<!\.)\.\.(?!\.)\s*(?:[A-Za-z_$][\w$]*|\*)"),
        "Packages.": re.compile(r"\bPackages\s*\.\s*[\w$]+(?:\s*\.\s*[\w$]+)*"),
        "importClass / importPackage": re.compile(r"\b(?:importClass|importPackage)\s*\("),
        "new java.lang / java.util": re.compile(r"\bnew\s+java\s*\.\s*(?:lang|util)\s*\.\s*[\w$]+"),
        ".length()": re.compile(r"(?:[A-Za-z_$][\w$]*|\))\s*\.\s*length\s*\(\s*\)"),
        "String(...)": re.compile(r"\bString\s*\("),
        "CryptoJS.": re.compile(r"\bCryptoJS\s*\.\s*[\w$]+"),
        "let": re.compile(r"\blet\s+[A-Za-z_$][\w$]*"),
        "const": re.compile(r"\bconst\s+[A-Za-z_$][\w$]*"),
    }
    calls = re.compile(r"(?<![\w$.])java\s*\.\s*([A-Za-z_$][\w$]*)\s*\(")
    lexical = re.compile(
        r"'(?:(?:\\[\s\S])|[^'\\])*'|\"(?:(?:\\[\s\S])|[^\"\\])*\"|"
        r"`(?:(?:\\[\s\S])|[^`\\])*`|//[^\n]*|/\*[\s\S]*?\*/|"
        r"(?P<prefix>(?:[=(,:;!&|?{}\[]|\breturn)\s*)"
        r"/(?=[^/*\n])(?:\\.|\[(?:\\.|[^\]\\\n])*\]|[^/\\\n])+/[dgimsuvy]*"
    )

    def __init__(self, directory, methods):
        self.directory = directory
        self.methods = methods
        self.sources = {}
        self.total = 0
        self.missing_keys = 0
        self.option_failures = 0
        self.examples = {name: [] for name in self.features}
        self.file_counts = {}
        self.vocabulary_sizes = None

    @staticmethod
    def public_methods(text, owner=None):
        lexical = re.compile(r'"""[\s\S]*?"""|"(?:\\.|[^"\\])*"|\'(?:\\.|[^\'\\])*\'|//[^\n]*|/\*[\s\S]*?\*/')
        code = lexical.sub(lambda match: re.sub(r"[^\n]", " ", match.group()), text)
        if owner:
            declaration = re.search(r"\b(?:class|interface)\s+" + re.escape(owner) + r"\b", code)
            if declaration is None:
                raise ValueError(f"缺少 Kotlin 宿主类型：{owner}")
            start = code.index("{", declaration.end())
            nesting = 1
            end = start + 1
            while nesting and end < len(code):
                nesting += (code[end] == "{") - (code[end] == "}")
                end += 1
            code = code[start:end]
        declarations = re.compile(r"(?m)^[ \t]*(?P<modifiers>(?:(?:public|private|internal|protected|override|open|final|abstract|suspend|inline|tailrec|operator|infix|external)\s+)*)fun\s+(?:<[^>]+>\s*)?(?P<name>[A-Za-z_]\w*)\s*\(")
        methods = set()
        depth = 0
        position = 0
        for match in declarations.finditer(code):
            prefix = code[position:match.start()]
            depth += prefix.count("{") - prefix.count("}")
            position = match.start()
            if depth == 1 and not set(match.group("modifiers").split()).intersection({"private", "internal", "protected"}):
                methods.add(match.group("name"))
        return methods

    @classmethod
    def load_vocabulary(cls, help_directory):
        legacy = set()
        base = set()
        for filename in ("JsExtensions.kt", "JsEncodeUtils.kt"):
            text = (help_directory / filename).read_text(encoding="utf-8")
            legacy.update(re.findall(r"\bfun\s+(?:<[^>]+>\s*)?([A-Za-z_]\w*)\s*\(", text))
            base.update(cls.public_methods(text, Path(filename).stem))
        expanded = set(base)
        for relative in ("model/analyzeRule/AnalyzeRule.kt", "model/analyzeRule/AnalyzeUrl.kt", "data/entities/BaseSource.kt"):
            expanded.update(cls.public_methods((help_directory.parent / relative).read_text(encoding="utf-8"), Path(relative).stem))
        return legacy, base, expanded

    @staticmethod
    def objects(path):
        """逐对象解码，缓冲区上界约为最大单条书源加 64 KiB。"""
        decoder = json.JSONDecoder()
        with path.open(encoding="utf-8-sig") as stream:
            buffer = ""
            eof = False

            def refill():
                nonlocal buffer, eof
                chunk = stream.read(65536)
                buffer += chunk
                eof = not chunk

            def whitespace():
                nonlocal buffer
                buffer = buffer.lstrip()
                while not buffer and not eof:
                    refill()
                    buffer = buffer.lstrip()

            whitespace()
            if not buffer.startswith("["):
                raise ValueError("语料必须是顶层 JSON 数组")
            buffer = buffer[1:]
            first = True
            while True:
                whitespace()
                if buffer.startswith("]"):
                    buffer = buffer[1:]
                    whitespace()
                    if buffer:
                        raise ValueError("JSON 数组后有多余内容")
                    return
                if not first:
                    if not buffer.startswith(","):
                        raise ValueError("JSON 数组元素之间缺少逗号")
                    buffer = buffer[1:]
                    whitespace()
                while True:
                    try:
                        obj, end = decoder.raw_decode(buffer)
                        break
                    except json.JSONDecodeError:
                        if eof:
                            raise ValueError("语料 JSON 无法解码") from None
                        refill()
                if not isinstance(obj, dict):
                    raise ValueError("书源数组元素必须为对象")
                yield obj
                buffer = buffer[end:]
                first = False

    @classmethod
    def mask(cls, text):
        def blank(match):
            prefix = match.group("prefix") or ""
            return prefix + re.sub(r"[^\n]", " ", match.group()[len(prefix):])
        return cls.lexical.sub(blank, text)

    @classmethod
    def strings(cls, obj, path=""):
        if isinstance(obj, str):
            yield path, obj
        elif isinstance(obj, dict):
            for key, value in obj.items():
                yield from cls.strings(value, f"{path}.{key}" if path else key)
        elif isinstance(obj, list):
            for value in obj:
                yield from cls.strings(value, path)

    def extract(self, strings):
        snippets = []
        keys = set()
        decoder = json.JSONDecoder()
        for path, value in strings:
            if path.split(".")[0] in {"searchUrl", "exploreUrl", "loginUrl", "ruleSearch", "ruleExplore", "ruleBookInfo", "ruleToc", "ruleContent"}:
                boundary = self.option_boundary(value)
                if boundary is not None:
                    start, end = boundary
                    option_text = value[end:]
                    value = value[:start]
                    try:
                        options, _ = decoder.raw_decode(option_text)
                    except json.JSONDecodeError:
                        self.option_failures += 1
                        keys.update(self.loose_option_keys(option_text))
                    else:
                        if isinstance(options, dict):
                            keys.update(options)
                            snippets.extend(options[key] for key in ("js", "webJs", "bodyJs") if isinstance(options.get(key), str))
            if path.split(".")[-1] in {"jsLib", "loginCheckJs", "js", "webJs", "bodyJs"}:
                snippets.append(value)
            snippets.extend(re.findall(r"<js>([\s\S]*?)(?:</js>|$)", value, re.I))
            snippets.extend(re.findall(r"@(?:web)?js:([\s\S]*)", value, re.I))
            snippets.extend(re.findall(r"\{\{([\s\S]*?)\}\}", value))
            if self.calls.search(value) and not re.search(r"<js>|@(?:web)?js:|\{\{", value, re.I) and path.split(".")[-1] not in {"jsLib", "loginCheckJs"}:
                snippets.append(value)
        cleaned = []
        for snippet in snippets:
            if re.match(r"\s*(?:\$\.|@(?:json|css|xpath):)", snippet, re.I):
                continue
            snippet = re.sub(r"\{\{[\s\S]*?\}\}", " ", snippet)
            snippet = re.sub(r"</?js>", " ", snippet, flags=re.I)
            cleaned.append(snippet)
        return cleaned, keys

    @staticmethod
    def option_boundary(value):
        tokens = re.finditer(r'''"(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*'|`(?:\\.|[^`\\])*`|[(){}\[\],]''', value)
        depth = 0
        for token in tokens:
            text = token.group()
            if text in {"(", "{", "["}:
                depth += 1
            elif text in {")", "}", "]"}:
                depth = max(0, depth - 1)
            elif text == "," and depth == 0:
                suffix = re.match(r"\s*(?=\{)", value[token.end():])
                if suffix:
                    return token.start(), token.end() + suffix.end()
        return None

    @staticmethod
    def loose_option_keys(value):
        """对非严格 JSON 只做括号与引号感知的顶层键扫描，不求值。"""
        tokens = re.finditer(r'''"(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*'|[A-Za-z_][A-Za-z_0-9]*|[{}\[\]:]''', value)
        depth = 0
        candidate = None
        keys = set()
        for match in tokens:
            token = match.group()
            if token in {"{", "["}:
                depth += 1
                candidate = None
            elif token in {"}", "]"}:
                depth -= 1
                candidate = None
                if depth == 0:
                    break
            elif depth == 1 and token == ":":
                if candidate:
                    keys.add(candidate)
                candidate = None
            elif depth == 1:
                candidate = token.strip("\"'")
        return keys

    @staticmethod
    def rule_modes(strings):
        modes = set()
        literals = ["@css:", "@json:", "<js>", "@js:", "@webjs:", "##", "&&", "||", "%%", "@get", "@put"]
        for path, value in strings:
            for token in literals:
                if token.lower() in value.lower():
                    modes.add(token)
            if "{{" in value and "}}" in value:
                modes.add("{{ }}")
            if "@xpath:" in value.lower() or (path.startswith("rule") and re.match(r"\s*/(?:/)?(?:[a-zA-Z_*]|\[)", value) and not re.match(r"\s*//[^/\s]+\.[a-zA-Z]{2,}(?:/|$)", value)):
                modes.add("XPath")
            if "@json:" in value.lower() or re.match(r"\s*\$\.", value):
                modes.add("JSONPath")
        return modes

    @staticmethod
    def anonymous(fragment):
        safe = {"Packages", "java", "lang", "util", "new", "length", "String", "CryptoJS", "let", "const", "importClass", "importPackage", "return"}
        fragment = re.sub(r"[A-Za-z_$][\w$]*", lambda m: m.group() if m.group() in safe else "x", fragment)
        fragment = re.sub(r"[^\x20-\x7e]", " ", fragment)
        return re.sub(r"\s+", " ", fragment).strip()[:100].replace("|", "&#124;").replace("`", "'")

    def run(self):
        allowed = {"jsLib", "loginUrl", "loginCheckJs", "header", "searchUrl", "exploreUrl", "ruleSearch", "ruleExplore", "ruleBookInfo", "ruleToc", "ruleContent"}
        for path in sorted(self.directory.glob("*.json")):
            count = 0
            for obj in self.objects(path):
                self.total += 1
                count += 1
                key = obj.get("bookSourceUrl")
                if not isinstance(key, str) or not key:
                    self.missing_keys += 1
                    identity = f"missing:{self.total}"
                else:
                    identity = hashlib.sha256(key.encode()).hexdigest()
                record = self.sources.setdefault(identity, {name: set() for name in ("methods", "rules", "features", "options", "variables")})
                strings = list(self.strings({key: value for key, value in obj.items() if key in allowed}))
                snippets, keys = self.extract(strings)
                record["rules"].update(self.rule_modes(strings))
                record["options"].update(keys)
                for snippet in set(snippets):
                    code = self.mask(snippet)
                    record["methods"].update(self.calls.findall(code))
                    record["variables"].update(set(re.findall(r"[A-Za-z_$][\w$]*", code)).intersection(self.variables))
                    for name, pattern in self.features.items():
                        match = pattern.search(code)
                        if match:
                            record["features"].add(name)
                            if len(self.examples[name]) < 2 and identity not in {item[0] for item in self.examples[name]}:
                                self.examples[name].append((identity, self.anonymous(match.group())))
                if any(name.startswith("E4X") for name in record["features"]):
                    record["features"].add("E4X 合计")
            self.file_counts[path.name] = count

    def counts(self, category):
        return Counter(item for record in self.sources.values() for item in record[category])

    def covered(self, implemented):
        return sum(bool(record["methods"]) and record["methods"] <= implemented for record in self.sources.values())

    def report(self, manifest, day, kotlin_revision):
        total = len(self.sources)
        denominator = sum(bool(record["methods"]) for record in self.sources.values())
        pct = lambda n, d=total: f"{100 * n / d:.2f}%" if d else "0.00%"
        rows = ["# JS 宿主 API 实现优先级", "", f"统计日期：{day}。只读离线静态分析，未执行书源 JS，未请求网络。", "", "## 语料来源", "", "| GitHub 仓库 | 仓库内路径 | commit SHA | 下载时间 UTC | 条数 |", "| --- | --- | --- | --- | ---: |"]
        for filename, repo, path, sha, downloaded, _ in manifest:
            rows.append(f"| {repo} | {path} | {sha} | {downloaded} | {self.file_counts.get(filename, 0)} |")
        rows += ["", "## 统计口径与总量", "", f"原始书源 {self.total} 条，按 bookSourceUrl 去重 {total} 个；空键 {self.missing_keys} 条。相同键各版本特性取并集。", f"直接调用 java 方法的源为 {denominator} 个（{pct(denominator)}）；Kotlin 方法词表 {len(self.methods)} 个唯一名。", f"Kotlin 主 checkout HEAD：`{kotlin_revision}`。词表来自 JsExtensions.kt、JsEncodeUtils.kt、AnalyzeRule.kt、AnalyzeUrl.kt 与 BaseSource.kt 的直接公开成员方法；排除 private/internal/protected、嵌套类型成员及 companion 扩展函数，不把内部 UrlOption 的方法当成 java 对象成员。", "", "下表以使用该特性的去重源数计数；规则标记为字符串出现率；JS 指标屏蔽字符串、注释及可识别正则。详情见 tools/corpus/README.md。", "覆盖率分母仅为使用 java 方法的源，必须完整覆盖该源全部直接方法调用；词表外调用仍阻止覆盖。注入变量未区分局部同名变量。", "同源多版本取并集比任选一个版本更保守；语料包含历史、失效或停用源，没有可用性权重，不代表全部生态。", "", "## 规则模式使用率", "", "| 规则模式 | 书源数 | 使用率 |", "| --- | ---: | ---: |"]
        if self.vocabulary_sizes:
            legacy, base = self.vocabulary_sizes
            rows.insert(rows.index("## 规则模式使用率"), f"词表由原两文件原始 {legacy} 名扩为五文件公开成员 {len(self.methods)} 名；原两文件筛选公开成员后为 {base} 名，新增三文件贡献 {len(self.methods) - base} 个唯一名。\n")
        counts = self.counts("rules")
        for name in ["@css:", "XPath", "JSONPath", "<js>", "@js:", "@webjs:", "{{ }}", "##", "&&", "||", "%%", "@get", "@put"]:
            rows.append(f"| {name.replace('|', '&#124;')} | {counts[name]} | {pct(counts[name])} |")
        rows += ["", "## java 方法优先级", "", "累计覆盖率是频率降序前缀的完整依赖覆盖率，同频按方法名排序。最小集合指该固定顺序的最短前缀，未求任意子集的全局最优解。", "", "| 顺位 | 方法 | 书源数 | 使用率 | 累计完整覆盖源数 | 累计覆盖率 |", "| ---: | --- | ---: | ---: | ---: | ---: |"]
        counts = self.counts("methods")
        ordered = sorted(self.methods | set(counts), key=lambda name: (-counts[name], name))
        implemented = set()
        thresholds = {}
        for index, name in enumerate(ordered, 1):
            implemented.add(name)
            covered = self.covered(implemented)
            label = name if name in self.methods else name + "（词表外）"
            rows.append(f"| {index} | {label} | {counts[name]} | {pct(counts[name])} | {covered} | {pct(covered, denominator)} |")
            for target in (80, 95):
                if denominator and covered * 100 >= denominator * target and target not in thresholds:
                    thresholds[target] = (index, covered)
        unknown = sorted(set(counts) - self.methods)
        rows += ["", "词表外直接调用（同时进入排序候选与覆盖分母；只报告 API 标识符，不能视作已经核实的 Android 契约）：", "", "| 方法名 | 书源数 |", "| --- | ---: |"]
        rows += [f"| {name} | {counts[name]} |" for name in unknown] or ["| 无 | 0 |"]
        rows.append(f"\n仅实现入口 Kotlin 词表的最高覆盖为 {self.covered(self.methods)} / {denominator}（{pct(self.covered(self.methods), denominator)}）；分级建议纳入词表外候选，以避免遗漏这些依赖。")
        rows += ["", "## Rhino 特性与相关 JavaScript 写法", "", "示例截取词法命中的最小结构，非保留标识符统一替换为 x；两例来自不同去重源，因此可能相同。无命中时不伪造例子。", "", "| 特性 | 书源数 | 使用率 | 脱敏片段 1 | 脱敏片段 2 |", "| --- | ---: | ---: | --- | --- |"]
        counts = self.counts("features")
        for name in self.features:
            examples = [f"`{item[1]}`" for item in self.examples[name]]
            examples += ["无可用命中"] * (2 - len(examples))
            rows.append(f"| {name} | {counts[name]} | {pct(counts[name])} | {' | '.join(examples)} |")
        rows += ["", "## URL 选项键", "", f"每个业务字符串只解析逗号后第一个选项对象的顶层键；body、headers 等嵌套对象不展开，JS 只取顶层 js/webJs/bodyJs。非严格 JSON 选项片段 {self.option_failures} 个（未去重）退回引号与括号感知的顶层键扫描，其 JS 值不解码。", "", "| 选项键 | 书源数 | 使用率 |", "| --- | ---: | ---: |"]
        counts = self.counts("options")
        for name in sorted(self.option_names, key=lambda name: (-counts[name], name)):
            label = name
            rows.append(f"| {label} | {counts[name]} | {pct(counts[name])} |")
        rows += ["", "### 未知选项键", "", "未知键按键分别统计；标签使用哈希脱敏，使用率仍以去重源总数为分母。", "", "| 未知选项键 | 书源数 | 使用率 |", "| --- | ---: | ---: |"]
        unknown_options = sorted(set(counts) - self.option_names, key=lambda name: (-counts[name], name))
        for name in unknown_options:
            label = hashlib.sha256(name.encode()).hexdigest()[:8]
            rows.append(f"| 未知选项键-{label} | {counts[name]} | {pct(counts[name])} |")
        if not unknown_options:
            rows.append("| 无 | 0 | 0.00% |")
        rows += ["", "## 注入变量使用率", "", "| 变量 | 书源数 | 使用率 |", "| --- | ---: | ---: |"]
        counts = self.counts("variables")
        for name in sorted(self.variables, key=lambda name: (-counts[name], name)):
            rows.append(f"| {name} | {counts[name]} | {pct(counts[name])} |")
        rows += ["", "## Rhino 特有语义的实际使用率", "", "这里的实际使用率是语料静态候选率，不是运行时实证；String 包装、CryptoJS、let、const 本身不是 Rhino 专有特性。"]
        counts = self.counts("features")
        for name in ("E4X 合计", "Packages.", ".length()"):
            decision = "可在首版暂不支持，但零命中不能证明生态内不存在。" if not counts[name] else "不能以未使用为由省略；若首版不支持，必须明确排除这些候选源并进行后续兼容验证。"
            rows.append(f"- {name}：{counts[name]} / {total}（{pct(counts[name])}）。{decision}")
        rows += ["", "E4X 检测 XML 字面量、属性访问和后代运算的并集；未进行完整语法解析。length() 可能是 Java 字符串、其他 Java 对象或自定义 JS 方法，静态分析不能确定；不应将全部命中直接改成 length 属性。", "", "## 分级实现建议", ""]
        previous = 0
        for target, label in ((80, "一级"), (95, "二级")):
            if target in thresholds:
                index, covered = thresholds[target]
                names = ", ".join(ordered[previous:index])
                rows.append(f"- {label}：新增 {index - previous} 个方法，累计 {index} 个，覆盖 {covered} / {denominator}（{pct(covered, denominator)}）。方法：{names}。")
                previous = index
            else:
                rows.append(f"- {label}：当前词表无法达到 {target}% 覆盖率，需先查明词表外依赖。")
        rows.append(f"- 三级：其余 {len(ordered) - previous} 个候选方法：{', '.join(ordered[previous:])}。三个级别共含 {len(unknown)} 个词表外调用名，须核查接口归属；零频方法按后续兼容需求评估，公开成员存在不代表所有 JS 上下文均可用。")
        rows += ["", "建议优先落地一级方法的同步返回值与对象桥接契约，再增加二级；Packages / Java 类型桥接和 length() 语义应独立评估，方法频率覆盖不能替代它们。", ""]
        return "\n".join(rows)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("directory", type=Path)
    parser.add_argument("--kotlin-dir", type=Path, default=Path("/Users/wujie/Work/legado-ios/app/src/main/java/io/legado/app/help"))
    parser.add_argument("--kotlin-revision", default="未指定；未验证")
    parser.add_argument("--date", default=date.today().isoformat())
    args = parser.parse_args()
    legacy, base, methods = AnalyzeSources.load_vocabulary(args.kotlin_dir)
    with (args.directory / "manifest.tsv").open(encoding="utf-8") as stream:
        manifest = list(csv.reader(stream, delimiter="\t"))
    analyzer = AnalyzeSources(args.directory, methods)
    analyzer.vocabulary_sizes = (len(legacy), len(base))
    analyzer.run()
    print(analyzer.report(manifest, args.date, args.kotlin_revision))


if __name__ == "__main__":
    main()
