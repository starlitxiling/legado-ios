from pathlib import Path
import struct
import zlib
import zipfile
import warnings

ROOT = Path(__file__).resolve().parents[2]
OUTPUT = ROOT / "Tests" / "Fixtures" / "localbook"


def section(kind: int, payload: bytes, flag: int = 0) -> bytes:
    return b"#" + struct.pack("<HBB", kind, flag, len(payload) + 5) + payload


def extra(check: int, payload: bytes) -> bytes:
    return b"$" + struct.pack("<II", check, len(payload) + 9) + payload


def umd() -> bytes:
    titles = ["Opening", "Ending"]
    contents = ["First paragraph\u2029Second paragraph", "The final page."]
    bodies = [text.encode("utf-16le") for text in contents]
    body = b"".join(bodies)
    output = struct.pack("<I", 0xDE9A9B89) + section(1, b"\x01\x00\x00")
    for kind, text in [(2, "Synthetic UMD"), (3, "Fixture Author"), (7, "Fiction")]:
        output += section(kind, text.encode("utf-16le"))
    output += section(11, struct.pack("<I", len(body)))
    output += section(131, struct.pack("<I", 17)) + extra(17, struct.pack("<II", 0, len(bodies[0])))
    output += section(132, struct.pack("<I", 23), 1)
    output += extra(23, b"".join(bytes([len(t.encode("utf-16le"))]) + t.encode("utf-16le") for t in titles))
    # Split through a UTF-16 code unit to exercise chunk concatenation.
    output += extra(24, zlib.compress(body[:31])) + section(241, bytes(16))
    output += extra(25, zlib.compress(body[31:]))
    output += section(130, b"\x01" + struct.pack("<I", 29)) + extra(29, b"fixture-cover")
    return output + section(12, struct.pack("<I", len(output) + 9))


def text_encodings() -> None:
    japanese = "これは日本語の物語です。東京の学校で友達と一緒に本を読みます。新しい世界へ旅に出かけましょう。"
    samples = {
        "shift-jis": ("shift_jis", japanese),
        "euc-jp": ("euc_jp", japanese),
        "euc-kr": ("euc_kr", "이것은 한국어로 작성된 이야기입니다. 오늘 우리는 도서관에서 책을 읽고 새로운 세상을 여행합니다."),
        "windows-1251": ("cp1251", "Это история о путешествии. Сегодня мы читаем новую книгу и говорим о мире, дружбе и жизни."),
        "windows-1252": ("cp1252", "“Bonjour”, dit l’auteur. Cette histoire française présente un garçon qui découvre le monde avec ses amis."),
        "latin1": ("latin1", "Cette histoire française présente un garçon qui découvre le monde avec ses amis. Voilà une journée très agréable."),
        "gbk": ("gbk", "这是一个有关读书和旅行的故事。我们今天在学校里面学习新的知识，了解世界和生活。"),
        "utf16": ("utf-16", "这是一个有关读书和旅行的故事。我们今天在学校里面学习新的知识，了解世界和生活。"),
    }
    for name, (encoding, text) in samples.items():
        (OUTPUT / (name + ".txt")).write_bytes((text * 5).encode(encoding))
        (OUTPUT / (name + ".expected")).write_text(text * 5, encoding="utf-8")


def main() -> None:
    OUTPUT.mkdir(parents=True, exist_ok=True)
    (OUTPUT / "synthetic.umd").write_bytes(umd())
    text_encodings()
    with zipfile.ZipFile(OUTPUT / "two-books.zip", "w") as archive:
        for name in ["First.txt", "nested/Second.txt"]:
            archive.writestr(zipfile.ZipInfo(name), "The final page of " + name)
        archive.writestr(zipfile.ZipInfo("notes.json"), "{}")
    with zipfile.ZipFile(OUTPUT / "traversal.zip", "w") as archive:
        archive.writestr(zipfile.ZipInfo("../escape.txt"), "Invalid")
    with warnings.catch_warnings():
        warnings.simplefilter("ignore", UserWarning)
        with zipfile.ZipFile(OUTPUT / "duplicate.zip", "w") as archive:
            archive.writestr(zipfile.ZipInfo("same.txt"), "First")
            archive.writestr(zipfile.ZipInfo("same.txt"), "Second")
    with zipfile.ZipFile(OUTPUT / "symlink.zip", "w") as archive:
        entry = zipfile.ZipInfo("link.txt")
        entry.create_system = 3
        entry.external_attr = 0o120777 << 16
        archive.writestr(entry, "../outside.txt")


if __name__ == "__main__":
    main()
