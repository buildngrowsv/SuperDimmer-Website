#!/bin/bash

# ============================================================================
# SuperDimmer FULL Release Script
# ============================================================================
# This is the ONE script to rule them all! Run this to:
#   1. Build the app (Release configuration)
#   2. Sign with Developer ID
#   3. Create DMG
#   4. Notarize with Apple (Gatekeeper approval)
#   5. Sign with EdDSA (Sparkle update verification)
#   6. Auto-update appcast.xml
#   7. Copy DMG to releases/ folder
#   8. Generate release notes template
#
# After running, just: git add . && git commit && git push
# Cloudflare Pages auto-deploys → Users get the update!
#
# USAGE:
#   ./release.sh 1.1.0              # Full release (needs all creds)
#   ./release.sh 1.1.0 --skip-sign  # Dev build (no signing/notarization)
#   ./release.sh 1.1.0 --dry-run    # Show what would happen
#
# PREREQUISITES:
#   - Xcode command line tools
#   - Developer ID certificate in Keychain
#   - Sparkle's sign_update tool (or EdDSA private key)
#   - Environment variables (see below) OR credentials in Keychain
#
# ENVIRONMENT VARIABLES:
#   APPLE_ID           - Apple ID email for notarization
#   APPLE_APP_PASSWORD - App-specific password (or @keychain:AC_PASSWORD)
#   APPLE_TEAM_ID      - Your 10-char Team ID
#   SIGNING_IDENTITY   - Developer ID name (default: auto-detect)
#   SPARKLE_KEY_PATH   - Path to EdDSA private key (if not in Keychain)
#   SPARKLE_BIN        - Path to Sparkle bin folder (auto-detect from SPM)
#
# Created: January 8, 2026
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
BUNDLE_ID="com.superdimmer.app"

# Output locations
BUILD_DIR="$APP_PROJECT_DIR/build"
RELEASES_DIR="$WEBSITE_DIR/releases"
APPCAST_FILE="$WEBSITE_DIR/sparkle/appcast.xml"
RELEASE_NOTES_DIR="$WEBSITE_DIR/release-notes"
OUTPUT_DIR="$SCRIPT_DIR/output"

# Signing identity - auto-detect or use environment variable
SIGNING_IDENTITY="${SIGNING_IDENTITY:-}"

# Sparkle tools location - try to auto-detect
SPARKLE_BIN="${SPARKLE_BIN:-}"

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
    echo "  $0 1.1.0              # Full signed release"
    echo "  $0 1.1.0 --skip-sign  # Development build"
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

# Find signing identity if not provided
find_signing_identity() {
    if [ -n "$SIGNING_IDENTITY" ]; then
        echo "$SIGNING_IDENTITY"
        return
    fi
    
    # Try to find Developer ID Application certificate
    local identity=$(security find-identity -v -p codesigning | grep "Developer ID Application" | head -1 | sed 's/.*"\(.*\)".*/\1/')
    
    if [ -n "$identity" ]; then
        echo "$identity"
    else
        echo ""
    fi
}

# Find Sparkle's sign_update tool
find_sparkle_bin() {
    if [ -n "$SPARKLE_BIN" ] && [ -d "$SPARKLE_BIN" ]; then
        echo "$SPARKLE_BIN"
        return
    fi
    
    # Try common locations
    local paths=(
        "$HOME/Library/Developer/Xcode/DerivedData/SuperDimmer-*/SourcePackages/artifacts/sparkle/Sparkle/bin"
        "$HOME/Sparkle/bin"
        "/usr/local/opt/sparkle/bin"
        "$APP_PROJECT_DIR/.build/artifacts/sparkle/Sparkle/bin"
    )
    
    for pattern in "${paths[@]}"; do
        for path in $pattern; do
            if [ -f "$path/sign_update" ]; then
                echo "$path"
                return
            fi
        done
    done
    
    echo ""
}

# Get current build number from Info.plist
get_current_build_number() {
    local plist="$APP_PROJECT_DIR/$APP_NAME/Supporting Files/Info.plist"
    if [ -f "$plist" ]; then
        /usr/libexec/PlistBuddy -c "Print CFBundleVersion" "$plist" 2>/dev/null || echo "0"
    else
        echo "0"
    fi
}

# Update Info.plist with new version
update_info_plist() {
    local new_version="$1"
    local new_build="$2"
    local plist="$APP_PROJECT_DIR/$APP_NAME/Supporting Files/Info.plist"
    
    if [ "$DRY_RUN" = true ]; then
        print_info "[DRY RUN] Would update Info.plist:"
        print_info "  CFBundleShortVersionString: $new_version"
        print_info "  CFBundleVersion: $new_build"
        return
    fi
    
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $new_version" "$plist"
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $new_build" "$plist"
}

# Sign DMG with EdDSA for Sparkle
sign_update_with_eddsa() {
    local dmg_path="$1"
    local sparkle_bin=$(find_sparkle_bin)
    
    if [ -z "$sparkle_bin" ]; then
        print_warning "Sparkle bin not found. EdDSA signature skipped."
        print_info "Install Sparkle via SPM or set SPARKLE_BIN environment variable"
        echo ""
        return
    fi
    
    local sign_tool="$sparkle_bin/sign_update"
    
    if [ ! -x "$sign_tool" ]; then
        print_warning "sign_update tool not executable at: $sign_tool"
        echo ""
        return
    fi
    
    # Run sign_update - it reads private key from Keychain by default
    local output
    if [ -n "$SPARKLE_KEY_PATH" ]; then
        output=$("$sign_tool" "$dmg_path" -f "$SPARKLE_KEY_PATH" 2>&1)
    else
        output=$("$sign_tool" "$dmg_path" 2>&1)
    fi
    
    # Parse the signature and length from output
    # Format: sparkle:edSignature="xxx" length="yyy"
    EDDSA_SIGNATURE=$(echo "$output" | grep -o 'sparkle:edSignature="[^"]*"' | cut -d'"' -f2)
    FILE_LENGTH=$(echo "$output" | grep -o 'length="[^"]*"' | cut -d'"' -f2)
    
    if [ -n "$EDDSA_SIGNATURE" ]; then
        print_success "EdDSA signature generated"
        echo "  Signature: ${EDDSA_SIGNATURE:0:40}..."
        echo "  Length: $FILE_LENGTH bytes"
    else
        print_warning "Could not parse EdDSA signature from output:"
        echo "$output"
    fi
}

# Update appcast.xml with new release
update_appcast() {
    local version="$1"
    local build="$2"
    local dmg_filename="$3"
    local signature="$4"
    local length="$5"
    
    if [ "$DRY_RUN" = true ]; then
        print_info "[DRY RUN] Would update appcast.xml with:"
        print_info "  Version: $version (build $build)"
        print_info "  DMG: $dmg_filename"
        print_info "  Signature: ${signature:0:30}..."
        return
    fi
    
    local pub_date=$(date -u "+%a, %d %b %Y %H:%M:%S %z")
    local download_url="https://superdimmer.app/releases/$dmg_filename"
    local release_notes_url="https://superdimmer.app/release-notes/v${version}.html"
    
    # Create the new item XML
    local new_item="        <item>
            <title>Version $version</title>
            <pubDate>$pub_date</pubDate>
            <sparkle:releaseNotesLink>
                $release_notes_url
            </sparkle:releaseNotesLink>
            <sparkle:version>$build</sparkle:version>
            <sparkle:shortVersionString>$version</sparkle:shortVersionString>
            <sparkle:minimumSystemVersion>13.0</sparkle:minimumSystemVersion>
            <enclosure 
                url=\"$download_url\" 
                length=\"$length\"
                type=\"application/octet-stream\"
                sparkle:edSignature=\"$signature\"/>
        </item>"
    
    # Insert new item after <language>en</language> line
    # This places it at the top of the items list (newest first)
    if [ -f "$APPCAST_FILE" ]; then
        # Create backup
        cp "$APPCAST_FILE" "$APPCAST_FILE.backup"
        
        # Use awk to insert after </language> tag
        awk -v new_item="$new_item" '
        /<\/language>/ {
            print
            print ""
            print "        <!-- Release v'"$version"' -->"
            print new_item
            next
        }
        { print }
        ' "$APPCAST_FILE.backup" > "$APPCAST_FILE"
        
        rm "$APPCAST_FILE.backup"
        print_success "appcast.xml updated with v$version"
    else
        print_warning "appcast.xml not found at $APPCAST_FILE"
    fi
}

# Create release notes template
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
    
    cat > "$notes_file" << 'EOFHTML'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>SuperDimmer vVERSION_PLACEHOLDER Release Notes</title>
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
        a:hover { text-decoration: underline; }
    </style>
</head>
<body>
    <h1>SuperDimmer</h1>
    <span class="version-badge">vVERSION_PLACEHOLDER</span>
    <p class="date">DATE_PLACEHOLDER</p>
    
    <h2>🆕 What's New</h2>
    <ul>
        <li><span class="highlight">New Feature</span> — Description here</li>
        <li>Improvement to existing feature</li>
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
        <p>Questions? Visit <a href="https://superdimmer.app">superdimmer.app</a></p>
    </div>
</body>
</html>
EOFHTML

    # Replace placeholders
    local date_str=$(date "+%B %d, %Y")
    sed -i '' "s/VERSION_PLACEHOLDER/$version/g" "$notes_file"
    sed -i '' "s/DATE_PLACEHOLDER/$date_str/g" "$notes_file"
    
    print_success "Release notes template created: $notes_file"
    print_warning "⚠️  Remember to edit the release notes before pushing!"
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
    
    # Calculate build number (increment from current)
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
    print_step "1/8" "Updating version in Info.plist"
    update_info_plist "$VERSION" "$new_build"
    print_success "Info.plist updated: v$VERSION (build $new_build)"
    
    # ─────────────────────────────────────────────────────────────────────────
    # STEP 2: Build Release
    # ─────────────────────────────────────────────────────────────────────────
    print_step "2/8" "Building $APP_NAME (Release configuration)"
    
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
    print_step "3/8" "Code signing with Developer ID"
    
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
        
        # Verify
        codesign -v "$APP_PATH"
        print_success "Code signed with Developer ID"
    fi
    
    # ─────────────────────────────────────────────────────────────────────────
    # STEP 4: Create DMG
    # ─────────────────────────────────────────────────────────────────────────
    print_step "4/8" "Creating DMG installer"
    
    DMG_FILENAME="${APP_NAME}-v${VERSION}.dmg"
    DMG_PATH="$OUTPUT_DIR/$DMG_FILENAME"
    
    if [ "$DRY_RUN" = true ]; then
        print_info "[DRY RUN] Would create DMG: $DMG_PATH"
    else
        mkdir -p "$OUTPUT_DIR"
        cd "$SCRIPT_DIR"
        
        # Use our create-dmg.sh script
        if [ -f "./create-dmg.sh" ]; then
            ./create-dmg.sh "$APP_PATH"
            # Rename to our version-specific name
            mv "$OUTPUT_DIR/${APP_NAME}-v${VERSION}.dmg" "$DMG_PATH" 2>/dev/null || true
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
        
        if [ ! -f "$DMG_PATH" ]; then
            print_error "DMG creation failed"
        fi
        
        print_success "DMG created: $DMG_PATH"
        echo "  Size: $(du -h "$DMG_PATH" | cut -f1)"
    fi
    
    # ─────────────────────────────────────────────────────────────────────────
    # STEP 5: Notarize with Apple
    # ─────────────────────────────────────────────────────────────────────────
    print_step "5/8" "Notarizing with Apple"
    
    if [ "$SKIP_SIGN" = true ]; then
        print_warning "Skipping notarization (--skip-sign)"
    elif [ "$DRY_RUN" = true ]; then
        print_info "[DRY RUN] Would submit for notarization"
    else
        if [ -z "$APPLE_ID" ] || [ -z "$APPLE_APP_PASSWORD" ] || [ -z "$APPLE_TEAM_ID" ]; then
            print_warning "Notarization credentials not set. Skipping."
            print_info "Set APPLE_ID, APPLE_APP_PASSWORD, APPLE_TEAM_ID to enable"
        else
            # Sign DMG itself
            codesign --force --sign "$SIGNING_IDENTITY" "$DMG_PATH"
            
            # Submit for notarization
            xcrun notarytool submit "$DMG_PATH" \
                --apple-id "$APPLE_ID" \
                --password "$APPLE_APP_PASSWORD" \
                --team-id "$APPLE_TEAM_ID" \
                --wait
            
            # Staple the ticket
            xcrun stapler staple "$DMG_PATH"
            
            print_success "Notarization complete and stapled"
        fi
    fi
    
    # ─────────────────────────────────────────────────────────────────────────
    # STEP 6: Sign with EdDSA for Sparkle
    # ─────────────────────────────────────────────────────────────────────────
    print_step "6/8" "Signing with EdDSA for Sparkle updates"
    
    EDDSA_SIGNATURE=""
    FILE_LENGTH=""
    
    if [ "$DRY_RUN" = true ]; then
        print_info "[DRY RUN] Would sign with EdDSA"
        EDDSA_SIGNATURE="DRY_RUN_SIGNATURE"
        FILE_LENGTH="12345678"
    else
        sign_update_with_eddsa "$DMG_PATH"
        
        # Get file length if not set by sign_update
        if [ -z "$FILE_LENGTH" ]; then
            FILE_LENGTH=$(stat -f%z "$DMG_PATH" 2>/dev/null || stat --format=%s "$DMG_PATH" 2>/dev/null)
        fi
    fi
    
    # ─────────────────────────────────────────────────────────────────────────
    # STEP 7: Update appcast.xml
    # ─────────────────────────────────────────────────────────────────────────
    print_step "7/8" "Updating appcast.xml"
    
    if [ -n "$EDDSA_SIGNATURE" ]; then
        update_appcast "$VERSION" "$new_build" "$DMG_FILENAME" "$EDDSA_SIGNATURE" "$FILE_LENGTH"
    else
        print_warning "No EdDSA signature - appcast.xml not updated"
        print_info "You'll need to manually update appcast.xml with the signature"
    fi
    
    # ─────────────────────────────────────────────────────────────────────────
    # STEP 8: Copy to releases/ and create release notes
    # ─────────────────────────────────────────────────────────────────────────
    print_step "8/8" "Finalizing release"
    
    if [ "$DRY_RUN" = true ]; then
        print_info "[DRY RUN] Would copy DMG to $RELEASES_DIR/"
        print_info "[DRY RUN] Would create release notes template"
    else
        # Copy DMG to releases
        mkdir -p "$RELEASES_DIR"
        cp "$DMG_PATH" "$RELEASES_DIR/"
        print_success "DMG copied to releases/"
        
        # Create release notes template
        create_release_notes_template "$VERSION"
    fi
    
    # ─────────────────────────────────────────────────────────────────────────
    # SUMMARY
    # ─────────────────────────────────────────────────────────────────────────
    print_header "Release v$VERSION Complete! 🎉"
    
    echo "  📦 App:          $APP_PATH"
    echo "  💿 DMG:          $DMG_PATH"
    echo "  📋 Appcast:      $APPCAST_FILE"
    echo "  📝 Release Notes: $RELEASE_NOTES_DIR/v${VERSION}.html"
    echo ""
    
    if [ "$SKIP_SIGN" = true ]; then
        echo -e "  ${YELLOW}⚠️  Not signed (development build)${NC}"
    else
        echo -e "  ${GREEN}✅ Signed with Developer ID${NC}"
        if [ -n "$EDDSA_SIGNATURE" ]; then
            echo -e "  ${GREEN}✅ EdDSA signature for Sparkle${NC}"
        else
            echo -e "  ${YELLOW}⚠️  No EdDSA signature (manual update needed)${NC}"
        fi
    fi
    
    echo ""
    echo "  ─────────────────────────────────────────────────────────────────"
    echo "  NEXT STEPS:"
    echo "  ─────────────────────────────────────────────────────────────────"
    echo ""
    echo "  1. Edit release notes:"
    echo "     open \"$RELEASE_NOTES_DIR/v${VERSION}.html\""
    echo ""
    echo "  2. Review changes:"
    echo "     cd \"$WEBSITE_DIR\" && git status"
    echo ""
    echo "  3. Commit and push:"
    echo "     git add ."
    echo "     git commit -m \"Release v$VERSION\""
    echo "     git push"
    echo ""
    echo "  4. Cloudflare auto-deploys → Users get the update! 🚀"
    echo ""
}

# Run the main function
main
