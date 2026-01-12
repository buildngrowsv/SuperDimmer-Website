# SuperDimmer Update System Checklists
## Simple JSON-Based Updates (No Sparkle)

---

## 📋 PART 1: One-Time Setup

### 1.1 Notarization Credentials

Apple notarization is required so users can open the app without Gatekeeper warnings.

**1.1.1 App-Specific Password**
- [ ] Go to https://appleid.apple.com
- [ ] Sign in → Security → App-Specific Passwords
- [ ] Generate password named "SuperDimmer Notarization"
- [ ] Copy the password (format: `xxxx-xxxx-xxxx-xxxx`)

**1.1.2 Environment Variables**
Add to `~/.zshrc`:
```bash
export APPLE_ID="your-apple-developer-email@example.com"
export APPLE_APP_PASSWORD="xxxx-xxxx-xxxx-xxxx"
export APPLE_TEAM_ID="HHHHZ6UV26"  # Your Team ID
```
Then: `source ~/.zshrc`

- [ ] APPLE_ID set
- [ ] APPLE_APP_PASSWORD set
- [ ] APPLE_TEAM_ID set
- [ ] Ran `source ~/.zshrc`

**1.1.3 Verify Setup**
```bash
echo "ID: $APPLE_ID, Team: $APPLE_TEAM_ID, Pass: ${APPLE_APP_PASSWORD:+SET}"
```
- [ ] All three show correctly

### 1.2 Create UpdateChecker.swift (In App)

Simple Swift class to check for updates:

```swift
import Foundation
import AppKit

/// Checks for app updates by fetching version.json from the website
/// No third-party frameworks needed - just URLSession and JSON parsing
final class UpdateChecker {
    static let shared = UpdateChecker()
    
    private let versionURL = URL(string: "https://superdimmer.app/version.json")!
    
    struct VersionInfo: Codable {
        let version: String
        let build: Int
        let downloadURL: String
        let releaseNotesURL: String
    }
    
    func checkForUpdates(showUpToDateAlert: Bool = false) {
        URLSession.shared.dataTask(with: versionURL) { [weak self] data, _, error in
            guard let data = data,
                  let remoteVersion = try? JSONDecoder().decode(VersionInfo.self, from: data) else {
                return
            }
            
            let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
            
            if self?.isNewer(remoteVersion.version, than: currentVersion) == true {
                DispatchQueue.main.async {
                    self?.showUpdateAlert(version: remoteVersion)
                }
            } else if showUpToDateAlert {
                DispatchQueue.main.async {
                    self?.showUpToDateAlert()
                }
            }
        }.resume()
    }
    
    private func isNewer(_ remote: String, than current: String) -> Bool {
        return remote.compare(current, options: .numeric) == .orderedDescending
    }
    
    private func showUpdateAlert(version: VersionInfo) {
        let alert = NSAlert()
        alert.messageText = "Update Available"
        alert.informativeText = "SuperDimmer \(version.version) is available. You have \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] ?? "unknown")."
        alert.addButton(withTitle: "Download")
        alert.addButton(withTitle: "Later")
        
        if alert.runModal() == .alertFirstButtonReturn {
            if let url = URL(string: version.downloadURL) {
                NSWorkspace.shared.open(url)
            }
        }
    }
    
    private func showUpToDateAlert() {
        let alert = NSAlert()
        alert.messageText = "You're Up to Date"
        alert.informativeText = "SuperDimmer \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] ?? "") is the latest version."
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
```

- [ ] Created `UpdateChecker.swift`
- [ ] Added to Xcode project
- [ ] Called on app launch: `UpdateChecker.shared.checkForUpdates()`
- [ ] Added "Check for Updates..." menu item

---

## ✅ One-Time Setup Complete!

---

## 📋 PART 2: New Version Release Checklist

### Before Release
- [ ] All code changes committed
- [ ] Tested the app manually
- [ ] Decided on version number (e.g., 1.1.0)

### Run Release Script

```bash
cd /Users/ak/UserRoot/Github/SuperDimmer/SuperDimmer-Website/packaging
./release.sh X.Y.Z
```

- [ ] Script completed
- [ ] DMG created in `releases/`
- [ ] version.json updated
- [ ] Release notes template created

### Edit Release Notes (Optional)

```bash
open /Users/ak/UserRoot/Github/SuperDimmer/SuperDimmer-Website/release-notes/vX.Y.Z.html
```

- [ ] Updated release notes content

### Commit and Push

```bash
cd /Users/ak/UserRoot/Github/SuperDimmer/SuperDimmer-Website
git add .
git commit -m "Release vX.Y.Z"
git push
```

- [ ] Committed
- [ ] Pushed
- [ ] Cloudflare deployed (~1 min)

### Verify

- [ ] https://superdimmer.app/version.json shows new version
- [ ] DMG downloads correctly
- [ ] App shows "Update Available" when checking

---

## 🚀 Quick Release (Copy-Paste)

```bash
# 1. Run release
cd /Users/ak/UserRoot/Github/SuperDimmer/SuperDimmer-Website/packaging
./release.sh 1.1.0

# 2. Push
cd .. && git add . && git commit -m "Release v1.1.0" && git push

# Done! 🎉
```

---

## How It Works

```
┌─────────────────────────────────────────────────────────────────┐
│                    UPDATE FLOW                                   │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  YOUR WEBSITE (Cloudflare)           USER'S MAC                 │
│  ─────────────────────────           ──────────                 │
│                                                                  │
│  version.json ◄──────────────────── App fetches on launch      │
│  {                                          │                   │
│    "version": "1.1.0",                      │                   │
│    "downloadURL": "..."                     ▼                   │
│  }                                   Compares versions          │
│                                             │                   │
│                                             ▼                   │
│                                      If newer: Alert!           │
│                                      "Update Available"         │
│                                             │                   │
│  releases/SuperDimmer-v1.1.0.dmg           │                   │
│         ▲                                   │                   │
│         │                                   ▼                   │
│         └─────────────────────── User clicks "Download"         │
│                                      Opens in browser           │
│                                      User installs DMG          │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

---

## Why This Approach?

| Feature | Sparkle | Simple JSON |
|---------|---------|-------------|
| HTTPS Security | ✅ | ✅ |
| Apple Notarization | ✅ | ✅ |
| Auto-install updates | ✅ | ❌ (user downloads) |
| Setup complexity | High (keys, signing) | Low (just JSON) |
| Third-party framework | Yes | No |
| Works if server hacked | Only with EdDSA | Relies on HTTPS |

**Our choice:** Simple JSON is enough because:
- Website is HTTPS (Cloudflare) - downloads are secure
- App is notarized - Apple trusts it
- Lower complexity = fewer things to break
