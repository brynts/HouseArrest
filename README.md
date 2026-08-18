# HouseArrest

Container patch tool for iOS. Apply file replacements into **app data** and **App Group** containers.

> Display name: **HouseArrest**  
> Bundle ID: `com.apple.mobile.MobileHouseArrest` (required for container access)

## Focus (v1)

- **Home** — device info, compatibility, quick status
- **Patches** — import / create / apply packages (app + `group.*`)
- Logs & Settings

Patch-first architecture with App Group support from day one.

## Package format

Uses `.ha` packages (schema v1).

## Build

Open `HouseArrest.xcodeproj` in Xcode 16+, target iOS 17+.

Or run **Actions → Build IPA** (manual only). Output is an unsigned IPA on a **draft** release.

Container access layer plugs into `ContainerAccess` (MCM + path grant). Not included in this scaffold until wired.

## Status

Scaffold. Wire `ContainerAccess` before device patch testing.
