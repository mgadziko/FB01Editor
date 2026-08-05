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
