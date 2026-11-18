#!/usr/bin/env bash
# Instala el paquete descomprimido de NexusStream en ~/.local, sin root.
# Uso: ./instalar.sh   (desde la carpeta NexusStream-<version>-linux-x64)
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
data="${XDG_DATA_HOME:-$HOME/.local/share}"
dest="$data/NexusStream"
apps="$data/applications"
icons="$data/icons/hicolor/1024x1024/apps"

mkdir -p "$dest" "$apps" "$icons"
cp -a "$here/." "$dest/"
rm -f "$dest/instalar.sh"
chmod +x "$dest/nexusstream"

sed "s|^Exec=.*|Exec=$dest/nexusstream %U|" "$dest/nexusstream.desktop" \
  > "$apps/nexusstream.desktop"
cp "$dest/nexusstream.png" "$icons/nexusstream.png"

if command -v update-desktop-database >/dev/null 2>&1; then
  update-desktop-database "$apps" >/dev/null 2>&1 || true
fi

echo "NexusStream instalado en $dest"
echo "Ya está disponible en el menú de aplicaciones."
