import json
import os
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
RESULTS = Path(os.environ.get("LEGADO_REGRESSION_DIR", ROOT / ".build/round5"))
OUTPUT = ROOT / "docs/5-UI对齐与解析补全/ALL-SOURCES.md"


def read_rows(directory: Path) -> list[dict]:
    path = directory / "results.jsonl"
    if not path.exists():
        raise FileNotFoundError(f"Missing regression results: {path}. Run the source smoke batch first.")
    rows = [json.loads(line) for line in path.read_text(encoding="utf-8").splitlines() if line.strip()]
    indexes = [row["index"] for row in rows]
    if not rows or len(indexes) != len(set(indexes)):
        raise ValueError(f"Empty results or duplicate source indexes: {path}")
    if any(row["status"] not in {"pass", "fail", "timeout"} for row in rows):
        raise ValueError(f"Unknown regression status in {path}")
    return rows


def reason(row: dict, directory: Path) -> str:
    if row["status"] == "pass":
        return "通过"
    if row["status"] == "timeout":
        return "网络/进程超时"
    file = directory / f"{row['index']}.error"
    error = file.read_text(encoding="utf-8") if file.exists() else ""
    if 'missingRule("searchUrl")' in error:
        return "书源配置：没有搜索地址（可能仅供发现使用）"
    if "webView 服务不可用" in error:
        return "运行环境：CLI 没有 WebView，不能据此判定 App 失败"
    if "NSURLErrorDomain" in error or "httpStatus(" in error or "HTTP error fetching URL" in error:
        return "网络/站点：HTTP、TLS、连接或超时错误"
    if any(value in error for value in ["Unsupported Java package", "Packages.java.security", "unimplemented", "未实现"]):
        return "平台兼容：脚本依赖未映射的 Java 原生类/API"
    if any(value in error for value in ["raw().request", "variable: org", "toArray is not a function", "select is not a function", "variable: JavaImporter", "book.getVariable", "timeFormat requires"]):
        return "引擎兼容：宿主桥缺口，已加入回流修复"
    if "DecodingError" in error:
        return "解析差异：配置/响应 JSON（请求头宽松解析已回流）"
    if "unsupportedCharset" in error:
        return "书源配置：不支持的编码名称"
    if "pickOutOfBounds" in error:
        return "待核：搜索为空，关键词未命中/站点变更/规则差异尚不能区分"
    if "JavaScript" in error:
        return "待核：脚本执行失败，需对应响应与 Android 对拍"
    if "invalidXPath" in error:
        return "书源规则：无效 XPath 表达式"
    if "pathNotFound" in error or "invalidPath" in error or "nullContent" in error:
        return "待核：响应数据或选择器不匹配"
    if "emptyDownloadURLs" in error:
        return "书源结果：没有可用下载地址"
    return "待核：未取得可分类诊断"


def main() -> None:
    baseline = read_rows(RESULTS / "all-search")
    retries = {row["index"]: row for row in read_rows(RESULTS / "host-retry")}
    if retries.keys() - {row["index"] for row in baseline}:
        raise ValueError("Retry results contain source indexes absent from the baseline")
    initial = Counter(row["status"] for row in baseline)
    latest = Counter(retries.get(row["index"], row)["status"] for row in baseline)
    causes: Counter[str] = Counter()
    table = []
    for row in sorted(baseline, key=lambda value: value["index"]):
        updated = retries.get(row["index"], row)
        directory = RESULTS / ("host-retry" if row["index"] in retries else "all-search")
        cause = reason(updated, directory)
        causes[cause] += 1
        table.append(f"| {row['index']} | {row['status']} | {updated['status']} | {cause} |")
    lines = ["# 全量书源搜索记录", "", f"数据集为用户备份的 {len(baseline)} 个条目；编号为 bookSource.json 的零起始下标。只提交编号和诊断分类，不提交私有配置、凭据、响应正文。", "",
             f"首轮：{dict(initial)}。修复后针对 {len(retries)} 个受影响条目重测，合并结果：{dict(latest)}。其余条目保留首轮结果，不能称为修复后全量重跑。", "",
             "失败原因按实际错误分类；空结果和一般脚本异常无法仅凭本次 CLI 结果确定是站点失效还是解析差异，明确保留待核，不强行归因。", "",
             "| 最新诊断 | 数量 |", "| --- | --- |"]
    lines += [f"| {key} | {count} |" for key, count in causes.most_common()]
    lines += ["", "| 编号 | 首轮 | 重测后/保留 | 最新诊断 |", "| --- | --- | --- | --- |"] + table
    OUTPUT.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(json.dumps({"initial": initial, "latest": latest, "causes": causes, "retested": len(retries)}, ensure_ascii=False))


if __name__ == "__main__":
    main()
