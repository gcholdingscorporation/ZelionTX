# 05. Decisions and risks

## Decisions already implied by the research (recommended, reversible where noted)

| Id | Decision | Why | Reversible? |
|---|---|---|---|
| D-1 | Licence ZelionTX as GPL-2.0-only. | It derives from EdgeTX, which is GPL-2.0-only. GPL-3.0 code (ExpressLRS, Rotorflight) cannot be linked in, so ELRS and Rotorflight protocols are re-implemented from facts. | No, unless the platform layer is rewritten. |
| D-2 | Fork EdgeTX's platform layer with `git subtree`; write everything above the HAL new. | Retires the hardware risk while avoiding the entanglement of the model-programming layer. | Partially: individual platform files can be replaced later. |
| D-3 | Targets: TX16S Mk3 and TX15 first. | Both STM32H750, internal-ELRS-only, already in EdgeTX, already verified with ZelionDash. | Yes, other H7 boards are board-definition work. |
| D-4 | No Lua in version 1. | The two Lua consumers (ELRS configurator, Rotorflight tool) are replaced by native screens for ELRS and by the Configurator for Rotorflight. Lua is the main "hog" the brief wants gone. | Yes, EdgeTX's Lua bindings remain forkable. |
| D-5 | Dashboard ported to C++, tests ported first. | Native decode by protocol id removes the name-guessing layer and the `.luac` cache problem; the 337 tests make the port checkable. | Yes. |
| D-6 | Telemetry keyed by protocol id, not by discovered name. | Rotorflight defines appIds and encoders; ELRS defines link-stats fields. Discovery by name is the source of the Lua widget's worst bug (throttle bound to TQly). | Yes. |
| D-7 | Storage format is flat text `key = value` with sections, not YAML. | A few dozen keys per model do not justify EdgeTX's libclang-generated YAML tables. | Yes. |
| D-8 | Three screens: Dash, Link, Heli. | Reading of "a baked in screen with 3 options". | Yes, cheap to change. |

## Decisions that need your answer

| Id | Question | Options | Recommendation |
|---|---|---|---|
| Q-1 | What did "a baked in screen with 3 options" mean? | (a) three screens Dash / Link / Heli; (b) one dashboard with three layout variants; (c) three dashboard presets by aircraft class. | (a). If (b) or (c), the Dash screen gains a selector and Link and Heli become setup pages; the module split does not change. |
| Q-2 | Arming: ELRS arming byte ("arm via switch") or CH5 arming? | ELRS default puts arm on CH5 and Rotorflight's default map also uses CH5 as collective, which conflicts. Betaflight-style setups move arm to an AUX channel via the ELRS arming byte; Rotorflight users typically map collective to CH5 and ARM to an AUX. | Support both in `model/`, default to CH5 = collective with ARM on AUX1 (CH6) sent through the 25-byte RC frame's arming byte set to "switch mode". Verify on the bench in phase 2 which combination the current ELRS receiver firmware honours for CH5 rewriting. [unverified until tested] |
| Q-3 | LVGL version: stay on EdgeTX's 8.2 branch or move to LVGL 9? | 8.2 is what the reused wrapper and DMA2D flush target; 9 has a better renderer but the wrapper must be rewritten. | Stay on 8.2 for version 1; revisit after phase 8. |
| Q-4 | Default internal module baud. | 400k works everywhere at 500 Hz; 1.87M is what the Rotorflight Lua suite demands and supports 1 kHz. | 1.87M default, 400k selectable. |
| Q-5 | Should the Heli screen include tuning (rates, PIDs, governor)? | Answered by the connected-system pillar (chapter 06): yes, as table-driven editors that store everything in the FC. | Closed: in scope, phase 7b. |
| Q-8 | How far should the setup wizard go in writing FC settings? | (a) only what the radio must own coherently: mode and adjustment ranges, telemetry list, name, ELRS id; (b) also a starter tuning (rates, governor headspeed, battery profile) chosen by aircraft class; (c) everything the Configurator's own setup does. | (a) for version 1. (b) is attractive but means shipping tuning opinions; decide after flying the wizard. (c) duplicates the Configurator and includes hardware-level settings the link should not touch. |
| Q-6 | Touch on TX16S Mk3: required or optional for navigation? | Every screen must be usable with rotary and keys on the TX15 anyway. | Keys and rotary are the primary input; touch is an accelerator. |
| Q-7 | Licence for the existing ZelionDash repository. | It has no licence file today. | Add one (GPL-2.0-only keeps the port simple; a permissive licence also works since it is your own code). |

## Risks

| Id | Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|---|
| R-1 | H750 bring-up surprises when EdgeTX's board code is separated from its build system (hidden dependencies on `g_eeGeneral`, `g_model`, GUI globals in drivers). | High | Medium | Phase 1 is exactly this; keep a shim header of the few globals drivers touch and burn them down one by one. |
| R-2 | ELRS module timing: the module drops RF after 1 s without frames and demotes rate on a slow baud; a scheduler bug looks like "the heli fell out of the sky". | Medium | High | Phase 2 exit test with a logic analyser; watchdog on the RC task; never block that task. |
| R-3 | Arming semantics across ELRS receiver versions (CH5 rewrite, CH14 mirror, arming byte). | Medium | High | Q-2 bench test with the actual receivers before phase 3 flight. |
| R-4 | Rotorflight API drift (12.7, 12.8, 12.9 already change payloads). | High | Low | Gate on API version like the Configurator does; decode only fields the version has; the 0x88 appIds are stable. |
| R-5 | Factory FC sends no custom telemetry until the sensor list is configured; a new user sees dashes and blames the radio. | High | Medium | F-C11 "write recommended list" action and an explicit message on the Dash screen. |
| R-6 | Licence compliance slip (someone pastes a Rotorflight table into the tree). | Medium | High | `NOTICE` and a CI grep for known GPL-3.0 headers; the research notes are the only permitted source of protocol facts. |
| R-7 | Scope creep back toward EdgeTX (one more mix, one more switch function). | High | Medium | The out-of-scope list in `01` is a contract; anything added needs a written reason and a test. |
| R-8 | Voice files: the number vocabulary depends on EdgeTX's sound pack layout. | Low | Low | Ship a voice pack built by `tools/` from a permissive TTS or reuse the EdgeTX pack under its terms (check the pack licence separately). [unverified] |
| R-9 | Single-developer bus factor on the hardware layer. | Medium | Medium | Bring-up checklist and module docs written as part of each phase, not after. |
| R-10 | Writing FC settings from the radio: a bad write makes a heli unsafe (chapter 06). | Medium | High | One write path with range checks from descriptors; refused while armed; automatic backup before the first write; summary and single confirmation; reboot-required flag shown. |
| R-11 | Link bandwidth makes configuration pages slow (seconds per page at 250 Hz 1:64), which reads as "broken". | High | Medium | Prioritised MSP queue, telemetry ratio boost while a page is open, throughput indicator, cached last-read values shown immediately with an "updating" mark. |
| R-12 | The VBar comparison sets expectations (vibration analysis, FC update over the air) the link cannot meet. | Medium | Low | Chapter 06 states the three impossibilities plainly; the UI says so where a user would look. |

## What the research could not settle

- Whether the current ELRS receiver firmware still rewrites CH5 from the arming bit
  when the handset uses the arming byte (Q-2). Bench test required.
- Any official Rotorflight recommendation for switch layout, packet rate or telemetry
  ratio: not found in the firmware, Lua or configurator repositories.
- The licence of the EdgeTX voice packs (they live outside the firmware repository).
- Exact flash and RAM figures for the trimmed platform layer; only obtainable by building it (phase 1).
- The Mikado VBar Control material was read through search summaries only; the primary
  manual should be checked before any VBar behaviour is quoted as exact
  (`../research/vbar-control.md`).
