#!/bin/bash

# ============================================================================
# SuperDimmer — Code Signing Environment Verification & Setup Guide
# ============================================================================
#
# PURPOSE: This script checks whether your Mac is properly set up for
# signing and notarizing SuperDimmer for direct distribution. It provides
# clear, actionable instructions for any missing components.
#
# WHY THIS EXISTS: Code signing has many moving parts (certificates, private
# keys, entitlements, notarization credentials, Xcode settings). When any
# one piece is missing, the error messages from Apple's tools are cryptic.
# This script checks everything upfront and tells you exactly what to fix.
#
# USAGE:
#   ./VerifyCodeSigningEnvironmentSetup.sh
#
# Created: 2026-03-23 by Builder 2 (BridgeSwarm)
# ============================================================================

set -uo pipefail

# ============================================================================
# CONFIGURATION — Must Match the Pipeline Script
# ============================================================================
# These values are duplicated from the pipeline script so this verification
# can be run independently. They must stay in sync.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WEBSITE_DIR="$(dirname "$SCRIPT_DIR")"
REPO_ROOT="$(dirname "$WEBSITE_DIR")"
APP_PROJECT_DIR="$REPO_ROOT/SuperDimmer-Mac-App"

APP_NAME="SuperDimmer"
TEAM_ID="${APPLE_TEAM_ID:-HHHHZ6UV26}"
EXPECTED_IDENTITY="Developer ID Application: Rolf Dergham (${TEAM_ID})"
ENTITLEMENTS="$APP_PROJECT_DIR/${APP_NAME}/Supporting Files/${APP_NAME}.entitlements"
CERTS_DIR="$REPO_ROOT/Certs"

# ============================================================================
# COLOR OUTPUT
# ============================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

pass() { echo -e "  ${GREEN}✓ PASS${NC}  $1"; }
fail() { echo -e "  ${RED}✗ FAIL${NC}  $1"; FAILURES=$((FAILURES + 1)); }
warn() { echo -e "  ${YELLOW}⚠ WARN${NC}  $1"; WARNINGS=$((WARNINGS + 1)); }
info() { echo -e "  ${CYAN}→ INFO${NC}  $1"; }

FAILURES=0
WARNINGS=0

# ============================================================================
# CHECK 1: Xcode and Command Line Tools
# ============================================================================
echo ""
echo "═══════════════════════════════════════════════════════"
echo "  SuperDimmer Code Signing Environment Check"
echo "═══════════════════════════════════════════════════════"
echo ""
echo "─── Xcode & Tools ───────────────────────────────────"

if xcode-select -p &>/dev/null; then
    pass "Xcode CLT: $(xcode-select -p)"
else
    fail "Xcode command line tools not installed"
    info "Fix: xcode-select --install"
fi

XCODE_VERSION=$(xcodebuild -version 2>/dev/null | head -1 || echo "not found")
if [[ "$XCODE_VERSION" == *"Xcode"* ]]; then
    pass "Xcode: $XCODE_VERSION"
else
    fail "xcodebuild not working: $XCODE_VERSION"
fi

if xcrun --find notarytool &>/dev/null; then
    pass "notarytool: available"
else
    fail "notarytool not found (need Xcode 13+)"
fi

if xcrun --find stapler &>/dev/null; then
    pass "stapler: available"
else
    fail "stapler not found"
fi

# ============================================================================
# CHECK 2: Developer ID Certificate
# ============================================================================
echo ""
echo "─── Developer ID Certificate ────────────────────────"

# Check if the certificate exists in keychain (cert only, no key needed)
CERT_EXISTS=$(security find-certificate -a -c "Developer ID Application" ~/Library/Keychains/login.keychain-db 2>/dev/null | grep -c "labl.*Developer ID Application" || true)

if [ "$CERT_EXISTS" -gt 0 ]; then
    CERT_NAME=$(security find-certificate -a -c "Developer ID Application" ~/Library/Keychains/login.keychain-db 2>/dev/null | grep "labl" | head -1 | sed 's/.*"\(.*\)"/\1/')
    pass "Certificate in keychain: $CERT_NAME"
else
    fail "Developer ID Application certificate not in keychain"
    if [ -f "$CERTS_DIR/developerID_application.cer" ]; then
        info "Certificate file exists at: $CERTS_DIR/developerID_application.cer"
        info "Import with: security import '$CERTS_DIR/developerID_application.cer' -k ~/Library/Keychains/login.keychain-db"
    else
        info "Download from: https://developer.apple.com/account/resources/certificates"
    fi
fi

# Check if private key exists for the signing identity
# find-identity only returns identities with both cert AND private key
IDENTITY_COUNT=$(security find-identity -v -p codesigning 2>/dev/null | grep -c "Developer ID Application" || true)

if [ "$IDENTITY_COUNT" -gt 0 ]; then
    IDENTITY_NAME=$(security find-identity -v -p codesigning 2>/dev/null | grep "Developer ID Application" | head -1 | sed 's/.*"\(.*\)".*/\1/')
    pass "Private key present: $IDENTITY_NAME"
    pass "Ready to sign with Developer ID!"
else
    fail "Private key MISSING for Developer ID Application certificate"
    echo ""
    echo "    ┌──────────────────────────────────────────────────────────┐"
    echo "    │  The certificate exists but the private key is missing.  │"
    echo "    │  Without the private key, code signing is impossible.    │"
    echo "    └──────────────────────────────────────────────────────────┘"
    echo ""
    echo "    HOW TO FIX (choose one):"
    echo ""
    echo "    Option A — Import .p12 from original Mac:"
    echo "      On the Mac where the cert was created:"
    echo "        1. Open Keychain Access"
    echo "        2. Go to 'My Certificates'"
    echo "        3. Find 'Developer ID Application: Rolf Dergham'"
    echo "        4. Right-click → Export Items → Save as .p12"
    echo "        5. Transfer .p12 file to this Mac"
    echo "        6. Run: security import DeveloperID.p12 -k ~/Library/Keychains/login.keychain-db"
    echo ""
    echo "    Option B — Revoke and recreate certificate:"
    echo "      1. Go to: https://developer.apple.com/account/resources/certificates"
    echo "      2. Revoke the existing Developer ID Application cert"
    echo "      3. Create a new one (+ button → Developer ID Application)"
    echo "      4. Download and import the new .cer file"
    echo "      (The private key will be created during CSR generation on THIS Mac)"
    echo ""
fi

# ============================================================================
# CHECK 3: Entitlements and Project Structure
# ============================================================================
echo ""
echo "─── Project Structure ───────────────────────────────"

if [ -f "$ENTITLEMENTS" ]; then
    pass "Entitlements file: $ENTITLEMENTS"

    # Verify screen-capture entitlement is present
    if grep -q "screen-capture" "$ENTITLEMENTS"; then
        pass "Screen capture entitlement: present"
    else
        fail "Screen capture entitlement missing from $ENTITLEMENTS"
    fi
else
    fail "Entitlements file not found: $ENTITLEMENTS"
fi

if [ -d "$APP_PROJECT_DIR/${APP_NAME}.xcodeproj" ]; then
    pass "Xcode project: ${APP_NAME}.xcodeproj"
else
    fail "Xcode project not found at $APP_PROJECT_DIR"
fi

if [ -f "$APP_PROJECT_DIR/${APP_NAME}/Supporting Files/Info.plist" ]; then
    CURRENT_VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$APP_PROJECT_DIR/${APP_NAME}/Supporting Files/Info.plist" 2>/dev/null || echo "unknown")
    CURRENT_BUILD=$(/usr/libexec/PlistBuddy -c "Print CFBundleVersion" "$APP_PROJECT_DIR/${APP_NAME}/Supporting Files/Info.plist" 2>/dev/null || echo "unknown")
    pass "Info.plist: v$CURRENT_VERSION (build $CURRENT_BUILD)"
else
    fail "Info.plist not found"
fi

# ============================================================================
# CHECK 4: Notarization Credentials
# ============================================================================
echo ""
echo "─── Notarization Credentials ────────────────────────"

if [ -n "${APPLE_ID:-}" ]; then
    pass "APPLE_ID: ${APPLE_ID}"
else
    warn "APPLE_ID not set"
    info "Set: export APPLE_ID='your@email.com'"
fi

if [ -n "${APPLE_APP_PASSWORD:-}" ]; then
    pass "APPLE_APP_PASSWORD: ****${APPLE_APP_PASSWORD: -4}"
else
    warn "APPLE_APP_PASSWORD not set"
    info "Create at: https://appleid.apple.com → Sign-In and Security → App-Specific Passwords"
    info "Set: export APPLE_APP_PASSWORD='xxxx-xxxx-xxxx-xxxx'"
fi

if [ -n "${APPLE_TEAM_ID:-}" ]; then
    pass "APPLE_TEAM_ID: ${APPLE_TEAM_ID}"
else
    info "APPLE_TEAM_ID not set (will default to: $TEAM_ID)"
fi

# ============================================================================
# CHECK 5: Optional Tools
# ============================================================================
echo ""
echo "─── Optional Tools ──────────────────────────────────"

if command -v create-dmg &>/dev/null; then
    pass "create-dmg: $(which create-dmg)"
else
    warn "create-dmg not installed (DMG will be less polished)"
    info "Install: brew install create-dmg"
fi

if command -v gh &>/dev/null; then
    pass "GitHub CLI: $(gh --version | head -1)"
else
    info "GitHub CLI not installed (optional, for creating releases)"
fi

# ============================================================================
# SUMMARY
# ============================================================================
echo ""
echo "═══════════════════════════════════════════════════════"

if [ "$FAILURES" -eq 0 ] && [ "$WARNINGS" -eq 0 ]; then
    echo -e "  ${GREEN}ALL CHECKS PASSED — Ready to build and sign!${NC}"
    echo ""
    echo "  Run the pipeline:"
    echo "    ./CodeSigningAndNotarizationPipelineForDirectDistribution.sh"
elif [ "$FAILURES" -eq 0 ]; then
    echo -e "  ${YELLOW}$WARNINGS warning(s), 0 failures — Can build with limitations${NC}"
else
    echo -e "  ${RED}$FAILURES failure(s), $WARNINGS warning(s) — Fix failures before building${NC}"
fi

echo "═══════════════════════════════════════════════════════"
echo ""

exit $FAILURES
