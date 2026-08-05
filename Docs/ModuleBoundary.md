# Forest Module Boundary

Forest Editor now has two active hardware paths:

- FB-01: the most complete voice/configuration editor path
- DX100/27: an active voice-only path with verified current-voice editing and
  Internal-bank support

The module boundary exists so the app shell can stay stable while individual
device behaviors are verified and expanded. Do not treat an unverified device
path as production-ready just because a sibling Yamaha module does something
similar.

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

The app currently uses concrete module services for:

- `FB01ModuleServices`
- `DX100ModuleServices`

Both expose device metadata and voice services behind shared module-facing
protocols. FB-01 additionally exposes configuration services.

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
shape. FB-01 cache progress event wording lives with `FB01DeviceCacheService`,
so the app shell does not need to switch over FB-01-specific cache events.

General MIDI bank installation remains an FB-01-specific command. It is exposed
only through the FB-01 module command descriptors and guarded by the FB-01
General MIDI capability flag. Future modules should not inherit that workflow
unless they explicitly implement and verify an equivalent.

Single-voice storage that rewrites and verifies a whole FB-01 bank image is
owned by `FB01VoiceService.storeVoiceInBankImage(...)`. The app shell still owns
user prompts, progress panels, and backup file placement, but the FB-01 service
owns Protect OFF, bank image rebuild, long SysEx send, readback request, and
verification retry behavior.

Configuration slot storage is similarly owned by
`FB01ConfigurationService.storeConfiguration(...)`. The app shell still owns
whether the user requested confirmation, status text, and backup file placement,
while the FB-01 service owns the Protect OFF, current-configuration send,
slot-store command, optional readback request, and parsed confirmation payload.

Current edit-buffer send/confirm workflows are now module-service owned:
`FB01ConfigurationService.sendCurrentConfigurationAndConfirm(...)` handles the
current configuration send plus readback parse, and
`FB01VoiceService.sendInstrumentVoiceAndConfirm(...)` handles instrument voice
send plus FB-01 status parsing. The app shell still chooses when to call these
operations and how to word the resulting status messages.

`ActiveSynthModule.current` is an internal placeholder for future module
selection. It is deliberately fixed to FB-01 until another real hardware module
can be verified.

Parameter binding descriptors are intentionally descriptive at this stage: they
identify which module parameter a UI control edits, but they do not yet replace
the existing typed FB-01 editing code.

The current FB-01 file profile is:

- `.fbv`: single voice document
- `.fbc`: single configuration document
- `.fbvb`: voice bank document
- `.fbcb`: configuration bank document
- `.fbx`: generic FB-01 SysEx

`.syx` remains useful as a raw SysEx import/debugging format, but module-owned
extensions are the preferred Forest document convention.

The current DX100/27 file profile is:

- `.dxv`: single voice document
- `.dxvb`: voice bank document
- `.dxx`: generic DX100/27 SysEx

Current verified DX100/27 behavior:

- fetch current edit voice
- fetch Internal bank
- load/save single voice files
- load/save voice bank files
- send edited voice data back to the current edit buffer for live audition

Current DX100/27 limitations:

- no configuration/function document support
- no verified device-side Bank A-D or preset-bank bulk recall/dump path yet
- no verified device-side bank-store workflow yet

## Future Devices

Before adding another real device module:

1. Capture and verify its SysEx identity and dumps from hardware.
2. Build a small service adapter that satisfies the neutral module protocols.
3. Add tests using captured fixtures.
4. Only then expose device selection in the UI.

Mock modules in tests are useful for proving the app architecture is not
hardwired to the FB-01, but they are not a substitute for hardware verification.
