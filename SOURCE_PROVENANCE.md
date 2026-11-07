# Source correspondence and release boundary

This public snapshot corresponds to the release-source working copy used for Lockstead 1.2.4 (21), based on private source commit `1e308ef5b0bd17385408bf97a2187d0d53608247`. It updates the earlier public snapshot without importing any private Git history. The source-copy record identifies that clean base; the release records and the actual archived app and all three extensions confirm version 1.2.4 and build 21. The release working copy subsequently reserved build 22 through the Archive post-action. This public snapshot deliberately sets build 21 to identify the archived release, not the next reserved build.

SOURCE_MANIFEST.json records the selected release-source hashes, public hashes and deliberate differences. The release working copy is not itself a Git commit; its exact correspondence is recorded by file hashes rather than by claiming the older private commit alone contains version 1.2.4. The prior snapshot base is retained for historical reference.

## Deliberate differences

- Shared/ReviewAccessStore.swift has a synthetic reviewer fixture with new salt/hash. The real private review code, its salt/hash and private review notes are excluded. Tests/LocksteadTests/ReviewAccessStoreTests.swift and VIPProductsTests.swift use the public synthetic fixture. The review verification algorithm and original default expiry are retained; the public fixture is never a secret. Production StoreKit product IDs, purchases and restoration logic are unchanged.
- All nine PNG files are new, original procedural placeholders. App icons, settings previews and launch appearance differ from the official product. Run the included generator to reproduce them; it uses no original artwork or third-party inputs.
- .gitignore excludes signing material, local configuration and build outputs.
- README and license/privacy/resource/brand/provenance documentation are newly written for this public snapshot.

Except for the build-number normalization and deliberate differences listed here, selected app source, build definitions, entitlements and tests correspond byte-for-byte to the release-source hashes. Runtime Swift code is unchanged from the previous public snapshot. The string catalog includes release-time ordering and extraction-state changes, with unchanged translated strings. The identifiers retain the original source definitions; forks must use their own valid signing and App Group identifiers when building for devices. No access to the owner's account or signing assets is granted.

The original project's uncommitted modifications and marketing-site directory are excluded. Operational App Store release notes, development-agent reports, old design/planning notes, generated projects, local developer configuration, credentials, Git history, build logs, test results and caches are excluded.

Source availability does not establish an independent audit or byte-for-byte equivalence with an App Store binary. The public build explicitly differs in reviewer fixture and artwork.
