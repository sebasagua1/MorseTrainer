#!/usr/bin/env bash
# Archiva, exporta y (si se le pide) sube un build.
#
#   ./Scripts/release.sh            → .ipa firmado para App Store Connect
#   ./Scripts/release.sh --dev      → .ipa de desarrollo, instalable en los
#                                     dispositivos registrados del equipo
#   ./Scripts/release.sh --upload   → como el primero, y además lo sube
#
# --upload usa la cuenta que Xcode tenga iniciada; no hace falta configurar
# nada más. Si prefieres una clave de API —por ejemplo para CI, donde no hay
# sesión de Xcode— exporta ASC_KEY_ID y ASC_ISSUER_ID y se usarán en su lugar.
# El Issuer ID está en App Store Connect › Usuarios y acceso › Integraciones.
set -euo pipefail

cd "$(dirname "$0")/.."

PROJECT="MorseTrainer.xcodeproj"
SCHEME="MorseTrainer"
ARCHIVE="build/MorseTrainer.xcarchive"
EXPORT_DIR="build/export"

MODE="store"
case "${1:-}" in
  --dev)    MODE="dev" ;;
  --upload) MODE="upload" ;;
  "")       ;;
  *) echo "Uso: $0 [--dev|--upload]"; exit 2 ;;
esac

if [[ "$MODE" == "dev" ]]; then
  OPTIONS="Scripts/ExportOptions-dev.plist"
  EXPORT_DIR="build/export-dev"
else
  OPTIONS="Scripts/ExportOptions.plist"
fi

# Número de build = número de commits. Siempre crece, nunca se repite y se
# puede rastrear hasta el commit exacto que generó el build que alguien probó.
# App Store Connect rechaza un build cuyo número ya existe para esta versión.
BUILD_NUMBER="$(git rev-list --count HEAD)"
echo "▸ Modo: ${MODE} · build ${BUILD_NUMBER} ($(git rev-parse --short HEAD))"

if [[ -n "$(git status --porcelain)" ]]; then
  echo "⚠️  Hay cambios sin commitear: el número de build no describirá lo que subes."
fi

# Bash 3.2 (el que trae macOS) aborta con `set -u` al expandir un array vacío,
# así que se expande con `${x[@]+"${x[@]}"}`, que no lo toca si no está definido.
AUTH_ARGS=()
if [[ -n "${ASC_KEY_ID:-}" && -n "${ASC_ISSUER_ID:-}" ]]; then
  KEY_PATH="${HOME}/.appstoreconnect/private_keys/AuthKey_${ASC_KEY_ID}.p8"
  [[ -f "$KEY_PATH" ]] || { echo "No encuentro la clave en ${KEY_PATH}"; exit 1; }
  AUTH_ARGS=(
    -authenticationKeyPath "$KEY_PATH"
    -authenticationKeyID "$ASC_KEY_ID"
    -authenticationKeyIssuerID "$ASC_ISSUER_ID"
  )
  echo "▸ Autenticando con la clave de API ${ASC_KEY_ID}"
elif [[ "$MODE" == "upload" ]]; then
  echo "▸ Autenticando con la cuenta iniciada en Xcode"
fi

# En modo subida no se exporta a disco: `destination = upload` hace que el
# propio -exportArchive entregue el build a App Store Connect. Evita el paso
# extra por altool, que Apple tiene en desuso. El plist se deriva del de tienda
# en vez de duplicarse, para que no puedan divergir.
if [[ "$MODE" == "upload" ]]; then
  DERIVED="$(mktemp -t morse-export-XXXXXX).plist"
  cp "$OPTIONS" "$DERIVED"
  plutil -replace destination -string upload "$DERIVED"
  OPTIONS="$DERIVED"
fi

echo "▸ Archivando…"
rm -rf "$ARCHIVE" "$EXPORT_DIR"
xcodebuild archive \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath "$ARCHIVE" \
  -allowProvisioningUpdates \
  ${AUTH_ARGS[@]+"${AUTH_ARGS[@]}"} \
  CURRENT_PROJECT_VERSION="$BUILD_NUMBER"

echo "▸ Exportando con ${OPTIONS}…"
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE" \
  -exportOptionsPlist "$OPTIONS" \
  -exportPath "$EXPORT_DIR" \
  -allowProvisioningUpdates \
  ${AUTH_ARGS[@]+"${AUTH_ARGS[@]}"}

if [[ "$MODE" == "upload" ]]; then
  IPA=""
else
  IPA="$(find "$EXPORT_DIR" -name '*.ipa' | head -1)"
  echo "▸ Listo: ${IPA}"
fi

case "$MODE" in
  dev)
    echo
    echo "Instalar en un simulador o dispositivo conectado:"
    echo "  xcrun devicectl device install app --device <UDID> \"${IPA}\""
    echo "O arrastra el .ipa sobre el dispositivo en Xcode › Window › Devices."
    ;;
  upload)
    echo "▸ Subido. El procesado en App Store Connect tarda entre 5 y 30 minutos."
    ;;
  store)
    echo
    echo "Para subirlo:  ./Scripts/release.sh --upload"
    ;;
esac
