# Forest Editor Reference Sources

This note records the Yamaha source material that Forest Editor should treat as
authoritative when there is tension between convenient UI wording and original
device terminology.

## DX100/27

Primary current reference for DX operator vocabulary, parameter naming, and
shared 4-operator semantics:

- `Yamaha Download Programming DX100_DX27SE2.pdf`

Why this source matters:

- it describes the DX100/27 parameter set in Yamaha's own wording
- it shows the programming workflow by parameter number and front-panel state
- it is the cleanest scan currently available in this project workflow
- it is a better anchor for DX terminology than the rougher owner/service scans

Forest should use this source first when tightening:

- DX operator labels
- DX tooltip wording
- neutral 4-op parameter naming
- DX-vs-FB shared voice-model semantics

Working guidance:

- keep the neutral editor model honest where FB-01 and DX100/27 really share a
  concept
- prefer Yamaha's own term when the DX family has a specific established name
- avoid inventing new "musical" labels where they would obscure the original DX
  behavior rather than clarify it

## FB-01

Primary current references for FB-01 SysEx, configuration behavior, and device
limits:

- `Yamaha FB-01 Owners Manual.pdf`
- `Yamaha FB-01 Service Manual.pdf`

## Usage Rule

When DX100/27 behavior and FB-01 behavior differ, the app shell should remain
neutral while the device module keeps the device-specific vocabulary.
