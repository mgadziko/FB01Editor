# Forest Module Boundary

Forest currently ships as an FB-01 editor. The module boundary exists so the app
shell can stay stable while other Yamaha 4-operator FM devices are studied later.
Do not add behavior for another synth until matching hardware can verify it.

## App Shell

The app shell owns:

- macOS windows, menus, preferences, and document lifecycle
- recent file and recent fetch lists
- the status/library window
- the floating Live Keyboard palette
- common progress and confirmation dialogs
- user-facing editor paradigms such as Console Sections and FM Routing Patch Bay

The app shell should ask the active module for vocabulary, capabilities, slot
ranges, and parameter descriptors. It should avoid embedding new hardcoded
device facts such as writable bank numbers or read-only slot ranges.

## Synth Module

A synth module owns:

- identity and user-facing device vocabulary
- file extension profiles and document type declarations
- supported document kinds
- capability flags and module-owned command descriptors
- slot ranges and bank rules
- parameter descriptors and parameter binding descriptors
- default blank document templates
- document candidate extraction from module-specific SysEx/data artifacts
- device-specific data structures
- SysEx request, parse, fetch, store, and cache behavior

FB-01-specific code should keep the `FB01` prefix. Shared concepts should use
neutral names such as `SynthModule`, `SynthDocumentDescriptor`, and
`SynthParameterDescriptor`.

## Current Adapter

`FB01ModuleAdapter` is the only concrete module adapter. It exposes
`FB01ModuleServices`, `FB01SynthModule`, and the FB-01 service implementations
behind module-facing protocols.

`FB01DocumentService` owns FB-01 blank voice/configuration templates and
extraction of voice/configuration document candidates from `FB01Artifact`.
App-level document extraction wraps those results in neutral document payloads
with the active module identity attached.

The FB-01 module also declares the app/menu commands it supports. The app shell
still executes the existing FB-01 actions, but command labels and availability
now come through module descriptors instead of being only hardcoded in SwiftUI
menus. Parameter binding descriptors are intentionally descriptive at this
stage: they identify which module parameter a UI control edits, but they do not
yet replace the existing typed FB-01 editing code.

The adapter is not a DX100 module. It is a boundary around the working FB-01
implementation.

The current FB-01 file profile is:

- `.fbv`: single voice document
- `.fbc`: single configuration document
- `.fbvb`: voice bank document
- `.fbcb`: configuration bank document
- `.fbx`: generic FB-01 SysEx

`.syx` remains useful as a raw SysEx import/debugging format, but module-owned
extensions are the preferred Forest document convention.

## Future Devices

Before adding a real device module:

1. Capture and verify its SysEx identity and dumps from hardware.
2. Build a small service adapter that satisfies the neutral module protocols.
3. Add tests using captured fixtures.
4. Only then expose device selection in the UI.

Mock modules in tests are useful for proving the app architecture is not
hardwired to the FB-01, but they are not a substitute for hardware verification.
