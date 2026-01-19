#!/bin/bash

# ============================================================================
# SuperDimmer Release Script (Simplified - No Sparkle)
# ============================================================================
# This script handles the complete release workflow:
#   1. Build the app (Release configuration)
#   2. Sign with Developer ID
#   3. Create DMG
#   4. Notarize with Apple (Gatekeeper approval)
#   5. Update version.json
#   6. Copy DMG to releases/ folder
#   7. Generate release notes template
#
# After running, just: git add . && git commit && git push
# Cloudflare Pages auto-deploys → Users get the update!
#
# WHY NO SPARKLE/EDDSA?
# - Website is HTTPS (Cloudflare) - download is secure
# - App is notarized by Apple - Gatekeeper trusts it
# - Simpler setup, no key management needed
#
# USAGE:
#   ./release.sh 1.1.0              # Full release (needs notarization creds)
#   ./release.sh 1.1.0 --skip-sign  # Dev build (no signing/notarization)
#   ./release.sh 1.1.0 --dry-run    # Show what would happen
#
# ENVIRONMENT VARIABLES (for notarization):
#   APPLE_ID           - Apple ID email
#   APPLE_APP_PASSWORD - App-specific password from appleid.apple.com
#   APPLE_TEAM_ID      - Your 10-char Team ID (yours: HHHHZ6UV26)
#
# Created: January 8, 2026
# Updated: January 9, 2026 - Simplified, removed Sparkle/EdDSA
# ============================================================================

set -e  # Exit on any error

# ============================================================================
# COLOR OUTPUT
# ============================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

print_header() {
    echo ""
    echo -e "${CYAN}╔════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${NC}  $1"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

print_step() {
    echo ""
    echo -e "${BLUE}▶ STEP $1: $2${NC}"
    echo "──────────────────────────────────────────────────────────────────────"
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

print_error() {
    echo -e "${RED}❌ ERROR: $1${NC}"
    exit 1
}

print_info() {
    echo -e "${CYAN}ℹ️  $1${NC}"
}

# ============================================================================
# CONFIGURATION
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WEBSITE_DIR="$(dirname "$SCRIPT_DIR")"
APP_PROJECT_DIR="$(dirname "$WEBSITE_DIR")/SuperDimmer-Mac-App"

APP_NAME="SuperDimmer"
SCHEME="SuperDimmer"
BUNDLE_ID="com.superdimmer.com"

# Output locations
BUILD_DIR="$APP_PROJECT_DIR/build"
RELEASES_DIR="$WEBSITE_DIR/releases"
VERSION_JSON="$WEBSITE_DIR/version.json"
RELEASE_NOTES_DIR="$WEBSITE_DIR/release-notes"
OUTPUT_DIR="$SCRIPT_DIR/output"

# Signing identity - auto-detect
SIGNING_IDENTITY="${SIGNING_IDENTITY:-}"

# ============================================================================
# ARGUMENT PARSING
# ============================================================================

VERSION=""
SKIP_SIGN=false
DRY_RUN=false

usage() {
    echo "Usage: $0 VERSION [OPTIONS]"
    echo ""
    echo "VERSION:  The version number (e.g., 1.1.0)"
    echo ""
    echo "OPTIONS:"
    echo "  --skip-sign    Skip code signing and notarization (dev builds)"
    echo "  --dry-run      Show what would happen without doing it"
    echo "  --help         Show this help"
    echo ""
    echo "EXAMPLES:"
    echo "  $0 1.1.0              # Full signed + notarized release"
    echo "  $0 1.1.0 --skip-sign  # Development build (unsigned)"
    echo "  $0 1.1.0 --dry-run    # Preview actions"
    exit 1
}

while [[ $# -gt 0 ]]; do
    case $1 in
        --skip-sign)
            SKIP_SIGN=true
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --help|-h)
            usage
            ;;
        -*)
            echo "Unknown option: $1"
            usage
            ;;
        *)
            if [ -z "$VERSION" ]; then
                VERSION="$1"
            else
                echo "Unexpected argument: $1"
                usage
            fi
            shift
            ;;
    esac
done

if [ -z "$VERSION" ]; then
    echo "Error: VERSION is required"
    usage
fi

# Validate version format (X.Y.Z)
if ! [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    print_error "Invalid version format. Use X.Y.Z (e.g., 1.1.0)"
fi

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

find_signing_identity() {
    if [ -n "$SIGNING_IDENTITY" ]; then
        echo "$SIGNING_IDENTITY"
        return
    fi
    local identity=$(security find-identity -v -p codesigning | grep "Developer ID Application" | head -1 | sed 's/.*"\(.*\)".*/\1/')
    echo "$identity"
}

get_current_build_number() {
    local plist="$APP_PROJECT_DIR/$APP_NAME/Supporting Files/Info.plist"
    if [ -f "$plist" ]; then
        /usr/libexec/PlistBuddy -c "Print CFBundleVersion" "$plist" 2>/dev/null || echo "0"
    else
        echo "0"
    fi
}

update_info_plist() {
    local new_version="$1"
    local new_build="$2"
    local plist="$APP_PROJECT_DIR/$APP_NAME/Supporting Files/Info.plist"
    
    if [ "$DRY_RUN" = true ]; then
        print_info "[DRY RUN] Would update Info.plist: v$new_version (build $new_build)"
        return
    fi
    
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $new_version" "$plist"
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $new_build" "$plist"
}

update_version_json() {
    local version="$1"
    local build="$2"
    local dmg_filename="$3"
    
    if [ "$DRY_RUN" = true ]; then
        print_info "[DRY RUN] Would update version.json with v$version"
        return
    fi
    
    local release_date=$(date "+%Y-%m-%d")
    
    cat > "$VERSION_JSON" << EOF
{
  "version": "$version",
  "build": $build,
  "downloadURL": "https://superdimmer.com/releases/$dmg_filename",
  "releaseNotesURL": "https://superdimmer.com/release-notes/v${version}.html",
  "minSystemVersion": "13.0",
  "releaseDate": "$release_date"
}
EOF
    
    print_success "version.json updated to v$version"
}

create_release_notes_template() {
    local version="$1"
    local notes_file="$RELEASE_NOTES_DIR/v${version}.html"
    
    if [ "$DRY_RUN" = true ]; then
        print_info "[DRY RUN] Would create release notes at: $notes_file"
        return
    fi
    
    mkdir -p "$RELEASE_NOTES_DIR"
    
    if [ -f "$notes_file" ]; then
        print_warning "Release notes already exist: $notes_file"
        return
    fi
    
    local date_str=$(date "+%B %d, %Y")
    
    cat > "$notes_file" << EOF
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>SuperDimmer v${version} Release Notes</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
            font-family: -apple-system, BlinkMacSystemFont, sans-serif;
            background: #1a1816;
            color: #f5f2eb;
            padding: 20px;
            line-height: 1.6;
            font-size: 14px;
        }
        h1 { font-size: 1.5rem; font-weight: 600; margin-bottom: 8px; }
        .version-badge {
            display: inline-block;
            background: linear-gradient(135deg, #e8a838 0%, #d4762c 100%);
            color: #1a1816;
            padding: 4px 12px;
            border-radius: 20px;
            font-size: 12px;
            font-weight: 600;
            margin-bottom: 16px;
        }
        .date { color: #6b665c; font-size: 13px; margin-bottom: 20px; }
        h2 { font-size: 1.1rem; color: #e8a838; margin-top: 20px; margin-bottom: 10px; font-weight: 500; }
        ul { list-style: none; padding-left: 0; }
        li { position: relative; padding-left: 20px; margin-bottom: 8px; color: #a39e94; }
        li::before { content: "•"; position: absolute; left: 0; color: #e8a838; font-weight: bold; }
        .highlight { color: #f5f2eb; font-weight: 500; }
        .footer { margin-top: 24px; padding-top: 16px; border-top: 1px solid rgba(245, 242, 235, 0.1); font-size: 12px; color: #6b665c; }
        a { color: #e8a838; text-decoration: none; }
    </style>
</head>
<body>
    <h1>SuperDimmer</h1>
    <span class="version-badge">v${version}</span>
    <p class="date">${date_str}</p>
    
    <h2>🆕 What's New</h2>
    <ul>
        <li><span class="highlight">New Feature</span> — Description here</li>
    </ul>
    
    <h2>🐛 Bug Fixes</h2>
    <ul>
        <li>Fixed issue with...</li>
    </ul>
    
    <h2>🔧 Improvements</h2>
    <ul>
        <li>Performance improvements</li>
    </ul>
    
    <div class="footer">
        <p>Questions? Visit <a href="https://superdimmer.com">superdimmer.com</a></p>
    </div>
</body>
</html>
EOF
    
    print_success "Release notes template created: $notes_file"
    print_warning "Remember to edit the release notes before pushing!"
}

# ============================================================================
# MAIN RELEASE PROCESS
# ============================================================================

main() {
    print_header "SuperDimmer Release Script v$VERSION"
    
    echo "  Configuration:"
    echo "  ─────────────────────────────────────────────"
    echo "  Version:     $VERSION"
    echo "  App Project: $APP_PROJECT_DIR"
    echo "  Website:     $WEBSITE_DIR"
    echo "  Skip Sign:   $SKIP_SIGN"
    echo "  Dry Run:     $DRY_RUN"
    echo ""
    
    # Verify directories exist
    if [ ! -d "$APP_PROJECT_DIR" ]; then
        print_error "App project not found at: $APP_PROJECT_DIR"
    fi
    
    # Calculate build number
    local current_build=$(get_current_build_number)
    local new_build=$((current_build + 1))
    echo "  Build:       $current_build → $new_build"
    
    # Check signing identity
    if [ "$SKIP_SIGN" = false ]; then
        SIGNING_IDENTITY=$(find_signing_identity)
        if [ -z "$SIGNING_IDENTITY" ]; then
            print_error "No Developer ID certificate found. Use --skip-sign for dev builds."
        fi
        echo "  Signing ID:  ${SIGNING_IDENTITY:0:50}..."
    fi
    
    echo ""
    
    if [ "$DRY_RUN" = true ]; then
        print_warning "DRY RUN MODE - No changes will be made"
        echo ""
    fi
    
    # ─────────────────────────────────────────────────────────────────────────
    # STEP 1: Update Info.plist
    # ─────────────────────────────────────────────────────────────────────────
    print_step "1/6" "Updating version in Info.plist"
    update_info_plist "$VERSION" "$new_build"
    print_success "Info.plist updated: v$VERSION (build $new_build)"
    
    # ─────────────────────────────────────────────────────────────────────────
    # STEP 2: Build Release
    # ─────────────────────────────────────────────────────────────────────────
    print_step "2/6" "Building $APP_NAME (Release configuration)"
    
    if [ "$DRY_RUN" = true ]; then
        print_info "[DRY RUN] Would run xcodebuild..."
    else
        mkdir -p "$BUILD_DIR/Release"
        cd "$APP_PROJECT_DIR"
        
        xcodebuild \
            -project "${APP_NAME}.xcodeproj" \
            -scheme "$SCHEME" \
            -configuration Release \
            -derivedDataPath "$BUILD_DIR/DerivedData" \
            CONFIGURATION_BUILD_DIR="$BUILD_DIR/Release" \
            clean build 2>&1 | tail -n 20
        
        APP_PATH="$BUILD_DIR/Release/${APP_NAME}.app"
        
        if [ ! -d "$APP_PATH" ]; then
            print_error "Build failed - app not found at $APP_PATH"
        fi
        
        print_success "Build complete"
    fi
    
    APP_PATH="$BUILD_DIR/Release/${APP_NAME}.app"
    
    # ─────────────────────────────────────────────────────────────────────────
    # STEP 3: Code Sign with Developer ID
    # ─────────────────────────────────────────────────────────────────────────
    print_step "3/6" "Code signing with Developer ID"
    
    if [ "$SKIP_SIGN" = true ]; then
        print_warning "Skipping code signing (--skip-sign)"
    elif [ "$DRY_RUN" = true ]; then
        print_info "[DRY RUN] Would sign with: $SIGNING_IDENTITY"
    else
        # Sign frameworks first if any exist
        if [ -d "$APP_PATH/Contents/Frameworks" ]; then
            find "$APP_PATH/Contents/Frameworks" \( -name "*.framework" -o -name "*.dylib" \) 2>/dev/null | while read framework; do
                codesign --force --sign "$SIGNING_IDENTITY" --options runtime "$framework" 2>/dev/null || true
            done
        fi
        
        # Sign the main app
        codesign --force --deep --verify --verbose \
            --sign "$SIGNING_IDENTITY" \
            --options runtime \
            --entitlements "$APP_PROJECT_DIR/${APP_NAME}/Supporting Files/${APP_NAME}.entitlements" \
            "$APP_PATH"
        
        codesign -v "$APP_PATH"
        print_success "Code signed with Developer ID"
    fi
    
    # ─────────────────────────────────────────────────────────────────────────
    # STEP 4: Create DMG & Notarize
    # ─────────────────────────────────────────────────────────────────────────
    print_step "4/6" "Creating DMG and notarizing"
    
    DMG_FILENAME="${APP_NAME}-v${VERSION}.dmg"
    DMG_PATH="$OUTPUT_DIR/$DMG_FILENAME"
    
    if [ "$DRY_RUN" = true ]; then
        print_info "[DRY RUN] Would create DMG: $DMG_PATH"
    else
        mkdir -p "$OUTPUT_DIR"
        cd "$SCRIPT_DIR"
        
        # Create DMG
        if [ -f "./create-dmg.sh" ]; then
            ./create-dmg.sh "$APP_PATH" 2>&1 | tail -n 10
        else
            # Fallback to hdiutil
            local staging="$OUTPUT_DIR/staging"
            rm -rf "$staging"
            mkdir -p "$staging"
            cp -R "$APP_PATH" "$staging/"
            ln -s /Applications "$staging/Applications"
            rm -f "$DMG_PATH"
            hdiutil create -srcfolder "$staging" -volname "$APP_NAME" -format UDZO -o "$DMG_PATH"
            rm -rf "$staging"
        fi
        
        # Rename if needed
        if [ -f "$OUTPUT_DIR/${APP_NAME}-v${VERSION}.dmg" ] && [ "$OUTPUT_DIR/${APP_NAME}-v${VERSION}.dmg" != "$DMG_PATH" ]; then
            mv "$OUTPUT_DIR/${APP_NAME}-v${VERSION}.dmg" "$DMG_PATH" 2>/dev/null || true
        fi
        
        if [ ! -f "$DMG_PATH" ]; then
            print_error "DMG creation failed"
        fi
        
        print_success "DMG created: $(du -h "$DMG_PATH" | cut -f1)"
        
        # Notarize if not skipping
        if [ "$SKIP_SIGN" = false ]; then
            if [ -z "$APPLE_ID" ] || [ -z "$APPLE_APP_PASSWORD" ] || [ -z "$APPLE_TEAM_ID" ]; then
                print_warning "Notarization skipped - credentials not set"
                print_info "Set APPLE_ID, APPLE_APP_PASSWORD, APPLE_TEAM_ID to enable"
            else
                print_info "Submitting for notarization (this takes 1-5 minutes)..."
                codesign --force --sign "$SIGNING_IDENTITY" "$DMG_PATH"
                
                xcrun notarytool submit "$DMG_PATH" \
                    --apple-id "$APPLE_ID" \
                    --password "$APPLE_APP_PASSWORD" \
                    --team-id "$APPLE_TEAM_ID" \
                    --wait
                
                xcrun stapler staple "$DMG_PATH"
                print_success "Notarization complete!"
            fi
        fi
    fi
    
    # ─────────────────────────────────────────────────────────────────────────
    # STEP 5: Update version.json
    # ─────────────────────────────────────────────────────────────────────────
    print_step "5/6" "Updating version.json"
    update_version_json "$VERSION" "$new_build" "$DMG_FILENAME"
    
    # ─────────────────────────────────────────────────────────────────────────
    # STEP 6: Copy to releases/ and create release notes
    # ─────────────────────────────────────────────────────────────────────────
    print_step "6/6" "Finalizing release"
    
    if [ "$DRY_RUN" = true ]; then
        print_info "[DRY RUN] Would copy DMG to $RELEASES_DIR/"
    else
        mkdir -p "$RELEASES_DIR"
        cp "$DMG_PATH" "$RELEASES_DIR/"
        print_success "DMG copied to releases/"
        
        create_release_notes_template "$VERSION"
    fi
    
    # ─────────────────────────────────────────────────────────────────────────
    # SUMMARY
    # ─────────────────────────────────────────────────────────────────────────
    print_header "Release v$VERSION Complete! 🎉"
    
    echo "  📦 App:           $APP_PATH"
    echo "  💿 DMG:           $RELEASES_DIR/$DMG_FILENAME"
    echo "  📋 version.json:  $VERSION_JSON"
    echo "  📝 Release Notes: $RELEASE_NOTES_DIR/v${VERSION}.html"
    echo ""
    
    if [ "$SKIP_SIGN" = true ]; then
        echo -e "  ${YELLOW}⚠️  Not signed (development build)${NC}"
    else
        echo -e "  ${GREEN}✅ Signed with Developer ID${NC}"
    fi
    
    echo ""
    echo "  ─────────────────────────────────────────────────────────────────"
    echo "  NEXT STEPS:"
    echo "  ─────────────────────────────────────────────────────────────────"
    echo ""
    echo "  1. Edit release notes (optional):"
    echo "     open \"$RELEASE_NOTES_DIR/v${VERSION}.html\""
    echo ""
    echo "  2. Commit and push:"
    echo "     cd \"$WEBSITE_DIR\""
    echo "     git add ."
    echo "     git commit -m \"Release v$VERSION\""
    echo "     git push"
    echo ""
    echo "  3. Cloudflare auto-deploys → Users see update available! 🚀"
    echo ""
}

# Run the main function
main
