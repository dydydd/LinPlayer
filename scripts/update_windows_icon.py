import argparse
from pathlib import Path
import struct


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_PNG_PATH = ROOT / "android" / "app" / "src" / "main" / "res" / "mipmap-xxxhdpi" / "ic_launcher.png"
DEFAULT_ICO_PATH = ROOT / "windows" / "runner" / "resources" / "app_icon.ico"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Build a Windows .ico file from a PNG source.")
    parser.add_argument("--png", type=Path, default=DEFAULT_PNG_PATH, help="Source PNG path.")
    parser.add_argument("--ico", type=Path, default=DEFAULT_ICO_PATH, help="Destination ICO path.")
    return parser.parse_args()


def read_png_size(data: bytes) -> tuple[int, int]:
    signature = b"\x89PNG\r\n\x1a\n"
    if not data.startswith(signature):
        raise ValueError("Source file is not a PNG.")
    width = struct.unpack(">I", data[16:20])[0]
    height = struct.unpack(">I", data[20:24])[0]
    return width, height


def ico_dimension(value: int) -> int:
    return 0 if value >= 256 else value


def build_ico(png_bytes: bytes) -> bytes:
    width, height = read_png_size(png_bytes)
    if width != height:
        raise ValueError("Source PNG must be square.")
    if width > 256 or height > 256:
        raise ValueError("Source PNG must be 256x256 or smaller for ICO output.")
    header = struct.pack("<HHH", 0, 1, 1)
    entry = struct.pack(
        "<BBBBHHII",
        ico_dimension(width),
        ico_dimension(height),
        0,
        0,
        1,
        32,
        len(png_bytes),
        22,
    )
    return header + entry + png_bytes


def main() -> None:
    args = parse_args()
    png_bytes = args.png.read_bytes()
    args.ico.parent.mkdir(parents=True, exist_ok=True)
    args.ico.write_bytes(build_ico(png_bytes))
    print(f"updated {args.ico}")


if __name__ == "__main__":
    main()
