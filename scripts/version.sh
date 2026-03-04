#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_PBXPROJ="${ROOT_DIR}/CoPaRe.xcodeproj/project.pbxproj"

COMMAND="${1:-next}"
if [[ $# -gt 0 ]]; then
  shift
fi

LEVEL="auto"
TAG_VERSION=""
TAG_REF="HEAD"

usage() {
  cat <<'USAGE'
Usage:
  scripts/version.sh current
  scripts/version.sh next [--level auto|major|minor|patch]
  scripts/version.sh bump [--level auto|major|minor|patch]
  scripts/version.sh tag [--version X.Y.Z] [--ref GIT_REF]

Commands:
  current   Print the current MARKETING_VERSION from Xcode build settings.
  next      Print the next semantic version inferred from git history.
  bump      Apply the next semantic version to MARKETING_VERSION and increment CURRENT_PROJECT_VERSION.
  tag       Create an annotated release tag (defaults to current MARKETING_VERSION) on the chosen ref.

Rules for --level auto:
  - major: commit subject contains conventional-commit breaking marker ('!:')
           or body contains 'BREAKING CHANGE'
  - minor: commit subject starts with 'feat:' / 'feat(scope):'
           or starts with 'Add ', 'Introduce ', or 'Integrate '
  - patch: everything else

The auto-detection compares commits since the latest semver tag matching vX.Y.Z.
If there are no commits since the latest tag, 'next' returns the current version unchanged.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --level)
      LEVEL="${2:-}"
      shift 2
      ;;
    --version)
      TAG_VERSION="${2:-}"
      shift 2
      ;;
    --ref)
      TAG_REF="${2:-}"
      shift 2
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

normalize_version() {
  local raw="$1"
  if [[ "$raw" =~ ^[0-9]+\.[0-9]+$ ]]; then
    printf "%s.0" "$raw"
  else
    printf "%s" "$raw"
  fi
}

current_version() {
  awk -F ' = ' '/MARKETING_VERSION = / {gsub(/;/, "", $2); print $2; exit}' "${PROJECT_PBXPROJ}"
}

current_build_number() {
  awk -F ' = ' '/CURRENT_PROJECT_VERSION = / {gsub(/;/, "", $2); print $2; exit}' "${PROJECT_PBXPROJ}"
}

latest_semver_tag() {
  git -C "${ROOT_DIR}" tag --list 'v[0-9]*.[0-9]*.[0-9]*' --sort=-version:refname | head -n 1
}

commit_count_since_latest_tag() {
  local tag="$1"
  if [[ -n "${tag}" ]]; then
    git -C "${ROOT_DIR}" rev-list --count "${tag}..HEAD"
  else
    git -C "${ROOT_DIR}" rev-list --count HEAD
  fi
}

subjects_since_latest_tag() {
  local tag="$1"
  if [[ -n "${tag}" ]]; then
    git -C "${ROOT_DIR}" log --format='%s' "${tag}..HEAD"
  else
    git -C "${ROOT_DIR}" log --format='%s'
  fi
}

bodies_since_latest_tag() {
  local tag="$1"
  if [[ -n "${tag}" ]]; then
    git -C "${ROOT_DIR}" log --format='%b' "${tag}..HEAD"
  else
    git -C "${ROOT_DIR}" log --format='%b'
  fi
}

infer_level() {
  local tag commit_count subjects bodies
  tag="$(latest_semver_tag)"
  commit_count="$(commit_count_since_latest_tag "${tag}")"

  if [[ "${commit_count}" == "0" ]]; then
    printf "none"
    return
  fi

  subjects="$(subjects_since_latest_tag "${tag}")"
  bodies="$(bodies_since_latest_tag "${tag}")"

  if printf '%s\n' "${bodies}" | grep -Eiq 'BREAKING CHANGE'; then
    printf "major"
    return
  fi

  if printf '%s\n' "${subjects}" | grep -Eiq '^[a-z]+(\([^)]+\))?!: '; then
    printf "major"
    return
  fi

  if printf '%s\n' "${subjects}" | grep -Eiq '^(feat)(\([^)]+\))?: '; then
    printf "minor"
    return
  fi

  if printf '%s\n' "${subjects}" | grep -Eiq '^(Add |Introduce |Integrate )'; then
    printf "minor"
    return
  fi

  printf "patch"
}

next_version_for_level() {
  local base_version="$1"
  local requested_level="$2"
  local major minor patch

  IFS=. read -r major minor patch <<<"${base_version}"

  case "${requested_level}" in
    none)
      printf "%s" "${base_version}"
      ;;
    major)
      printf "%d.0.0" "$((major + 1))"
      ;;
    minor)
      printf "%d.%d.0" "${major}" "$((minor + 1))"
      ;;
    patch)
      printf "%d.%d.%d" "${major}" "${minor}" "$((patch + 1))"
      ;;
    *)
      echo "Unsupported level: ${requested_level}" >&2
      exit 1
      ;;
  esac
}

resolved_level() {
  if [[ "${LEVEL}" == "auto" ]]; then
    infer_level
  else
    printf "%s" "${LEVEL}"
  fi
}

apply_version() {
  local new_version="$1"
  local new_build="$2"

  perl -0pi -e "s/MARKETING_VERSION = [0-9]+(?:\\.[0-9]+){1,2};/MARKETING_VERSION = ${new_version};/g" "${PROJECT_PBXPROJ}"
  perl -0pi -e "s/CURRENT_PROJECT_VERSION = [0-9]+;/CURRENT_PROJECT_VERSION = ${new_build};/g" "${PROJECT_PBXPROJ}"
}

case "${COMMAND}" in
  current)
    normalize_version "$(current_version)"
    ;;
  next)
    base_version="$(normalize_version "$(current_version)")"
    detected_level="$(resolved_level)"
    next_version_for_level "${base_version}" "${detected_level}"
    ;;
  bump)
    base_version="$(normalize_version "$(current_version)")"
    build_number="$(current_build_number)"
    detected_level="$(resolved_level)"
    next_version="$(next_version_for_level "${base_version}" "${detected_level}")"

    if [[ "${next_version}" == "${base_version}" ]]; then
      printf "Version unchanged at %s (no new commits since latest release tag)\n" "${base_version}"
      exit 0
    fi

    apply_version "${next_version}" "$((build_number + 1))"
    printf "Updated version: %s -> %s (build %s -> %s)\n" "${base_version}" "${next_version}" "${build_number}" "$((build_number + 1))"
    ;;
  tag)
    if [[ -z "${TAG_VERSION}" ]]; then
      TAG_VERSION="$(normalize_version "$(current_version)")"
    else
      TAG_VERSION="$(normalize_version "${TAG_VERSION}")"
    fi

    git -C "${ROOT_DIR}" tag -a "v${TAG_VERSION}" "${TAG_REF}" -m "CoPaRe ${TAG_VERSION}"
    printf "Created tag v%s at %s\n" "${TAG_VERSION}" "${TAG_REF}"
    ;;
  *)
    echo "Unknown command: ${COMMAND}" >&2
    usage >&2
    exit 1
    ;;
esac
