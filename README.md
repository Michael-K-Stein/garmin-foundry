# Foundry

An idle production-chain game for the Garmin Venu 2, reimagining *Builderment
Idle* for a 416px round screen. You do not lay belts and you do not place
tiles - there is no room for either on a watch. What survives is the part that
made the original tick: **a line is only as fast as its slowest stage**, and
every purchase is a decision about which stage that should be.

```
HARVEST  ->  CRAFT  ->  SELL        x5 factories, each worth more than the last
```

## Playing

One factory fills the glass. Three stages stacked down the middle, the buffer
between each pair drawn in the gap under it, and one contextual button along
the bottom.

| Gesture | What it does |
| --- | --- |
| Tap a stage row | Buy one more machine for that stage |
| Bottom button | Buy for whichever stage is slowest right now |
| Swipe left / right | Change factory |
| Swipe up | Upgrades, storage, this line, rebuild, options |
| Swipe down / back | Back to the board |
| Select key | Same as the bottom button |

Each row carries the character who works that stage - a feller with an axe, a
hand at a bench with the assembly cog turning behind them, a trader with a
coin coming off the sale - and they animate at the pace their stage is
actually running, so twenty extractors visibly swing harder than one. All of
it is drawn from primitives rather than bitmaps, so it scales from the 416px
Venu 2 to the 360px Venu 2S without a second set of art.

Every row is a full-width 58px slab, so nothing needs precision and nothing
needs two hands. The stage holding the line back is outlined and lettered in
orange, on the board and on its detail page - it is the only thing you have to
read to know what to buy.

A buffer that fills up turns orange too. That is the game telling you the
stage feeding it is now wasted money.

## The loop

1. Extractors pull raw material out of the ground into the raw buffer.
2. Assemblers turn two raw units into one product.
3. Traders sell products for gold, which is the only currency.
4. Buy machines for the slowest stage; the bottleneck moves to the next stage
   along, and you buy there instead.
5. Upgrades apply to every factory at once, so they never become per-line
   bookkeeping.
6. When a line is running itself, open the next one - where everything is
   worth an order of magnitude more.

Five factories, one raw material and one product each:

| Factory | Raw | Product | Each |
| --- | --- | --- | --- |
| Lumber Yard | logs | planks | $1 |
| Stone Pit | stone | bricks | $9 |
| Iron Mine | ore | plates | $120 |
| Oil Field | crude | plastic | $2.6K |
| Silicon Lab | sand | chips | $90K |

The stage rates are deliberately not in exact balance with each other. If one
extractor fed exactly one assembler, a single machine at either would raise
throughput by nothing at all and the shop would feel dead. Offset, every
purchase moves the line and hands the bottleneck to the next stage.

## Rebuilding

Past $600M earned in a run, **rebuild**: gold, machines, upgrades and every
factory but the first go, and you keep blueprints - a permanent +25% on
everything you sell, forever. Optimal play reaches the first rebuild in about
90 minutes; a first playthrough takes rather longer.

Away from the watch, every open line keeps running at 60% for 8 hours, and
STORAGE buys more of those hours as well as bigger buffers. You get a card on
the way back in.

## Building

Needs a Connect IQ SDK and a JDK. If you installed an SDK with the graphical
SDK Manager it is found automatically; otherwise point `CIQ_SDK` at it.

```sh
tools/build.sh              # build build/Foundry-venu2.prg
tools/verify.sh             # the checks that need no SDK
CIQ_SDK=~/my-sdk tools/build.sh
```

`tools/build.sh` generates the launcher icons, runs the layout check and signs
the build with `build/developer_key.der`, generating one if there is none.
That key is personal and is never committed.

To sideload, copy `build/Foundry-venu2.prg` to `GARMIN/APPS` on the watch. To
run it in the simulator:

```sh
"$CIQ_SDK/bin/simulator" &
"$CIQ_SDK/bin/monkeydo" build/Foundry-venu2.prg venu2
```

`manifest.xml` ships `venu2` only, because that is the device profile this was
tested against. The layout scales from a 416x416 design space, so adding
`venu2s` and `venu2plus` to the manifest and to `tools/build.sh` is enough to
cover the rest of the family.

## Layout

```
source/
  FoundryApp.mc      entry point; picks the board or the welcome card
  GameState.mc       the wallet, the five factories, save/load, offline maths
  Factory.mc         one line: three stages, two buffers, the flow between them
  Balance.mc         every tunable number in the game
  GameView.mc        the board
  Sprites.mc         the workers, the cogs and the works, drawn from primitives
  ManageView.mc      the five management pages
  WelcomeView.mc     what happened while you were away
  Theme.mc           colours and drawing primitives
  Layout.mc          416x416 design space to whatever the device has
  Fmt.mc             big numbers, short strings
  Events.mc          state changes, announced rather than polled
```

Two things are worth knowing before changing anything:

**Balance lives in `Balance.mc`.** Factories are described by parallel arrays
indexed by factory id, and anything that varies per stage as well is flattened
to `factory * STAGE_COUNT + stage`. Nothing else in the game hardcodes a cost,
a rate or a position.

**Idle progress is arithmetic, not simulation.** While the app is open the
buffers are stepped for real, so a stage you just bought visibly fills the one
in front of it. While it is closed nothing is stepped at all: a line's output
is its steady-state throughput, which is exactly what the stepped version
converges to - so the two never disagree about what a factory is worth.

## Checks

`tools/verify.sh` runs without an SDK and is what CI runs:

- `check_layout.py` reads the board out of `Balance.mc` and asserts every row
  clears the bezel, clears the wallet above it and the income line below it,
  leaves room for its buffer bar, and does not overlap the button or the
  factory dots.
- `simulate_economy.py` replays the balance table with a greedy buyer and
  reports how long each factory takes to reach, failing if the curve collapses
  or the factories come out of order. It also catches a subtler thing: if the
  stage rates were ever put in exact balance, the buyer would find every
  purchase worth nothing and stall - which is the same dead shop a player
  would find.
