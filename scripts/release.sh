#!/usr/bin/env bash
set -euo pipefail

APP_NAME="CoPaRe"
SCHEME="CoPaRe"
PROJECT_FILE="CoPaRe.xcodeproj"
CONFIGURATION="Release"
VOLUME_NAME="${APP_NAME} Installer"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="${ROOT_DIR}/dist"
BUILD_DIR="${ROOT_DIR}/build/release"
DERIVED_DATA_DIR="${BUILD_DIR}/DerivedData"
DMG_ROOT_DIR="${DIST_DIR}/dmg-root"

SIGN_IDENTITY="${SIGN_IDENTITY:-}"
NOTARY_PROFILE="${NOTARY_PROFILE:-}"
VERSION="${VERSION:-}"
INSTALL_PATH="${INSTALL_PATH:-/Applications/${APP_NAME}.app}"
SKIP_NOTARIZE="${SKIP_NOTARIZE:-0}"
SKIP_INSTALL="${SKIP_INSTALL:-0}"
CLEAN_BUILD="${CLEAN_BUILD:-1}"

usage() {
  cat <<'USAGE'
Usage:
  scripts/release.sh --sign-identity "Developer ID Application: NAME (TEAMID)" --notary-profile "profile-name" [options]

Options:
  --sign-identity VALUE   Developer ID Application certificate common name (required)
  --notary-profile VALUE  Keychain profile created with `xcrun notarytool store-credentials` (required unless --skip-notarize)
  --version VALUE         Release version used in DMG filename (default: MARKETING_VERSION from Xcode, normalized to x.y.z)
  --install-path PATH     App install destination (default: /Applications/CoPaRe.app)
  --skip-notarize         Skip notarization/stapling steps
  --skip-install          Do not copy app to /Applications
  --no-clean              Do not run clean build
  -h, --help              Show help

Environment variable equivalents:
  SIGN_IDENTITY, NOTARY_PROFILE, VERSION, INSTALL_PATH, SKIP_NOTARIZE=1, SKIP_INSTALL=1, CLEAN_BUILD=0
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --sign-identity)
      SIGN_IDENTITY="${2:-}"
      shift 2
      ;;
    --notary-profile)
      NOTARY_PROFILE="${2:-}"
      shift 2
      ;;
    --version)
      VERSION="${2:-}"
      shift 2
      ;;
    --install-path)
      INSTALL_PATH="${2:-}"
      shift 2
      ;;
    --skip-notarize)
      SKIP_NOTARIZE=1
      shift
      ;;
    --skip-install)
      SKIP_INSTALL=1
      shift
      ;;
    --no-clean)
      CLEAN_BUILD=0
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage
      exit 1
      ;;
  esac
done

if [[ -z "${SIGN_IDENTITY}" ]]; then
  echo "Error: --sign-identity is required." >&2
  exit 1
fi

if [[ "${SKIP_NOTARIZE}" != "1" && -z "${NOTARY_PROFILE}" ]]; then
  echo "Error: --notary-profile is required unless --skip-notarize is set." >&2
  exit 1
fi

normalize_version() {
  local raw="$1"
  if [[ "$raw" =~ ^[0-9]+\.[0-9]+$ ]]; then
    printf "%s.0" "$raw"
  else
    printf "%s" "$raw"
  fi
}

resolve_version() {
  if [[ -n "${VERSION}" ]]; then
    normalize_version "${VERSION}"
    return
  fi

  local marketing
  marketing="$({
    xcodebuild -project "${ROOT_DIR}/${PROJECT_FILE}" -scheme "${SCHEME}" -configuration "${CONFIGURATION}" -showBuildSettings 2>/dev/null \
      | awk -F ' = ' '/MARKETING_VERSION/ {print $2; exit}'
  } || true)"

  if [[ -z "${marketing}" ]]; then
    echo "Error: unable to resolve MARKETING_VERSION. Pass --version explicitly." >&2
    exit 1
  fi

  normalize_version "${marketing}"
}

RELEASE_VERSION="$(resolve_version)"
DMG_NAME="${APP_NAME}-v${RELEASE_VERSION}.dmg"
DMG_PATH="${DIST_DIR}/${DMG_NAME}"
SHA_PATH="${DMG_PATH}.sha256"
APP_PRODUCT_PATH="${DERIVED_DATA_DIR}/Build/Products/${CONFIGURATION}/${APP_NAME}.app"
STAGED_APP_PATH="${DMG_ROOT_DIR}/${APP_NAME}.app"

cleanup_mount() {
  if [[ -n "${MOUNT_POINT:-}" && -d "${MOUNT_POINT}" ]]; then
    hdiutil detach "${MOUNT_POINT}" >/dev/null 2>&1 || true
  fi
}
trap cleanup_mount EXIT

mkdir -p "${DIST_DIR}" "${BUILD_DIR}"

if [[ "${CLEAN_BUILD}" == "1" ]]; then
  echo "[1/9] Clean build ${APP_NAME} (${CONFIGURATION})"
  xcodebuild -project "${ROOT_DIR}/${PROJECT_FILE}" -scheme "${SCHEME}" -configuration "${CONFIGURATION}" -destination 'platform=macOS' -derivedDataPath "${DERIVED_DATA_DIR}" clean build
else
  echo "[1/9] Build ${APP_NAME} (${CONFIGURATION})"
  xcodebuild -project "${ROOT_DIR}/${PROJECT_FILE}" -scheme "${SCHEME}" -configuration "${CONFIGURATION}" -destination 'platform=macOS' -derivedDataPath "${DERIVED_DATA_DIR}" build
fi

if [[ ! -d "${APP_PRODUCT_PATH}" ]]; then
  echo "Error: built app not found at ${APP_PRODUCT_PATH}" >&2
  exit 1
fi

echo "[2/9] Stage app bundle"
rm -rf "${DMG_ROOT_DIR}"
mkdir -p "${DMG_ROOT_DIR}"
ditto "${APP_PRODUCT_PATH}" "${STAGED_APP_PATH}"

echo "[3/9] Sign app bundle"
codesign --deep --force --verify --verbose --options runtime --timestamp --sign "${SIGN_IDENTITY}" "${STAGED_APP_PATH}"
codesign --verify --deep --strict --verbose=2 "${STAGED_APP_PATH}"

if [[ "${SKIP_INSTALL}" != "1" ]]; then
  echo "[4/9] Install app to ${INSTALL_PATH}"
  rm -rf "${INSTALL_PATH}"
  ditto "${STAGED_APP_PATH}" "${INSTALL_PATH}"
  echo "Installed: ${INSTALL_PATH}"
else
  echo "[4/9] Install skipped"
fi

echo "[5/9] Create DMG ${DMG_NAME}"
rm -f "${DMG_PATH}" "${SHA_PATH}"
hdiutil create -volname "${VOLUME_NAME}" -srcfolder "${DMG_ROOT_DIR}" -ov -format UDZO "${DMG_PATH}"

echo "[6/9] Sign DMG"
codesign --force --timestamp --sign "${SIGN_IDENTITY}" "${DMG_PATH}"
codesign --verify --verbose=2 "${DMG_PATH}"

if [[ "${SKIP_NOTARIZE}" != "1" ]]; then
  echo "[7/9] Notarize DMG (profile: ${NOTARY_PROFILE})"
  xcrun notarytool submit "${DMG_PATH}" --keychain-profile "${NOTARY_PROFILE}" --wait

  echo "[8/9] Staple + validate"
  xcrun stapler staple "${DMG_PATH}"
  xcrun stapler validate "${DMG_PATH}"
else
  echo "[7/9] Notarization skipped"
  echo "[8/9] Stapling skipped"
fi

echo "[9/9] Verify + SHA256"
spctl -a -t open -vv "${DMG_PATH}" || true
ATTACH_OUT="$(hdiutil attach "${DMG_PATH}" -readonly -nobrowse)"
MOUNT_POINT="$(printf '%s\n' "${ATTACH_OUT}" | awk '/\/Volumes\// {for (i=1;i<=NF;i++) if ($i ~ /^\/Volumes\//) {print substr($0, index($0, $i)); exit}}')"
if [[ -n "${MOUNT_POINT}" ]]; then
  spctl -a -vvv -t exec "${MOUNT_POINT}/${APP_NAME}.app" || true
fi
(
  cd "$(dirname "${DMG_PATH}")"
  shasum -a 256 "$(basename "${DMG_PATH}")" > "${SHA_PATH}"
)

if [[ -n "${MOUNT_POINT}" ]]; then
  hdiutil detach "${MOUNT_POINT}" >/dev/null
  MOUNT_POINT=""
fi

echo ""
echo "Release completed"
echo "- App (staged): ${STAGED_APP_PATH}"
echo "- DMG: ${DMG_PATH}"
echo "- SHA256: ${SHA_PATH}"
if [[ "${SKIP_INSTALL}" != "1" ]]; then
  echo "- Installed app: ${INSTALL_PATH}"
fi
