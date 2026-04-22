#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 3 ]]; then
  echo "Usage: $0 <bundle-dir> <arch> <output-dir>" >&2
  exit 1
fi

bundle_dir="$1"
arch="$2"
output_dir="$3"

case "$arch" in
  x64)
    deb_arch="amd64"
    rpm_arch="x86_64"
    ;;
  arm64)
    deb_arch="arm64"
    rpm_arch="aarch64"
    ;;
  *)
    echo "Unsupported Linux package arch: $arch" >&2
    exit 1
    ;;
esac

if [[ ! -d "$bundle_dir" ]]; then
  echo "Bundle directory does not exist: $bundle_dir" >&2
  exit 1
fi

: "${BUILD_NAME:?BUILD_NAME is required}"
: "${BUILD_NUMBER:?BUILD_NUMBER is required}"
: "${VERSION_FULL:?VERSION_FULL is required}"

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/../.." && pwd)"

app_name="LinPlayer"
binary_name="LinPlayer"
package_name="linplayer"
summary="A cross-platform media player built with Flutter."
description="LinPlayer is a cross-platform media player built with Flutter."
package_version="$BUILD_NAME"
package_release="$BUILD_NUMBER"
install_dir="/opt/linplayer"
bin_link="/usr/bin/linplayer"
icon_path="/usr/share/pixmaps/linplayer.jpg"

mkdir -p "$output_dir"

work_dir="$(mktemp -d "${TMPDIR:-/tmp}/linplayer-linux-package.XXXXXX")"
trap 'rm -rf "$work_dir"' EXIT

stage_root="$work_dir/stage"
mkdir -p \
  "$stage_root$install_dir" \
  "$stage_root/usr/bin" \
  "$stage_root/usr/share/applications" \
  "$stage_root/usr/share/pixmaps"

cp -a "$bundle_dir/." "$stage_root$install_dir/"
install -m 0644 "$repo_root/assets/app_icon.jpg" "$stage_root$icon_path"
ln -s "$install_dir/$binary_name" "$stage_root$bin_link"

cat > "$stage_root/usr/share/applications/${package_name}.desktop" <<EOF
[Desktop Entry]
Version=1.0
Type=Application
Name=LinPlayer
GenericName=Media Player
Comment=$summary
Exec=$bin_link %U
Icon=$icon_path
Terminal=false
Categories=AudioVideo;Player;
StartupNotify=true
StartupWMClass=LinPlayer
EOF

tar_stage="$work_dir/tar"
mkdir -p "$tar_stage/$app_name"
cp -a "$bundle_dir/." "$tar_stage/$app_name/"
tar -C "$tar_stage" -czf "$output_dir/LinPlayer-Linux-${arch}.tar.gz" "$app_name"

deb_root="$work_dir/deb"
mkdir -p "$deb_root"
cp -a "$stage_root/." "$deb_root/"
mkdir -p "$deb_root/DEBIAN"

installed_size_kb="$(du -sk "$deb_root" | awk '{print $1}')"

cat > "$deb_root/DEBIAN/control" <<EOF
Package: $package_name
Version: ${package_version}-${package_release}
Section: video
Priority: optional
Architecture: $deb_arch
Maintainer: LinPlayer CI <noreply@github.com>
Depends: libc6, libstdc++6, libgtk-3-0, libasound2 | libasound2t64, libmpv2 | libmpv1
Installed-Size: $installed_size_kb
Description: $summary
 $description
EOF

dpkg-deb --build --root-owner-group "$deb_root" "$output_dir/LinPlayer-Linux-${arch}.deb"

rpm_topdir="$work_dir/rpm"
rpm_buildroot="$rpm_topdir/BUILDROOT/${package_name}-${package_version}-${package_release}.${rpm_arch}"
rpm_payload="$work_dir/rpm-payload"

mkdir -p \
  "$rpm_topdir/BUILD" \
  "$rpm_topdir/BUILDROOT" \
  "$rpm_topdir/RPMS" \
  "$rpm_topdir/SOURCES" \
  "$rpm_topdir/SPECS" \
  "$rpm_topdir/SRPMS" \
  "$rpm_payload"

cp -a "$stage_root/." "$rpm_payload/"

cat > "$rpm_topdir/SPECS/${package_name}.spec" <<EOF
Name: $package_name
Version: $package_version
Release: $package_release
Summary: $summary
License: Proprietary
URL: https://github.com/${GITHUB_REPOSITORY:-zzzwannasleep/LinPlayer}

%description
$description

%install
mkdir -p %{buildroot}
cp -a "$rpm_payload/." %{buildroot}/

%files
/opt/linplayer
/usr/bin/linplayer
/usr/share/applications/linplayer.desktop
/usr/share/pixmaps/linplayer.jpg
EOF

rpmbuild \
  --define "_topdir $rpm_topdir" \
  --buildroot "$rpm_buildroot" \
  -bb "$rpm_topdir/SPECS/${package_name}.spec"

cp -f \
  "$rpm_topdir/RPMS/$rpm_arch/${package_name}-${package_version}-${package_release}.${rpm_arch}.rpm" \
  "$output_dir/LinPlayer-Linux-${arch}.rpm"

echo "Created Linux packages:"
ls -la "$output_dir"/LinPlayer-Linux-"$arch".*
