#!/usr/bin/env bash
set -euo pipefail

APP_NAME="CoPaRe"
SCHEME="CoPaRe GitHub Release"
PROJECT_FILE="CoPaRe.xcodeproj"
CONFIGURATION="Distribution"
VOLUME_NAME="${APP_NAME} Installer"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="${ROOT_DIR}/dist"
RELEASE_DIR="${ROOT_DIR}/release"
BUILD_DIR="${ROOT_DIR}/build/release"
DERIVED_DATA_DIR="${BUILD_DIR}/DerivedData"
DMG_ROOT_DIR="${DIST_DIR}/dmg-root"

SIGN_IDENTITY="${SIGN_IDENTITY:-}"
NOTARY_PROFILE="${NOTARY_PROFILE:-}"
VERSION="${VERSION:-}"
INSTALL_PATH="${INSTALL_PATH:-/Applications/${APP_NAME}.app}"
SKIP_NOTARIZE="${SKIP_NOTARIZE:-0}"
SKIP_INSTALL="${SKIP_INSTALL:-1}"
CLEAN_BUILD="${CLEAN_BUILD:-1}"
SPARKLE_KEY_ACCOUNT="${SPARKLE_KEY_ACCOUNT:-io.copare.sparkle}"
SPARKLE_DOWNLOAD_URL_PREFIX="${SPARKLE_DOWNLOAD_URL_PREFIX:-}"

usage() {
  cat <<'USAGE'
Usage:
  scripts/release.sh --sign-identity "Developer ID Application: NAME (TEAMID)" --notary-profile "profile-name" [options]

Options:
  --sign-identity VALUE   Developer ID Application certificate common name (required)
  --notary-profile VALUE  Keychain profile created with `xcrun notarytool store-credentials` (required unless --skip-notarize)
  --version VALUE         Release version used in DMG filename (default: MARKETING_VERSION from Xcode, normalized to x.y.z)
  --install               Install the verified app after the release succeeds
  --install-path PATH     App install destination (default: /Applications/CoPaRe.app; requires --install)
  --skip-notarize         Skip notarization/stapling steps
  --skip-install          Do not copy app to /Applications
  --no-clean              Do not run clean build
  -h, --help              Show help

Environment variable equivalents:
  SIGN_IDENTITY, NOTARY_PROFILE, VERSION, INSTALL_PATH, SKIP_NOTARIZE=1, SKIP_INSTALL=0, CLEAN_BUILD=0
  SPARKLE_KEY_ACCOUNT, SPARKLE_DOWNLOAD_URL_PREFIX
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
    --install)
      SKIP_INSTALL=0
      shift
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

if [[ "${SKIP_INSTALL}" != "1" ]]; then
  case "${INSTALL_PATH}" in
    /*.app) ;;
    *)
      echo "Error: --install-path must be an absolute .app bundle path." >&2
      exit 1
      ;;
  esac

  INSTALL_PARENT="$(dirname "${INSTALL_PATH}")"
  if [[ ! -d "${INSTALL_PARENT}" ]]; then
    echo "Error: install destination directory does not exist: ${INSTALL_PARENT}" >&2
    exit 1
  fi
  INSTALL_PATH="$(cd "${INSTALL_PARENT}" && pwd -P)/$(basename "${INSTALL_PATH}")"
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
if [[ -z "${SPARKLE_DOWNLOAD_URL_PREFIX}" ]]; then
  SPARKLE_DOWNLOAD_URL_PREFIX="https://github.com/mane/CoPaRe/releases/latest/download/"
fi
DMG_NAME="${APP_NAME}-v${RELEASE_VERSION}.dmg"
DMG_PATH="${DIST_DIR}/${DMG_NAME}"
SHA_PATH="${DMG_PATH}.sha256"
ZIP_NAME="${APP_NAME}-v${RELEASE_VERSION}.zip"
ZIP_PATH="${RELEASE_DIR}/${ZIP_NAME}"
APP_PRODUCT_PATH="${DERIVED_DATA_DIR}/Build/Products/${CONFIGURATION}/${APP_NAME}.app"
STAGED_APP_PATH="${DMG_ROOT_DIR}/${APP_NAME}.app"
SPARKLE_FRAMEWORK_PATH="${STAGED_APP_PATH}/Contents/Frameworks/Sparkle.framework"
SPARKLE_FRAMEWORK_VERSION_PATH="${SPARKLE_FRAMEWORK_PATH}/Versions/B"
SPARKLE_AUTOUPDATE_PATH="${SPARKLE_FRAMEWORK_VERSION_PATH}/Autoupdate"
SPARKLE_UPDATER_PATH="${SPARKLE_FRAMEWORK_VERSION_PATH}/Updater.app"
SPARKLE_DOWNLOADER_XPC_PATH="${SPARKLE_FRAMEWORK_VERSION_PATH}/XPCServices/Downloader.xpc"
SPARKLE_INSTALLER_XPC_PATH="${SPARKLE_FRAMEWORK_VERSION_PATH}/XPCServices/Installer.xpc"
DMG_BACKGROUND_NAME="dmg-background.png"
DMG_BACKGROUND_DIR="${DMG_ROOT_DIR}/.background"
DMG_BACKGROUND_PATH="${DMG_BACKGROUND_DIR}/${DMG_BACKGROUND_NAME}"
DMG_BACKGROUND_HIDPI_PATH="${DMG_BACKGROUND_DIR}/dmg-background@2x.png"
DMGBUILD_VERSION="${DMGBUILD_VERSION:-1.6.7}"
DMGBUILD_VENV_DIR="${BUILD_DIR}/release-tools-venv"
DMGBUILD_BIN="${DMGBUILD_BIN:-}"
TEMP_DMGBUILD_SETTINGS=""
TEMP_DMGBUILD_DIR=""
INSTALL_TEMP_DIR=""
INSTALL_BACKUP_PATH=""
SPARKLE_BIN_DIR="${DERIVED_DATA_DIR}/SourcePackages/artifacts/sparkle/Sparkle/bin"
GENERATE_APPCAST_BIN="${SPARKLE_BIN_DIR}/generate_appcast"

extract_mount_point() {
  printf '%s\n' "$1" | awk '/\/Volumes\// {for (i=1;i<=NF;i++) if ($i ~ /^\/Volumes\//) {print substr($0, index($0, $i)); exit}}'
}

generate_dmg_background() {
  mkdir -p "${DMG_BACKGROUND_DIR}"
  "${ROOT_DIR}/scripts/generate-dmg-background.swift" "${DMG_BACKGROUND_PATH}" 1
  "${ROOT_DIR}/scripts/generate-dmg-background.swift" "${DMG_BACKGROUND_HIDPI_PATH}" 2
}

resolve_dmgbuild_bin() {
  if [[ -n "${DMGBUILD_BIN}" && -x "${DMGBUILD_BIN}" ]]; then
    return 0
  fi

  if command -v dmgbuild >/dev/null 2>&1; then
    DMGBUILD_BIN="$(command -v dmgbuild)"
    return 0
  fi

  local local_bin="${DMGBUILD_VENV_DIR}/bin/dmgbuild"
  if [[ -x "${local_bin}" ]]; then
    DMGBUILD_BIN="${local_bin}"
    return 0
  fi

  if ! command -v python3 >/dev/null 2>&1; then
    return 1
  fi

  echo "Preparing local release toolchain (dmgbuild ${DMGBUILD_VERSION})"
  if ! python3 -m venv "${DMGBUILD_VENV_DIR}"; then
    return 1
  fi

  if ! "${DMGBUILD_VENV_DIR}/bin/python" -m pip install --quiet --disable-pip-version-check "dmgbuild==${DMGBUILD_VERSION}"; then
    return 1
  fi

  if [[ -x "${local_bin}" ]]; then
    DMGBUILD_BIN="${local_bin}"
    return 0
  fi

  return 1
}

create_styled_dmg() {
  TEMP_DMGBUILD_DIR="$(mktemp -d "${BUILD_DIR}/dmgbuild.XXXXXX")"
  TEMP_DMGBUILD_SETTINGS="${TEMP_DMGBUILD_DIR}/settings.json"
  cat > "${TEMP_DMGBUILD_SETTINGS}" <<EOF
{
  "title": "${VOLUME_NAME}",
  "background": "${DMG_BACKGROUND_PATH}",
  "icon-size": 128,
  "format": "UDZO",
  "filesystem": "HFS+",
  "window": {
    "position": {"x": 140, "y": 120},
    "size": {"width": 720, "height": 460}
  },
  "contents": [
    {"path": "${STAGED_APP_PATH}", "type": "file", "x": 180, "y": 255, "hide_extension": true},
    {"path": "/Applications", "type": "link", "name": "Applications", "x": 540, "y": 255}
  ]
}
EOF

  "${DMGBUILD_BIN}" -s "${TEMP_DMGBUILD_SETTINGS}" "${VOLUME_NAME}" "${DMG_PATH}"
  rm -rf "${TEMP_DMGBUILD_DIR}"
  TEMP_DMGBUILD_SETTINGS=""
  TEMP_DMGBUILD_DIR=""
}

cleanup_mount() {
  if [[ -n "${MOUNT_POINT:-}" && -d "${MOUNT_POINT}" ]]; then
    hdiutil detach "${MOUNT_POINT}" >/dev/null 2>&1 || true
  fi
  if [[ -n "${TEMP_DMGBUILD_DIR}" && -d "${TEMP_DMGBUILD_DIR}" ]]; then
    rm -rf "${TEMP_DMGBUILD_DIR}"
  fi
  if [[ -n "${INSTALL_BACKUP_PATH}" && ( -e "${INSTALL_BACKUP_PATH}" || -L "${INSTALL_BACKUP_PATH}" ) ]]; then
    if [[ ! -e "${INSTALL_PATH}" && ! -L "${INSTALL_PATH}" ]]; then
      if mv "${INSTALL_BACKUP_PATH}" "${INSTALL_PATH}"; then
        INSTALL_BACKUP_PATH=""
      fi
    fi
    if [[ -n "${INSTALL_BACKUP_PATH}" && ( -e "${INSTALL_BACKUP_PATH}" || -L "${INSTALL_BACKUP_PATH}" ) ]]; then
      echo "Warning: previous app backup retained at ${INSTALL_BACKUP_PATH}" >&2
      INSTALL_TEMP_DIR=""
    fi
  fi
  if [[ -n "${INSTALL_TEMP_DIR}" && -d "${INSTALL_TEMP_DIR}" ]]; then
    rm -rf "${INSTALL_TEMP_DIR}"
  fi
}
trap cleanup_mount EXIT

run_spctl_check() {
  local label="$1"
  shift

  if "$@"; then
    return 0
  fi

  if [[ "${SKIP_NOTARIZE}" == "1" ]]; then
    echo "Warning: ${label} failed; continuing because notarization was skipped." >&2
    return 0
  fi

  echo "Error: ${label} failed." >&2
  exit 1
}

strip_quarantine_attributes() {
  local target="$1"

  if command -v xattr >/dev/null 2>&1; then
    xattr -dr com.apple.quarantine "${target}" 2>/dev/null || true
  fi
}

sign_path() {
  local path="$1"
  shift

  codesign --force --timestamp --options runtime --sign "${SIGN_IDENTITY}" "$@" "${path}"
}

sign_staged_app_bundle() {
  if [[ ! -d "${SPARKLE_FRAMEWORK_PATH}" ]]; then
    echo "Error: Sparkle.framework not found at ${SPARKLE_FRAMEWORK_PATH}" >&2
    exit 1
  fi

  strip_quarantine_attributes "${STAGED_APP_PATH}"

  sign_path "${SPARKLE_AUTOUPDATE_PATH}"
  sign_path "${SPARKLE_UPDATER_PATH}"
  sign_path "${SPARKLE_DOWNLOADER_XPC_PATH}"
  sign_path "${SPARKLE_INSTALLER_XPC_PATH}"
  sign_path "${SPARKLE_FRAMEWORK_PATH}"
  sign_path "${STAGED_APP_PATH}" --preserve-metadata=identifier,entitlements,flags
}

mkdir -p "${DIST_DIR}" "${RELEASE_DIR}" "${BUILD_DIR}"

if [[ "${CLEAN_BUILD}" == "1" ]]; then
  echo "[1/11] Clean build ${APP_NAME} (${CONFIGURATION})"
  xcodebuild -project "${ROOT_DIR}/${PROJECT_FILE}" -scheme "${SCHEME}" -configuration "${CONFIGURATION}" -destination 'platform=macOS' -derivedDataPath "${DERIVED_DATA_DIR}" clean build
else
  echo "[1/11] Build ${APP_NAME} (${CONFIGURATION})"
  xcodebuild -project "${ROOT_DIR}/${PROJECT_FILE}" -scheme "${SCHEME}" -configuration "${CONFIGURATION}" -destination 'platform=macOS' -derivedDataPath "${DERIVED_DATA_DIR}" build
fi

if [[ ! -d "${APP_PRODUCT_PATH}" ]]; then
  echo "Error: built app not found at ${APP_PRODUCT_PATH}" >&2
  exit 1
fi

echo "[2/11] Stage app bundle"
rm -rf "${DMG_ROOT_DIR}"
mkdir -p "${DMG_ROOT_DIR}"
ditto "${APP_PRODUCT_PATH}" "${STAGED_APP_PATH}"
# Present the standard drag-to-Applications install flow in a single Finder window.
ln -s /Applications "${DMG_ROOT_DIR}/Applications"
generate_dmg_background

echo "[3/11] Sign app bundle"
sign_staged_app_bundle
codesign --verify --deep --strict --verbose=2 "${STAGED_APP_PATH}"
"${ROOT_DIR}/scripts/security-check.sh" "${STAGED_APP_PATH}"

if [[ ! -x "${GENERATE_APPCAST_BIN}" ]]; then
  echo "Error: Sparkle generate_appcast tool not found at ${GENERATE_APPCAST_BIN}" >&2
  echo "Run xcodebuild once to resolve package dependencies, or verify the project still includes Sparkle." >&2
  exit 1
fi

echo "[4/11] Create Sparkle update archive ${ZIP_NAME}"
# Keep older archives available so Sparkle can generate delta updates.
rm -f "${ZIP_PATH}" "${RELEASE_DIR}/${APP_NAME}"*.delta
ditto -c -k --sequesterRsrc --keepParent "${STAGED_APP_PATH}" "${ZIP_PATH}"

echo "[5/11] Refresh Sparkle appcast"
"${GENERATE_APPCAST_BIN}" \
  --account "${SPARKLE_KEY_ACCOUNT}" \
  --download-url-prefix "${SPARKLE_DOWNLOAD_URL_PREFIX}" \
  "${RELEASE_DIR}"

echo "[6/11] Create DMG ${DMG_NAME}"
rm -f "${DMG_PATH}" "${SHA_PATH}"
if resolve_dmgbuild_bin; then
  create_styled_dmg
else
  echo "Warning: dmgbuild is unavailable; creating a plain DMG without custom Finder layout." >&2
  hdiutil create -fs HFS+ -volname "${VOLUME_NAME}" -srcfolder "${DMG_ROOT_DIR}" -ov -format UDZO "${DMG_PATH}"
fi

echo "[7/11] Sign DMG"
codesign --force --timestamp --sign "${SIGN_IDENTITY}" "${DMG_PATH}"
codesign --verify --verbose=2 "${DMG_PATH}"

if [[ "${SKIP_NOTARIZE}" != "1" ]]; then
  echo "[8/11] Notarize DMG (profile: ${NOTARY_PROFILE})"
  xcrun notarytool submit "${DMG_PATH}" --keychain-profile "${NOTARY_PROFILE}" --wait

  echo "[9/11] Staple + validate"
  xcrun stapler staple "${DMG_PATH}"
  xcrun stapler validate "${DMG_PATH}"
else
  echo "[8/11] Notarization skipped"
  echo "[9/11] Stapling skipped"
fi

echo "[10/11] Verify + SHA256"
run_spctl_check "DMG Gatekeeper assessment" spctl -a -t open --context context:primary-signature -vv "${DMG_PATH}"
ATTACH_OUT="$(hdiutil attach "${DMG_PATH}" -readonly -nobrowse)"
MOUNT_POINT="$(extract_mount_point "${ATTACH_OUT}")"
if [[ -n "${MOUNT_POINT}" ]]; then
  run_spctl_check "mounted app Gatekeeper assessment" spctl -a -vvv -t exec "${MOUNT_POINT}/${APP_NAME}.app"
fi

(
  cd "$(dirname "${DMG_PATH}")"
  shasum -a 256 "$(basename "${DMG_PATH}")" > "${SHA_PATH}"
)

if [[ -n "${MOUNT_POINT}" ]]; then
  hdiutil detach "${MOUNT_POINT}" >/dev/null
  MOUNT_POINT=""
fi

if [[ "${SKIP_INSTALL}" != "1" ]]; then
  echo "[11/11] Install verified app to ${INSTALL_PATH}"
  INSTALL_TEMP_DIR="$(mktemp -d "${INSTALL_PARENT}/.${APP_NAME}-install.XXXXXX")"
  INSTALL_TEMP_PATH="${INSTALL_TEMP_DIR}/$(basename "${INSTALL_PATH}")"
  ditto "${STAGED_APP_PATH}" "${INSTALL_TEMP_PATH}"

  if [[ -e "${INSTALL_PATH}" || -L "${INSTALL_PATH}" ]]; then
    INSTALL_BACKUP_PATH="${INSTALL_TEMP_DIR}/previous-$(basename "${INSTALL_PATH}")"
    mv "${INSTALL_PATH}" "${INSTALL_BACKUP_PATH}"
  fi

  if mv "${INSTALL_TEMP_PATH}" "${INSTALL_PATH}"; then
    if [[ -n "${INSTALL_BACKUP_PATH}" ]]; then
      rm -rf "${INSTALL_BACKUP_PATH}"
      INSTALL_BACKUP_PATH=""
    fi
  else
    replacement_status=$?
    if [[ -n "${INSTALL_BACKUP_PATH}" && ( -e "${INSTALL_BACKUP_PATH}" || -L "${INSTALL_BACKUP_PATH}" ) ]]; then
      if mv "${INSTALL_BACKUP_PATH}" "${INSTALL_PATH}"; then
        INSTALL_BACKUP_PATH=""
      else
        echo "Error: replacement failed and the previous app could not be restored. Backup retained at ${INSTALL_BACKUP_PATH}" >&2
        INSTALL_TEMP_DIR=""
        exit 1
      fi
    fi
    exit "${replacement_status}"
  fi

  rmdir "${INSTALL_TEMP_DIR}"
  INSTALL_TEMP_DIR=""
  echo "Installed: ${INSTALL_PATH}"
else
  echo "[11/11] Install skipped"
fi

echo ""
echo "Release completed"
echo "- App (staged): ${STAGED_APP_PATH}"
echo "- ZIP (Sparkle archive): ${ZIP_PATH}"
echo "- Appcast: ${RELEASE_DIR}/appcast.xml"
echo "- DMG: ${DMG_PATH}"
echo "- SHA256: ${SHA_PATH}"
if [[ "${SKIP_INSTALL}" != "1" ]]; then
  echo "- Installed app: ${INSTALL_PATH}"
fi
