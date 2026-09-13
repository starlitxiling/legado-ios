"""将本地 Mozilla PSL 转为不依赖 SwiftPM resources 的静态规则表。"""

import argparse
import hashlib
from pathlib import Path


class PublicSuffixGenerator:
    @staticmethod
    def generate(source: Path, output: Path) -> None:
        data = source.read_bytes()
        groups: dict[str, set[str]] = {"exact": set(), "wildcard": set(), "exception": set()}
        for line in data.decode("utf-8").splitlines():
            rule = line.split("//", 1)[0].strip()
            if not rule:
                continue
            group = "exact"
            if rule.startswith("!"):
                group, rule = "exception", rule[1:]
            elif rule.startswith("*."):
                group, rule = "wildcard", rule[2:]
            groups[group].add(rule.encode("idna").decode("ascii").lower())
        if not groups["exact"]:
            raise ValueError("公共后缀规则不能为空")
        lines = [
            "// Mozilla Public Suffix List，按 MPL-2.0 分发。",
            "// 许可见 ../Resources/PUBLIC_SUFFIX_LIST_LICENSE.md。",
            "// 由 tools/psl/generate_psl.py 生成，请修改源数据后重新生成。",
            f"// 源文件 SHA-256: {hashlib.sha256(data).hexdigest()}",
            "enum PublicSuffixTable {",
        ]
        for name, rules in groups.items():
            lines.append(f'    static let {name}: Set<String> = Set("""')
            lines.extend(f"    {rule}" for rule in sorted(rules))
            lines.append('    """.split(separator: "\\n").map(String.init))')
        lines.append("}")
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_text("\n".join(lines) + "\n", encoding="utf-8")


def main() -> None:
    root = Path(__file__).resolve().parents[2]
    core = root / "Packages/LegadoCore/Sources/LegadoCore"
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, default=core / "Resources/public_suffix_list.dat")
    parser.add_argument("--output", type=Path, default=core / "Network/PublicSuffixTable.swift")
    args = parser.parse_args()
    PublicSuffixGenerator.generate(args.source, args.output)


if __name__ == "__main__":
    main()
