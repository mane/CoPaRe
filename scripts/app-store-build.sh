#!/usr/bin/env bash
set -euo pipefail

APP_NAME="CoPaRe"
SCHEME="CoPaRe"
PROJECT_FILE="CoPaRe.xcodeproj"
CONFIGURATION="Release"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="${ROOT_DIR}/build/app-store"
WORK_DIR="${BUILD_DIR}/work"
ARCHIVE_DIR="${BUILD_DIR}/archives"
EXPORT_DIR="${BUILD_DIR}/export"
EXPORT_OPTIONS_PATH="${BUILD_DIR}/ExportOptions-AppStore.plist"

TEAM_ID="${TEAM_ID:-6246LWZM9N}"
BUNDLE_ID="${BUNDLE_ID:-io.copare.app}"
SIGNING_CERTIFICATE="${SIGNING_CERTIFICATE:-Apple Distribution}"
AUTHENTICATION_KEY_PATH="${AUTHENTICATION_KEY_PATH:-}"
AUTHENTICATION_KEY_ID="${AUTHENTICATION_KEY_ID:-}"
AUTHENTICATION_KEY_ISSUER_ID="${AUTHENTICATION_KEY_ISSUER_ID:-}"
ALLOW_PROVISIONING_UPDATES="${ALLOW_PROVISIONING_UPDATES:-0}"
SKIP_EXPORT="${SKIP_EXPORT:-0}"
UPLOAD="${UPLOAD:-0}"
CLEAN="${CLEAN:-1}"
UNSIGNED_CHECK="${UNSIGNED_CHECK:-0}"

usage() {
  cat <<'USAGE'
Usage:
  scripts/app-store-build.sh [options]

Options:
  --team-id VALUE                 Apple Developer team ID (default: 6246LWZM9N)
  --bundle-id VALUE               App Store bundle identifier (default: io.copare.app)
  --signing-certificate VALUE     Signing certificate selector (default: Apple Distribution)
  --authentication-key-path PATH   App Store Connect API key path for xcodebuild
  --authentication-key-id VALUE    App Store Connect API key ID
  --authentication-key-issuer-id VALUE
                                  App Store Connect issuer ID
  --allow-provisioning-updates    Let xcodebuild create/download App Store signing assets
  --skip-export                   Create only the .xcarchive
  --unsigned-check                Build an unsigned App Store variant and verify
                                  bundle shape without creating a submission archive
  --upload                        Export with destination=upload instead of a local package
  --no-clean                      Reuse the previous temporary App Store build workspace
  -h, --help                      Show help

Environment variable equivalents:
  TEAM_ID, BUNDLE_ID, SIGNING_CERTIFICATE, AUTHENTICATION_KEY_PATH,
  AUTHENTICATION_KEY_ID, AUTHENTICATION_KEY_ISSUER_ID,
  ALLOW_PROVISIONING_UPDATES=1, SKIP_EXPORT=1, UNSIGNED_CHECK=1,
  UPLOAD=1, CLEAN=0

The script builds a temporary App Store project copy with Sparkle removed, APP_STORE
compilation enabled, App Store entitlements, and Sparkle Info.plist keys stripped.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --team-id)
      TEAM_ID="${2:-}"
      shift 2
      ;;
    --bundle-id)
      BUNDLE_ID="${2:-}"
      shift 2
      ;;
    --signing-certificate)
      SIGNING_CERTIFICATE="${2:-}"
      shift 2
      ;;
    --authentication-key-path)
      AUTHENTICATION_KEY_PATH="${2:-}"
      shift 2
      ;;
    --authentication-key-id)
      AUTHENTICATION_KEY_ID="${2:-}"
      shift 2
      ;;
    --authentication-key-issuer-id)
      AUTHENTICATION_KEY_ISSUER_ID="${2:-}"
      shift 2
      ;;
    --allow-provisioning-updates)
      ALLOW_PROVISIONING_UPDATES=1
      shift
      ;;
    --skip-export)
      SKIP_EXPORT=1
      shift
      ;;
    --unsigned-check)
      UNSIGNED_CHECK=1
      shift
      ;;
    --upload)
      UPLOAD=1
      shift
      ;;
    --no-clean)
      CLEAN=0
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if [[ -z "${TEAM_ID}" ]]; then
  echo "Error: --team-id is required." >&2
  exit 1
fi

if [[ -z "${BUNDLE_ID}" ]]; then
  echo "Error: --bundle-id is required." >&2
  exit 1
fi

if [[ -z "${SIGNING_CERTIFICATE}" ]]; then
  echo "Error: --signing-certificate must not be empty." >&2
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

current_version() {
  awk -F ' = ' '/MARKETING_VERSION = / {gsub(/;/, "", $2); print $2; exit}' "${ROOT_DIR}/${PROJECT_FILE}/project.pbxproj"
}

patch_project_for_app_store() {
  local pbxproj="$1"

  perl -0pi -e '
    s/\n\t\tA11A00012F60000000D25DBC \/\* Sparkle in Frameworks \*\/ = \{[^\n]*\n//g;
    s/\n\t\t\t\tA11A00012F60000000D25DBC \/\* Sparkle in Frameworks \*\/,\n//g;
    s/\n\t\t\t\tA11A00032F60000000D25DBC \/\* Sparkle \*\/,\n//g;
    s/\n\t\t\t\tA11A00022F60000000D25DBC \/\* XCRemoteSwiftPackageReference "Sparkle" \*\/,\n//g;
    s/\n\/\* Begin XCRemoteSwiftPackageReference section \*\/\n\t\tA11A00022F60000000D25DBC \/\* XCRemoteSwiftPackageReference "Sparkle" \*\/ = \{.*?\n\t\t\};\n\/\* End XCRemoteSwiftPackageReference section \*\/\n//s;
    s/\n\/\* Begin XCSwiftPackageProductDependency section \*\/\n\t\tA11A00032F60000000D25DBC \/\* Sparkle \*\/ = \{.*?\n\t\t\};\n\/\* End XCSwiftPackageProductDependency section \*\/\n//s;
  ' "${pbxproj}"
}

strip_sparkle_info_keys() {
  local plist="$1"
  local keys=(
    SUAutomaticallyUpdate
    SUEnableAutomaticChecks
    SUEnableInstallerLauncherService
    SUFeedURL
    SUPublicEDKey
    SURequireSignedFeed
    SUVerifyUpdateBeforeExtraction
  )

  for key in "${keys[@]}"; do
    /usr/libexec/PlistBuddy -c "Delete :${key}" "${plist}" >/dev/null 2>&1 || true
  done
}

write_export_options() {
  local destination="export"
  if [[ "${UPLOAD}" == "1" ]]; then
    destination="upload"
  fi

  cat > "${EXPORT_OPTIONS_PATH}" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>destination</key>
    <string>${destination}</string>
    <key>generateAppStoreInformation</key>
    <true/>
    <key>manageAppVersionAndBuildNumber</key>
    <false/>
    <key>method</key>
    <string>app-store-connect</string>
    <key>signingStyle</key>
    <string>automatic</string>
    <key>stripSwiftSymbols</key>
    <true/>
    <key>teamID</key>
    <string>${TEAM_ID}</string>
    <key>uploadSymbols</key>
    <true/>
</dict>
</plist>
EOF
}

require_no_sparkle() {
  local app_path="$1"

  if [[ -e "${app_path}/Contents/Frameworks/Sparkle.framework" ]]; then
    echo "Error: Sparkle.framework is present in the App Store build." >&2
    exit 1
  fi

  if otool -L "${app_path}/Contents/MacOS/${APP_NAME}" | grep -Fq Sparkle; then
    echo "Error: App Store executable still links Sparkle." >&2
    exit 1
  fi

  if /usr/libexec/PlistBuddy -c "Print :SUFeedURL" "${app_path}/Contents/Info.plist" >/dev/null 2>&1; then
    echo "Error: App Store Info.plist still contains SUFeedURL." >&2
    exit 1
  fi
}

require_app_store_entitlements_plist() {
  local entitlements_path="$1"
  local description="$2"
  local sandbox_value
  local get_task_allow_value

  sandbox_value="$(/usr/libexec/PlistBuddy -c "Print :com.apple.security.app-sandbox" "${entitlements_path}" 2>/dev/null || true)"
  if [[ "${sandbox_value}" != "true" ]]; then
    echo "Error: ${description} must set com.apple.security.app-sandbox to true." >&2
    return 1
  fi

  get_task_allow_value="$(/usr/libexec/PlistBuddy -c "Print :com.apple.security.get-task-allow" "${entitlements_path}" 2>/dev/null || true)"
  if [[ "${get_task_allow_value}" != "false" ]]; then
    echo "Error: ${description} must set com.apple.security.get-task-allow to false." >&2
    return 1
  fi

  if plutil -convert xml1 -o - "${entitlements_path}" 2>/dev/null | grep -Fq "temporary-exception.mach-lookup"; then
    echo "Error: ${description} still contains Sparkle mach-lookup temporary exceptions." >&2
    return 1
  fi
}

require_app_store_entitlements() {
  local app_path="$1"
  local entitlements_path
  entitlements_path="$(mktemp "${TMPDIR:-/tmp}/copare-app-store-entitlements.XXXXXX")"

  if ! codesign -d --entitlements :- "${app_path}" >"${entitlements_path}" 2>/dev/null; then
    rm -f "${entitlements_path}"
    echo "Error: unable to read entitlements from the App Store build." >&2
    exit 1
  fi

  if ! require_app_store_entitlements_plist "${entitlements_path}" "App Store build"; then
    rm -f "${entitlements_path}"
    exit 1
  fi

  rm -f "${entitlements_path}"
}

require_privacy_manifest() {
  local app_path="$1"
  local manifest_path="${app_path}/Contents/Resources/PrivacyInfo.xcprivacy"

  if [[ ! -f "${manifest_path}" ]]; then
    echo "Error: PrivacyInfo.xcprivacy is missing from the App Store build resources." >&2
    exit 1
  fi

  plutil -lint "${manifest_path}" >/dev/null
}

warn_if_signing_assets_are_missing() {
  local identities
  identities="$(security find-identity -v -p codesigning || true)"

  if ! printf '%s\n' "${identities}" | grep -Eq "\"(${SIGNING_CERTIFICATE}|Apple Development|Mac Developer|3rd Party Mac Developer Application|Mac App Distribution): .*\\(${TEAM_ID}\\)\""; then
    echo "Warning: no local App Store-capable signing identity was found for team ${TEAM_ID}." >&2
    echo "         Use --allow-provisioning-updates with a logged-in Xcode account/API key, or install the certificate/profile first." >&2
  fi
}

if [[ "${UNSIGNED_CHECK}" != "1" && "${ALLOW_PROVISIONING_UPDATES}" != "1" ]]; then
  warn_if_signing_assets_are_missing
fi

mkdir -p "${BUILD_DIR}" "${ARCHIVE_DIR}" "${EXPORT_DIR}"

if [[ "${CLEAN}" == "1" ]]; then
  rm -rf "${WORK_DIR}" "${EXPORT_DIR}"
fi

mkdir -p "${WORK_DIR}" "${EXPORT_DIR}"
rsync -a --delete \
  --exclude ".git" \
  --exclude "build" \
  --exclude "dist" \
  --exclude "release/CoPaRe-v*.zip" \
  --exclude "release/CoPaRe"*.delta \
  "${ROOT_DIR}/" "${WORK_DIR}/"

patch_project_for_app_store "${WORK_DIR}/${PROJECT_FILE}/project.pbxproj"
strip_sparkle_info_keys "${WORK_DIR}/CoPaRe-Info.plist"
plutil -lint "${WORK_DIR}/CoPaRe-Info.plist" "${WORK_DIR}/CoPaRe/CoPaRe.AppStore.entitlements" "${WORK_DIR}/CoPaRe/PrivacyInfo.xcprivacy" >/dev/null
require_app_store_entitlements_plist "${WORK_DIR}/CoPaRe/CoPaRe.AppStore.entitlements" "App Store entitlements file"

RELEASE_VERSION="$(normalize_version "$(current_version)")"
ARCHIVE_PATH="${ARCHIVE_DIR}/${APP_NAME}-v${RELEASE_VERSION}-AppStore.xcarchive"

if [[ "${UNSIGNED_CHECK}" == "1" ]]; then
  UNSIGNED_DERIVED_DATA="${BUILD_DIR}/UnsignedDerivedData"

  echo "[1/2] Build unsigned App Store variant ${APP_NAME} ${RELEASE_VERSION}"
  rm -rf "${UNSIGNED_DERIVED_DATA}"
  xcodebuild \
    -project "${WORK_DIR}/${PROJECT_FILE}" \
    -scheme "${SCHEME}" \
    -configuration "${CONFIGURATION}" \
    -destination "generic/platform=macOS" \
    -derivedDataPath "${UNSIGNED_DERIVED_DATA}" \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGN_ENTITLEMENTS="CoPaRe/CoPaRe.AppStore.entitlements" \
    "OTHER_SWIFT_FLAGS=\$(inherited) -D APP_STORE" \
    build

  UNSIGNED_APP_PATH="${UNSIGNED_DERIVED_DATA}/Build/Products/${CONFIGURATION}/${APP_NAME}.app"
  if [[ ! -d "${UNSIGNED_APP_PATH}" ]]; then
    echo "Error: unsigned app not found at ${UNSIGNED_APP_PATH}" >&2
    exit 1
  fi

  echo "[2/2] Validate unsigned App Store bundle shape"
  require_no_sparkle "${UNSIGNED_APP_PATH}"
  require_privacy_manifest "${UNSIGNED_APP_PATH}"

  echo ""
  echo "Unsigned App Store variant check passed"
  echo "- App: ${UNSIGNED_APP_PATH}"
  exit 0
fi

XCODEBUILD_PROVISIONING_ARGS=()
if [[ "${ALLOW_PROVISIONING_UPDATES}" == "1" ]]; then
  XCODEBUILD_PROVISIONING_ARGS=(-allowProvisioningUpdates)
fi

if [[ -n "${AUTHENTICATION_KEY_PATH}${AUTHENTICATION_KEY_ID}${AUTHENTICATION_KEY_ISSUER_ID}" ]]; then
  if [[ -z "${AUTHENTICATION_KEY_PATH}" || -z "${AUTHENTICATION_KEY_ID}" || -z "${AUTHENTICATION_KEY_ISSUER_ID}" ]]; then
    echo "Error: all authentication key options are required when using an App Store Connect API key." >&2
    exit 1
  fi

  XCODEBUILD_PROVISIONING_ARGS+=(
    -authenticationKeyPath "${AUTHENTICATION_KEY_PATH}"
    -authenticationKeyID "${AUTHENTICATION_KEY_ID}"
    -authenticationKeyIssuerID "${AUTHENTICATION_KEY_ISSUER_ID}"
  )
fi

echo "[1/3] Archive App Store build ${APP_NAME} ${RELEASE_VERSION}"
xcodebuild \
  -project "${WORK_DIR}/${PROJECT_FILE}" \
  -scheme "${SCHEME}" \
  -configuration "${CONFIGURATION}" \
  -destination "generic/platform=macOS" \
  -archivePath "${ARCHIVE_PATH}" \
  -derivedDataPath "${BUILD_DIR}/DerivedData" \
  "${XCODEBUILD_PROVISIONING_ARGS[@]}" \
  DEVELOPMENT_TEAM="${TEAM_ID}" \
  PRODUCT_BUNDLE_IDENTIFIER="${BUNDLE_ID}" \
  CODE_SIGN_STYLE=Automatic \
  CODE_SIGN_IDENTITY="${SIGNING_CERTIFICATE}" \
  CODE_SIGN_ENTITLEMENTS="CoPaRe/CoPaRe.AppStore.entitlements" \
  "OTHER_SWIFT_FLAGS=\$(inherited) -D APP_STORE" \
  archive

APP_PATH="${ARCHIVE_PATH}/Products/Applications/${APP_NAME}.app"
if [[ ! -d "${APP_PATH}" ]]; then
  echo "Error: archived app not found at ${APP_PATH}" >&2
  exit 1
fi

echo "[2/3] Validate App Store archive shape"
require_no_sparkle "${APP_PATH}"
require_app_store_entitlements "${APP_PATH}"
require_privacy_manifest "${APP_PATH}"

if [[ "${SKIP_EXPORT}" == "1" ]]; then
  echo "[3/3] Export skipped"
else
  echo "[3/3] Export App Store package"
  write_export_options
  xcodebuild \
    -exportArchive \
    -archivePath "${ARCHIVE_PATH}" \
    -exportPath "${EXPORT_DIR}" \
    -exportOptionsPlist "${EXPORT_OPTIONS_PATH}" \
    "${XCODEBUILD_PROVISIONING_ARGS[@]}"
fi

echo ""
echo "App Store build prepared"
echo "- Archive: ${ARCHIVE_PATH}"
if [[ "${SKIP_EXPORT}" != "1" ]]; then
  echo "- Export: ${EXPORT_DIR}"
fi
