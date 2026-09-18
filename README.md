# ZelionTX

A transmitter firmware for RC helicopters that does four things well: stick
translation, ExpressLRS link control, Rotorflight telemetry, and being the flight
controller's control surface. It deliberately does nothing else.

It is built on the concept, borrowed from Mikado's VBar Control and VBar NEO, that the
flight controller is the model and the radio is a window onto it. Rotorflight owns
rates, expo, mixing, governor, rescue and arming logic; the radio reads the pilot's
hands accurately, keeps the ELRS link fed, recognises the aircraft from the FC's
identity, sets it up and tunes it over the link with every parameter stored in the FC,
and shows, speaks and logs what the aircraft reports through the ZelionDash dashboard
that already exists as an EdgeTX widget.

**Status: phase 1 bring-up.** The TX15 firmware builds (see `docs/modules/platform.md`); build 1 awaits its first flash. Start with the handoff below.

## Documents

Proposal (read in order):

0. [Handoff: current state](docs/HANDOFF.md)
1. [Vision and scope](docs/proposal/01-vision-and-scope.md)
2. [Requirements](docs/proposal/02-requirements.md)
3. [Architecture and modules](docs/proposal/03-architecture-and-modules.md)
4. [Roadmap](docs/proposal/04-roadmap.md)
5. [Decisions and risks](docs/proposal/05-decisions-and-risks.md)
6. [The connected-system pillar](docs/proposal/06-connected-system-pillar.md)

Research notes (the facts the proposal rests on, with file and line references):

- [Mikado VBar Control and NEO](docs/research/vbar-control.md) (secondary sources only)
- [EdgeTX](docs/research/edgetx.md)
- [ExpressLRS](docs/research/expresslrs.md)
- [Rotorflight firmware and Lua scripts](docs/research/rotorflight-firmware.md)
- [Rotorflight Configurator](docs/research/rotorflight-configurator.md)
- [ZelionDash](docs/research/zeliondash.md)

## Planned targets

RadioMaster TX15 first, then the TX16S Mk3 and the GX15 (STM32H750, internal ELRS
module only). Only the TX15 is wired up in the build so far. Other EdgeTX H7 radios
are expected to be board-definition work.

## Licence

GPL-2.0-only, because the hardware layer derives from EdgeTX. See `LICENSE`, `NOTICE`
and decision D-1 in the proposal. No code from ExpressLRS or Rotorflight (GPL-3.0) is
used; their protocols are re-implemented from the research notes.
