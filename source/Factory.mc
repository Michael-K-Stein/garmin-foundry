import Toybox.Lang;

//! One factory: three stages in a line with a buffer between each pair.
//!
//! Extractors pull raw material out of the ground into the raw buffer,
//! assemblers turn raw into product, traders sell product for gold. Nothing
//! here knows about the wallet or the screen - `tick` returns the gold it
//! made and the caller banks it.
class Factory {

    public var id as Number;
    public var unlocked as Boolean = false;

    //! Machines owned per stage.
    public var counts as Array<Number>;

    //! What is sitting between the stages right now.
    public var raw as Float = 0.0;
    public var product as Float = 0.0;

    //! Lifetime products sold from this factory, for the detail page. It is
    //! a float because a tick sells a fraction of a product: rounding each
    //! one down would quietly lose most of a slow line's output.
    public var sold as Float = 0.0;

    function initialize(index as Number) {
        id = index;
        counts = [0, 0, 0] as Array<Number>;
        unlocked = (index == Balance.LUMBER);
        if (unlocked) {
            staff();
        }
    }

    //! Put the opening machine in every stage. A factory the player has paid
    //! for should be making something by the time they look at it.
    function staff() as Void {
        for (var s = 0; s < Balance.STAGE_COUNT; s += 1) {
            if (counts[s] < Balance.MACHINE_START) {
                counts[s] = Balance.MACHINE_START;
            }
        }
    }

    function name() as String {
        return (Balance.FACTORY_NAME as Array<String>)[id];
    }

    function rawName() as String {
        return (Balance.RAW_NAME as Array<String>)[id];
    }

    function productName() as String {
        return (Balance.PRODUCT_NAME as Array<String>)[id];
    }

    function unlockCost() as Double {
        return (Balance.UNLOCK_COST as Array<Float>)[id].toDouble();
    }

    function value() as Float {
        return (Balance.PRODUCT_VALUE as Array<Float>)[id];
    }

    // -------------------------------------------------------------- machines

    function canBuy(stage as Number) as Boolean {
        return unlocked && counts[stage] < Balance.MACHINE_MAX;
    }

    //! Price of the next machine at this stage.
    function cost(stage as Number) as Double {
        var base = Balance.machineCost(id, stage).toDouble();
        var owned = counts[stage];
        var price = base;
        for (var i = 0; i < owned; i += 1) {
            price *= Balance.COST_GROWTH;
        }
        return price;
    }

    function add(stage as Number) as Void {
        counts[stage] += 1;
    }

    // ----------------------------------------------------------------- rates

    //! What a stage moves per second at its current size, in its own units:
    //! raw/s for harvest, products/s for craft and sell.
    function stageRate(stage as Number, mult as Array<Float>) as Float {
        return counts[stage] * Balance.stageBaseRate(id, stage) * mult[stage];
    }

    //! Every stage expressed in the one unit that matters - finished
    //! products per second - so the three are directly comparable and the
    //! smallest of them is the bottleneck.
    function stageFlow(stage as Number, mult as Array<Float>) as Float {
        var rate = stageRate(stage, mult);
        if (stage == Balance.HARVEST) {
            return rate / Balance.CRAFT_INPUT;
        }
        return rate;
    }

    //! Products per second this factory settles at once the buffers stop
    //! moving. This is the number the screen quotes, the number offline
    //! progress is priced from, and the number a stage purchase changes.
    function throughput(mult as Array<Float>) as Float {
        var slowest = stageFlow(0, mult);
        for (var s = 1; s < Balance.STAGE_COUNT; s += 1) {
            var flow = stageFlow(s, mult);
            if (flow < slowest) {
                slowest = flow;
            }
        }
        return slowest;
    }

    //! Which stage is holding the other two back. Ties resolve to the
    //! earliest stage, because that is the one starving the rest.
    function bottleneck(mult as Array<Float>) as Number {
        var worst = 0;
        var slowest = stageFlow(0, mult);
        for (var s = 1; s < Balance.STAGE_COUNT; s += 1) {
            var flow = stageFlow(s, mult);
            if (flow < slowest) {
                slowest = flow;
                worst = s;
            }
        }
        return worst;
    }

    function incomePerSecond(mult as Array<Float>) as Double {
        return throughput(mult).toDouble() * value().toDouble();
    }

    function bufferMax(mult as Array<Float>) as Float {
        return Balance.BUFFER_BASE * mult[Balance.UPG_BUFFER];
    }

    // ------------------------------------------------------------ simulation

    //! Move `dt` seconds of material through the line and return the gold the
    //! traders made. Buffers are simulated rather than assumed, so a stage
    //! that has just been bought visibly fills the one in front of it before
    //! the income catches up.
    function tick(dt as Float, mult as Array<Float>) as Double {
        if (!unlocked) {
            return 0.0d;
        }
        var cap = bufferMax(mult);

        // Harvest, discarding anything the raw buffer cannot hold.
        raw += stageRate(Balance.HARVEST, mult) * dt;
        if (raw > cap) {
            raw = cap;
        }

        // Craft, limited by demand, by raw on hand, and by room to put it.
        var made = stageRate(Balance.CRAFT, mult) * dt;
        var fromRaw = raw / Balance.CRAFT_INPUT;
        if (made > fromRaw) {
            made = fromRaw;
        }
        var room = cap - product;
        if (made > room) {
            made = room;
        }
        if (made > 0.0) {
            raw -= made * Balance.CRAFT_INPUT;
            product += made;
        }

        // Sell whatever the traders can reach.
        var shifted = stageRate(Balance.SELL, mult) * dt;
        if (shifted > product) {
            shifted = product;
        }
        if (shifted <= 0.0) {
            return 0.0d;
        }
        product -= shifted;
        sold += shifted;
        return shifted.toDouble() * value().toDouble();
    }

    //! The same line run forward by a long stretch of wall-clock time without
    //! stepping it. At this scale the buffers have settled, so the answer is
    //! the steady-state throughput - which is exactly what `tick` converges
    //! to, and why the two never disagree about what a factory is worth.
    function offline(secs as Number, mult as Array<Float>) as Double {
        if (!unlocked) {
            return 0.0d;
        }
        var flow = throughput(mult) * Balance.OFFLINE_EFFICIENCY;
        var count = flow * secs;
        if (count <= 0.0) {
            return 0.0d;
        }
        sold += count;
        return count.toDouble() * value().toDouble();
    }

    //! Everything a rebuild takes away. The lifetime sold counter is not on
    //! the list: it is the one number in the game that answers "how much have
    //! I ever made here", and a rebuild is not supposed to unmake that.
    function reset() as Void {
        counts = [0, 0, 0] as Array<Number>;
        raw = 0.0;
        product = 0.0;
        unlocked = (id == Balance.LUMBER);
        if (unlocked) {
            staff();
        }
    }
}
