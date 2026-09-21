from pathlib import Path
import struct
import zlib

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


def main() -> None:
    OUTPUT.mkdir(parents=True, exist_ok=True)
    (OUTPUT / "synthetic.umd").write_bytes(umd())


if __name__ == "__main__":
    main()
