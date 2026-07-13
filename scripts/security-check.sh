#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_PATH="${1:-}"
BUILT_LOCALLY=0
DD=""
BUILD_LOG=""
ENT_TMP=""

cleanup() {
  [[ -z "${ENT_TMP}" ]] || rm -f "${ENT_TMP}"
  [[ -z "${BUILD_LOG}" ]] || rm -f "${BUILD_LOG}"
  [[ -z "${DD}" ]] || rm -rf "${DD}"
}
trap cleanup EXIT

if [[ -z "${APP_PATH}" ]]; then
  BUILT_LOCALLY=1
  DD="$(mktemp -d /tmp/copare-security-check-dd.XXXXXX)"
  BUILD_LOG="$(mktemp /tmp/copare-security-check-build.log.XXXXXX)"
  if ! xcodebuild \
    -project "${PROJECT_ROOT}/CoPaRe.xcodeproj" \
    -scheme "CoPaRe" \
    -configuration Release \
    -destination 'platform=macOS' \
    -derivedDataPath "${DD}" \
    build >"${BUILD_LOG}" 2>&1; then
    cat "${BUILD_LOG}" >&2
    exit 1
  fi

  APP_PATH="${DD}/Build/Products/Release/CoPaRe.app"
fi

if [[ ! -d "${APP_PATH}" ]]; then
  echo "ERROR: app not found at ${APP_PATH}" >&2
  exit 1
fi

ENT_TMP="$(mktemp /tmp/copare-entitlements.plist.XXXXXX)"

if ! codesign -d --entitlements :- "${APP_PATH}" >"${ENT_TMP}" 2>/dev/null; then
  echo "ERROR: unable to read entitlements from ${APP_PATH}" >&2
  exit 1
fi

ENT_DUMP="$(plutil -p "${ENT_TMP}" 2>/dev/null || true)"

if printf '%s\n' "${ENT_DUMP}" | grep -Fq '$('; then
  echo "ERROR: unresolved entitlement placeholder detected in signed app" >&2
  exit 1
fi

if ! printf '%s\n' "${ENT_DUMP}" | grep -Fq '"com.apple.security.app-sandbox" => true'; then
  echo "ERROR: app sandbox is not enabled" >&2
  exit 1
fi

if ! printf '%s\n' "${ENT_DUMP}" | grep -Fq '"com.apple.security.files.user-selected.read-write" => true'; then
  echo "ERROR: user-selected-files read-write entitlement is not enabled" >&2
  exit 1
fi

if printf '%s\n' "${ENT_DUMP}" | grep -Fq '"com.apple.security.get-task-allow" => true'; then
  echo "ERROR: get-task-allow must be disabled for release builds" >&2
  exit 1
fi

CODE_SIGN_DV="$(codesign -dv --verbose=4 "${APP_PATH}" 2>&1 || true)"
if ! printf '%s\n' "${CODE_SIGN_DV}" | grep -Eq 'Runtime Version|flags=.*runtime'; then
  echo "WARNING: hardened runtime signal not detected in current signature metadata"
fi

SPARKLE_FRAMEWORK_PATH="${APP_PATH}/Contents/Frameworks/Sparkle.framework"
SPARKLE_AUTOUPDATE_PATH="${SPARKLE_FRAMEWORK_PATH}/Versions/B/Autoupdate"
SPARKLE_INSTALLER_XPC_PATH="${SPARKLE_FRAMEWORK_PATH}/Versions/B/XPCServices/Installer.xpc"

if [[ -d "${SPARKLE_FRAMEWORK_PATH}" ]]; then
  for helper_path in "${SPARKLE_AUTOUPDATE_PATH}" "${SPARKLE_INSTALLER_XPC_PATH}"; do
    if [[ ! -e "${helper_path}" ]]; then
      echo "ERROR: expected Sparkle helper missing at ${helper_path}" >&2
      exit 1
    fi

    if xattr -lr "${helper_path}" 2>/dev/null | grep -Fq 'com.apple.quarantine'; then
      echo "ERROR: Sparkle helper still has quarantine attribute: ${helper_path}" >&2
      exit 1
    fi
  done

  if [[ "${BUILT_LOCALLY}" != "1" ]]; then
    AUTOUPDATE_SIGN_DV="$(codesign -dv --verbose=4 "${SPARKLE_AUTOUPDATE_PATH}" 2>&1 || true)"
    if ! printf '%s\n' "${AUTOUPDATE_SIGN_DV}" | grep -Fq 'Authority=Developer ID Application:'; then
      echo "ERROR: Autoupdate is not signed with a Developer ID Application certificate" >&2
      exit 1
    fi
  fi
fi

echo "Security check passed for ${APP_PATH}"
echo "- app-sandbox: true"
echo "- files.user-selected.read-write: true"
echo "- get-task-allow: false"
if [[ -d "${SPARKLE_FRAMEWORK_PATH}" ]]; then
  echo "- sparkle helper quarantine: none"
  if [[ "${BUILT_LOCALLY}" == "1" ]]; then
    echo "- sparkle autoupdate signer: skipped for local build"
  else
    echo "- sparkle autoupdate signer: Developer ID Application"
  fi
fi
