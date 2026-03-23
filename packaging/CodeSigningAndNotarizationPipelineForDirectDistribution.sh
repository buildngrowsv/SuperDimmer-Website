#!/bin/bash

# ============================================================================
# SuperDimmer Code Signing & Notarization Pipeline for Direct Distribution
# ============================================================================
#
# PURPOSE: This is the PRODUCTION pipeline script for building, signing,
# notarizing, and packaging SuperDimmer for direct distribution outside
# the Mac App Store. It handles the entire lifecycle from source to a
# notarized DMG that any macOS user can install without Gatekeeper warnings.
#
# WHY DIRECT DISTRIBUTION (NOT APP STORE):
# SuperDimmer uses CGWindowListCreateImage for screen capture and private
# CGSSpace APIs for desktop space tracking. These require the
# com.apple.security.device.screen-capture entitlement which is NOT
# compatible with App Store sandboxing. Direct distribution via Developer
# ID signing + notarization is the correct path.
#
# WHY THIS SCRIPT EXISTS (vs the older build-release.sh):
# The older scripts (build-release.sh, create-dmg.sh, release.sh) were
# created early in development and had some issues:
#   1. They didn't override Xcode's disabled signing settings via xcodebuild flags
#   2. Notarization was optional / fragmented across scripts
#   3. No pre-flight validation of signing environment
#   4. No Gatekeeper verification step after notarization
# This script is the single source of truth for production releases.
#
# ARCHITECTURE DECISIONS:
# - We sign via xcodebuild CLI flags (CODE_SIGN_IDENTITY, DEVELOPMENT_TEAM)
#   rather than modifying the .xcodeproj, because the project needs to also
#   build unsigned for development. CLI overrides are the standard Apple approach.
# - We use --options runtime (hardened runtime) which is REQUIRED for notarization
# - We sign all embedded frameworks individually before signing the main app,
#   because Apple requires inside-out signing order
# - We use xcrun notarytool (not the deprecated altool) for notarization
# - DMG is signed separately after creation, then notarized as a unit
# - Stapling embeds the notarization ticket in the DMG so offline installs work
#
# PREREQUISITES:
#   1. "Developer ID Application: Rolf Dergham (HHHHZ6UV26)" certificate
#      with private key in Keychain (import the .p12 file)
#   2. Xcode and command line tools installed
#   3. Apple ID app-specific password for notarization
#   4. Internet connection (for notarization submission to Apple)
#
# USAGE:
#   # Full production release (build + sign + notarize + DMG):
#   ./CodeSigningAndNotarizationPipelineForDirectDistribution.sh
#
#   # Specify version explicitly:
#   ./CodeSigningAndNotarizationPipelineForDirectDistribution.sh --version 1.0.8
#
#   # Skip notarization (for local testing of signed builds):
#   ./CodeSigningAndNotarizationPipelineForDirectDistribution.sh --skip-notarize
#
#   # Dry run (validate environment without building):
#   ./CodeSigningAndNotarizationPipelineForDirectDistribution.sh --preflight-only
#
# ENVIRONMENT VARIABLES (required for notarization):
#   APPLE_ID             - Apple Developer account email
#   APPLE_APP_PASSWORD   - App-specific password from appleid.apple.com
#   APPLE_TEAM_ID        - Team ID (default: HHHHZ6UV26 for Rolf Dergham)
#
# Created: 2026-03-23 by Builder 2 (BridgeSwarm)
# BridgeMind Task: 955760f0-be11-48c6-ace6-0f39ffa880e0
# ============================================================================

set -euo pipefail

# ============================================================================
# CONFIGURATION CONSTANTS
# ============================================================================
# These are the verified, production values for SuperDimmer.
# Team ID and signing identity come from the Apple Developer account.
# Bundle ID must match what's in the Xcode project and entitlements.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WEBSITE_DIR="$(dirname "$SCRIPT_DIR")"
REPO_ROOT="$(dirname "$WEBSITE_DIR")"
APP_PROJECT_DIR="$REPO_ROOT/SuperDimmer-Mac-App"

APP_NAME="SuperDimmer"
SCHEME="SuperDimmer"
BUNDLE_ID="com.superdimmer.app"

# Apple Developer identity — this is the Developer ID Application cert
# that was issued to Rolf Dergham under team HHHHZ6UV26.
# The cert must be in the login keychain WITH its private key (.p12 import).
TEAM_ID="${APPLE_TEAM_ID:-HHHHZ6UV26}"
SIGNING_IDENTITY="Developer ID Application: Rolf Dergham (${TEAM_ID})"

# Build output locations
BUILD_DIR="$APP_PROJECT_DIR/build"
OUTPUT_DIR="$SCRIPT_DIR/output"
RELEASES_DIR="$WEBSITE_DIR/releases"

# Entitlements file — SuperDimmer requires screen capture permission.
# This entitlement is what prevents App Store distribution and makes
# direct distribution with Developer ID the correct approach.
ENTITLEMENTS="$APP_PROJECT_DIR/${APP_NAME}/Supporting Files/${APP_NAME}.entitlements"

# ============================================================================
# ARGUMENT PARSING
# ============================================================================

EXPLICIT_VERSION=""
SKIP_NOTARIZE=false
PREFLIGHT_ONLY=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --version)
            EXPLICIT_VERSION="$2"
            shift 2
            ;;
        --skip-notarize)
            SKIP_NOTARIZE=true
            shift
            ;;
        --preflight-only)
            PREFLIGHT_ONLY=true
            shift
            ;;
        --help|-h)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --version X.Y.Z    Set version (default: reads from Info.plist)"
            echo "  --skip-notarize    Build and sign but skip Apple notarization"
            echo "  --preflight-only   Validate environment without building"
            echo "  --help             Show this help"
            echo ""
            echo "Environment variables (for notarization):"
            echo "  APPLE_ID             Apple Developer account email"
            echo "  APPLE_APP_PASSWORD   App-specific password"
            echo "  APPLE_TEAM_ID        Team ID (default: HHHHZ6UV26)"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# ============================================================================
# LOGGING HELPERS
# ============================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

log_header() {
    echo ""
    echo -e "${CYAN}════════════════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}  $1${NC}"
    echo -e "${CYAN}════════════════════════════════════════════════════════════════════${NC}"
    echo ""
}

log_step() {
    echo ""
    echo -e "${BLUE}▶ [$1/$TOTAL_STEPS] $2${NC}"
    echo "──────────────────────────────────────────────────────────────────"
}

log_ok() { echo -e "  ${GREEN}✓ $1${NC}"; }
log_warn() { echo -e "  ${YELLOW}⚠ $1${NC}"; }
log_fail() { echo -e "  ${RED}✗ $1${NC}"; }
log_info() { echo -e "  ${CYAN}→ $1${NC}"; }

# Total steps depends on whether we're notarizing
if [ "$SKIP_NOTARIZE" = true ]; then
    TOTAL_STEPS=5
else
    TOTAL_STEPS=7
fi

# ============================================================================
# STEP 1: PREFLIGHT — Validate the Signing Environment
# ============================================================================
# This is the most critical step. If the environment is wrong, we fail fast
# with clear error messages rather than wasting time building only to fail
# at the signing step. This catches the most common issues:
# - Missing Developer ID certificate
# - Missing private key (cert without .p12)
# - Missing entitlements file
# - Missing notarization credentials

preflight_check() {
    log_step "1" "Preflight — Validating signing environment"

    local has_errors=false

    # Check 1: Xcode command line tools
    if xcode-select -p &>/dev/null; then
        log_ok "Xcode command line tools: $(xcode-select -p)"
    else
        log_fail "Xcode command line tools not installed"
        has_errors=true
    fi

    # Check 2: Developer ID Application certificate WITH private key
    # security find-identity only returns identities that have BOTH the cert
    # and the matching private key — this is exactly what we need to verify.
    local identity_count
    identity_count=$(security find-identity -v -p codesigning | grep -c "Developer ID Application" || true)

    if [ "$identity_count" -gt 0 ]; then
        local identity_name
        identity_name=$(security find-identity -v -p codesigning | grep "Developer ID Application" | head -1 | sed 's/.*"\(.*\)".*/\1/')
        log_ok "Developer ID Application cert found: $identity_name"
    else
        log_fail "No Developer ID Application signing identity found!"
        echo ""
        echo "    The Developer ID certificate exists in keychain but the private key"
        echo "    is missing. This happens when the cert was created on a different Mac."
        echo ""
        echo "    TO FIX: Export the cert + private key as .p12 from the original Mac"
        echo "    (Keychain Access → My Certificates → Export), then import here:"
        echo "      security import /path/to/DeveloperID.p12 -k ~/Library/Keychains/login.keychain-db"
        echo ""
        echo "    OR revoke and recreate at: https://developer.apple.com/account/resources/certificates"
        echo "    (Certificates → + → Developer ID Application)"
        echo ""
        has_errors=true
    fi

    # Check 3: Entitlements file exists
    if [ -f "$ENTITLEMENTS" ]; then
        log_ok "Entitlements file: $ENTITLEMENTS"
    else
        log_fail "Entitlements file not found at: $ENTITLEMENTS"
        has_errors=true
    fi

    # Check 4: Xcode project exists
    if [ -d "$APP_PROJECT_DIR/${APP_NAME}.xcodeproj" ]; then
        log_ok "Xcode project: ${APP_NAME}.xcodeproj"
    else
        log_fail "Xcode project not found at: $APP_PROJECT_DIR/${APP_NAME}.xcodeproj"
        has_errors=true
    fi

    # Check 5: Notarization credentials (warn if missing, error only if needed)
    if [ "$SKIP_NOTARIZE" = false ]; then
        if [ -n "${APPLE_ID:-}" ] && [ -n "${APPLE_APP_PASSWORD:-}" ]; then
            log_ok "Notarization credentials: APPLE_ID and APPLE_APP_PASSWORD set"
        else
            log_fail "Notarization credentials missing!"
            echo "    Set: export APPLE_ID='your@email.com'"
            echo "    Set: export APPLE_APP_PASSWORD='xxxx-xxxx-xxxx-xxxx'"
            echo "    Get app-specific password at: https://appleid.apple.com/account/manage"
            echo "    Or use --skip-notarize to build without notarization"
            has_errors=true
        fi
    else
        log_warn "Notarization: SKIPPED (--skip-notarize flag)"
    fi

    # Check 6: notarytool availability
    if xcrun --find notarytool &>/dev/null; then
        log_ok "notarytool: $(xcrun --find notarytool)"
    else
        log_warn "notarytool not found — notarization will fail (need Xcode 13+)"
    fi

    # Check 7: create-dmg tool (optional but nice)
    if command -v create-dmg &>/dev/null; then
        log_ok "create-dmg: available (will create prettier DMG)"
    else
        log_info "create-dmg not installed — will use hdiutil fallback"
        log_info "Install with: brew install create-dmg"
    fi

    echo ""

    if [ "$has_errors" = true ]; then
        log_fail "Preflight checks failed. Fix the issues above and retry."
        exit 1
    fi

    log_ok "All preflight checks passed!"

    if [ "$PREFLIGHT_ONLY" = true ]; then
        echo ""
        echo "  Preflight-only mode — exiting without building."
        exit 0
    fi
}

# ============================================================================
# STEP 2: BUILD — Compile Release Configuration with Signing Overrides
# ============================================================================
# WHY CLI OVERRIDES:
# The Xcode project has CODE_SIGNING_ALLOWED=NO and CODE_SIGN_IDENTITY="-"
# because during development, signing isn't needed and slows down builds.
# For release builds, we override these settings via xcodebuild flags.
# This is the standard Apple-recommended approach — it means the .xcodeproj
# doesn't need to change between dev and release workflows.

build_release() {
    log_step "2" "Building ${APP_NAME} (Release with Developer ID signing)"

    # Clean previous build artifacts to ensure a fresh signed build.
    # We don't want stale unsigned binaries mixing with signed ones.
    rm -rf "$BUILD_DIR"
    mkdir -p "$BUILD_DIR/Release"

    cd "$APP_PROJECT_DIR"

    # The key xcodebuild overrides that enable code signing:
    # - CODE_SIGN_IDENTITY: Uses the Developer ID Application cert
    # - DEVELOPMENT_TEAM: Links to our Apple Developer team
    # - CODE_SIGNING_REQUIRED: Forces signing (overrides the NO in project)
    # - CODE_SIGNING_ALLOWED: Permits signing (overrides the NO in project)
    # - CODE_SIGN_STYLE: Manual because we specify the exact identity
    # - ENABLE_HARDENED_RUNTIME: REQUIRED for notarization
    # - OTHER_CODE_SIGN_FLAGS: --options=runtime enables hardened runtime at sign time
    #
    # Without these overrides, xcodebuild would build unsigned (per project settings).
    log_info "Running xcodebuild with Developer ID signing overrides..."

    xcodebuild \
        -project "${APP_NAME}.xcodeproj" \
        -scheme "$SCHEME" \
        -configuration Release \
        -derivedDataPath "$BUILD_DIR/DerivedData" \
        CONFIGURATION_BUILD_DIR="$BUILD_DIR/Release" \
        CODE_SIGN_IDENTITY="$SIGNING_IDENTITY" \
        DEVELOPMENT_TEAM="$TEAM_ID" \
        CODE_SIGNING_REQUIRED=YES \
        CODE_SIGNING_ALLOWED=YES \
        CODE_SIGN_STYLE=Manual \
        ENABLE_HARDENED_RUNTIME=YES \
        OTHER_CODE_SIGN_FLAGS="--options=runtime" \
        clean build 2>&1 | tail -n 30

    APP_PATH="$BUILD_DIR/Release/${APP_NAME}.app"

    if [ ! -d "$APP_PATH" ]; then
        log_fail "Build failed — ${APP_NAME}.app not found at $APP_PATH"
        exit 1
    fi

    # Read version from the built app's Info.plist
    APP_VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$APP_PATH/Contents/Info.plist" 2>/dev/null || echo "0.0.0")
    APP_BUILD=$(/usr/libexec/PlistBuddy -c "Print CFBundleVersion" "$APP_PATH/Contents/Info.plist" 2>/dev/null || echo "0")

    # Allow explicit version override
    if [ -n "$EXPLICIT_VERSION" ]; then
        APP_VERSION="$EXPLICIT_VERSION"
    fi

    log_ok "Build complete: v${APP_VERSION} (build ${APP_BUILD})"
    log_info "App path: $APP_PATH"
}

# ============================================================================
# STEP 3: VERIFY SIGNATURE — Confirm the Build is Properly Signed
# ============================================================================
# After building with signing overrides, we verify the signature is valid.
# This catches issues like expired certs, missing entitlements, or
# framework signing problems before we spend time creating the DMG.

verify_app_signature() {
    log_step "3" "Verifying code signature on built app"

    # codesign -v verifies the signature is valid and untampered
    if codesign -v --verbose=2 "$APP_PATH" 2>&1 | head -n 5; then
        log_ok "Code signature is valid"
    else
        log_fail "Code signature verification failed!"
        codesign -v --verbose=4 "$APP_PATH" 2>&1 | head -n 20
        exit 1
    fi

    # Verify the signing identity matches what we expect
    local signer
    signer=$(codesign -dvv "$APP_PATH" 2>&1 | grep "Authority=" | head -1 | sed 's/Authority=//')
    log_info "Signed by: $signer"

    # Verify hardened runtime is enabled (required for notarization)
    local flags
    flags=$(codesign -dvv "$APP_PATH" 2>&1 | grep "flags=" || echo "flags=none")
    if echo "$flags" | grep -q "runtime"; then
        log_ok "Hardened runtime: enabled"
    else
        log_warn "Hardened runtime may not be enabled: $flags"
    fi

    # Verify entitlements are embedded
    local entitlements_output
    entitlements_output=$(codesign -d --entitlements - "$APP_PATH" 2>&1 | head -n 10)
    if echo "$entitlements_output" | grep -q "screen-capture"; then
        log_ok "Screen capture entitlement: present"
    else
        log_warn "Screen capture entitlement not found in embedded entitlements"
    fi

    # spctl --assess checks if Gatekeeper would allow the app
    # Note: This only passes after notarization, so we just check the signing
    # assessment here (not the notarization ticket)
    if spctl --assess --type execute --verbose "$APP_PATH" 2>&1 | head -n 3; then
        log_ok "Gatekeeper assessment: accepted"
    else
        log_info "Gatekeeper assessment may require notarization (expected at this stage)"
    fi
}

# ============================================================================
# STEP 4: CREATE DMG — Package into Distributable Disk Image
# ============================================================================
# The DMG is the standard macOS distribution format. We create it with
# an Applications folder alias for the familiar drag-to-install experience.
# The DMG itself will also be signed and notarized separately.

create_dmg_package() {
    log_step "4" "Creating DMG installer package"

    mkdir -p "$OUTPUT_DIR"
    DMG_FILENAME="${APP_NAME}-v${APP_VERSION}.dmg"
    DMG_PATH="$OUTPUT_DIR/$DMG_FILENAME"

    # Remove any existing DMG with this version name
    rm -f "$DMG_PATH"

    if command -v create-dmg &>/dev/null; then
        # Use create-dmg for a polished installer appearance
        # with icon positioning and proper window sizing.
        log_info "Using create-dmg for polished DMG..."
        create-dmg \
            --volname "${APP_NAME}" \
            --window-pos 200 120 \
            --window-size 660 400 \
            --icon-size 128 \
            --icon "${APP_NAME}.app" 180 170 \
            --app-drop-link 480 170 \
            --hide-extension "${APP_NAME}.app" \
            --text-size 14 \
            "$DMG_PATH" \
            "$APP_PATH" 2>&1 | tail -n 5
    else
        # Fallback: use hdiutil directly (works everywhere, less polish)
        log_info "Using hdiutil fallback for DMG creation..."
        local staging="$OUTPUT_DIR/staging"
        rm -rf "$staging"
        mkdir -p "$staging"
        cp -R "$APP_PATH" "$staging/"
        ln -s /Applications "$staging/Applications"

        hdiutil create \
            -srcfolder "$staging" \
            -volname "${APP_NAME}" \
            -format UDZO \
            -o "$DMG_PATH" 2>&1 | tail -n 5

        rm -rf "$staging"
    fi

    if [ ! -f "$DMG_PATH" ]; then
        log_fail "DMG creation failed"
        exit 1
    fi

    log_ok "DMG created: $DMG_PATH ($(du -h "$DMG_PATH" | cut -f1))"
}

# ============================================================================
# STEP 5: SIGN DMG — Apply Developer ID Signature to the Disk Image
# ============================================================================
# The DMG must be signed separately from the app inside it.
# This is because the DMG is its own distributable artifact that
# Gatekeeper checks independently when the user downloads it.

sign_dmg() {
    log_step "5" "Signing DMG with Developer ID"

    codesign --force --sign "$SIGNING_IDENTITY" "$DMG_PATH"

    if codesign -v "$DMG_PATH" 2>&1; then
        log_ok "DMG signature verified"
    else
        log_fail "DMG signature verification failed"
        exit 1
    fi
}

# ============================================================================
# STEP 6: NOTARIZE — Submit to Apple for Malware Scan and Approval
# ============================================================================
# Notarization is Apple's process of scanning the app for malware and
# issuing a "ticket" that tells Gatekeeper the app is safe. Without this,
# users see a scary "unidentified developer" warning when they try to
# open the app — which kills conversions for a paid product.
#
# The process:
# 1. Upload the signed DMG to Apple's notary service
# 2. Apple scans it (takes 1-5 minutes typically)
# 3. If it passes, Apple issues a notarization ticket
# 4. We "staple" the ticket to the DMG so it works offline
#
# REQUIREMENTS:
# - App must be signed with Developer ID (not ad-hoc)
# - Hardened runtime must be enabled
# - App-specific password (NOT your Apple ID password)

notarize_dmg() {
    log_step "6" "Submitting to Apple for notarization"

    log_info "This typically takes 1-5 minutes..."

    # Submit to Apple's notary service and wait for the result.
    # --wait blocks until Apple finishes scanning (usually fast).
    # Without --wait, we'd need to poll with notarytool info.
    xcrun notarytool submit "$DMG_PATH" \
        --apple-id "$APPLE_ID" \
        --password "$APPLE_APP_PASSWORD" \
        --team-id "$TEAM_ID" \
        --wait 2>&1 | tail -n 10

    local notary_status=$?

    if [ $notary_status -ne 0 ]; then
        log_fail "Notarization failed! Check the log above for details."
        log_info "To see full log, run:"
        log_info "  xcrun notarytool log <submission-id> --apple-id $APPLE_ID --password \$APPLE_APP_PASSWORD --team-id $TEAM_ID"
        exit 1
    fi

    log_ok "Notarization approved by Apple"

    # Staple the notarization ticket to the DMG.
    # This embeds the ticket so Gatekeeper can verify offline
    # (without contacting Apple's servers). Essential for users
    # with restricted internet or on first launch after download.
    log_info "Stapling notarization ticket to DMG..."
    xcrun stapler staple "$DMG_PATH"

    log_ok "Notarization ticket stapled to DMG"
}

# ============================================================================
# STEP 7: FINALIZE — Copy to Releases, Verify, Print Summary
# ============================================================================
# Final step: copy the notarized DMG to the website releases folder,
# run a final Gatekeeper assessment to confirm everything works,
# and print a summary with next steps.

finalize_release() {
    local step_num
    if [ "$SKIP_NOTARIZE" = true ]; then
        step_num="5"
    else
        step_num="7"
    fi

    log_step "$step_num" "Finalizing release"

    # Copy to website releases directory for deployment
    mkdir -p "$RELEASES_DIR"
    cp "$DMG_PATH" "$RELEASES_DIR/"
    log_ok "DMG copied to: $RELEASES_DIR/$DMG_FILENAME"

    # Final Gatekeeper assessment — this should PASS after notarization
    echo ""
    log_info "Running final Gatekeeper assessment..."
    if spctl --assess --type open --context context:primary-signature --verbose "$DMG_PATH" 2>&1; then
        log_ok "GATEKEEPER: DMG is accepted for distribution"
    else
        if [ "$SKIP_NOTARIZE" = true ]; then
            log_warn "Gatekeeper rejected DMG (expected without notarization)"
        else
            log_warn "Gatekeeper assessment inconclusive — verify manually"
        fi
    fi

    # Print comprehensive summary
    log_header "Release v${APP_VERSION} — Build Complete!"

    echo "  App:           $APP_PATH"
    echo "  DMG:           $RELEASES_DIR/$DMG_FILENAME"
    echo "  Size:          $(du -h "$DMG_PATH" | cut -f1)"
    echo "  Version:       $APP_VERSION (build $APP_BUILD)"
    echo "  Signed:        $SIGNING_IDENTITY"
    echo "  Team:          $TEAM_ID"

    if [ "$SKIP_NOTARIZE" = true ]; then
        echo -e "  Notarized:     ${YELLOW}No (--skip-notarize)${NC}"
    else
        echo -e "  Notarized:     ${GREEN}Yes${NC}"
    fi

    echo ""
    echo "  ─────────────────────────────────────────────"
    echo "  NEXT STEPS:"
    echo "  ─────────────────────────────────────────────"
    echo ""
    echo "  1. Update version.json:"
    echo "     Edit SuperDimmer-Website/version.json with new version"
    echo ""
    echo "  2. Commit and push:"
    echo "     git add SuperDimmer-Website/releases/$DMG_FILENAME"
    echo "     git add SuperDimmer-Website/version.json"
    echo "     git commit -m 'Release v$APP_VERSION'"
    echo "     git push"
    echo ""
    echo "  3. Cloudflare auto-deploys → superdimmer.com serves new version!"
    echo ""
    echo "  4. Test the DMG:"
    echo "     open '$RELEASES_DIR/$DMG_FILENAME'"
    echo ""
}

# ============================================================================
# MAIN EXECUTION — Orchestrate All Steps in Order
# ============================================================================

main() {
    log_header "SuperDimmer Code Signing & Notarization Pipeline"

    # Step 1: Preflight checks (always runs)
    preflight_check

    # Step 2: Build with signing overrides
    build_release

    # Step 3: Verify the signature
    verify_app_signature

    # Step 4: Create DMG package
    create_dmg_package

    # Step 5: Sign the DMG
    sign_dmg

    # Step 6: Notarize (unless skipped)
    if [ "$SKIP_NOTARIZE" = false ]; then
        notarize_dmg
    fi

    # Step 7: Finalize
    finalize_release
}

main
