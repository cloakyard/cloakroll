# Signed public update

## Production verification on 18 November 2026

The installed build `20261118.1` found `20261118.2` using **Settings → About → Check for Updates** against the public HTTPS feed. **Install Update** downloaded the signed GitHub ZIP. **Install and Relaunch** replaced the app in Applications. About then displayed build `20261118.2`, and a second check reported that the app was up to date. The unauthenticated public DMG, ZIP and checksum manifest matched the local release files byte for byte.

All three apps used the same update offer, cancellable progress window, relaunch action and up-to-date dialog. An isolated copy of each release with an unavailable test feed showed Sparkle’s update error and **Cancel Update**. In those copies automatic checks and downloads started off. Enabling checks enabled the download switch, and disabling checks disabled it again. The production apps kept their own saved preferences.
