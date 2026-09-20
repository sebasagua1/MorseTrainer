#!/usr/bin/env bash
# Archiva, exporta y (si se le pide) sube un build a TestFlight.
#
#   ./Scripts/release.sh            → archiva y exporta el .ipa
#   ./Scripts/release.sh --upload   → además lo sube a App Store Connect
#
# Requiere, para la subida:
#   - La clave privada en ~/.appstoreconnect/private_keys/AuthKey_<KEY_ID>.p8
#   - ASC_KEY_ID y ASC_ISSUER_ID en el entorno
#
# El Issuer ID está en App Store Connect › Usuarios y acceso › Integraciones.
set -euo pipefail

cd "$(dirname "$0")/.."

PROJECT="MorseTrainer.xcodeproj"
SCHEME="MorseTrainer"
ARCHIVE="build/MorseTrainer.xcarchive"
EXPORT_DIR="build/export"
UPLOAD=false
[[ "${1:-}" == "--upload" ]] && UPLOAD=true

# Número de build = número de commits. Siempre crece, nunca se repite y se
# puede rastrear hasta el commit exacto que generó el build que alguien probó.
# App Store Connect rechaza un build cuyo número ya existe para esta versión.
BUILD_NUMBER="$(git rev-list --count HEAD)"
echo "▸ Versión de build: ${BUILD_NUMBER} ($(git rev-parse --short HEAD))"

if [[ -n "$(git status --porcelain)" ]]; then
  echo "⚠️  Hay cambios sin commitear: el número de build no describirá lo que subes."
fi

AUTH_ARGS=()
if $UPLOAD; then
  : "${ASC_KEY_ID:?Falta ASC_KEY_ID}"
  : "${ASC_ISSUER_ID:?Falta ASC_ISSUER_ID}"
  KEY_PATH="${HOME}/.appstoreconnect/private_keys/AuthKey_${ASC_KEY_ID}.p8"
  [[ -f "$KEY_PATH" ]] || { echo "No encuentro la clave en ${KEY_PATH}"; exit 1; }
  AUTH_ARGS=(
    -authenticationKeyPath "$KEY_PATH"
    -authenticationKeyID "$ASC_KEY_ID"
    -authenticationKeyIssuerID "$ASC_ISSUER_ID"
  )
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
  "${AUTH_ARGS[@]}" \
  CURRENT_PROJECT_VERSION="$BUILD_NUMBER"

echo "▸ Exportando el .ipa…"
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE" \
  -exportOptionsPlist Scripts/ExportOptions.plist \
  -exportPath "$EXPORT_DIR" \
  -allowProvisioningUpdates \
  "${AUTH_ARGS[@]}"

IPA="$(find "$EXPORT_DIR" -name '*.ipa' | head -1)"
echo "▸ Listo: ${IPA}"

if $UPLOAD; then
  echo "▸ Subiendo a App Store Connect…"
  xcrun altool --upload-app \
    --type ios \
    --file "$IPA" \
    --apiKey "$ASC_KEY_ID" \
    --apiIssuer "$ASC_ISSUER_ID"
  echo "▸ Subido. El procesado en App Store Connect tarda entre 5 y 30 minutos."
else
  echo
  echo "Para subirlo:  ASC_KEY_ID=… ASC_ISSUER_ID=… ./Scripts/release.sh --upload"
fi
