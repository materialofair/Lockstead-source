# Source correspondence and release boundary

This is an independent source snapshot of the owner's private Lockstead commit `e0e3b2ecf452650f8e2ebb9a7dc9c3d72bf9a2d4` (2026-10-07). It contains no parent Git history. SOURCE_MANIFEST.json maps every selected source file to its original Git blob and SHA-256 and identifies modified public files.

## Deliberate differences

- Shared/ReviewAccessStore.swift has a synthetic reviewer fixture with new salt/hash. The real private review code, its salt/hash and private review notes are excluded. Tests/LocksteadTests/ReviewAccessStoreTests.swift and VIPProductsTests.swift use the public synthetic fixture. The review verification algorithm and original default expiry are retained; the public fixture is never a secret. Production StoreKit product IDs, purchases and restoration logic are unchanged.
- All nine PNG files are new, original procedural placeholders. App icons, settings previews and launch appearance differ from the official product. Run the included generator to reproduce them; it uses no original artwork or third-party inputs.
- .gitignore excludes signing material, local configuration and build outputs.
- README and license/privacy/resource/brand/provenance documentation are newly written for this public snapshot.

All other selected source, build definitions, entitlements and test files correspond byte-for-byte to the listed original blobs. The identifiers retain the original source definitions; forks must use their own valid signing and App Group identifiers when building for devices. No access to the owner's account or signing assets is granted.

The original project's uncommitted modifications and marketing-site directory are excluded. Operational App Store release notes, development-agent reports, old design/planning notes, generated projects, local developer configuration, credentials, Git history, build logs, test results and caches are excluded.

Source availability does not establish an independent audit or byte-for-byte equivalence with an App Store binary. The public build explicitly differs in reviewer fixture and artwork.
