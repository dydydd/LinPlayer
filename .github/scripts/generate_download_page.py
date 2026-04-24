#!/usr/bin/env python3
import argparse
import json
import os
import re
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path


PROXY_BASES: list[tuple[str, str]] = [
    ("v6", "https://v6.gh-proxy.org/"),
    ("gh-proxy", "https://gh-proxy.org/"),
    ("hk", "https://hk.gh-proxy.org/"),
    ("cdn", "https://cdn.gh-proxy.org/"),
    ("edgeone", "https://edgeone.gh-proxy.org/"),
]

KNOWN_ASSETS: list[tuple[str, str]] = [
    ("Windows (Portable x64 / zip)", "LinPlayer-Windows-Portable-x64.zip"),
    ("Windows (Portable x64 / 7z)", "LinPlayer-Windows-Portable-x64.7z"),
    ("Android（arm64-v8a）", "LinPlayer-Android-arm64-v8a.apk"),
    ("Android TV", "LinPlayer-Android-TV.apk"),
    ("Android（通用）", "LinPlayer-Android.apk"),
    ("Windows（安装包 x64）", "LinPlayer-Windows-Setup-x64.exe"),
    ("Linux（x64，tar.gz）", "LinPlayer-Linux-x64.tar.gz"),
    ("Linux（x64，deb）", "LinPlayer-Linux-x64.deb"),
    ("Linux（x64，rpm）", "LinPlayer-Linux-x64.rpm"),
    ("Linux（arm64，tar.gz）", "LinPlayer-Linux-arm64.tar.gz"),
    ("Linux（arm64，deb）", "LinPlayer-Linux-arm64.deb"),
    ("Linux（arm64，rpm）", "LinPlayer-Linux-arm64.rpm"),
    ("iOS（未签名）", "LinPlayer-iOS-unsigned.ipa"),
    ("Apple TV（tvOS，未签名，可选）", "LinPlayer-AppleTV-unsigned.ipa"),
    ("macOS（Apple Silicon / arm64）", "LinPlayer-macOS-arm64.dmg"),
    ("macOS（Intel / x86_64）", "LinPlayer-macOS-x86_64.dmg"),
]


def _fail(message: str) -> None:
    sys.stderr.write(message.rstrip() + "\n")
    raise SystemExit(1)


def _gh_json(*args: str) -> dict:
    try:
        p = subprocess.run(
            ["gh", *args],
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
    except FileNotFoundError:
        _fail("GitHub CLI (gh) not found. Install it or run this script in GitHub Actions.")
    except subprocess.CalledProcessError as e:
        sys.stderr.write(e.stderr)
        _fail(f"Command failed: gh {' '.join(args)}")

    try:
        return json.loads(p.stdout)
    except json.JSONDecodeError as e:
        _fail(f"Failed to parse JSON from gh output ({type(e).__name__}: {e}).")


def _gh_json_optional(*args: str) -> dict | None:
    try:
        p = subprocess.run(
            ["gh", *args],
            check=False,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
    except FileNotFoundError:
        _fail("GitHub CLI (gh) not found. Install it or run this script in GitHub Actions.")

    if p.returncode != 0:
        if "HTTP 404" in p.stderr or "Not Found" in p.stderr:
            return None
        sys.stderr.write(p.stderr)
        _fail(f"Command failed: gh {' '.join(args)}")

    try:
        return json.loads(p.stdout)
    except json.JSONDecodeError as e:
        _fail(f"Failed to parse JSON from gh output ({type(e).__name__}: {e}).")


def _extract_version(body: str | None) -> str | None:
    if not body:
        return None
    m = re.search(r"(?m)^- Version:\s*(.+?)\s*$", body)
    return m.group(1).strip() if m else None


def _fmt_utc(iso: str | None) -> str | None:
    if not iso:
        return None
    try:
        dt = datetime.fromisoformat(iso.replace("Z", "+00:00")).astimezone(timezone.utc)
    except ValueError:
        return iso
    return dt.strftime("%Y-%m-%d %H:%M:%S UTC")


def _direct_url(repo: str, tag: str, asset_name: str) -> str:
    return f"https://github.com/{repo}/releases/download/{tag}/{asset_name}"


def _proxy_url(proxy_base: str, direct: str) -> str:
    base = proxy_base if proxy_base.endswith("/") else (proxy_base + "/")
    return base + direct


def _render_release_section(*, repo: str, tag: str, title: str) -> list[str]:
    release = _gh_json_optional("api", f"repos/{repo}/releases/tags/{tag}")
    if release is None:
        html_url = f"https://github.com/{repo}/releases/tag/{tag}"
        return [
            f"## {title}",
            "",
            f"- Release：[`{tag}`]({html_url})（尚未创建）",
            "",
        ]
    assets = release.get("assets") or []
    asset_names = {a.get("name") for a in assets if isinstance(a, dict) and a.get("name")}

    version = _extract_version(release.get("body"))
    published_at = _fmt_utc(release.get("published_at"))
    html_url = release.get("html_url") or f"https://github.com/{repo}/releases/tag/{tag}"

    lines: list[str] = []
    lines.append(f"## {title}")
    lines.append("")
    lines.append(f"- Release：[`{tag}`]({html_url})")
    if version:
        lines.append(f"- 版本：`{version}`")
    if published_at:
        lines.append(f"- 发布时间（UTC）：`{published_at}`")
    lines.append("")

    lines.append("| 平台 | 直链 | 反代 |")
    lines.append("| --- | --- | --- |")

    remaining = set(asset_names)
    for platform, asset_name in KNOWN_ASSETS:
        if asset_name not in asset_names:
            continue
        remaining.discard(asset_name)

        direct = _direct_url(repo, tag, asset_name)
        proxies = " · ".join(f"[{name}]({_proxy_url(url, direct)})" for name, url in PROXY_BASES)
        lines.append(f"| {platform} | [{asset_name}]({direct}) | {proxies} |")

    other = sorted(n for n in remaining if isinstance(n, str))
    if other:
        lines.append("")
        lines.append("**其他文件**")
        for asset_name in other:
            direct = _direct_url(repo, tag, asset_name)
            proxies = " · ".join(f"[{name}]({_proxy_url(url, direct)})" for name, url in PROXY_BASES)
            lines.append(f"- [{asset_name}]({direct})（反代：{proxies}）")

    lines.append("")
    return lines


def main() -> None:
    parser = argparse.ArgumentParser(description="Generate VitePress download page from GitHub Releases.")
    parser.add_argument("--repo", default=os.environ.get("GITHUB_REPOSITORY", "zzzwannasleep/LinPlayer"))
    parser.add_argument("--out", default="docs/download.md")
    parser.add_argument("--stable-tag", default="latest")
    parser.add_argument("--nightly-tag", default="nightly")
    args = parser.parse_args()

    repo = str(args.repo).strip()
    if "/" not in repo:
        _fail(f"--repo must look like owner/repo (got: {repo!r}).")

    out_path = Path(args.out)

    lines: list[str] = []
    lines.append("# 下载")
    lines.append("")
    lines.append("> 本页由 GitHub Actions 自动生成，请勿手动编辑。")
    lines.append("")
    lines.append("反代节点（把“直链”整段 URL 拼到下面任意节点后面即可）：")
    for _, url in PROXY_BASES:
        lines.append(f"- `{url}`")
    lines.append("")

    lines += _render_release_section(repo=repo, tag=args.stable_tag, title=f"稳定版（{args.stable_tag}）")
    lines += _render_release_section(repo=repo, tag=args.nightly_tag, title=f"每夜版（{args.nightly_tag}）")

    lines.append("> iOS / tvOS 为未签名安装包；需要自行签名后安装。")
    lines.append("")

    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text("\n".join(lines), encoding="utf-8", newline="\n")
    sys.stdout.write(f"Wrote: {out_path}\n")


if __name__ == "__main__":
    main()
