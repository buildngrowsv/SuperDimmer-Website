# SuperDimmer Release Packaging

Simple release workflow - no Sparkle framework needed.

## Quick Start

```bash
# One command does everything
./release.sh 1.1.0

# Then push to deploy
cd .. && git add . && git commit -m "Release v1.1.0" && git push
```

## What the Script Does

| Step | Action |
|------|--------|
| 1 | Updates Info.plist (version + build number) |
| 2 | Builds app (Release configuration) |
| 3 | Signs with Developer ID |
| 4 | Creates DMG |
| 5 | Notarizes with Apple (Gatekeeper approval) |
| 6 | Updates version.json |
| 7 | Copies DMG to releases/ |
| 8 | Creates release notes template |

## Prerequisites

### For Development Builds (`--skip-sign`)
- Xcode command line tools

### For Production Releases
Add to `~/.zshrc`:
```bash
export APPLE_ID="your@email.com"
export APPLE_APP_PASSWORD="xxxx-xxxx-xxxx-xxxx"  # From appleid.apple.com
export APPLE_TEAM_ID="HHHHZ6UV26"
```

## Usage

```bash
./release.sh 1.1.0              # Full release (signed + notarized)
./release.sh 1.1.0 --skip-sign  # Dev build (no signing)
./release.sh 1.1.0 --dry-run    # Preview only
```

## How Updates Work

```
version.json on website ←── App checks on launch
        │
        ▼
If newer version found → Shows "Update Available" alert
        │
        ▼
User clicks "Download" → Opens browser to DMG
        │
        ▼
User installs manually (standard macOS flow)
```

**No Sparkle framework, no EdDSA keys, no complexity.**

Website is HTTPS (secure), app is notarized (trusted by Apple).

## File Structure

```
SuperDimmer-Website/
├── version.json          ← Updated by release.sh
├── releases/
│   └── SuperDimmer-v1.0.0.dmg
├── release-notes/
│   └── v1.0.0.html
└── packaging/
    └── release.sh        ← Run this!
```
