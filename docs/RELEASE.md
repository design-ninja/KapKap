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
5. **FFmpeg build tools**: `brew install pkg-config cmake meson ninja`. The bundled FFmpeg is
   built from pinned sources by `script/build_ffmpeg.sh`, which downloads them into
   `dist/release/sources/` and checks their SHA-256. x264 has no release tarballs: keep
   `x264-b35605a.tar.bz2` there. Each release carries these archives as
   `KapKap-<version>-third-party-sources.tar`, since FFmpeg, x264 and x265 are GPL. Gifsicle, also
   GPL, is built the same way by `script/build_gifsicle.sh` and its archive is packed alongside. To
   update a component, change its line in the script and its row in `THIRD_PARTY_NOTICES.md`.

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
builds with the hardened runtime and the Developer ID certificate (the shipped binaries are
stripped; `KapKap.app.dSYM` next to the app keeps the symbols for crash reports), packs exactly
the source archives FFmpeg and Gifsicle were built from (each must be listed in `THIRD_PARTY_NOTICES.md`), notarizes and staples the app,
zips it, writes an `appcast.xml` signed with the Sparkle key (release notes included), commits,
tags `v0.2.0`, pushes and creates the GitHub release with the zip and the appcast attached.

If any step fails before the release commit, `Info.plist` and `CHANGELOG.md` are restored, so the
script can simply be run again.

Versions follow [Semantic Versioning](https://semver.org). The build number only ever grows:
Sparkle compares it to decide what is newer.

## Checking an update end to end

Build an older copy that points at a local feed and let it update itself: set `SUFeedURL` to
`http://127.0.0.1:8765/appcast.xml` in a copy of `Info.plist`, build two versions with
`KAPKAP_INFO_PLIST`, `KAPKAP_APP` and `KAPKAP_RELEASE=1`, run `generate_appcast` over a folder
holding the newer zip and serve that folder with `python3 -m http.server 8765`.
