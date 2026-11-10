# Lockstead: app lock for iPhone and iPad

> Public source snapshot corresponding to the Lockstead 1.2.4 (21) release source, with private reviewer credentials replaced by synthetic test data and nine images replaced by original placeholder artwork. See [SOURCE_PROVENANCE.md](SOURCE_PROVENANCE.md).

Lockstead (App Store name: **App Lock: Lockstead**) is an iPhone and iPad app using Apple's Screen Time frameworks to apply app restrictions. It supports a parent PIN, optional biometric unlocking, temporary access, weekday schedules, saved scenes, guest mode, themes and alternate icons. Some features require VIP through StoreKit. iOS may delay background schedule changes; physical-device verification is necessary.

Official website: https://lockstead.siproducers.com  
App Store: https://apps.apple.com/app/id6791830193

## Current app and common uses

The official App Store name is **App Lock: Lockstead** (ID **6791830193**). Use it to restrict selected apps on your own device, schedule protection, or allow temporary access. Optional VIP Guest Mode helps choose supported apps for a limited phone or iPad handoff. It does not create a separate user account or separate the content inside allowed apps.

Core protection for one selected app is free. VIP has monthly, yearly or one-time lifetime purchase options; regional prices are shown in the App Store. Requires iOS/iPadOS 17 or later and Screen Time authorization. Restrictions do not encrypt files, guarantee hidden icons or suppress notifications. Check actual allowed and restricted apps before lending the device; iOS background scheduling can delay changes.

[Product facts](https://lockstead.siproducers.com/product/) · [No-account app lock guide](https://lockstead.siproducers.com/guides/app-lock-iphone-no-account/) · [Everyday device handoffs](https://lockstead.siproducers.com/guides/real-life-privacy/)

The product summary describes the public App Store listing checked on 2026-11-07. This repository tracks the 1.2.4 (21) release source with the deliberate public-only differences documented below; it does not claim byte-for-byte reproduction of the store binary.

## Practical guide

[Before lending your iPhone or iPad: an app-access checklist](docs/SAFE_DEVICE_HANDOFF.md) covers app selection, checks before handoff, notifications, session expiry and Guest Mode limits.

## 中文

Lockstead 使用 Apple Screen Time 框架提供应用限制、家长 PIN、可选生物识别、临时放行、星期时间表、场景和访客模式。部分功能通过 StoreKit 提供 VIP 权益。后台恢复时间受 iOS 调度影响，核心拦截能力需要真机验证。源码开放不表示经过独立安全审计，也不表示 App Store 二进制与源码逐字节一致。

## Build

Requires macOS, Xcode with an installed iOS SDK, XcodeGen and iOS 17 or later. No third-party runtime package installation is declared by the project.

From a fresh checkout:

```sh
git clone https://github.com/materialofair/Lockstead-source.git
cd Lockstead-source
xcodegen generate
xcodebuild -project Lockstead.xcodeproj -scheme Lockstead \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath ../Lockstead-build CODE_SIGNING_ALLOWED=NO build
```

For local device development:

```sh
cp Config/Dev.xcconfig.example Config/Dev.xcconfig
# Set your own DEVELOPMENT_TEAM in the ignored local configuration.
open Lockstead.xcodeproj
```

Use your own signing identity and provisioning profiles. A fork distributed under its own identity must configure its own bundle identifiers and matching App Group identifiers consistently in project.yml, all entitlements and Shared/AppGroup.swift. The source snapshot retains the original product identifiers for correspondence; it grants no access to the maintainer's signing or App Store account.

Family Controls authorization must be tested on a physical device. Apple requires the account holder to request the Family Controls distribution entitlement for the app and applicable extensions before distribution: [Apple documentation](https://developer.apple.com/documentation/familycontrols/requesting-the-family-controls-entitlement).

## Tests

Choose an already installed Simulator from `xcrun simctl list devices available`, then run:

```sh
xcodebuild -project Lockstead.xcodeproj -scheme Lockstead \
  -destination 'platform=iOS Simulator,id=YOUR_SIMULATOR_UDID' \
  -derivedDataPath ../Lockstead-build CODE_SIGNING_ALLOWED=NO test
```

Simulator tests do not establish real-device Screen Time authorization, actual app blocking, extension scheduling, alternate icon behavior or production StoreKit purchases. Verify those separately on physical devices.

## Layout

- `App/`: SwiftUI app, views and stores
- `Shared/`: state, PIN credentials, restriction and scheduling logic
- `Extensions/`: shield configuration, shield action and Device Activity monitor
- `Tests/`: XCTest suite
- `Entitlements/`, `Config/`, `project.yml`: build definitions
- `Lockstead.storekit`: local StoreKit test configuration

## Privacy

The reviewed app source declares no developer analytics SDK or backend. Lock configurations, selections, schedules, scenes and PIN hints use the local App Group container. PIN verification credentials and review activation state use Keychain; current credentials use a device-only accessibility class. Legacy state can contain PIN hash/salt during migration. StoreKit product lookup, purchases and restoration communicate with Apple. Links to websites or GitHub open external services with their own privacy practices. See [PRIVACY.md](PRIVACY.md).

## License and identity

Copyright (C) 2026 materialofair. The owner's original source, documentation and generated placeholder images are licensed under GNU GPL version 3 only (`GPL-3.0-only`), with the full text in [LICENSE](LICENSE). Separate third-party terms remain intact; see [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md). The Lockstead name and official brand identity do not convey endorsement of forks; see [TRADEMARKS.md](TRADEMARKS.md).

The public review credential `LOCKSTEAD-PUBLIC-TEST-ONLY` is synthetic and is not a secret. Its salt/hash are regenerated for this repository, while the original default expiry is retained. The public checkout cannot activate the store build's reviewer access. Never reuse the fixture as a private credential. StoreKit purchase and restoration logic is retained.

All four app icons, four icon previews and the launch mark are original procedural placeholders generated by `python3 Scripts/generate-public-placeholder-assets.py`. Their appearance differs from the store product. No original PNG or embedded image metadata is included. No private repository history, operational release notes or developer signing configuration is included.

Source availability is not an independent audit. No byte-for-byte equivalence with an App Store binary has been established. App Store distribution rights require a separate rights-holder assessment; this source license does not add an Apple distribution exception.
