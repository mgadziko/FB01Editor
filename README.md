# Forest Editor

Forest Editor is a macOS editor and librarian for Yamaha 4-operator FM
hardware, with the Yamaha FB-01 and DX100/27 currently in active development.

The app is centered on document windows: open, fetch, edit, save, and store
individual voices and configurations without having to treat a synth as one
giant library file. A status/library window remains available for global MIDI
state, open documents, and legacy source-library browsing.

The codebase is also separating the editor shell from concrete device modules.
Module capabilities, cache behavior, voice/configuration services, and document
fetch bridges now sit behind a clearer boundary so additional Yamaha 4-operator
modules can be evaluated without disturbing the working FB-01 editor.

## Current App

Forest Editor currently supports:

- load and save single voice files for FB-01 and DX100/27
- load and save single FB-01 configuration files
- load and save voice bank files for FB-01 and DX100/27
- fetch voices from the FB-01, including RAM banks and factory ROM banks
- fetch configurations from the FB-01, including read-only preset configurations
- store voices into writable FB-01 voice slots in Banks 1 and 2
- store configurations into writable FB-01 configuration slots 1-16
- copy a voice directly from one FB-01 slot to another without opening an editor window
- copy a configuration directly from one FB-01 slot to another without opening an editor window
- install a General MIDI-oriented 48-voice set into FB-01 Bank 1 or Bank 2
- display reset instructions for restoring the FB-01 from the front panel
- fetch the current edit voice from a DX100/27
- fetch the DX100/27 Internal voice bank
- send the current editable voice to the DX100/27 current edit buffer for live audition
- use a floating live on-screen keyboard and an external MIDI keyboard for auditioning
- pass through external MIDI performance messages such as notes, modulation, and pitch bend

Current DX100/27 limits:

- no configuration/function document support
- Bank A-D and preset-bank device fetch remain experimental and are not presented as standard fetchable banks
- DX current-voice and Internal-bank workflows are the verified device paths today

The app uses the terminology:

- **Load**: read a voice or configuration from a disk file
- **Save**: write a voice or configuration to a disk file
- **Fetch**: read a voice or configuration from the FB-01
- **Store**: write a voice or configuration to the FB-01

## Voice Editing

Voice documents support two editing paradigms, selectable from Preferences:

- **Console Sections**: grouped controls organized by parameter family
- **FM Routing Patch Bay**: a routing-first view that lays out operators according
  to the selected FM algorithm

The FM Routing Patch Bay is the preferred current UI. It presents the voice as
an FM signal-flow patch bay, with operators arranged by algorithm, arrows showing
modulator/carrier routing, operator enable highlighting, OP4 feedback routing,
ADSR envelope displays, rotary knob controls, rocker switches, and green LED
numeric readouts.

When a voice document comes to the foreground, Forest prepares the active
device's live audition buffer for that document so the floating Live Keyboard
auditions the voice the user is looking at. The Live Keyboard reports both the
visible document voice name and the current device voice-buffer status to make
audition state easier to reason about.

The editor includes controls for voice identity, feedback, user code, transpose,
stereo output assignment, LFO and modulation settings, algorithm selection, and
per-operator parameters such as total level, frequency multiple, detune, attack,
decay, sustain, release, velocity sensitivity, level scaling, rate scaling, PMD,
LFO enable, and operator enable.

When a voice document is saved with Save As, the selected file name also becomes
the internal voice name, subject to the active device's name-length limit.

## Configuration Editing

Configuration documents currently expose the FB-01 performance setup:

- configuration name
- system channel
- combine mode
- key-code receive mode
- LFO speed, AMD, PMD, and waveform
- all 8 instrument slots
- per-instrument MIDI channel, note allocation, key limits, voice bank/number,
  voice name, output level, stereo pan, detune, octave transpose, LFO enable,
  pitch bend range, portamento, mono/poly mode, and PMD controller assignment

Configurations 1-16 are writable on the FB-01. Configurations 17-20 are factory
preset/read-only configurations.

## MIDI Setup

The main window has separate MIDI endpoint selections for:

- **MIDI In from FB-01**
- **MIDI Out to FB-01**

The live keyboard areas also have a separate:

- **MIDI In from External Keyboard**

This distinction matters when using a synth module and a separate controller
keyboard at the same time. For example, the FB-01 can remain connected through
one MIDI interface while an M-Audio Oxygen keyboard supplies note and controller
input over USB.

Live MIDI playback and forwarding are handled outside the main UI path to keep
mouse interaction and note auditioning responsive.

## Device Capability Snapshot

| Area | FB-01 | DX100/27 |
| --- | --- | --- |
| Single voice file load/save | Yes | Yes |
| Voice bank file load/save | Yes | Yes |
| Configuration file load/save | Yes | No |
| Current voice fetch | Yes | Yes |
| Device voice-bank fetch | Yes, Banks 1-7 | Internal bank verified |
| Additional device bank fetch | ROM via standard requests | Bank A-D and presets still experimental |
| Live voice edit send | Yes | Yes |
| Voice slot store | Yes | Current edit buffer only |
| Configuration support | Yes | No |
| General MIDI bank install | Yes | No |

## Module Boundary

The app shell now talks to module services rather than directly embedding synth
details. FB-01 and DX100/27 both expose module metadata and voice services
through shared protocols, while FB-01 also exposes configuration services.

Module metadata now also includes device vocabulary, supported document
descriptors, and a neutral parameter descriptor catalogue. See
`Docs/ModuleBoundary.md` for the working rule of thumb about what belongs to the
app shell and what belongs to a synth module.

The FB-01 path remains the most complete module. DX100/27 support is now active
for single-voice documents, Internal-bank browsing, bank-file load/save, and
live current-buffer editing, while broader DX bank recall/dump behavior remains
under hardware investigation.

## Files And Document Types

The app supports module-owned document types and Finder icons for:

- `.fbv`: single voice documents
- `.fbc`: single configuration documents
- `.fbvb`: voice bank documents
- `.fbcb`: configuration bank documents
- `.fbx`: generic FB-01 SysEx files
- `.dxv`: DX100/27 single voice documents
- `.dxvb`: DX100/27 voice bank documents
- `.dxx`: generic DX100/27 SysEx files

Generic `.syx` files remain readable for import and troubleshooting, but Forest's
preferred document naming uses the module-owned extensions above.

The default save/load folder is:

```sh
~/Documents/Forest Editor
```

The app creates that folder when needed and remembers the most recently used
load and save folders.

## Command-Line Tools

The package includes command-line tools for hardware capture and maintenance.

`fb01-dump` lists MIDI endpoints, listens for manual dumps, and sends safe dump
requests:

```sh
swift run fb01-dump list
swift run fb01-dump listen --source 0 --output fb01-dump.syx --count 1
swift run fb01-dump request unit-id --source 0 --destination 0 --output unit-id.syx
swift run fb01-dump request current-configuration --source 0 --destination 0 --output current-config.syx
swift run fb01-dump request voice-bank --bank 2 --source 0 --destination 0 --output voice-bank-2.syx
```

`fb01-gm-load` supports the General MIDI bank-loading workflow used by the app.

`dx100-dump` is an experimental, read-only DX100 helper used while the DX100
module is being developed. It can list MIDI endpoints, request the current
edit-buffer voice, and request a raw 32-voice bulk dump with name/checksum
validation:

```sh
swift run dx100-dump list
swift run dx100-dump current-voice --source 0 --destination 0 --output current.dxv
swift run dx100-dump voice-bank --source 0 --destination 0 --output current-bank.dxvb
```

## Build And Run

Build and run from Swift Package Manager:

```sh
swift run FB01EditorApp
```

Run tests:

```sh
swift test
```

Build a launchable local app bundle:

```sh
./scripts/build-macos-app.sh
open "dist/Forest Editor.app"
```

The script creates an ad-hoc signed development bundle at:

```sh
dist/Forest Editor.app
```

## Xcode

The repo includes a native Xcode project:

```sh
open "Forest FB-01 Editor.xcodeproj"
```

The primary app scheme is `Forest Editor`. The project also contains
targets for the shared `FB01Editor` library, `fb01-dump`, `fb01-gm-load`, and
`FB01EditorTests`.

Command-line Xcode builds should use repo-local DerivedData:

```sh
xcodebuild -project "Forest FB-01 Editor.xcodeproj" -scheme "Forest Editor" -configuration Debug -derivedDataPath .xcode-derived build CODE_SIGNING_ALLOWED=NO
xcodebuild -project "Forest FB-01 Editor.xcodeproj" -scheme "Forest Editor" -configuration Debug -derivedDataPath .xcode-derived test CODE_SIGNING_ALLOWED=NO
```

## SysEx And Data Model

The shared `FB01Editor` Swift library models and tests:

- Yamaha SysEx message splitting and parsing
- FB-01 voice data and nibble encoding
- FB-01 voice bank dumps
- current and stored configuration dumps
- configuration sets
- Yamaha 7-bit two's-complement checksums
- system, instrument, store, memory-protect, voice-bank, and configuration commands

Captured fixtures live in:

```sh
Tests/FB01EditorTests/Fixtures
```

Those fixtures include voice banks 1-7, Voice RAM 1, a current configuration
dump, and an invalid bank-byte response used to preserve observed hardware
behavior.

## Hardware Notes

Observed FB-01 behavior during development:

- The app and CLI use user-facing bank numbers 1-7; the SysEx request byte is
  zero-based.
- Banks 1 and 2 are writable RAM banks.
- Banks 3-7 are factory voice banks.
- Configurations 1-16 are writable.
- Configurations 17-20 are read-only preset configurations.
- The FB-01 memory protect setting must be off before storing data; the app sends
  the documented memory-protect-off command as part of store operations.
- Some generic USB MIDI interfaces can pass notes but behave unreliably for
  FB-01 SysEx request/response work. If requests time out, verify cable direction,
  selected MIDI endpoints, system channel, and the interface's SysEx support.

## Project History

`fb01editor-context.json` is a recovered handoff file from the original Codex
task. It records early project context, SysEx research notes, and the initial
hardware-safe capture milestone.
