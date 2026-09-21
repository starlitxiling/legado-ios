from pathlib import Path
import os
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[2]
SIMULATOR = os.environ.get("LEGADO_SIMULATOR_ID", "booted")


def main() -> None:
    result = subprocess.run(
        ["xcrun", "simctl", "get_app_container", SIMULATOR, "com.legado.ios", "data"],
        capture_output=True, text=True, check=False,
    )
    if result.returncode:
        raise RuntimeError("Install Legado on a booted simulator first: " + result.stderr.strip())
    output = Path(result.stdout.strip()) / "Documents" / "LocalBookRegression" / "input"
    output.mkdir(parents=True, exist_ok=True)
    local = ROOT / "Tests" / "Fixtures" / "localbook"
    archive = ROOT / "tools" / "archive-probe" / "Tests" / "ArchiveProbeTests" / "Fixtures"
    files = [local / name for name in [
        "utf16.txt", "nested-nav.epub", "synthetic.umd", "scanned.pdf",
        "illustrated.mobi", "illustrated.azw3", "illustrated.azw", "two-books.zip",
    ]] + [archive / "rar5.rar", archive / "lzma.7z"]
    for source in files:
        shutil.copy2(source, output / source.name)
    print("Seeded ten local-book formats in the simulator.")


if __name__ == "__main__":
    main()
