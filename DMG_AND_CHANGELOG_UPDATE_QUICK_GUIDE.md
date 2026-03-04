# DMG and Changelog Update Quick Guide

> **Last Updated:** March 3, 2026  
> **Current Version:** 1.0.7 (build 14)

One-page reference for releasing a new SuperDimmer version and updating the site.

---

## Prerequisites

- **For signed/notarized releases:** Set env vars in `~/.zshrc`:
  ```bash
  export APPLE_ID="your@email.com"
  export APPLE_APP_PASSWORD="xxxx-xxxx-xxxx-xxxx"
  export APPLE_TEAM_ID="HHHHZ6UV26"
  ```
  Then: `source ~/.zshrc`

---

## Release Flow (One Command + Manual Changelog)

### 1. Run the Release Script

```bash
cd /Users/ak/UserRoot/Github/SuperDimmer/SuperDimmer-Website/packaging

# Full release (signs, notarizes)
./release.sh X.Y.Z

# Dev build (no signing)
./release.sh X.Y.Z --skip-sign

# Preview only
./release.sh X.Y.Z --dry-run
```

**What it does:**
- Updates `Info.plist` (version + build)
- Builds Release app
- Signs with Developer ID
- Creates DMG via `create-dmg.sh`
- Notarizes (if creds set)
- Updates `version.json`
- Copies DMG to `releases/`
- Creates `release-notes/vX.Y.Z.html` template

### 2. Update Changelog (Manual)

Edit `SuperDimmer-Website/changelog.html`:

1. Add a new `release-entry` div at the **top** of the `.changelog-entries` section (newest first)
2. Copy structure from the v1.0.7 entry
3. Add `release-tag latest` to the new release
4. Remove `latest` from the previous release

### 3. Edit Release Notes (Optional)

```bash
open SuperDimmer-Website/release-notes/vX.Y.Z.html
```

Replace template bullets with real changes.

### 4. Commit and Push

```bash
cd /Users/ak/UserRoot/Github/SuperDimmer
git add SuperDimmer-Mac-App/SuperDimmer/Supporting\ Files/Info.plist \
        SuperDimmer-Website/version.json \
        SuperDimmer-Website/changelog.html \
        SuperDimmer-Website/release-notes/ \
        SuperDimmer-Website/releases/
git commit -m "Release vX.Y.Z - [brief description]"
git push
```

Cloudflare Pages auto-deploys; users see the update within 1–2 minutes.

---

## File Locations

| File | Purpose |
|------|---------|
| `SuperDimmer-Mac-App/SuperDimmer/Supporting Files/Info.plist` | App version (CFBundleShortVersionString, CFBundleVersion) |
| `SuperDimmer-Website/version.json` | Update checker feed (downloadURL, releaseNotesURL) |
| `SuperDimmer-Website/changelog.html` | Public version history page |
| `SuperDimmer-Website/release-notes/vX.Y.Z.html` | Per-version release notes |
| `SuperDimmer-Website/releases/SuperDimmer-vX.Y.Z.dmg` | Installer |
| `SuperDimmer-Website/packaging/release.sh` | Main release script |
| `SuperDimmer-Website/packaging/create-dmg.sh` | DMG builder (called by release.sh) |

---

## Verify After Push

- https://superdimmer.com/version.json
- https://superdimmer.com/changelog.html
- https://superdimmer.com/releases/SuperDimmer-vX.Y.Z.dmg

---

## Troubleshooting

| Issue | Fix |
|-------|-----|
| No Developer ID | Use `--skip-sign` for dev builds |
| Notarization fails | Check APPLE_ID, APPLE_APP_PASSWORD, APPLE_TEAM_ID |
| Build fails | `xcode-select -p`; clean: `rm -rf build/DerivedData` |
| DMG creation path wrong | `create-dmg.sh` reads app path from script dir; `release.sh` passes it |
