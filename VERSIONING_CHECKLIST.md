# SuperDimmer Versioning Checklist

> **Last Updated:** January 10, 2026  
> **Current Version:** 1.0.1 (build 6)

This checklist covers everything needed to release a new version of SuperDimmer. Follow these steps in order.

---

## 📋 Quick Reference

| File | Purpose | Location |
|------|---------|----------|
| `Info.plist` | App version numbers | `SuperDimmer-Mac-App/SuperDimmer/Supporting Files/` |
| `appcast.xml` | Sparkle update feed | `SuperDimmer-Website/sparkle/` |
| `changelog.html` | Public version history | `SuperDimmer-Website/` |
| `vX.X.X.html` | Individual release notes | `SuperDimmer-Website/release-notes/` |
| DMG files | Installers | `SuperDimmer-Website/releases/` |
| `release.sh` | Automated release script | `SuperDimmer-Website/packaging/` |

---

## 🔢 Version Number Format

We use **Semantic Versioning** (SemVer): `MAJOR.MINOR.PATCH`

- **MAJOR** (X.0.0): Breaking changes, major UI overhauls
- **MINOR** (0.X.0): New features, significant improvements
- **PATCH** (0.0.X): Bug fixes, minor improvements, stability

**Build Number:** Internal counter that increments with every build (currently: 6)

---

## ✅ Pre-Release Checklist

### 1. Decide Version Number
- [ ] Determine appropriate version bump (major/minor/patch)
- [ ] Check current version in `Info.plist`
- [ ] Document what's changing for release notes

### 2. Update Code (if needed)
- [ ] Make all code changes
- [ ] Test locally
- [ ] Verify app builds without errors: `xcodebuild -project SuperDimmer.xcodeproj -scheme SuperDimmer -configuration Release`

---

## 🚀 Release Process

### Option A: Automated (Recommended)

Run the release script from `SuperDimmer-Website/packaging/`:

```bash
# Development build (no signing)
./release.sh X.X.X --skip-sign

# Full signed release (requires certificates)
./release.sh X.X.X

# Dry run (preview what will happen)
./release.sh X.X.X --dry-run
```

The script automatically:
- [x] Updates `Info.plist` version and build numbers
- [x] Builds the app in Release configuration
- [x] Creates DMG installer
- [x] Copies DMG to `releases/` folder
- [x] Creates release notes template (if not exists)

**After script completes, you still need to:**
- [ ] Edit release notes content
- [ ] Update `changelog.html` manually
- [ ] Update `appcast.xml` (if EdDSA signature missing)
- [ ] Commit and push

---

### Option B: Manual Process

#### Step 1: Update Version Numbers

Edit `SuperDimmer-Mac-App/SuperDimmer/Supporting Files/Info.plist`:

```xml
<key>CFBundleShortVersionString</key>
<string>X.X.X</string>  <!-- User-facing version -->
<key>CFBundleVersion</key>
<string>N</string>      <!-- Build number (increment by 1) -->
```

#### Step 2: Build the App

```bash
cd SuperDimmer-Mac-App
xcodebuild \
    -project SuperDimmer.xcodeproj \
    -scheme SuperDimmer \
    -configuration Release \
    -derivedDataPath build/DerivedData \
    CONFIGURATION_BUILD_DIR=build/Release \
    clean build
```

#### Step 3: Create DMG

```bash
cd SuperDimmer-Website/packaging
./create-dmg.sh ../SuperDimmer-Mac-App/build/Release/SuperDimmer.app
```

#### Step 4: Copy DMG to Releases

```bash
cp packaging/output/SuperDimmer-vX.X.X.dmg releases/
```

#### Step 5: Get File Size

```bash
stat -f%z releases/SuperDimmer-vX.X.X.dmg
# Example output: 2871440
```

---

## 📝 Update Website Files

### 1. Create Release Notes Page

Create `SuperDimmer-Website/release-notes/vX.X.X.html`:

```html
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>SuperDimmer vX.X.X Release Notes</title>
    <style>
        /* Copy styles from existing release notes */
    </style>
</head>
<body>
    <h1>SuperDimmer</h1>
    <span class="version-badge">vX.X.X</span>
    <p class="date">Month DD, YYYY</p>
    
    <h2>🆕 What's New</h2>
    <ul>
        <li><span class="highlight">Feature Name</span> — Description</li>
    </ul>
    
    <h2>🐛 Bug Fixes</h2>
    <ul>
        <li>Fixed issue with...</li>
    </ul>
    
    <h2>🔧 Improvements</h2>
    <ul>
        <li>Performance improvements</li>
    </ul>
</body>
</html>
```

### 2. Update Changelog Page

Edit `SuperDimmer-Website/changelog.html`:

Add new entry at the **TOP** of `.changelog-entries` section:

```html
<!-- vX.X.X - Latest -->
<div class="release-entry">
    <div class="release-header">
        <span class="version-badge">vX.X.X</span>
        <span class="release-date">Month DD, YYYY</span>
        <span class="release-tag latest">Latest</span>
    </div>
    <p class="release-summary">
        Brief description of this release.
    </p>
    <div class="release-sections">
        <div class="release-section">
            <h3><span class="emoji">🆕</span> What's New</h3>
            <ul>
                <li><strong>Feature</strong> — Description</li>
            </ul>
        </div>
        <!-- Add more sections as needed -->
    </div>
    <a href="/release-notes/vX.X.X.html" class="release-link">
        View full release notes
        <svg viewBox="0 0 24 24" stroke-width="2"><path d="M5 12h14M12 5l7 7-7 7"/></svg>
    </a>
</div>
```

**Important:** Remove the `latest` tag from the previous release entry!

### 3. Update Appcast (Sparkle Feed)

Edit `SuperDimmer-Website/sparkle/appcast.xml`:

Add new `<item>` after `<language>en</language>`:

```xml
<item>
    <title>Version X.X.X</title>
    <pubDate>Day, DD Mon YYYY HH:MM:SS -0800</pubDate>
    <sparkle:releaseNotesLink>
        https://superdimmer.app/release-notes/vX.X.X.html
    </sparkle:releaseNotesLink>
    <sparkle:version>BUILD_NUMBER</sparkle:version>
    <sparkle:shortVersionString>X.X.X</sparkle:shortVersionString>
    <sparkle:minimumSystemVersion>13.0</sparkle:minimumSystemVersion>
    <enclosure 
        url="https://superdimmer.app/releases/SuperDimmer-vX.X.X.dmg" 
        length="FILE_SIZE_IN_BYTES"
        type="application/octet-stream"
        sparkle:edSignature="SIGNATURE_HERE=="/>
</item>
```

---

## 🔐 Signing (For Production Releases)

### Code Signing

```bash
# List available signing identities
security find-identity -v -p codesigning

# Sign the app
codesign --force --deep --verify --verbose \
    --sign "Developer ID Application: YOUR NAME (TEAM_ID)" \
    --options runtime \
    --entitlements SuperDimmer/Supporting\ Files/SuperDimmer.entitlements \
    build/Release/SuperDimmer.app

# Sign the DMG
codesign --force --sign "Developer ID Application: YOUR NAME (TEAM_ID)" \
    releases/SuperDimmer-vX.X.X.dmg
```

### Notarization

```bash
# Submit for notarization
xcrun notarytool submit releases/SuperDimmer-vX.X.X.dmg \
    --apple-id "your@email.com" \
    --password "app-specific-password" \
    --team-id "TEAM_ID" \
    --wait

# Staple the ticket
xcrun stapler staple releases/SuperDimmer-vX.X.X.dmg
```

### EdDSA Signature (Sparkle)

```bash
# Generate signature for appcast.xml
/path/to/Sparkle/bin/sign_update releases/SuperDimmer-vX.X.X.dmg

# Output format:
# sparkle:edSignature="ABC123==" length="2871440"
```

---

## 📤 Deploy

### 1. Commit Changes

```bash
# Mac App repo
cd SuperDimmer-Mac-App
git add -A
git commit -m "Release vX.X.X - brief description

- Feature 1
- Bug fix 1
- Improvement 1"
git push

# Website repo
cd SuperDimmer-Website
git add -A
git commit -m "Release vX.X.X - website update

- Added release-notes/vX.X.X.html
- Updated changelog.html
- Updated sparkle/appcast.xml
- Added releases/SuperDimmer-vX.X.X.dmg"
git push
```

### 2. Verify Deployment

- [ ] Wait for Cloudflare Pages to deploy (~1-2 minutes)
- [ ] Check https://superdimmer.app/changelog.html
- [ ] Check https://superdimmer.app/release-notes/vX.X.X.html
- [ ] Verify DMG downloads: https://superdimmer.app/releases/SuperDimmer-vX.X.X.dmg
- [ ] Check appcast: https://superdimmer.app/sparkle/appcast.xml

---

## 🔄 Post-Release

- [ ] Test auto-update in older version of app (if available)
- [ ] Monitor for any user issues
- [ ] Update any external documentation/marketing

---

## 📊 Version History

| Version | Build | Date | Notes |
|---------|-------|------|-------|
| 1.0.1 | 6 | Jan 10, 2026 | Stability improvements |
| 1.0.0 | 4 | Jan 8, 2026 | Initial release |

---

## 🆘 Troubleshooting

### Build Failed
- Check Xcode command line tools: `xcode-select -p`
- Clean derived data: `rm -rf build/DerivedData`

### DMG Won't Open (Gatekeeper)
- App needs to be signed and notarized
- Use `--skip-sign` for development only

### Sparkle Updates Not Working
- Verify `SUFeedURL` in Info.plist matches appcast URL
- Check EdDSA signature is correct
- Verify build numbers are incrementing
- Check `sparkle:version` matches `CFBundleVersion`

### File Size Mismatch in Appcast
- Get exact size: `stat -f%z releases/SuperDimmer-vX.X.X.dmg`
- Update `length` attribute in appcast.xml

---

## 📁 File Templates

All templates can be found in existing files:
- **Release notes**: Copy from `release-notes/v1.0.0.html`
- **Changelog entry**: Copy from existing entry in `changelog.html`
- **Appcast item**: Copy from existing item in `sparkle/appcast.xml`
