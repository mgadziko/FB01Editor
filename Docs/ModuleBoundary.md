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
- supported document kinds
- capability flags
- slot ranges and bank rules
- parameter descriptors
- device-specific data structures
- SysEx request, parse, fetch, store, and cache behavior

FB-01-specific code should keep the `FB01` prefix. Shared concepts should use
neutral names such as `SynthModule`, `SynthDocumentDescriptor`, and
`SynthParameterDescriptor`.

## Current Adapter

`FB01ModuleAdapter` is the only concrete module adapter. It exposes
`FB01ModuleServices`, `FB01SynthModule`, and the FB-01 service implementations
behind module-facing protocols.

The adapter is not a DX100 module. It is a boundary around the working FB-01
implementation.

## Future Devices

Before adding a real device module:

1. Capture and verify its SysEx identity and dumps from hardware.
2. Build a small service adapter that satisfies the neutral module protocols.
3. Add tests using captured fixtures.
4. Only then expose device selection in the UI.

Mock modules in tests are useful for proving the app architecture is not
hardwired to the FB-01, but they are not a substitute for hardware verification.
