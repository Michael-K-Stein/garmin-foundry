import Toybox.Lang;

//! Every tunable number in the game. Nothing in the simulation hardcodes a
//! cost, a rate or a position: balance passes live here so they can be
//! retuned without touching the systems that read them.
//!
//! The five factories are described by parallel arrays indexed by factory id,
//! and anything that varies per stage as well is flattened to
//! `factory * STAGE_COUNT + stage`. That is clumsier to read than one record
//! per factory would be, but Monkey C has no struct type and a dictionary of
//! mixed-type values fights the type checker, so the arrays stay flat and
//! each one is documented where it is declared.
module Balance {

    // --- The screen -----------------------------------------------------
    //! The board is authored for a 416x416 round face and scaled in Layout.
    //! Three stage rows stacked down the middle, one contextual button under
    //! them. tools/check_layout.py reads these back and asserts they fit.
    //! The factory name, then the wallet, then the three rows, then what the
    //! whole operation earns, then the button, then one dot per factory.
    //! GOLD_H and INCOME_H are the heights those two text lines actually
    //! occupy - the numeric face is a good deal taller than the point size
    //! suggests, and a row that starts too high gets a wallet through it.
    const NAME_Y = 20;
    const GOLD_TOP = 40;
    const GOLD_H = 64;

    const ROW_TOP = [112, 178, 244];
    const ROW_H = 58;
    //! Buffer bar, drawn in the gap under a row.
    const BAR_H = 6;
    const BAR_DROP = 1;
    //! How far a row is held off the bezel on each side.
    const ROW_INSET = 8;

    //! Where a row's text starts, clear of the character drawn on its left,
    //! and how big that character is.
    const ROW_TEXT_X = 74;
    const WORKER_SIZE = 46;

    //! Animation pace: turns per second is ANIM_MIN plus the stage's own
    //! throughput scaled by ANIM_PER_UNIT, capped at ANIM_MAX. It flattens
    //! because past a couple of swings a second more frames of the same
    //! motion read as noise rather than as more work being done.
    const ANIM_MIN = 0.35;
    const ANIM_PER_UNIT = 0.22;
    const ANIM_MAX = 2.2;

    const INCOME_Y = 306;
    const INCOME_H = 24;
    const BUTTON_TOP = 336;
    const BUTTON_H = 52;
    //! One dot per factory, under the button.
    const DOTS_Y = 400;

    // --- Stages ---------------------------------------------------------
    //! One factory is three stages in a line: dig it up, make it into
    //! something, sell that. Every machine the player buys belongs to one of
    //! them, and the slowest stage is the one worth spending on.
    const STAGE_COUNT = 3;
    const HARVEST = 0;
    const CRAFT = 1;
    const SELL = 2;

    const STAGE_NAME = ["HARVEST", "CRAFT", "SELL"];
    //! What one machine of each stage is called, for the detail line.
    const UNIT_NAME = ["extractors", "assemblers", "traders"];

    //! Raw units an assembler eats per product it makes.
    //!
    //! The stage rates below are deliberately *not* in exact balance with it:
    //! one extractor feeds slightly more than one assembler, and one trader
    //! clears slightly more than one assembler makes. If the three tied, a
    //! single machine at either of the tied stages would raise throughput by
    //! nothing at all and the shop would feel dead - offset, every purchase
    //! moves the line and hands the bottleneck to the next stage along.
    const CRAFT_INPUT = 2.0;

    // --- Factories ------------------------------------------------------
    const FACTORY_COUNT = 5;
    const LUMBER = 0;
    const STONE = 1;
    const IRON = 2;
    const OIL = 3;
    const SILICON = 4;

    const FACTORY_NAME = ["LUMBER YARD", "STONE PIT", "IRON MINE", "OIL FIELD",
                          "SILICON LAB"];
    const RAW_NAME = ["logs", "stone", "ore", "crude", "sand"];
    const PRODUCT_NAME = ["planks", "bricks", "plates", "plastic", "chips"];

    //! Gold for one finished product. The whole income curve hangs off this.
    const PRODUCT_VALUE = [1.0, 9.0, 120.0, 2600.0, 90000.0];
    //! Gold to open the factory. The first one is free.
    const UNLOCK_COST = [0.0, 2500.0, 55000.0, 1.2e6, 4.0e7];

    //! Per-machine throughput at level zero, per second. Later factories are
    //! slower per machine and worth far more per product, so a late board is
    //! about buying fewer, better-paid units rather than more of the same.
    const HARVEST_RATE = [1.10, 0.99, 0.88, 0.77, 0.66];
    const CRAFT_RATE = [0.50, 0.45, 0.40, 0.35, 0.30];
    //! Traders run slightly ahead of the assemblers on purpose: the product
    //! buffer should only back up when the player has over-bought crafting.
    const SELL_RATE = [0.60, 0.54, 0.48, 0.42, 0.36];

    //! Cost of the first machine of each stage, flattened by
    //! `factory * STAGE_COUNT + stage`. Sell machines are dearest because
    //! they are the stage that actually pays.
    //! Each factory's prices are its own income scaled: a machine costs
    //! roughly the same number of seconds of that line's output wherever you
    //! are, so a late board fills at the same pace an early one did and the
    //! pacing comes from the unlock costs rather than from the shop.
    const MACHINE_COST = [
        12.0, 30.0, 45.0,
        100.0, 250.0, 360.0,
        1150.0, 2900.0, 4300.0,
        22000.0, 55000.0, 82000.0,
        650000.0, 1.6e6, 2.4e6
    ];
    //! cost = base * COST_GROWTH^owned, the usual idle exponential.
    const COST_GROWTH = 1.14;
    //! A stage stops accepting machines here, so the next factory is the
    //! only place left to put money.
    const MACHINE_MAX = 25;
    //! Every factory starts with one machine in each stage the moment it is
    //! opened, so a fresh board is producing before the player buys anything.
    const MACHINE_START = 1;

    // --- Buffers --------------------------------------------------------
    //! Units that can sit between two stages. A full buffer means the stage
    //! feeding it is wasting output, which is the game's way of saying "you
    //! bought the wrong stage".
    const BUFFER_BASE = 60.0;
    //! Storage buys the same fraction of two things: what a buffer holds, and
    //! how long a line keeps going with nobody watching. Both are the same
    //! idea - somewhere to put output until it can be dealt with - and one
    //! upgrade for both keeps the shop one row shorter.
    const BUFFER_STEP = 0.45;

    // --- Upgrades -------------------------------------------------------
    //! Bought once and applied to every factory, because per-factory tuning
    //! is exactly the fiddling this game is avoiding.
    const UPG_COUNT = 4;
    const UPG_HARVEST = 0;
    const UPG_CRAFT = 1;
    const UPG_SELL = 2;
    const UPG_BUFFER = 3;

    //! Kept short: the row draws the name on the left and the price on the
    //! right, and a seven-figure price leaves little room for a long word.
    const UPG_NAME = ["EXTRACT", "ASSEMBLE", "TRADE", "STORAGE"];
    //! Fraction of base added per level: rate upgrades are +30%, storage
    //! +45% because it never raises throughput, only how much of it survives
    //! being unattended.
    const UPG_STEP = [0.30, 0.30, 0.30, BUFFER_STEP];
    const UPG_COST = [90.0, 140.0, 200.0, 320.0];
    const UPG_GROWTH = 1.72;

    // --- Rebuilding (prestige) ------------------------------------------
    //! Tear the whole operation down and put it up again knowing what you
    //! know: gold, machines, upgrades and factory unlocks all go, and every
    //! blueprint is a permanent cut of everything you will ever earn again.
    const PRESTIGE_SCALE = 4.0e7;
    const BLUEPRINT_STEP = 0.25;
    //! Below this in lifetime earnings there is nothing to learn yet.
    const PRESTIGE_MIN = 6.0e8;

    // --- Idle / offline -------------------------------------------------
    //! The unattended window at storage level zero, extended by every level
    //! of it after that.
    const MAX_OFFLINE_SECS = 8 * 3600;
    const MIN_OFFLINE_SECS = 60;
    //! A factory nobody is watching runs, but not at full tilt.
    const OFFLINE_EFFICIENCY = 0.6;

    const AUTOSAVE_SECS = 20.0;
    //! Simulation cadence while a view is on screen.
    const TICK_MS = 100;

    // ------------------------------------------------------------ lookups

    function machineCost(factory as Number, stage as Number) as Float {
        return (MACHINE_COST as Array<Float>)[factory * STAGE_COUNT + stage];
    }

    function stageBaseRate(factory as Number, stage as Number) as Float {
        if (stage == HARVEST) {
            return (HARVEST_RATE as Array<Float>)[factory];
        }
        if (stage == CRAFT) {
            return (CRAFT_RATE as Array<Float>)[factory];
        }
        return (SELL_RATE as Array<Float>)[factory];
    }
}
