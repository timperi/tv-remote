# Room Remote

A personal iPhone remote for a Sony TV (or any other set) running Google TV / Android TV. It talks to the TV directly on the local Wi-Fi network using Android TV Remote protocol v2, the same protocol as Google's own phone remote.

There is no account, subscription, ad, cloud backend, or analytics. The pairing certificate stays in the iPhone Keychain. Commands never leave the home network.

Requires iOS 17 or later. Day-to-day work can stay on Linux. Apple only ships the iOS SDK with Xcode, so the installable file is built by [`.github/workflows/ipa.yml`](.github/workflows/ipa.yml) on a hosted Mac. That file is an unsigned IPA. Sideloadly or AltStore on Windows re-signs it with a free Apple ID.

## What it does

- Finds TVs advertising `_androidtvremote2._tcp` (Bonjour), and lets you type an IP address if discovery misses one.
- Pairs once. The TV shows a 6-character hexadecimal code; you type it into the phone. The client certificate is stored in the Keychain.
- Sends power (sleep / wake), a D-pad with OK, back, home, volume, mute, channel, and play/pause.
- Holds a direction, volume, or channel key to repeat it.
- Optional swipe touchpad in place of the D-pad, and optional haptic taps.
- Launches YouTube (`https://www.youtube.com`) and Netflix (`netflix://`).
- Types into the TV's text field when one is focused.

## Protocol, checked against open-source clients

This is not a Sony-specific protocol. Sony Google TVs ship Google's Android TV Remote Service, and that service speaks protocol v2.

Checked against [tronikos/androidtvremote2](https://github.com/tronikos/androidtvremote2) (the library Home Assistant uses), the AOSP Polo pairing sources, and the message schemas those projects publish:

| Piece | What the implementations actually do |
| --- | --- |
| Discovery | DNS-SD / Bonjour service `_androidtvremote2._tcp` |
| Pairing | TLS on port **6467**. The phone presents a self-signed RSA client certificate and does not verify the TV's self-signed certificate. |
| Commands | TLS on port **6466**, same client certificate, after pairing. |
| Framing | Each protobuf message is prefixed with a protobuf varint length. |
| Pairing messages | `polo.proto` `OuterMessage`, protocol version **2** (the proto default is 1; v2 clients send 2). Service name `atvremote`. The phone is the input role and asks for a 6-symbol hexadecimal code. |
| Secret | SHA-256 of client modulus, client exponent, server modulus, server exponent, then the nonce. Leading `0x00` bytes are stripped from each integer first. That is `PoloChallengeResponse.getAlpha` in AOSP `google-tv-pairing-protocol`. |
| Code on screen | Six hex characters. The first byte must equal `digest[0]`. The other two bytes are the nonce. The phone sends the full 32-byte digest, not the older Polo "gamma" value. This matches `androidtvremote2`'s `pairing.py`. |
| Commands | `remotemessage.proto` `RemoteMessage`: key inject, ping reply, configure / set-active, IME batch edit for text, and `remote_app_link_launch_request` for app links. |
| App links | A string that already contains `://` is sent as-is. A bare package id is prefixed with `market://launch?id=`. Deep links are more reliable than package ids on current Google TV builds. |

`swift test` checks the Swift encoder against byte strings produced by Python's protobuf compiler from those `.proto` files, and checks the pairing digest against hashlib for the same inputs. It also checks split length prefixes, the checksum on the pairing code, and the shape of the self-signed certificate.

## Project layout

- `Sources/ATVRemoteCore/` is pure Swift: protobuf, framing, pairing state machine, remote commands, SHA-256, and the X.509 certificate builder. It builds on Linux and on a Mac.
- `App/` is the SwiftUI app: Bonjour, Network.framework TLS, Keychain identity, and the remote UI.
- `RoomRemote.xcodeproj` is the iOS app. It compiles the core sources and the app sources together. It has no entitlements file.
- `Scripts/package-unsigned-ipa.sh` builds a device `.app` with code signing turned off and zips it into an IPA.
- `.github/workflows/ipa.yml` runs that script on a GitHub-hosted `macos-15` runner and publishes the IPA.

## Tests on Linux or a Mac

Install Swift 5.9 or newer, then from this directory:

```bash
swift test
```

That does not build the iPhone app. The iOS SDK is not available on Linux.

## Install on an iPhone

The path below matches a Linux PC, a Windows 10 dual-boot, and a free Apple ID. You download an unsigned IPA that a hosted Mac already compiled, then Sideloadly or AltStore on Windows re-signs it. The Apple ID password stays on that Windows PC. The CI job never sees it.

A free Apple ID signature lasts **7 days**. Refresh the app before then or it stops opening. You can refresh it as many times as you want. The phone and the TV have to be on the same Wi-Fi. Guest networks and AP isolation hide the TV from the phone.

On the iPhone, turn on Developer Mode first: Settings → Privacy & Security → Developer Mode, then restart when iOS asks. iOS 17 or later is required.

### 1. Download the unsigned IPA

This repository lives on Origin. Origin does not run macOS CI. Its Apps tab can attach Depot or Buildkite, and both of those read a GitHub Actions workflow file, but neither one gives you a Mac here:

- Depot CI, the engine Origin connects, runs Linux sandboxes only. A job that says `runs-on: macos-15` is rewritten to `depot-ubuntu-latest`, and Xcode is not on that image, so the IPA job fails. Depot's Mac runners (`depot-macos-15` and similar) are GitHub Actions runners. They are not available inside Depot CI on Origin.
- Buildkite on Origin still needs a Mac agent that you own.

The simplest place the workflow actually runs is **GitHub Actions** on GitHub's own `macos-15` runner. Standard runners, including that Mac, are free on a public repository. On a private repository they draw from the account's included minutes, and macOS minutes count at about ten times a Linux minute.

1. Create a free GitHub repository. A public repository avoids the macOS minute meter. The workflow does not contain the Apple ID or any other secret.
2. Push this project to it. From a clone that already has the Origin remote:

   ```bash
   git remote add github git@github.com:YOU/room-remote.git
   git push github main
   ```

3. GitHub runs **Unsigned IPA** on that push. When it is green, open the repository's **Releases** page and download `RoomRemote-unsigned.ipa` from the **Unsigned IPA** pre-release (tag `unsigned`). That asset is the IPA itself.
4. The same file is also attached to the workflow run as the artifact `RoomRemote-unsigned-ipa`. The Actions download is a zip with the IPA inside it. Unzip once, then give `RoomRemote-unsigned.ipa` to Sideloadly or AltStore.

Each push to `main` replaces that pre-release with a build of the new commit. To build a different bundle id, open Actions → Unsigned IPA → Run workflow and set the bundle id input. Use that when the free Apple ID reports that `personal.roomremote` is already registered.

`Scripts/package-unsigned-ipa.sh` is what the runner executes. It compiles for a real device (`iphoneos`, arm64), turns code signing off, and refuses to publish an IPA that still contains a provisioning profile, a signature, or an entitlements file.

### 2. Install from Windows with Sideloadly

Sideloadly is the shorter path when Room Remote is the only app you are sideloading.

1. Install iTunes from [apple.com/itunes](https://www.apple.com/itunes/). Use that installer. If the Microsoft Store edition of iTunes is already installed, uninstall it first. The Store edition does not include the USB driver Sideloadly talks to.
2. Download Sideloadly from [sideloadly.io](https://sideloadly.io) and install it.
3. Plug the iPhone into the Windows PC with a cable. Unlock the phone and tap Trust.
4. Drag `RoomRemote-unsigned.ipa` into Sideloadly. Enter the Apple ID. Sideloadly asks for the account password and then the two-factor code Apple sends.
5. Click Start. Sideloadly re-signs the IPA with that Apple ID and installs it.
6. If Apple says the bundle id is unavailable, change it in Sideloadly's advanced options to something unique such as `personal.roomremote.yourname`, or rerun the GitHub workflow with that bundle id and install the new IPA.
7. On the iPhone open Settings → General → VPN & Device Management, trust the developer certificate, then open Room Remote.
8. The first time the app searches for a TV, allow local network access.

To refresh before the 7 days run out, plug the phone in, open Sideloadly, and press Start again with the same IPA.

### 3. Install from Windows with AltStore and AltServer

AltStore is the better fit if you want the phone to refresh itself while the PC is on the same Wi-Fi. AltStore counts as one of the free account's three app slots, and Room Remote counts as a second.

1. Install iTunes and iCloud from Apple's website, the same way as above: the installers on apple.com, after removing the Microsoft Store editions if those are present. Sign in to iCloud with the free Apple ID.
2. Download AltServer from [altstore.io](https://altstore.io) and install it. It lives in the Windows system tray.
3. Plug in the iPhone, unlock it, and tap Trust. In the AltServer tray menu, choose Install AltStore and pick the phone. Approve the Apple ID prompt, including the two-factor code.
4. On the iPhone, trust the certificate under Settings → General → VPN & Device Management, then open AltStore.
5. Install Room Remote from AltStore (My Apps, then the + button) by choosing `RoomRemote-unsigned.ipa`. AltStore re-signs it with the same Apple ID.
6. Allow local network access when Room Remote asks.

To refresh, leave AltServer running on Windows and put the iPhone on the same Wi-Fi, or plug in the cable. Open AltStore and refresh Room Remote before the 7 days run out. AltStore also refreshes itself on that schedule.

### Free Apple ID limits

These limits come from Apple, and both Windows tools hit them:

- The installed app stops opening 7 days after it was signed. Refreshing restarts the clock.
- Three sideloaded apps can be installed with one free Apple ID at a time. AltStore itself uses one slot.
- A free account can register only a small number of new bundle ids per week (about ten). Rebuilding over and over with a new bundle id uses that allowance up.
- The app has no entitlements file. A free account can sign the default Keychain access and the local-network usage declared in `Info.plist`. Push notifications, App Groups, iCloud, associated domains, and other paid capabilities are not used, and adding them would make a free Apple ID refuse to sign the IPA.
- Developer Mode stays on, and the certificate has to be trusted on the phone.
- The signed copy runs only on devices registered to that Apple ID.

### If you have a Mac

Xcode 15 or newer includes the iOS 17 SDK. A free Apple ID from Xcode is the same 7-day Personal Team install. Plug the phone back into the Mac and press Run to refresh it. A free account cannot use TestFlight.

1. Install Xcode from the Mac App Store. Open it once and let it install the extra components.
2. In Xcode, sign in with the Apple ID: Xcode → Settings → Accounts → +.
3. On the iPhone, tap Trust when the Mac asks. Wireless debugging also works after the first trust.
4. Open `RoomRemote.xcodeproj`.
5. Select the **RoomRemote** target, open **Signing & Capabilities**, check **Automatically manage signing**, and choose the Personal Team. If Xcode says the bundle id `personal.roomremote` is unavailable, change it to something unique such as `personal.roomremote.yourname`. Leave the entitlements list empty.
6. Choose the iPhone as the run destination (the scheme is **RoomRemote**) and press Run.
7. If the first launch says Untrusted Developer, open Settings → General → VPN & Device Management, trust the certificate, then open Room Remote again.

You can also run `Scripts/package-unsigned-ipa.sh` on that Mac and install the IPA with Sideloadly or AltServer instead of pressing Run.

### Paid Apple Developer Program and TestFlight

The [Apple Developer Program](https://developer.apple.com/programs/) is 99 USD per year. A paid membership removes the 7-day limit. TestFlight builds are valid for 90 days, and the distribution certificate is valid for a year. This is optional. The Windows steps above do not need it.

1. Enroll, then accept any agreements in App Store Connect.
2. Follow the Mac steps above, and choose the paid team. The bundle id has to be unique across the App Store. Change `personal.roomremote` if App Store Connect says it is already registered.
3. Create an iOS app record in App Store Connect with that same bundle id. The name can be Room Remote. You do not have to submit it for review to use TestFlight internal testing.
4. In Xcode choose **Any iOS Device (arm64)** as the destination. Product → Archive.
5. In the Organizer, **Distribute App** → **App Store Connect** → Upload.
6. In App Store Connect, open the app → TestFlight. Add yourself as an internal tester (internal testers must be users on the developer team).
7. Install Apple's TestFlight app on the iPhone and accept the build.

Export compliance: the app sets `ITSAppUsesNonExemptEncryption` to false. It only uses standard TLS, which Apple treats as exempt.

Ad Hoc is the other paid option. Register the iPhone's UDID in the developer portal, archive, and export an Ad Hoc IPA. Install that IPA with Apple Configurator or the Devices window in Xcode. The device has to be on the provisioning profile.

A rented Mac, Codemagic, or Xcode Cloud can upload to TestFlight the same way. Each of those still needs the paid membership and an App Store Connect API key. They are a different path from the unsigned IPA.

## Using it

1. Turn the TV on. It can already be on the home screen.
2. Open Room Remote and wait for the TV to appear. If it does not, tap + and enter the TV's IP address (on the TV: Settings → Network). Leave the ports at 6466 and 6467 unless you know the TV uses others. The discovered command port is whatever Bonjour advertises, and pairing uses the next port (6466 → 6467).
3. The first time, the TV shows a code. Type it into the phone. Allow the remote if the TV asks.
4. After that, the app reconnects with the saved certificate. Pair again from the ••• menu if the TV was factory reset or its Android TV Remote Service storage was cleared. "Reset pairing certificate" throws away the Keychain identity; the TV will then require a new pairing.

Text input only works when the TV is already in a text field. App launches use deep links, so YouTube or Netflix has to be installed.

## What was not verified on a real TV

This environment is Linux and has no iPhone and no Sony TV, so the following are implemented from the open-source clients but were not exercised against hardware:

- Bonjour discovery and the iOS local-network permission prompt.
- The TLS handshake, including whether a given TV accepts the self-signed certificate this app builds and stores in the Keychain.
- A full pairing against a television, and every remote button, text field, and app link on a Sony Google TV.
- `xcodebuild` itself. The Xcode project is a normal iOS 17 SwiftUI app (Xcode 14-compatible project format, Xcode 15 settings). It has not been compiled with Xcode here, because Xcode does not run on Linux, and this Origin repository does not run the macOS workflow. The protocol package has been compiled and its unit tests have been run with Swift 6 on Linux. The first green run of **Unsigned IPA** on GitHub is the first time the device binary is actually produced.

If a command connects and then the TV drops it, the usual fix on the TV is Settings → Apps → See all apps → Show system apps → Android TV Remote Service → Storage → Clear data, then pair again.
