"""生成可重复的合成备份语料；仅使用 Python 标准库。"""

import io
import json
from pathlib import Path
from zipfile import ZIP_DEFLATED, ZIP_STORED, ZipFile, ZipInfo

ROOT = Path(__file__).resolve().parent
FILES = {
    "bookshelf.json": [{"bookUrl": "https://example.invalid/book/1", "name": "合成书", "author": "作者", "origin": "https://example.invalid", "durChapterIndex": 3, "readConfig": {"reverseToc": True}}],
    "bookmark.json": [{"time": 100, "bookName": "合成书", "bookAuthor": "作者", "chapterIndex": 3, "content": "标注"}],
    "bookGroup.json": [{"groupId": 1, "groupName": "合成分组"}],
    "bookSource.json": [{"bookSourceUrl": "https://example.invalid", "bookSourceName": "合成源", "ruleSearch": {"bookList": "tag.li"}}],
    "replaceRule.json": [{"id": 7, "name": "清理", "pattern": "广告", "replacement": ""}],
    "readRecord.json": [{"deviceId": "", "bookName": "合成书", "author": "作者", "readTime": 20, "lastRead": 100, "lastChapterIndex": 3}],
    "rssSources.json": [],
    "config.xml": "<map/>",
    "unknown.txt": "合成的未知文件",
}


def write_archive(name: str, files: dict, method: int, streaming: bool = False, utf8: bool = False) -> None:
    class UTF8ZipInfo(ZipInfo):
        def _encodeFilenameFlags(self):
            return self.filename.encode("utf-8"), self.flag_bits | 0x0800

    class Stream(io.BytesIO):
        def seekable(self):
            return False

        def seek(self, *args):
            raise io.UnsupportedOperation("stream")

    output = Stream() if streaming else io.BytesIO()
    with ZipFile(output, "w") as archive:
        for path, value in files.items():
            info = (UTF8ZipInfo if utf8 else ZipInfo)(path, (2024, 1, 2, 3, 4, 6))
            if utf8:
                info.create_system = 0
            info.compress_type = method
            content = value if isinstance(value, str) else json.dumps(value, ensure_ascii=False)
            archive.writestr(info, content.encode("utf-8"))
    (ROOT / name).write_bytes(output.getvalue())


if __name__ == "__main__":
    write_archive("backup2024-01-02.zip", FILES, ZIP_DEFLATED, streaming=True)
    write_archive("stored.zip", {"empty.txt": "", "中文.txt": "stored"}, ZIP_STORED)
    write_archive("traversal.zip", {"../bookshelf.json": []}, ZIP_STORED)
    write_archive("malformed-json.zip", {"bookshelf.json": "[broken", "bookmark.json": FILES["bookmark.json"]}, ZIP_DEFLATED)
    large = {"bookshelf.json": '["' + "a" * (160792 - 4) + '"]',
             "bookSource.json": '["' + "b" * (12349274 - 4) + '"]'}
    large.update({f"synthetic{index:02}.json": "[]" for index in range(20)})
    large["synthetic-directory/"] = ""
    write_archive("large-streaming.zip", large, ZIP_DEFLATED, streaming=True, utf8=True)
