# Forest FB01 Editor

Offline-first editor and librarian core for the Yamaha FB-01 FM sound generator.

The first milestone is intentionally hardware-free:

- model FB-01 voice and configuration data
- encode and decode documented Yamaha SysEx command forms
- validate 7-bit MIDI payloads, nibble-packed voice data, and Yamaha checksums
- add CoreMIDI transport only after the byte-level core is covered by tests

## Current Scope

This package currently contains the `FB01Editor` Swift library. It does not send MIDI yet.

The core is shaped around separately saveable artifacts:

- single instrument voice dumps
- voice bank dumps
- current configuration dumps
- stored configuration dumps
- configuration sets
- raw SysEx fallback files

## Early Command Coverage

- instrument parameter changes
- MIDI-channel parameter changes
- system parameter changes
- voice bank and configuration dump requests
- current instrument/configuration store requests
- FB-01 voice-byte nibble packing
- Yamaha 7-bit two's-complement checksums

## Parser Coverage

- split `.syx` byte streams into individual SysEx messages
- classify generated request/store commands
- parse checksum-protected dump packets
- classify dump messages into artifact kinds for future file save/open workflows
- round-trip artifacts through `.syx` files without requiring connected hardware

## Configuration Model Coverage

The first real FB-01 fixture is a captured current configuration named `single`.
`FB01ConfigurationData` currently decodes:

- configuration name
- combine mode
- shared LFO speed, AMD, PMD, waveform, and key-code receive mode
- all 8 instrument definition blocks
- per-instrument note allocation, MIDI channel, key limits, voice bank/number, detune, octave transpose, output level, pan, LFO enable, portamento, pitch bend range, mono/poly mode, and PMD controller assignment

## macOS App Shell

`FB01EditorApp` is a safe SwiftUI librarian/editor shell:

```sh
swift run FB01EditorApp
```

It opens one or more `.syx` files from the File menu, shows them in a source library, displays decoded current configuration fields, displays voice banks in a selectable browser with a local voice editor, saves the selected source from the File menu, saves open stored configurations as a configuration-set `.syx`, and exports the selected voice as a standalone single-voice SysEx file. The first local editor controls cover voice name, algorithm, feedback, and LFO speed. Local voice edits are tracked in the source library, so they survive voice/source selection changes; edited standalone single-voice sources, numbered voice-bank sources, and Voice RAM sources save through the File menu with rebuilt checksums. It can also fetch the current configuration, Banks 1-7, Voice RAM 1, and stored configurations 1-20 from the connected FB-01 into the same source browser, with a choice to replace or append when sources are already open. Sources can be renamed, removed, or cleared locally. It does not write to the FB-01.

To build a launchable local `.app` bundle:

```sh
./scripts/build-macos-app.sh
open "dist/Forest FB01 Editor.app"
```

The script creates an ad-hoc signed development bundle at `dist/Forest FB01 Editor.app`.

## MIDI Capture And Safe Dump Requests

The `fb01-dump` executable is the first CoreMIDI tool. Manual capture is receive-only:

```sh
swift run fb01-dump list
swift run fb01-dump listen --source "USB Midi Cable" --output fb01-dump.syx --count 1
```

Use the FB-01 front panel to send a bulk dump while `listen` is running. The tool saves complete SysEx messages, then classifies them with the library parser. Request/send/write-back features should wait until captured dumps are verified.

The tool also supports documented dump requests that do not store or write data to the FB-01:

```sh
swift run fb01-dump request unit-id --source 0 --destination 0 --output unit-id.syx
swift run fb01-dump request current-configuration --source 0 --destination 0 --output current-config.syx
swift run fb01-dump request voice-bank --bank 2 --source 0 --destination 0 --output voice-bank-2.syx
```

If manual front-panel dumps work but computer-originated requests time out, verify the MIDI Out to FB-01 MIDI In cable direction, the FB-01 system channel, and whether the interface is passing outbound SysEx. The tested generic `USB Midi Cable` interface was unreliable for Mac-originated SysEx requests; a different interface enumerating as `USB MIDI Device` handled note bursts, current-configuration requests, and voice-bank requests successfully.

Observed hardware behavior:

- Current configuration requests return 171-byte dumps with the working `USB MIDI Device` interface.
- The app and CLI use the FB-01's user-facing bank numbers `1...7`; the SysEx request byte is zero-based (`0...6`).
- Banks 1 through 7 returned 6363-byte dumps with the working interface when requested with SysEx bank bytes `0...6`.
- Bank 7 returned a 6363-byte dump when requested with SysEx bank byte `6`.
- A raw request with SysEx bank byte `7` returned the short response `F0 43 60 04 F7`, which is preserved as an invalid-request raw SysEx fixture.
- The separate `voice-ram1` request returned a 6360-byte dump. This appears to be the user/RAM bank path described separately from numbered voice-bank requests, and is preserved as `voice-ram1.syx`.
- `Tests/FB01EditorTests/Fixtures/voice-bank-1.syx` through `voice-bank-7.syx` are captured numbered voice-bank fixtures. They are recognized, exact-byte round-tripped, and decoded into 48 voice entries each.
- `Tests/FB01EditorTests/Fixtures/voice-ram1.syx` is recognized as voice RAM dump data and decoded through the same 48-voice table model.
- `FB01EditorApp` displays a selectable voice browser and local voice editor when a captured voice-bank dump is opened.
- `FB01EditorApp` can open multiple `.syx` files at once and adds each opened bank, configuration, or single voice to the source library.
- Source-library entries can be renamed, removed individually, or cleared from the app without touching disk files or the FB-01.
- The selected voice can be edited locally and exported as a standalone single-voice SysEx artifact without writing anything to the FB-01.
- Local voice edits are stored on the source entry. Edited standalone single-voice, numbered voice-bank, and Voice RAM sources are saved by File > Save SysEx with rebuilt SysEx checksums.
- `FB01EditorApp` has a manual `Fetch Banks` action that requests current configuration, Banks 1-7, and Voice RAM 1, then shows the fetched dumps in a source sidebar. Source and destination MIDI endpoints are selectable from the toolbar and remembered between launches. This is still read-only and does not perform any store/write-back commands.
- `FB01EditorApp` has a manual `Fetch Configs` action that requests stored configurations 1-20 and adds them as separate sources. Configurations 17-20 are labeled read-only/preset in the source browser.
- File > Save Configuration Set writes the open stored-configuration sources as one multi-message `.syx` file, sorted by configuration number.

## Recovered Context

`fb01editor-context.json` is a handoff file from the original Codex task. It records the recovered project context, the SysEx research summary, the initial commit boundary, and the planned hardware-safe capture milestone.
