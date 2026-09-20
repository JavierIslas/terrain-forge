#!/bin/bash
# pack.sh — Builds the distributable packages for Terrain Forge.
# Uso: ./pack.sh
#
# Terrain Forge es un monolito dual-licensed: el MISMO código se entrega en
# ambos paquetes; lo único que cambia es la licencia que gobierna el uso. Por
# eso no hay tiers free/pro — solo dos ZIP con distinto NOTICE.txt:
#   dist/terrain_forge_agpl.zip        → Godot Asset Store / Asset Library (AGPLv3, gratis)
#   dist/terrain_forge_commercial.zip  → itch.io (licencia comercial)

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
ADDON_DIR="$REPO_ROOT/addons/terrain_forge"
DIST_DIR="$REPO_ROOT/dist"
VERSION=$(awk -F'"' '/^version=/{print $2}' "$ADDON_DIR/plugin.cfg")

rm -rf "$DIST_DIR"
mkdir -p "$DIST_DIR"

# build_package <suffix> <notice_text>
# Ensambla un paquete idéntico (addon + README + ambas licencias) y le añade un
# NOTICE.txt que declara qué licencia gobierna esta copia concreta.
build_package() {
    local suffix="$1" notice_text="$2"
    local stage="/tmp/terrain_forge_pack_${suffix}"
    local zip="$DIST_DIR/terrain_forge_${suffix}.zip"

    rm -rf "$stage"
    mkdir -p "$stage/addons"

    # Addon completo (módulos + docs/ + examples/). Los .import se regeneran al
    # abrir el proyecto; los .uid sí viajan para que Godot resuelva las clases
    # por class_name sin reasignarlas.
    cp -r "$ADDON_DIR" "$stage/addons/terrain_forge"

    # El código es dual-licensed y cada header .gd referencia ambos archivos, así
    # que los dos viajan siempre. El NOTICE indica cuál aplica a esta copia.
    cp "$REPO_ROOT/README.md"              "$stage/README.md"
    cp "$REPO_ROOT/LICENSE"                "$stage/LICENSE"
    cp "$REPO_ROOT/LICENSE_COMMERCIAL.md"  "$stage/LICENSE_COMMERCIAL.md"
    printf '%s\n' "$notice_text" > "$stage/NOTICE.txt"

    (cd "$stage" && zip -rq "$zip" . -x "*.import")
    echo "  $zip ($(du -sh "$zip" | cut -f1))"
}

echo "=== Terrain Forge v${VERSION} — distributables ==="

echo "AGPL (Asset Store, free):"
build_package "agpl" "Terrain Forge v${VERSION}

This distribution is provided under the GNU Affero General Public License v3.0
(see LICENSE). Using Terrain Forge — including running it server-side as part
of a networked product (e.g. a procedural map generation service) — places
your project under the AGPL too.

A commercial license that exempts you from the AGPL is available for
closed-source or proprietary use: see LICENSE_COMMERCIAL.md or contact
islasjavieralf@gmail.com."

echo "Commercial (itch.io):"
build_package "commercial" "Terrain Forge v${VERSION}

This copy is licensed to the purchaser under the COMMERCIAL LICENSE
(see LICENSE_COMMERCIAL.md), which exempts you from the AGPL obligations,
including server-side use, for closed-source and proprietary projects.

The GNU AGPLv3 text (LICENSE) is included for reference only. The commercial
license governs your use of this copy. The code is identical to the public
AGPL release; what you purchased is the license grant, not different code."

# Sanity: el addon debe ser idéntico en ambos paquetes (mismo código).
agpl_sum=$(unzip -p "$DIST_DIR/terrain_forge_agpl.zip"       'addons/*' | sha256sum | cut -d' ' -f1)
comm_sum=$(unzip -p "$DIST_DIR/terrain_forge_commercial.zip" 'addons/*' | sha256sum | cut -d' ' -f1)
echo ""
if [[ "$agpl_sum" == "$comm_sum" ]]; then
    echo "OK: el addon es idéntico en ambos paquetes ($agpl_sum)"
else
    echo "ERROR: el addon difiere entre paquetes (agpl=$agpl_sum commercial=$comm_sum)" >&2
    exit 1
fi

echo ""
echo "=== Destinos ==="
echo "  terrain_forge_agpl.zip       → Godot Asset Store / Asset Library (gratis)"
echo "  terrain_forge_commercial.zip → itch.io (venta de licencia comercial)"
