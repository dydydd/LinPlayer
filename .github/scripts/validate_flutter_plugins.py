#!/usr/bin/env python3
from __future__ import annotations

import json
import re
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]


def fail(message: str) -> None:
    print(f"[validate_flutter_plugins] ERROR: {message}", file=sys.stderr)


def main() -> int:
    errors: list[str] = []

    plugins_file = ROOT / ".flutter-plugins-dependencies"
    if not plugins_file.exists():
        errors.append(f"Missing {plugins_file}. Run `flutter pub get` first.")
    else:
        try:
            plugins = json.loads(plugins_file.read_text(encoding="utf-8"))
        except json.JSONDecodeError as exc:
            errors.append(f"Could not parse {plugins_file}: {exc}")
        else:
            android_plugins = {
                plugin.get("name", "")
                for plugin in plugins.get("plugins", {}).get("android", [])
            }
            if "desktop_drop" in android_plugins:
                errors.append(
                    "desktop_drop is still registered for Android. "
                    "The local fork must stay desktop/web-only."
                )

    pubspec_text = (ROOT / "pubspec.yaml").read_text(encoding="utf-8")
    if "path: packages/desktop_drop_patched" not in pubspec_text:
        errors.append(
            "Root pubspec.yaml is not pinned to packages/desktop_drop_patched."
        )

    fork_pubspec = (ROOT / "packages" / "desktop_drop_patched" / "pubspec.yaml")
    if not fork_pubspec.exists():
        errors.append("Missing packages/desktop_drop_patched/pubspec.yaml.")
    else:
        fork_pubspec_text = fork_pubspec.read_text(encoding="utf-8")
        if re.search(r"^\s+android:\s*$", fork_pubspec_text, re.MULTILINE):
            errors.append(
                "packages/desktop_drop_patched/pubspec.yaml still declares an "
                "Android plugin platform."
            )

    build_gradle = ROOT / "android" / "app" / "build.gradle.kts"
    build_gradle_text = build_gradle.read_text(encoding="utf-8")
    forbidden_markers = [
        "patchGeneratedPluginRegistrant",
        "pluginByClassName(",
        "reflective-plugin-keep-rules.pro",
    ]
    for marker in forbidden_markers:
        if marker in build_gradle_text:
            errors.append(
                f"android/app/build.gradle.kts still contains forbidden marker: {marker}"
            )

    if errors:
        for error in errors:
            fail(error)
        return 1

    print("[validate_flutter_plugins] OK: Android plugin registration is stable.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
