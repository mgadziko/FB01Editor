# Forest 4-Op Capability Matrix

This table is a practical snapshot of what Forest Editor currently supports in
real hardware workflows.

| Capability | FB-01 | DX100/27 |
| --- | --- | --- |
| Single voice file load/save | Yes | Yes |
| Voice bank file load/save | Yes | Yes |
| Configuration file load/save | Yes | No |
| Current voice fetch | Yes | Yes |
| Device voice-bank fetch | Banks 1-7 | Internal bank only |
| Additional device-bank fetch | ROM banks supported | Bank A-D and presets still experimental |
| Live voice edits sent to device | Yes | Yes |
| Voice slot store | Yes | Current edit buffer only |
| Whole-bank store to device | FB-01 RAM Banks 1-2 | Not verified |
| Configuration fetch/store | Yes | No |
| General MIDI install | Yes | No |
| Live keyboard note audition | Yes | Yes |
| Configuration/performance documents | Yes | No |

## Notes

- DX100/27 support is now active, but still narrower than FB-01 support.
- The DX100/27 Internal bank and current edit voice are the verified device
  fetch paths today.
- Device-side DX100/27 Bank A-D and preset workflows remain under hardware
  investigation and should not be presented as equivalent to verified fetch
  paths.

## Shared And Device-Specific Parameter Areas

Forest's editor is moving toward a neutral 4-operator voice model with
device-specific projection layers at the edges. The table below is the current
working map of what belongs to the shared voice core and what remains module
specific.

| Area | Shared neutral 4-op voice model | FB-01-specific | DX100-specific |
| --- | --- | --- | --- |
| Voice structure | Voice name, algorithm, feedback, transpose, global LFO waveform/speed/depths, pitch/amplitude modulation sensitivities, per-operator enable state, operator frequency controls, detune, envelopes, output/level controls, velocity sensitivities, keyboard scaling controls | FB-01 instrument-voice packaging, FB-01 bank-image voice layout, FB-01 current-instrument voice send/confirm path | DX100 current edit-buffer voice packaging, DX100 Internal bank voice layout, DX100 live current-buffer resend path |
| Operator frequency semantics | Shared concepts such as oscillator multiple, detune, and operator role within the selected algorithm | FB-01-specific byte layout and value packing for those controls | DX100-specific parameter numbering and value packing for those controls |
| Envelope semantics | Shared attack, decay, sustain, release, velocity-to-attack, and level/keyboard-scaling concepts | FB-01-specific encoding and instrument-voice writeback rules | DX100-specific encoding and current-buffer writeback rules |
| Modulation semantics | Shared LFO speed, pitch modulation depth, amplitude modulation depth, and related sensitivities | FB-01 wording and SysEx command layout | DX100 wording and parameter-change command layout |
| Voice-bank browsing | Shared idea of a bank document full of individually openable voices | FB-01 Banks 1-7, 48 voices per bank, RAM-vs-ROM behavior | DX100 Internal plus additional bank families, 24 voices per displayed bank |
| Device-side single-voice store | Shared app-level idea of storing the edited voice into a slot | FB-01 stores by rebuilding and rewriting a whole bank image around the edited slot | DX100 stores by rewriting Internal-bank content around the chosen slot and then verifying against Internal |
| Whole-bank store | Shared app-level idea of writing a full bank document back to hardware | Verified for FB-01 RAM banks | Not yet verified for DX100 hardware |
| Multi-timbral/performance data | None in the neutral voice core | FB-01 configurations, instruments, key ranges, output routing, stored/current configuration behavior, memory protect, General MIDI install workflow | No DX100 configuration document or equivalent multi setup in Forest today |
| Device control state | None in the neutral voice core | FB-01 protect state, current/stored configuration state, bank writability rules | DX100 PLAY/edit state quirks, manual dump/listen fallback, MEMORY PROTECT dependency |

### Practical Summary

- If a control changes the sound of a single 4-op voice, it should live in the
  shared neutral voice model whenever possible.
- If a control exists because of how a device stores, fetches, routes, or
  protects that voice, it belongs in the module bridge instead.
- FB-01 configurations remain deliberately outside the shared voice core.
