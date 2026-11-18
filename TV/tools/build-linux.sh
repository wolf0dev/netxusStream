#!/usr/bin/env bash
# Compila NexusStream para Linux x64 y genera un paquete .tar.gz listo para
# distribuir (binario Flutter + launcher .desktop + icono + instalador local).
#
# En Linux, desde la raíz del repositorio:
#   bash tv/tools/build-linux.sh
#
# Requisitos: Flutter, clang, cmake, ninja, pkg-config, libgtk-3-dev,
# liblzma-dev y libmpv-dev. Ver docs/LINUX.md.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
tv="$(cd "$here/.." && pwd)"
repo="$(cd "$tv/.." && pwd)"
version="$(grep -m1 '^version:' "$tv/pubspec.yaml" | sed 's/version: *//; s/+.*//')"
name="NexusStream-$version-linux-x64"

cd "$tv"
flutter build linux --release

bundle="$tv/build/linux/x64/release/bundle"
if [ ! -x "$bundle/nexusstream" ]; then
  echo "No se encontró el bundle de Linux en $bundle" >&2
  exit 1
fi

stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT
pkg="$stage/$name"
mkdir -p "$pkg"
cp -a "$bundle/." "$pkg/"
cp "$tv/packaging/linux/nexusstream.desktop" "$pkg/"
cp "$tv/packaging/linux/instalar.sh" "$pkg/"
cp "$tv/assets/launcher_icon.png" "$pkg/nexusstream.png"
chmod +x "$pkg/nexusstream" "$pkg/instalar.sh"

mkdir -p "$repo/dist"
out="$repo/dist/$name.tar.gz"
tar -C "$stage" -czf "$out" "$name"
echo "Generado: $out"
