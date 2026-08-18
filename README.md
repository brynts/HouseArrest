# HouseArrest

Container patch tool for iOS. Apply file replacements into **app data** and **App Group** containers.

> Display name: **HouseArrest**  
> Bundle ID for MHA path: `com.apple.mobile.MobileHouseArrest` (required for container access)

## Focus (v1)

- **Home** — device info, compatibility, quick status
- **Patches** — import / create / apply / restore packages (app + `group.*`)
- Logs & Settings

Not a 3105 fork. New UI, patch-first architecture, App Group support from day one.

## Package format

Uses `.ha` packages (schema v1). Import of legacy `.3105` can be added later.

## Build

Open `HouseArrest.xcodeproj` in Xcode 16+, target iOS 17+.

Exploit / MCM bridge code is **not** bundled in this scaffold — plug your `MobileHouseArrest` container access layer into `ContainerAccess`.

## Status

Scaffold. Wire `ContainerAccess` to real MCM + `bad_query` before device testing.
