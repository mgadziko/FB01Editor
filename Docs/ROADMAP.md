# Forest Editor Roadmap

This is a consolidated view of what is verified, what is experimental, and what
is still to come. It gathers the "not yet / experimental / not verified"
statements scattered across the README, `Docs/FourOpCapabilityMatrix.md`, and
`Docs/ModuleBoundary.md` into one checklist so there is a single place to see
what is left.

This file is a *view*, not a source of truth. The authoritative status for any
capability is the capability matrix and the module-boundary doc; if this file
and those disagree, trust those.

Generated from branch `modular-device-boundary` at commit `7f4910f`.

## How to read the statuses

- **[x] Verified** — works against real hardware and is presented as a normal,
  supported path.
- **[~] Experimental / assisted** — works, but through a manual or assisted
  flow, or not yet confirmed on hardware. Do not present as equivalent to a
  verified path.
- **[ ] Not yet** — intentionally not exposed or not implemented.

The project's standing rule (from `Docs/ModuleBoundary.md`): *do not treat an
unverified device path as production-ready just because a sibling Yamaha module
does something similar.*

## At a glance

| Device | Maturity | Verified core | Biggest remaining gaps |
| --- | --- | --- | --- |
| FB-01 | Complete | Voice + configuration fetch/store, banks 1-7, GM install, live audition | (reference module — essentially feature-complete) |
| DX100/27 | Active, voice-only | Current-voice + Internal-bank fetch/store, bank-file I/O, live audition | Preset banks, bulk Bank A-D dump, whole-bank store, no config docs |
| TX81Z | Initial, read-only | Current-voice + Voice Bank I fetch (ACED+VCED), live audition | File I/O, editing, voice store, extra banks, performance documents |
| Architecture | Mid-refactor | Module boundary live for FB-01 + DX100 | Real module selection, typed neutral 4-op model |

## FB-01 (reference module)

The FB-01 is the most complete path and the template other modules are held
against.

### Verified
- [x] Load/save single voice files
- [x] Load/save single configuration files
- [x] Load/save voice bank files
- [x] Fetch current voice (RAM banks + factory ROM banks)
- [x] Fetch configurations (including read-only presets 17-20)
- [x] Store voices to writable RAM Banks 1 and 2
- [x] Store configurations to writable slots 1-16
- [x] Voice slot-to-slot copy without opening an editor window
- [x] Configuration slot-to-slot copy without opening an editor window
- [x] General MIDI 48-voice bank install to Bank 1 or Bank 2
- [x] Live on-screen + external MIDI keyboard audition
- [x] Whole-bank store (RAM Banks 1-2)

### Not yet
- No outstanding FB-01 gaps are tracked. Treat this module as the baseline for
  what "complete" means in this app.

## DX100/27 (active, voice-only)

Narrower than FB-01. The verified device paths today are current-voice,
Internal-bank, and Internal-bank store.

### Verified
- [x] Fetch current edit voice
- [x] Fetch Internal voice bank
- [x] Load/save single voice files
- [x] Load/save voice bank files
- [x] Send edited voice to the current edit buffer for live audition
- [x] Live keyboard note audition
- [x] Bank window cross-bank drag and Internal-bank drag reordering

### Experimental / assisted (hardware still under investigation)
- [~] Bank A-D fetch — uses Forest's **manual assisted capture flow**, not a
  one-shot bulk SysEx dump. A verified device-side bulk recall/dump path is
  still missing.
- [~] Whole-bank store to device — not yet verified for DX100 hardware (single
  current-edit-buffer store only is verified).

### Not yet
- [ ] Device-side **preset-bank** fetch (Preset Normal and Preset Shift banks
  are not available through Forest).
- [ ] A **verified device-side bank-store / whole-bank-store** workflow.
- [ ] A **verified one-shot bulk Bank A-D dump** path (replacing assisted
  capture).
- [ ] **Configuration / function document support** (no DX100 configuration
  document or equivalent multi-timbral/performance setup exists in Forest
  today).

## TX81Z (initial, read-only)

Deliberately starts with a read-only, real-hardware-verified current-voice path
that requests the Additional Voice Edit Data (ACED) and Voice Edit Data (VCED)
blocks together.

### Verified (read-only)
- [x] Fetch current voice (ACED + VCED pair)
- [x] Fetch the complete, fetch-only 32-voice **Voice Bank I**
- [x] `forest-cli`: `select-device tx81z`, `fetch-current-voice`, `show-bank i`
- [x] TX81Z device choice in Forest Main View with its own MIDI route
- [x] Voice > Fetch Current Voice / Show Voice Bank > Voice Bank I (read-only docs)
- [x] Selecting a Voice Bank I tile selects the program and fetches its full
  ACED + VCED pair
- [x] Live-keyboard note audition without a lossy edit-buffer rewrite
- [x] TX81Z **Performance fetch workflow** (added at the CLI/command layer)

### Not yet (intentionally not exposed)
- [ ] TX81Z **file load/save**
- [ ] TX81Z **editing** (the codec fetches and exposes the shared 4-op voice,
  but editing is not exposed yet)
- [ ] TX81Z **voice store** (writing to hardware is intentionally off)
- [ ] **Additional banks** beyond Voice Bank I
- [ ] **Performance documents** in the app UI (the fetch workflow exists at the
  command layer; the document/exposure is not yet exposed)

## Architecture / cross-cutting

The app shell talks to module services behind shared protocols. FB-01 and
DX100/27 both expose metadata + voice services; FB-01 additionally exposes
configuration services.

### In progress / not yet
- [ ] **Real module selection** — `ActiveSynthModule.current` is an internal
  placeholder deliberately fixed to FB-01 until another real hardware module
  can be verified. A genuine selection mechanism across modules is the next
  step.
- [ ] **Typed neutral 4-op voice model** — parameter binding descriptors are
  "descriptive at this stage": they identify which module parameter a UI
  control edits but do not yet replace the existing typed FB-01 editing code.
  The goal is to move every control that changes a single 4-op voice's sound
  into the shared neutral model and leave only device storage/fetch/route/
  protect quirks in the module bridges.
- [ ] **General MIDI install parity** — GM bank install remains an FB-01-only
  command guarded by the FB-01 capability flag. Future modules should not
  inherit it unless they explicitly implement and verify an equivalent.
- [ ] **DX100/27 configuration equivalent** — no neutral multi-timbral/
  performance model exists yet; FB-01 configurations are deliberately outside
  the shared voice core.

## Future device onboarding

Before adding another real device module, follow this sequence (from
`Docs/ModuleBoundary.md`). Mock modules in tests prove the architecture is not
hardwired to the FB-01 but are *not* a substitute for hardware verification.

- [ ] 1. Capture and verify its SysEx identity and dumps from hardware.
- [ ] 2. Build a small service adapter that satisfies the neutral module
      protocols.
- [ ] 3. Add tests using captured fixtures.
- [ ] 4. Only then expose device selection in the UI.

## Suggested next steps (priority order)

Derived from the open items above, roughly in the order they unblock the most:

1. **TX81Z write path** — file load/save, editing, and voice store, reusing the
   verified ACED+VCED codec. This is the natural continuation of the current
   read-only TX81Z work.
2. **TX81Z additional banks** beyond Voice Bank I.
3. **DX100 preset-bank fetch** — the remaining unverified device fetch path.
4. **DX100 whole-bank store** verification on hardware.
5. **DX100 bulk Bank A-D dump** to replace the manual assisted-capture flow.
6. **Real module selection** so `ActiveSynthModule.current` stops being pinned
   to FB-01.
7. **Typed neutral 4-op model** to finish collapsing device-specific editing
   into the shared voice core.

## Sources of truth

- `README.md` — user-facing feature list and per-device limits
- `Docs/FourOpCapabilityMatrix.md` — per-capability verified status + shared
  vs device-specific parameter map
- `Docs/ModuleBoundary.md` — what belongs to the shell vs the module, current
  adapters, and the future-device playbook
- `Docs/ReferenceSources.md` — authoritative Yamaha wording (DX100/27, FB-01)
- `fb01editor-context.json` — historical handoff from the original Codex task
  (genesis context; not a live tracker)
