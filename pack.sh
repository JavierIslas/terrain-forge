#!/bin/bash
# pack.sh — Builds the distributable packages for Terrain Forge.
# Uso: ./pack.sh
#
# Terrain Forge es un monolito dual-licensed: el MISMO código se entrega en
# ambos paquetes; lo único que cambia es la licencia que gobierna el uso. Por
# eso no hay tiers free/pro — solo dos ZIP:
#   dist/terrain_forge_agpl.zip        → Godot Asset Store / Asset Library (AGPLv3, gratis)
#   dist/terrain_forge_commercial.zip  → itch.io (licencia comercial)
#
# Layout (revisión del Godot Asset Store, DIM-34): la raíz no lleva nada
# suelto. El README y los dos textos de licencia viajan DENTRO de
# addons/terrain_forge/ — el revisor exige la licencia empaquetada junto al
# contenido y los headers .gd referencian ambos archivos. Única diferencia
# entre paquetes: el commercial añade un NOTICE.txt en la raíz que declara al
# comprador qué licencia gobierna su copia.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
ADDON_DIR="$REPO_ROOT/addons/terrain_forge"
DIST_DIR="$REPO_ROOT/dist"
VERSION=$(awk -F'"' '/^version=/{print $2}' "$ADDON_DIR/plugin.cfg")

rm -rf "$DIST_DIR"
mkdir -p "$DIST_DIR"

# build_package <suffix> [<notice_text>]
# Ensambla un paquete: addon completo con README y ambas licencias dentro de
# addons/terrain_forge/, y —solo si se pasa notice_text— un NOTICE.txt en la
# raíz que declara qué licencia gobierna esta copia concreta.
build_package() {
    local suffix="$1" notice_text="${2:-}"
    local stage="/tmp/terrain_forge_pack_${suffix}"
    local zip="$DIST_DIR/terrain_forge_${suffix}.zip"

    rm -rf "$stage"
    mkdir -p "$stage/addons"

    # Addon completo (módulos + docs/ + examples/ + LICENSE commiteado). Los
    # .import se regeneran al abrir el proyecto; los .uid sí viajan para que
    # Godot resuelva las clases por class_name sin reasignarlas.
    cp -r "$ADDON_DIR" "$stage/addons/terrain_forge"

    # El README viaja dentro del addon: Godot Asset Library espera la
    # documentación junto al código, no en la raíz del zip.
    cp "$REPO_ROOT/README.md" "$stage/addons/terrain_forge/README.md"

    # LICENSE (AGPL) ya vive commiteado dentro del addon; LICENSE_COMMERCIAL.md
    # se copia en pack-time desde la raíz (fuente única en el repo). El código
    # es dual-licensed y cada header .gd referencia ambos, así que los dos
    # viajan siempre.
    cp "$REPO_ROOT/LICENSE_COMMERCIAL.md" "$stage/addons/terrain_forge/LICENSE_COMMERCIAL.md"

    if [[ -n "$notice_text" ]]; then
        printf '%s\n' "$notice_text" > "$stage/NOTICE.txt"
    fi

    (cd "$stage" && zip -rq "$zip" . -x "*.import")
    echo "  $zip ($(du -sh "$zip" | cut -f1))"
}

echo "=== Terrain Forge v${VERSION} — distributables ==="

echo "AGPL (Asset Store, free):"
# Sin NOTICE ni archivos sueltos en la raíz: el revisor del Asset Store exige
# raíz limpia (DIM-34). La licencia que gobierna esta copia es LICENSE (AGPL),
# dentro del propio addon.
build_package "agpl"

echo "Commercial (itch.io):"
build_package "commercial" "Terrain Forge v${VERSION}

This copy is licensed to the purchaser under the COMMERCIAL LICENSE
(see addons/terrain_forge/LICENSE_COMMERCIAL.md), which exempts you from the
AGPL obligations, including server-side use, for closed-source and proprietary
projects.

The GNU AGPLv3 text (addons/terrain_forge/LICENSE) is included for reference
only. The commercial license governs your use of this copy. The code is
identical to the public AGPL release; what you purchased is the license grant,
not different code."

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
