# Privacy handling in the reviewed source

No app-operated server, account system, analytics SDK or explicit telemetry client was found in the selected source. StoreKit performs product discovery, purchases and restoration through Apple; the app is not universally network-free. External website and GitHub links expose requests to their destination services when opened.

App Group storage holds restriction selections, schedules, scenes, temporary sessions, local preferences, PIN hints and mirrored VIP state. Screen Time selection tokens are handled through Apple's frameworks. Current PIN verification material is derived and stored in Keychain with kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly. Review activation uses a separate device-only Keychain entry. Legacy PIN hash/salt state is migrated by the credential code. A device-only credential policy does not establish that every App Group file is excluded from OS backups.

Biometric authentication uses LocalAuthentication. The source does not receive or store biometric templates. Platform privacy behavior, Apple purchase data and external websites are governed by their providers.

Do not submit real PINs, device tokens, purchases, logs with personal data or App Review access codes in public issues. Source publication does not establish an independent security audit or prove equivalence with an App Store binary.
