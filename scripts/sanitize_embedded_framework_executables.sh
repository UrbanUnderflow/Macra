#!/bin/sh
set -e

FRAMEWORKS_DIR="${BUILT_PRODUCTS_DIR}/${PRODUCT_NAME}.app/Frameworks"
if [ ! -d "$FRAMEWORKS_DIR" ]; then
  exit 0
fi

SIGNING_IDENTITY="${EXPANDED_CODE_SIGN_IDENTITY:-${CODE_SIGN_IDENTITY:--}}"

plist_get() {
  /usr/libexec/PlistBuddy -c "Print :$2" "$1" 2>/dev/null || true
}

plist_set_or_add() {
  PLIST_FILE="$1"
  PLIST_KEY="$2"
  PLIST_TYPE="$3"
  PLIST_VALUE="$4"

  if /usr/libexec/PlistBuddy -c "Print :${PLIST_KEY}" "$PLIST_FILE" >/dev/null 2>&1; then
    /usr/libexec/PlistBuddy -c "Set :${PLIST_KEY} ${PLIST_VALUE}" "$PLIST_FILE"
  else
    /usr/libexec/PlistBuddy -c "Add :${PLIST_KEY} ${PLIST_TYPE} ${PLIST_VALUE}" "$PLIST_FILE"
  fi
}

safe_executable_name() {
  case "$1" in
    "gRPC-C++")
      printf "%s" "gRPCCxx"
      ;;
    *)
      printf "%s" "$1" | sed 's/[+]/x/g; s/[][]//g; s/[{}()*]//g'
      ;;
  esac
}

resign_framework_if_needed() {
  FRAMEWORK_DIR="$1"

  if [ "${CODE_SIGNING_ALLOWED:-YES}" = "NO" ]; then
    return
  fi

  rm -rf "${FRAMEWORK_DIR}/_CodeSignature"
  /usr/bin/codesign --force --sign "$SIGNING_IDENTITY" --generate-entitlement-der --timestamp=none "$FRAMEWORK_DIR"
}

generate_framework_dsym_if_needed() {
  FRAMEWORK_DIR="$1"
  FRAMEWORK_NAME="$2"
  EXECUTABLE_NAME="$3"

  if [ "${PLATFORM_NAME:-}" != "iphoneos" ]; then
    return
  fi

  if [ "${DEBUG_INFORMATION_FORMAT:-}" != "dwarf-with-dsym" ]; then
    return
  fi

  if [ -z "${DWARF_DSYM_FOLDER_PATH:-}" ] || [ -z "$EXECUTABLE_NAME" ]; then
    return
  fi

  EXECUTABLE_PATH="${FRAMEWORK_DIR}/${EXECUTABLE_NAME}"
  if [ ! -f "$EXECUTABLE_PATH" ]; then
    return
  fi

  mkdir -p "$DWARF_DSYM_FOLDER_PATH"
  /usr/bin/dsymutil "$EXECUTABLE_PATH" -o "${DWARF_DSYM_FOLDER_PATH}/${FRAMEWORK_NAME}.dSYM" >/dev/null 2>&1 || true
}

for FRAMEWORK_DIR in "$FRAMEWORKS_DIR"/*.framework; do
  [ -d "$FRAMEWORK_DIR" ] || continue

  INFO_PLIST="${FRAMEWORK_DIR}/Info.plist"
  [ -f "$INFO_PLIST" ] || continue

  FRAMEWORK_NAME="$(basename "$FRAMEWORK_DIR")"
  EXECUTABLE_NAME="$(plist_get "$INFO_PLIST" CFBundleExecutable)"
  MODIFIED=0

  if [ -n "$EXECUTABLE_NAME" ]; then
    SAFE_EXECUTABLE_NAME="$(safe_executable_name "$EXECUTABLE_NAME")"

    if [ -n "$SAFE_EXECUTABLE_NAME" ] && [ "$SAFE_EXECUTABLE_NAME" != "$EXECUTABLE_NAME" ]; then
      OLD_EXECUTABLE_PATH="${FRAMEWORK_DIR}/${EXECUTABLE_NAME}"
      NEW_EXECUTABLE_PATH="${FRAMEWORK_DIR}/${SAFE_EXECUTABLE_NAME}"

      if [ -f "$OLD_EXECUTABLE_PATH" ] && [ ! -e "$NEW_EXECUTABLE_PATH" ]; then
        mv "$OLD_EXECUTABLE_PATH" "$NEW_EXECUTABLE_PATH"
      fi

      plist_set_or_add "$INFO_PLIST" CFBundleExecutable string "$SAFE_EXECUTABLE_NAME"
      EXECUTABLE_NAME="$SAFE_EXECUTABLE_NAME"
      MODIFIED=1
    fi
  fi

  if [ "$MODIFIED" = "1" ]; then
    resign_framework_if_needed "$FRAMEWORK_DIR"
  fi

  generate_framework_dsym_if_needed "$FRAMEWORK_DIR" "$FRAMEWORK_NAME" "$EXECUTABLE_NAME"
done
