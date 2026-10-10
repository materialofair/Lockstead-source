# Snapshot validation

Validated locally on 2026-10-10 using Xcode 27.0 (27A266a), XcodeGen and an already installed iOS 26.5 iPhone 17 Simulator.

- XcodeGen project generation succeeded.
- xcodebuild compiled the main app, three extensions and unit tests with CODE_SIGNING_ALLOWED=NO.
- XCTest: 190 tests executed, zero failures; TEST SUCCEEDED.
- Source-manifest hashes remained unchanged after project generation.
- Public files were scanned for common private keys, GitHub tokens, AWS access keys, sensitive assignments, private reviewer code, original review salt/hash and private absolute paths; no matches were found.
- All nine included PNGs differ from original product artwork and contain only IHDR, IDAT and IEND chunks, with no ancillary metadata.
- The only included hidden file is .gitignore. No original Git history, logs, xcresult, certificates, profiles, local signing configuration or generated projects are included.

These checks are bounded release checks, not an independent security or legal audit. No physical-device Family Controls authorization, production purchase, real-device background timing or App Store binary equivalence was tested.

Reproduce using the README build/test steps with an installed Simulator UDID. No runtime downloads are required if the SDK/runtime is already installed. Existing warnings about an immutable query variable and extension AppIntents metadata do not prevent compilation.
