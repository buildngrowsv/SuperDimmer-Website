# SuperDimmer Release Packaging

This folder contains all the scripts needed to build, package, and deploy SuperDimmer updates.

## Quick Start: Full Release

```bash
# One command does it all!
./release.sh 1.1.0

# Then commit and push:
git add .
git commit -m "Release v1.1.0"
git push
# → Cloudflare auto-deploys → Users get the update!
```

## What the Release Script Does

The `release.sh` script handles the entire release workflow:

| Step | Action | Details |
|------|--------|---------|
| 1 | Update Info.plist | Sets version number and increments build number |
| 2 | Build App | `xcodebuild` Release configuration |
| 3 | Code Sign | Developer ID Application certificate |
| 4 | Create DMG | Professional installer with drag-to-Applications |
| 5 | Notarize | Apple Gatekeeper approval |
| 6 | EdDSA Sign | Sparkle update verification |
| 7 | Update appcast.xml | Adds new version entry automatically |
| 8 | Copy & Notes | DMG to releases/, release notes template |

## Usage

```bash
# Full signed release (production)
./release.sh 1.2.0

# Development build (skip signing)
./release.sh 1.2.0 --skip-sign

# Preview what would happen
./release.sh 1.2.0 --dry-run
```

## Prerequisites

### For Development Builds (`--skip-sign`)
- Xcode and command line tools

### For Production Releases
- **Developer ID Certificate** - In your Keychain
- **Apple Notarization Credentials** - Set these environment variables:
  ```bash
  export APPLE_ID="your@email.com"
  export APPLE_APP_PASSWORD="xxxx-xxxx-xxxx-xxxx"  # App-specific password
  export APPLE_TEAM_ID="XXXXXXXXXX"  # Your 10-char Team ID
  ```
- **Sparkle EdDSA Key** - Run `generate_keys` once (see below)

## Setting Up EdDSA Keys (One-Time)

Sparkle uses EdDSA signatures to verify updates are authentic. You need to generate a key pair once:

```bash
# Find Sparkle's tools (after adding Sparkle via SPM)
cd ~/Library/Developer/Xcode/DerivedData/SuperDimmer-*/SourcePackages/artifacts/sparkle/Sparkle/bin

# Generate keys (saves private key to Keychain, prints public key)
./generate_keys
```

**Output:**
```
A key has been generated and saved in your keychain. Add the `SUPublicEDKey` key to
the Info.plist of each app...

    <key>SUPublicEDKey</key>
    <string>YOUR_PUBLIC_KEY_HERE</string>
```

**IMPORTANT:**
1. Add the public key to your app's Info.plist
2. Backup the private key: `./generate_keys -x ~/backup/superdimmer-sparkle.key`
3. Never commit the private key to Git!

## File Structure

```
SuperDimmer-Website/
├── packaging/
│   ├── release.sh          # ← Main script - run this!
│   ├── create-dmg.sh       # DMG creation helper
│   ├── create-background.sh # DMG background image
│   ├── build-release.sh    # Legacy build script
│   └── output/             # Temporary build output
├── releases/
│   ├── SuperDimmer-v1.0.0.dmg
│   └── SuperDimmer-v1.1.0.dmg
├── sparkle/
│   └── appcast.xml         # ← Auto-updated by release.sh
└── release-notes/
    ├── v1.0.0.html
    └── v1.1.0.html         # ← Template created by release.sh
```

## How Users Get Updates

1. User's app checks `https://superdimmer.com/sparkle/appcast.xml`
2. Sparkle compares `sparkle:version` with app's CFBundleVersion
3. If newer version found → Shows update dialog with release notes
4. User clicks "Install" → Downloads DMG from releases/
5. Sparkle verifies EdDSA signature matches
6. Installs and relaunches

## Scripts Reference

| Script | Purpose |
|--------|---------|
| `release.sh` | **Main script** - Full automated release |
| `create-dmg.sh` | Creates DMG installer from .app bundle |
| `create-background.sh` | Generates DMG background image |
| `build-release.sh` | Builds app only (legacy, use release.sh instead) |

## Environment Variables

| Variable | Purpose | Required |
|----------|---------|----------|
| `APPLE_ID` | Apple ID for notarization | For production |
| `APPLE_APP_PASSWORD` | App-specific password | For production |
| `APPLE_TEAM_ID` | 10-char Team ID | For production |
| `SIGNING_IDENTITY` | Override auto-detected cert | Optional |
| `SPARKLE_BIN` | Path to Sparkle bin folder | Auto-detected |
| `SPARKLE_KEY_PATH` | Path to EdDSA private key | If not in Keychain |

## Troubleshooting

### "No Developer ID certificate found"
Run: `security find-identity -v -p codesigning`
You need a "Developer ID Application" certificate.

### "Sparkle bin not found"
Either:
1. Add Sparkle to your Xcode project via SPM
2. Download Sparkle manually and set `SPARKLE_BIN=/path/to/Sparkle/bin`

### "EdDSA signature failed"
Run `generate_keys` to ensure your key is in Keychain, or set `SPARKLE_KEY_PATH`.

### Notarization failed
1. Check your app-specific password is correct
2. Ensure APPLE_TEAM_ID is your 10-character Team ID
3. Try manual: `xcrun notarytool log <submission-id> --apple-id ...`

## Complete Release Checklist

```
□ Update version number
□ Write release notes content
□ Run ./release.sh X.Y.Z
□ Edit release-notes/vX.Y.Z.html
□ Review git diff
□ git add . && git commit -m "Release vX.Y.Z"
□ git push
□ Wait ~1 min for Cloudflare deployment
□ Test update from previous version
□ Announce release!
```
