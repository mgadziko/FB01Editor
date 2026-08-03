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
- selector-window grid layouts for module-specific bank/configuration browsers
- full-device cache scope and cache progress wording
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
It also owns module-specific voice/configuration document file reads and writes.
App-level document file helpers wrap those results in neutral document payloads
with the active module identity attached, so document windows no longer need to
construct single voice/configuration SysEx artifacts directly for ordinary file
load/save.

The FB-01 module also declares the app/menu commands it supports. The app shell
routes those commands through a small command runner that currently dispatches
to the existing FB-01 document model actions. Command labels and availability
come through module descriptors instead of being only hardcoded in SwiftUI
menus.

The FB-01 module declares the selector layouts for its Voice Bank and
Configuration Bank windows. These layouts are intentionally module-owned because
other Yamaha 4-operator devices may have different bank counts, slot counts, or
no configuration bank concept at all.

The FB-01 module also declares the scope of a complete device cache: voice banks
1-7, stored configurations 1-20, and the current configuration buffer. The app
shell can report cache coverage and build progress messages from this module
description instead of assuming that every supported device has the same cache
shape.

General MIDI bank installation remains an FB-01-specific command. It is exposed
only through the FB-01 module command descriptors and guarded by the FB-01
General MIDI capability flag. Future modules should not inherit that workflow
unless they explicitly implement and verify an equivalent.

`ActiveSynthModule.current` is an internal placeholder for future module
selection. It is deliberately fixed to FB-01 until another real hardware module
can be verified.

Parameter binding descriptors are intentionally descriptive at this stage: they
identify which module parameter a UI control edits, but they do not yet replace
the existing typed FB-01 editing code.

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
