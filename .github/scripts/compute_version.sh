#!/usr/bin/env bash
set -euo pipefail

build_name="${BUILD_NAME_INPUT:-}"
build_number="${BUILD_NUMBER_INPUT:-}"
version_full_input="${VERSION_FULL_INPUT:-}"

derive_build_number_from_git() {
  local git_ref commit_epoch

  git_ref="${GITHUB_SHA:-HEAD}"
  commit_epoch="$(git show -s --format=%ct "$git_ref" 2>/dev/null || git show -s --format=%ct HEAD 2>/dev/null || true)"
  if ! [[ "${commit_epoch:-}" =~ ^[0-9]+$ ]]; then
    return 1
  fi

  # Keep Android versionCode within signed 32-bit int range while still making the
  # default CI build number stable across jobs and independent of workflow run counters.
  python3 - "$commit_epoch" <<'PY'
import sys
from datetime import datetime, timezone

commit_epoch = int(sys.argv[1])
print(datetime.fromtimestamp(commit_epoch, tz=timezone.utc).strftime("%y%j%H%M"))
PY
}

if [[ -n "${version_full_input:-}" ]]; then
  if [[ "${version_full_input}" == *"+"* ]]; then
    build_name="${version_full_input%%+*}"
    build_number="${version_full_input##*+}"
    if [[ -z "${build_name:-}" ]]; then
      echo "VERSION_FULL_INPUT build name is empty (got: ${version_full_input})" >&2
      exit 1
    fi
  else
    # Accept "1.2.3" and treat it as a build name override. build_number is resolved later.
    build_name="${version_full_input}"
  fi
fi

raw_version="$(awk '$1 == "version:" { print $2; exit }' pubspec.yaml 2>/dev/null || true)"
if [[ -z "${build_name:-}" && -n "${raw_version:-}" ]]; then
  build_name="${raw_version%%+*}"
fi
if [[ -z "${build_name:-}" ]]; then
  build_name="0.1.0"
fi

if [[ -z "${build_number:-}" ]]; then
  build_number="$(derive_build_number_from_git || true)"
fi
if [[ -z "${build_number:-}" ]]; then
  build_number="${GITHUB_RUN_NUMBER:-}"
fi
if [[ -z "${build_number:-}" && -n "${raw_version:-}" && "${raw_version}" == *"+"* ]]; then
  build_number="${raw_version##*+}"
fi
if [[ -z "${build_number:-}" ]]; then
  build_number="1"
fi

if ! [[ "$build_number" =~ ^[0-9]+$ ]]; then
  echo "build_number must be an integer (got: $build_number)" >&2
  exit 1
fi

version_full="${build_name}+${build_number}"
app_version="${build_name}.${build_number}"

echo "Using version: ${version_full}"

if [[ -n "${GITHUB_ENV:-}" ]]; then
  {
    echo "BUILD_NAME=${build_name}"
    echo "BUILD_NUMBER=${build_number}"
    echo "VERSION_FULL=${version_full}"
    echo "APP_VERSION=${app_version}"
    echo "APP_VERSION_FULL=${version_full}"
  } >> "${GITHUB_ENV}"
else
  cat <<EOF
BUILD_NAME=${build_name}
BUILD_NUMBER=${build_number}
VERSION_FULL=${version_full}
APP_VERSION=${app_version}
APP_VERSION_FULL=${version_full}
EOF
fi
