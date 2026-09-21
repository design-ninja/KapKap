# Releasing KapKap

Installed copies update themselves with [Sparkle](https://sparkle-project.org). Their feed is
`https://github.com/design-ninja/KapKap/releases/latest/download/appcast.xml`, so publishing a
GitHub release with a new `appcast.xml` is what ships an update. `script/release.sh` does all of it.

## One-time setup

1. **Developer ID Application certificate** in the login keychain (Xcode → Settings → Accounts →
   Manage Certificates). The script finds it on its own.
2. **Sparkle signing key.** Every update is signed with it, and installed copies trust only this key:
   ```sh
   swift package resolve
   .build/artifacts/sparkle/Sparkle/bin/generate_keys --account KapKap
   .build/artifacts/sparkle/Sparkle/bin/generate_keys --account KapKap -x ~/KapKap-sparkle-key.txt
   ```
   Keep the exported file somewhere safe and offline. Losing the key means installed copies can
   never be updated again; leaking it lets anyone ship an "update".
3. **Notarization credentials**, with an [app-specific password](https://account.apple.com):
   ```sh
   xcrun notarytool store-credentials KapKap --apple-id <apple-id> --team-id 75V6XX25FG
   ```
4. **GitHub CLI** signed in with push access: `gh auth status`.

## Every release

1. Make sure `CHANGELOG.md` lists the changes under `## [Unreleased]`, and that everything is
   committed on `main`.
2. Try it without publishing anything:
   ```sh
   ./script/release.sh 0.2.0 --dry-run
   ```
3. Release:
   ```sh
   ./script/release.sh 0.2.0
   ```

The script moves the `[Unreleased]` notes under the new version, raises `CFBundleVersion`,
builds with the hardened runtime and the Developer ID certificate, notarizes and staples the app,
zips it, writes an `appcast.xml` signed with the Sparkle key (release notes included), commits,
tags `v0.2.0`, pushes and creates the GitHub release with the zip and the appcast attached.

Versions follow [Semantic Versioning](https://semver.org). The build number only ever grows:
Sparkle compares it to decide what is newer.

## Checking an update end to end

Build an older copy that points at a local feed and let it update itself: set `SUFeedURL` to
`http://127.0.0.1:8765/appcast.xml` in a copy of `Info.plist`, build two versions with
`KAPKAP_INFO_PLIST`, `KAPKAP_APP` and `KAPKAP_RELEASE=1`, run `generate_appcast` over a folder
holding the newer zip and serve that folder with `python3 -m http.server 8765`.
