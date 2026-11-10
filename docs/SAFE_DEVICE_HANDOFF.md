# Before lending your iPhone or iPad: an app-access checklist

Developer-maintained guide for Lockstead. Prepared with AI assistance from the published product documentation. Updated 10 November 2026. This is a workflow guide, not a security audit or a claim that every device configuration has been tested.

## What problem does this solve?

You want someone to use a few apps on your device without freely opening your other supported apps. Lockstead's optional VIP Guest Mode applies a temporary app allowlist through Apple's Screen Time frameworks. It does not create a separate iOS user account.

## Before you hand over the device

1. Decide which apps the person actually needs. Keep the list short.
2. Review what is already visible inside those apps. Allowing an app can expose its existing content; Guest Mode does not create a clean, empty copy of it.
3. In Lockstead, choose the supported apps for Guest Mode, select a duration from 15 minutes to 12 hours, and confirm the session. Screen Time authorization is required.
4. Try opening one allowed app and one app that should be restricted. Do this on the actual device before handing it over.
5. Check whether notification previews reveal information you do not want to share. Lockstead does not suppress notifications.

If the observed access does not match your intention, do not rely on the session for that handoff. Keep the device with you until you understand its current state.

## When the session ends

Check access again rather than assuming everything is unlocked. Lockstead reapplies the rules applicable at that time; existing schedules may still restrict apps. iOS background scheduling can delay changes.

## What this is not

- Not file encryption or a photo vault.
- Not a guarantee that icons disappear.
- Not separate data for another person inside allowed apps.
- Not remote management of somebody else's device.
- Not a guarantee that every route to private information is blocked.

## Free and paid features

Core protection for one selected app is free. Guest Mode and multi-app management require optional VIP. The App Store offers monthly, yearly and one-time lifetime options; check your regional purchase screen before buying. Requires iOS/iPadOS 17 or later.

## Verify the product

- [Current App Store listing and screenshots](https://apps.apple.com/app/id6791830193)
- [Source and build instructions](../README.md)
- [Public-source differences](../SOURCE_PROVENANCE.md)
- [Privacy details](../PRIVACY.md)

The published source is a documented snapshot with deliberate public-only differences. It is not proof of byte-for-byte equivalence with the App Store binary. Screen Time enforcement and purchases need separate physical-device verification.
