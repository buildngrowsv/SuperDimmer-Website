# SuperDimmer Update System Checklists

## 📋 PART 1: One-Time Setup (Before First Release)

These tasks only need to be done **once** to enable the update system.

### 1.1 Add Sparkle Framework to Xcode Project

```bash
# In Xcode:
# File → Add Package Dependencies
# Enter: https://github.com/sparkle-project/Sparkle
# Select version 2.6.0 or later
# Add to SuperDimmer target
```

- [ ] Sparkle package added to Xcode project
- [ ] Build succeeds with Sparkle imported

### 1.2 Generate EdDSA Signing Keys

```bash
# After adding Sparkle via SPM, find the tools:
cd ~/Library/Developer/Xcode/DerivedData/SuperDimmer-*/SourcePackages/artifacts/sparkle/Sparkle/bin

# Generate keys (saves to Keychain, prints public key)
./generate_keys

# BACKUP YOUR PRIVATE KEY (critical!)
./generate_keys -x ~/Desktop/superdimmer-sparkle-private.key
# Store this backup file somewhere SAFE (not in Git!)
```

- [ ] Ran `generate_keys` 
- [ ] Copied the public key (starts with `SUPublicEDKey`)
- [ ] **Backed up private key** to secure location

### 1.3 Update Info.plist with Public Key

Edit `SuperDimmer-Mac-App/SuperDimmer/Supporting Files/Info.plist`:

```xml
<!-- Add/update this key with YOUR generated public key -->
<key>SUPublicEDKey</key>
<string>YOUR_PUBLIC_KEY_FROM_GENERATE_KEYS_HERE</string>
```

- [ ] Added `SUPublicEDKey` to Info.plist
- [ ] Verified `SUFeedURL` is `https://superdimmer.app/sparkle/appcast.xml`

### 1.4 Create UpdateManager.swift

Create the file `SuperDimmer-Mac-App/SuperDimmer/App/UpdateManager.swift`:

```swift
import Foundation
import Sparkle

/// Manages automatic software updates via Sparkle framework
final class UpdateManager {
    static let shared = UpdateManager()
    
    private var updaterController: SPUStandardUpdaterController!
    
    private init() {
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }
    
    /// Call from "Check for Updates" menu item
    func checkForUpdates() {
        updaterController.checkForUpdates(nil)
    }
}
```

- [ ] Created `UpdateManager.swift`
- [ ] Added to Xcode project

### 1.5 Add "Check for Updates" Menu Item

In `MenuBarController.swift` or menu setup:

```swift
// Add menu item
let updateItem = NSMenuItem(
    title: "Check for Updates...", 
    action: #selector(checkForUpdates), 
    keyEquivalent: ""
)
menu.addItem(updateItem)

@objc func checkForUpdates() {
    UpdateManager.shared.checkForUpdates()
}
```

- [ ] Added menu item
- [ ] Wired to UpdateManager

### 1.6 Get Apple Developer Credentials

For notarization (required for distribution):

1. **Apple ID**: Your developer account email
2. **App-Specific Password**: 
   - Go to https://appleid.apple.com
   - Sign In → Security → App-Specific Passwords → Generate
3. **Team ID**: 
   - Go to https://developer.apple.com/account
   - Membership → Team ID (10 characters)

- [ ] Have Apple ID ready
- [ ] Generated app-specific password
- [ ] Found Team ID

### 1.7 Set Environment Variables

Add to your `~/.zshrc` or `~/.bash_profile`:

```bash
export APPLE_ID="your@email.com"
export APPLE_APP_PASSWORD="xxxx-xxxx-xxxx-xxxx"
export APPLE_TEAM_ID="XXXXXXXXXX"
```

Then run: `source ~/.zshrc`

- [ ] Added environment variables
- [ ] Sourced shell config

### 1.8 Verify Developer ID Certificate

```bash
# Check you have a Developer ID certificate
security find-identity -v -p codesigning | grep "Developer ID"
```

Should show: `Developer ID Application: Your Name (TEAM_ID)`

- [ ] Developer ID certificate is in Keychain

### 1.9 Test Build

```bash
cd /Users/ak/UserRoot/Github/SuperDimmer/SuperDimmer-Website/packaging
./release.sh 1.0.1 --dry-run
```

- [ ] Dry run completes without errors

---

## ✅ One-Time Setup Complete!

Once all boxes above are checked, you're ready to push updates.

---

## 📋 PART 2: New Version Release Checklist

Use this checklist **every time** you release a new version.

### Before Running Release Script

- [ ] All code changes committed to Mac-App repo
- [ ] Tested the app manually
- [ ] Decided on version number (e.g., 1.1.0)

### Run the Release Script

```bash
cd /Users/ak/UserRoot/Github/SuperDimmer/SuperDimmer-Website/packaging
./release.sh X.Y.Z
```

Replace `X.Y.Z` with your version number.

- [ ] Script completed successfully
- [ ] DMG created in `releases/` folder
- [ ] appcast.xml updated automatically
- [ ] Release notes template created

### Edit Release Notes

```bash
open /Users/ak/UserRoot/Github/SuperDimmer/SuperDimmer-Website/release-notes/vX.Y.Z.html
```

- [ ] Updated "What's New" section
- [ ] Updated "Bug Fixes" section  
- [ ] Updated "Improvements" section
- [ ] Saved file

### Commit and Push

```bash
cd /Users/ak/UserRoot/Github/SuperDimmer/SuperDimmer-Website
git add .
git commit -m "Release vX.Y.Z - [brief description]"
git push
```

- [ ] Changes committed
- [ ] Pushed to GitHub
- [ ] Cloudflare deployment triggered (check: https://dash.cloudflare.com)

### Verify Deployment

Wait ~1-2 minutes, then:

- [ ] Visit https://superdimmer.app/sparkle/appcast.xml - new version appears
- [ ] Visit https://superdimmer.app/releases/ - DMG is downloadable
- [ ] Test download link works

### Test Update Flow

On a Mac with the **previous** version installed:

- [ ] Launch old version of SuperDimmer
- [ ] Click "Check for Updates" (or wait for auto-check)
- [ ] Update dialog appears with correct version
- [ ] Click "Install Update"
- [ ] App downloads, installs, and relaunches
- [ ] New version running correctly

### Post-Release

- [ ] Announce release (social media, website, etc.)
- [ ] Monitor for crash reports / support tickets
- [ ] Commit Mac-App repo if Info.plist changed:
  ```bash
  cd /Users/ak/UserRoot/Github/SuperDimmer/SuperDimmer-Mac-App
  git add .
  git commit -m "Bump version to X.Y.Z"
  git push
  ```

---

## 🚀 Quick Reference: Minimal Release Steps

```bash
# 1. Run release script
cd /Users/ak/UserRoot/Github/SuperDimmer/SuperDimmer-Website/packaging
./release.sh 1.2.0

# 2. Edit release notes (optional but recommended)
open ../release-notes/v1.2.0.html

# 3. Commit and push
cd ..
git add .
git commit -m "Release v1.2.0"
git push

# 4. Done! Users get update automatically 🎉
```

---

## ⚠️ Troubleshooting

### "Sparkle bin not found"
The release script can't find Sparkle's `sign_update` tool.
- Make sure Sparkle is added to Xcode via SPM
- Build the project at least once
- Or set `SPARKLE_BIN=/path/to/Sparkle/bin`

### "No Developer ID certificate"
- Open Keychain Access → login → My Certificates
- Look for "Developer ID Application"
- If missing, download from developer.apple.com

### "Notarization failed"
- Check APPLE_ID, APPLE_APP_PASSWORD, APPLE_TEAM_ID are set
- Verify app-specific password is valid
- Run `xcrun notarytool log <id>` to see error details

### "EdDSA signature missing"
- Run `generate_keys` if you haven't
- Check the key is in your Keychain
- Or set `SPARKLE_KEY_PATH=/path/to/private/key`

### Users don't see update
- Check appcast.xml has the new version
- Verify `sparkle:version` > user's `CFBundleVersion`
- Check Cloudflare deployed (can take 1-2 min)
