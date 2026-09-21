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


def png(red: int, green: int, blue: int) -> bytes:
    def chunk(kind: bytes, payload: bytes) -> bytes:
        return struct.pack(">I", len(payload)) + kind + payload + struct.pack(">I", zlib.crc32(kind + payload))
    rows = (b"\x00" + bytes([red, green, blue]) * 64) * 64
    return b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", 64, 64, 8, 2, 0, 0, 0)) + chunk(b"IDAT", zlib.compress(rows)) + chunk(b"IEND", b"")


def epub_navigation() -> None:
    files = {
        "mimetype": "application/epub+zip",
        "META-INF/container.xml": '<container><rootfiles><rootfile full-path="OPS/book.opf"/></rootfiles></container>',
        "OPS/book.opf": '<package><metadata><title>Illustrated Book</title><creator>Fixture Writer</creator><meta name="cover" content="cover"/></metadata><manifest><item id="nav" href="nav.xhtml" properties="nav"/><item id="cover" href="images/cover.png"/><item id="front" href="titlepage.xhtml"/><item id="a" href="a.xhtml"/><item id="b" href="b.xhtml"/></manifest><spine toc="ncx"><itemref idref="front"/><itemref idref="a"/><itemref idref="b"/></spine></package>',
        "OPS/nav.xhtml": '<html xmlns:epub="http://www.idpf.org/2007/ops"><body><nav epub:type="toc"><ol><li><span>Part</span><ol><li><a href="a.xhtml#one">One</a><ol><li><a href="a.xhtml#one">Alias</a></li></ol></li><li><a href="a.xhtml#two">Two</a></li></ol></li><li><a href="b.xhtml">Last</a></li></ol></nav></body></html>',
        "OPS/titlepage.xhtml": '<html><body>Cover placeholder</body></html>',
        "OPS/a.xhtml": '<html><body><script>script-hidden</script><style>style-hidden</style><h1 id="one">One</h1><p>First body</p><svg xmlns:xlink="http://www.w3.org/1999/xlink"><image xlink:href="images/picture.png"/></svg><h1 id="two">Two</h1><p>Second body</p></body></html>',
        "OPS/b.xhtml": '<html><body><h1>Last</h1><img src="images/picture.png"/><p>Final page</p></body></html>',
        "OPS/images/cover.png": png(40, 120, 200),
        "OPS/images/picture.png": png(200, 80, 40),
    }
    for kind in ["nav", "ncx"]:
        output = dict(files)
        if kind == "ncx":
            output["OPS/book.opf"] = files["OPS/book.opf"].replace('<item id="nav" href="nav.xhtml" properties="nav"/>', '<item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/>')
            output["OPS/toc.ncx"] = '<ncx><navMap><navPoint><navLabel><text>Part</text></navLabel><navPoint><navLabel><text>One</text></navLabel><content src="a.xhtml#one"/><navPoint><navLabel><text>Alias</text></navLabel><content src="a.xhtml#one"/></navPoint></navPoint><navPoint><navLabel><text>Two</text></navLabel><content src="a.xhtml#two"/></navPoint></navPoint><navPoint><navLabel><text>Last</text></navLabel><content src="b.xhtml"/></navPoint></navMap></ncx>'
        with zipfile.ZipFile(OUTPUT / ("nested-" + kind + ".epub"), "w") as archive:
            for name, body in output.items():
                archive.writestr(zipfile.ZipInfo(name), body)


def scanned_pdf() -> bytes:
    image = zlib.compress(bytes([220, 50, 40]) * 24)
    drawing = b"q 200 0 0 300 0 0 cm /Im0 Do Q"
    page = b"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 300] /Resources << /XObject << /Im0 6 0 R >> >> /Contents 5 0 R >>"
    objects = [
        b"<< /Type /Catalog /Pages 2 0 R /Outlines 7 0 R >>",
        b"<< /Type /Pages /Count 2 /Kids [3 0 R 4 0 R] >>", page, page,
        b"<< /Length " + str(len(drawing)).encode() + b" >>\nstream\n" + drawing + b"\nendstream",
        b"<< /Type /XObject /Subtype /Image /Width 4 /Height 6 /ColorSpace /DeviceRGB /BitsPerComponent 8 /Filter /FlateDecode /Length " + str(len(image)).encode() + b" >>\nstream\n" + image + b"\nendstream",
        b"<< /Type /Outlines /First 8 0 R /Last 8 0 R /Count 2 >>",
        b"<< /Title (Part) /Parent 7 0 R /First 9 0 R /Last 9 0 R /Count 1 >>",
        b"<< /Title (Last scan) /Parent 8 0 R /Dest [4 0 R /Fit] >>",
    ]
    output = b"%PDF-1.4\n"
    offsets = [0]
    for index, value in enumerate(objects, 1):
        offsets.append(len(output))
        output += f"{index} 0 obj\n".encode() + value + b"\nendobj\n"
    start = len(output)
    output += f"xref\n0 {len(offsets)}\n0000000000 65535 f \n".encode()
    for offset in offsets[1:]:
        output += f"{offset:010d} 00000 n \n".encode()
    return output + f"trailer\n<< /Size {len(offsets)} /Root 1 0 R >>\nstartxref\n{start}\n%%EOF\n".encode()


def main() -> None:
    OUTPUT.mkdir(parents=True, exist_ok=True)
    (OUTPUT / "synthetic.umd").write_bytes(umd())
    text_encodings()
    epub_navigation()
    (OUTPUT / "scanned.pdf").write_bytes(scanned_pdf())
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
