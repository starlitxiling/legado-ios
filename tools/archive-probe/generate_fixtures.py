from pathlib import Path
import shutil
import subprocess
import tempfile


def main() -> None:
    destination = Path(__file__).resolve().parent / "Tests" / "ArchiveProbeTests" / "Fixtures"
    destination.mkdir(parents=True, exist_ok=True)
    for executable in ("7z", "rar"):
        if shutil.which(executable) is None:
            raise RuntimeError(f"Fixture generation requires {executable} on PATH; checked-in fixtures can be used without it")
    with tempfile.TemporaryDirectory() as temporary:
        directory = Path(temporary)
        chapter = directory / "chapter.txt"
        chapter.write_text("Synthetic archive probe chapter.\n" * 100, encoding="ascii")
        (directory / "second.txt").write_text("Second synthetic chapter.\n", encoding="ascii")
        commands = [
            ["7z", "a", "-t7z", "-m0=lzma", "-mtc=off", "lzma.7z", "chapter.txt"],
            ["7z", "a", "-t7z", "-m0=lzma2", "-ms=on", "-mtc=off", "lzma2-solid.7z", "chapter.txt", "second.txt"],
            ["rar", "a", "-ma5", "-m3", "-ep", "rar5.rar", "chapter.txt"],
        ]
        for command in commands:
            subprocess.run(command, cwd=directory, check=True)
        for filename in ("lzma.7z", "lzma2-solid.7z", "rar5.rar"):
            shutil.copyfile(directory / filename, destination / filename)


if __name__ == "__main__":
    main()
