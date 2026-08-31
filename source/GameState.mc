import Toybox.Application;
import Toybox.Lang;
import Toybox.Math;
import Toybox.System;
import Toybox.Time;

//! The whole simulation: five factories, the four upgrades they all share,
//! the single wallet they feed, and the save file. Views never write these
//! fields directly - they call the command and buy helpers below, so every
//! invariant lives in one place.
class GameState {

    //! Bumped whenever the save layout changes incompatibly.
    private const SAVE_VERSION = 1;
    private const SAVE_KEY = "foundry";

    // --- Persistent ------------------------------------------------------
    public var gold as Double = 0.0d;
    public var lifetime as Double = 0.0d;
    //! Lifetime earnings since the last rebuild, which is what a rebuild is
    //! priced from. `lifetime` itself never resets.
    public var run as Double = 0.0d;

    //! Upgrade levels, indexed by Balance.UPG_*.
    public var levels as Array<Number>;
    //! Blueprints, earned by rebuilding. They never reset.
    public var blueprints as Number = 0;

    public var haptics as Boolean = true;
    public var lastSeen as Number = 0;

    // --- The world -------------------------------------------------------
    public var factories as Array<Factory>;
    public var current as Number = Balance.LUMBER;

    // --- Waiting to be claimed ------------------------------------------
    public var offlineGold as Double = 0.0d;
    public var offlineSecs as Number = 0;

    private var mLastTickMs as Number = 0;
    private var mSinceSaveSecs as Float = 0.0;

    function initialize() {
        levels = new [Balance.UPG_COUNT] as Array<Number>;
        for (var i = 0; i < Balance.UPG_COUNT; i += 1) {
            levels[i] = 0;
        }
        factories = new [Balance.FACTORY_COUNT] as Array<Factory>;
        for (var f = 0; f < Balance.FACTORY_COUNT; f += 1) {
            factories[f] = new Factory(f);
        }
        mLastTickMs = System.getTimer();
    }

    function factory() as Factory {
        return factories[current];
    }

    // ------------------------------------------------------------ stat curves

    //! The four global multipliers, in the order the rest of the game indexes
    //! them: the first three line up with the stage ids on purpose, so a
    //! stage can look up its own multiplier without a translation table.
    function multipliers() as Array<Float> {
        var out = new [Balance.UPG_COUNT] as Array<Float>;
        for (var i = 0; i < Balance.UPG_COUNT; i += 1) {
            out[i] = 1.0 + (Balance.UPG_STEP as Array<Float>)[i] * levels[i];
        }
        return out;
    }

    //! Permanent cut on everything sold, bought with blueprints.
    function blueprintBonus() as Float {
        return 1.0 + Balance.BLUEPRINT_STEP * blueprints;
    }

    //! How long the lines keep going unattended, in seconds. Storage buys
    //! this as well as the buffers themselves.
    function offlineWindow() as Number {
        var mult = multipliers();
        return (Balance.MAX_OFFLINE_SECS * mult[Balance.UPG_BUFFER]).toNumber();
    }

    function upgradeCost(index as Number) as Double {
        var price = (Balance.UPG_COST as Array<Float>)[index].toDouble();
        for (var i = 0; i < levels[index]; i += 1) {
            price *= Balance.UPG_GROWTH;
        }
        return price;
    }

    function factoriesOpen() as Number {
        var total = 0;
        for (var f = 0; f < factories.size(); f += 1) {
            if (factories[f].unlocked) {
                total += 1;
            }
        }
        return total;
    }

    //! Hands-off income from every open factory, in gold per second.
    function incomePerSecond() as Double {
        var mult = multipliers();
        var total = 0.0d;
        for (var f = 0; f < factories.size(); f += 1) {
            if (factories[f].unlocked) {
                total += factories[f].incomePerSecond(mult);
            }
        }
        return total * blueprintBonus();
    }

    // -------------------------------------------------------------- commands

    function earn(amount as Double) as Void {
        if (amount <= 0.0d) {
            return;
        }
        gold += amount;
        lifetime += amount;
        run += amount;
        Events.emit(Events.GOLD_CHANGED, gold);
    }

    private function spend(amount as Double) as Boolean {
        if (gold < amount) {
            return false;
        }
        gold -= amount;
        Events.emit(Events.GOLD_CHANGED, gold);
        return true;
    }

    //! Add one machine to a stage of the factory on screen.
    function buyMachine(stage as Number) as Boolean {
        var here = factory();
        if (!here.canBuy(stage)) {
            return false;
        }
        if (!spend(here.cost(stage))) {
            return false;
        }
        here.add(stage);
        Events.emit(Events.MACHINE_BOUGHT, stage.toDouble());
        return true;
    }

    function buyUpgrade(index as Number) as Boolean {
        if (index < 0 || index >= Balance.UPG_COUNT) {
            return false;
        }
        if (!spend(upgradeCost(index))) {
            return false;
        }
        levels[index] += 1;
        Events.emit(Events.UPGRADE_BOUGHT, levels[index].toDouble());
        return true;
    }

    function unlockFactory() as Boolean {
        var here = factory();
        if (here.unlocked || !spend(here.unlockCost())) {
            return false;
        }
        here.unlocked = true;
        here.staff();
        Events.emit(Events.FACTORY_UNLOCKED, here.id.toDouble());
        return true;
    }

    function moveTo(delta as Number) as Void {
        current = (current + delta + Balance.FACTORY_COUNT) % Balance.FACTORY_COUNT;
    }

    // -------------------------------------------------------------- rebuilding

    //! Blueprints a rebuild would pay out right now. The square root is what
    //! keeps the second rebuild worth doing after the first one multiplied
    //! everything: earnings grow geometrically, blueprints grow slowly.
    function prestigeGain() as Number {
        if (run < Balance.PRESTIGE_MIN) {
            return 0;
        }
        var ratio = run / Balance.PRESTIGE_SCALE.toDouble();
        var points = Math.sqrt(ratio.toFloat()).toNumber();
        return (points > 0) ? points : 0;
    }

    function canPrestige() as Boolean {
        return prestigeGain() > 0;
    }

    //! Lifetime earnings still needed before a rebuild pays anything.
    function prestigeNeeded() as Double {
        var need = Balance.PRESTIGE_MIN.toDouble() - run;
        return (need > 0.0d) ? need : 0.0d;
    }

    function prestige() as Boolean {
        var gain = prestigeGain();
        if (gain <= 0) {
            return false;
        }
        blueprints += gain;
        gold = 0.0d;
        run = 0.0d;
        for (var i = 0; i < levels.size(); i += 1) {
            levels[i] = 0;
        }
        for (var f = 0; f < factories.size(); f += 1) {
            factories[f].reset();
        }
        current = Balance.LUMBER;
        offlineGold = 0.0d;
        offlineSecs = 0;
        save();
        return true;
    }

    // -------------------------------------------------------------- simulation

    //! Advance everything by wall-clock time, so the result does not depend
    //! on how often the active view happens to redraw.
    //!
    //! Every open factory is stepped, not just the one on screen: a line you
    //! walked away from is the whole point of having built it.
    function tick() as Void {
        var now = System.getTimer();
        var dtMs = now - mLastTickMs;
        mLastTickMs = now;

        // System.getTimer() wraps roughly every 25 days; a negative or absurd
        // delta means we lost track, so charge nothing for it.
        if (dtMs <= 0 || dtMs > 5000) {
            return;
        }
        var dt = dtMs / 1000.0;

        var mult = multipliers();
        var earned = 0.0d;
        for (var f = 0; f < factories.size(); f += 1) {
            earned += factories[f].tick(dt, mult);
        }
        if (earned > 0.0d) {
            earn(earned * blueprintBonus());
        }

        mSinceSaveSecs += dt;
        if (mSinceSaveSecs >= Balance.AUTOSAVE_SECS) {
            mSinceSaveSecs = 0.0;
            save();
        }
    }

    function claimOffline() as Void {
        if (offlineGold > 0.0d) {
            earn(offlineGold);
        }
        offlineGold = 0.0d;
        offlineSecs = 0;
    }

    function hasOffline() as Boolean {
        return offlineGold > 0.0d;
    }

    // ------------------------------------------------------------ persistence

    function save() as Void {
        lastSeen = Time.now().value();

        var open = new [factories.size()] as Array<Number>;
        var raws = new [factories.size()] as Array<Double>;
        var products = new [factories.size()] as Array<Double>;
        var solds = new [factories.size()] as Array<Double>;
        var counts = new [factories.size() * Balance.STAGE_COUNT] as Array<Number>;

        for (var f = 0; f < factories.size(); f += 1) {
            var line = factories[f];
            open[f] = line.unlocked ? 1 : 0;
            raws[f] = line.raw.toDouble();
            products[f] = line.product.toDouble();
            solds[f] = line.sold.toDouble();
            for (var s = 0; s < Balance.STAGE_COUNT; s += 1) {
                counts[f * Balance.STAGE_COUNT + s] = line.counts[s];
            }
        }

        var data = {
            "v" => SAVE_VERSION,
            "gold" => gold,
            "life" => lifetime,
            "run" => run,
            "lvl" => levels,
            "bp" => blueprints,
            "at" => current,
            "open" => open,
            "raw" => raws,
            "prod" => products,
            "sold" => solds,
            "count" => counts,
            "haptics" => haptics,
            "seen" => lastSeen
        };
        try {
            Application.Storage.setValue(SAVE_KEY, data);
        } catch (ex) {
            // A full storage partition must never take the game down.
            System.println("save failed");
        }
    }

    function load() as Void {
        mLastTickMs = System.getTimer();
        var raw = null;
        try {
            raw = Application.Storage.getValue(SAVE_KEY);
        } catch (ex) {
            raw = null;
        }
        if (!(raw instanceof Lang.Dictionary)) {
            return;
        }
        var data = raw as Dictionary;
        // Saves from an older layout are dropped rather than guessed at.
        if (readNumber(data, "v", 0) != SAVE_VERSION) {
            return;
        }

        gold = readDouble(data, "gold", 0.0d);
        lifetime = readDouble(data, "life", 0.0d);
        run = readDouble(data, "run", 0.0d);
        blueprints = readNumber(data, "bp", 0);
        if (blueprints < 0) {
            blueprints = 0;
        }
        lastSeen = readNumber(data, "seen", 0);

        var flag = data["haptics"];
        haptics = (flag instanceof Lang.Boolean) ? flag : true;

        var saved = numbers(data, "lvl");
        for (var i = 0; i < levels.size(); i += 1) {
            var level = at(saved, i, 0.0).toNumber();
            levels[i] = (level > 0) ? level : 0;
        }

        var open = numbers(data, "open");
        var raws = numbers(data, "raw");
        var products = numbers(data, "prod");
        var solds = numbers(data, "sold");
        var counts = numbers(data, "count");

        for (var f = 0; f < factories.size(); f += 1) {
            var line = factories[f];
            line.unlocked = (f == Balance.LUMBER) || at(open, f, 0.0) > 0.5;
            line.raw = positive(at(raws, f, 0.0));
            line.product = positive(at(products, f, 0.0));
            line.sold = positive(at(solds, f, 0.0));
            for (var s = 0; s < Balance.STAGE_COUNT; s += 1) {
                var owned = at(counts, f * Balance.STAGE_COUNT + s, 0.0).toNumber();
                if (owned < 0) {
                    owned = 0;
                }
                if (owned > Balance.MACHINE_MAX) {
                    owned = Balance.MACHINE_MAX;
                }
                line.counts[s] = owned;
            }
            if (line.unlocked) {
                line.staff();
            }
        }

        var where = readNumber(data, "at", Balance.LUMBER);
        current = (where >= 0 && where < factories.size()) ? where : Balance.LUMBER;

        computeOffline();
    }

    //! What every open factory got through while the app was closed. Nothing
    //! is simulated step by step: each line settles at its throughput, and
    //! that is the same number the screen quotes while the app is open.
    private function computeOffline() as Void {
        offlineGold = 0.0d;
        offlineSecs = 0;
        if (lastSeen <= 0) {
            return;
        }
        var elapsed = Time.now().value() - lastSeen;
        if (elapsed < Balance.MIN_OFFLINE_SECS) {
            return;
        }
        var window = offlineWindow();
        if (elapsed > window) {
            elapsed = window;
        }

        var mult = multipliers();
        var earned = 0.0d;
        for (var f = 0; f < factories.size(); f += 1) {
            earned += factories[f].offline(elapsed, mult);
        }
        earned *= blueprintBonus();
        if (earned > 0.0d) {
            offlineGold = earned;
            offlineSecs = elapsed;
        }
    }

    // ---------------------------------------------------------------- helpers

    private function positive(value as Float) as Float {
        return (value > 0.0) ? value : 0.0;
    }

    private function readNumber(data as Dictionary, key as String, fallback as Number) as Number {
        var value = data[key];
        return (value instanceof Lang.Number) ? value : fallback;
    }

    private function readDouble(data as Dictionary, key as String, fallback as Double) as Double {
        var value = data[key];
        if (value instanceof Lang.Double || value instanceof Lang.Float
                || value instanceof Lang.Number || value instanceof Lang.Long) {
            var d = value.toDouble();
            return (d >= 0.0d) ? d : fallback;
        }
        return fallback;
    }

    //! A saved array read back as plain floats, or null if it is missing or
    //! is not an array at all.
    private function numbers(data as Dictionary, key as String) as Array<Float> or Null {
        var value = data[key];
        if (!(value instanceof Lang.Array)) {
            return null;
        }
        var list = value as Array;
        var out = new [list.size()] as Array<Float>;
        for (var i = 0; i < list.size(); i += 1) {
            var item = list[i];
            out[i] = (item instanceof Lang.Number || item instanceof Lang.Float
                || item instanceof Lang.Double || item instanceof Lang.Long)
                ? item.toFloat() : 0.0;
        }
        return out;
    }

    private function at(list as Array<Float> or Null, index as Number,
                        fallback as Float) as Float {
        if (list == null || index < 0 || index >= list.size()) {
            return fallback;
        }
        return list[index];
    }
}
