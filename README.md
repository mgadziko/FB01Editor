# FB01 Editor

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

`FB01EditorApp` is a read-only SwiftUI librarian shell:

```sh
swift run FB01EditorApp
```

It opens `.syx` files, shows artifact/message metadata, displays decoded current configuration fields, and exports the original SysEx bytes. It does not send MIDI or write to the FB-01.

## Receive-Only MIDI Capture

The `fb01-dump` executable is the first CoreMIDI tool. It is intentionally receive-only:

```sh
swift run fb01-dump list
swift run fb01-dump listen --source "USB Midi Cable" --output fb01-dump.syx --count 1
```

Use the FB-01 front panel to send a bulk dump while `listen` is running. The tool saves complete SysEx messages, then classifies them with the library parser. Request/send/write-back features should wait until captured dumps are verified.

## Recovered Context

`fb01editor-context.json` is a handoff file from the original Codex task. It records the recovered project context, the SysEx research summary, the initial commit boundary, and the planned hardware-safe capture milestone.
