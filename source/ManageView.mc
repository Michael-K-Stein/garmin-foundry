import Toybox.Graphics;
import Toybox.Lang;
import Toybox.WatchUi;

//! The management pages, swiped between left and right.
module Page {
    const UPGRADES = 0;
    const STORAGE = 1;
    const LINE = 2;
    const REBUILD = 3;
    const OPTIONS = 4;
    const COUNT = 5;
}

//! Everything you spend money on that is not a machine. One page per
//! category, at most three rows per page, every row a 72px slab you can hit
//! without looking.
class ManageView extends WatchUi.View {

    private var mGame as GameState or Null = null;
    private var mPage as Number;

    // Row geometry in device pixels, recomputed on layout.
    private var mRowY as Array<Number> = [] as Array<Number>;
    private var mRowX as Array<Number> = [] as Array<Number>;
    private var mRowW as Array<Number> = [] as Array<Number>;
    private var mRowH as Number = 0;

    //! Rows on the current page: [title, detail, cost, enabled].
    private var mRows as Array<Array<Object> > = [] as Array<Array<Object> >;

    function initialize(page as Number) {
        View.initialize();
        mPage = page;
    }

    function onLayout(dc as Dc) as Void {
        Layout.measure(dc);
        mRowH = Layout.s(72);
        var tops = [Layout.s(70), Layout.s(148), Layout.s(226)] as Array<Number>;
        mRowY = tops;
        mRowX = new [tops.size()] as Array<Number>;
        mRowW = new [tops.size()] as Array<Number>;
        for (var i = 0; i < tops.size(); i += 1) {
            var row = Layout.fitRow(tops[i], mRowH, Layout.s(10));
            mRowX[i] = row[0];
            mRowW[i] = row[1];
        }
    }

    function onShow() as Void {
        mGame = FoundryApp.game();
    }

    function turnPage(delta as Number) as Void {
        mPage = (mPage + delta + Page.COUNT) % Page.COUNT;
        WatchUi.requestUpdate();
    }

    // ------------------------------------------------------------------ input

    //! A tap in device pixels. Returns true if it bought something.
    function onTapAt(px as Number, py as Number) as Boolean {
        for (var i = 0; i < mRows.size() && i < mRowY.size(); i += 1) {
            var y = mRowY[i];
            if (py < y || py > y + mRowH || px < mRowX[i] || px > mRowX[i] + mRowW[i]) {
                continue;
            }
            return buy(i);
        }
        return false;
    }

    private function buy(index as Number) as Boolean {
        var game = mGame;
        if (game == null) {
            return false;
        }
        var done = false;
        if (mPage == Page.UPGRADES) {
            done = game.buyUpgrade(index);
        } else if (mPage == Page.STORAGE) {
            done = game.buyUpgrade(Balance.UPG_BUFFER);
        } else if (mPage == Page.LINE) {
            done = game.unlockFactory();
        } else if (mPage == Page.REBUILD) {
            return rebuild(game);
        } else if (mPage == Page.OPTIONS) {
            game.haptics = !game.haptics;
            game.save();
            if (game.haptics) {
                Haptics.confirm();
            }
            WatchUi.requestUpdate();
            return true;
        }

        if (done) {
            Haptics.confirm();
            game.save();
        } else {
            Haptics.deny();
        }
        WatchUi.requestUpdate();
        return done;
    }

    //! Rebuilding throws away everything on every board, so it asks.
    private function rebuild(game as GameState) as Boolean {
        if (!game.canPrestige()) {
            Haptics.deny();
            return false;
        }
        WatchUi.pushView(
            new WatchUi.Confirmation("Rebuild? +"
                + game.prestigeGain().toString() + " blueprints"),
            new PrestigeDelegate(),
            WatchUi.SLIDE_UP);
        return true;
    }

    // ----------------------------------------------------------------- drawing

    function onUpdate(dc as Dc) as Void {
        Layout.measure(dc);
        dc.setColor(Theme.TEXT, Theme.BG);
        dc.clear();

        var game = mGame;
        if (game == null) {
            return;
        }
        mRows = rowsFor(game);

        dc.setColor(Theme.TEXT_DIM, Graphics.COLOR_TRANSPARENT);
        dc.drawText(Layout.cx, Layout.s(34), Graphics.FONT_XTINY, title(game),
            Graphics.TEXT_JUSTIFY_CENTER);

        for (var i = 0; i < mRows.size() && i < mRowY.size(); i += 1) {
            drawRow(dc, i, mRows[i]);
        }

        if (mPage == Page.STORAGE) {
            drawStorageDetail(dc, game);
        } else if (mPage == Page.LINE) {
            drawLineDetail(dc, game);
        } else if (mPage == Page.REBUILD) {
            drawRebuildDetail(dc, game);
        }

        dc.setColor(Theme.GOLD, Graphics.COLOR_TRANSPARENT);
        dc.drawText(Layout.cx, Layout.s(304), Graphics.FONT_TINY,
            Fmt.cash(game.gold), Graphics.TEXT_JUSTIFY_CENTER);
        drawPageDots(dc);
    }

    //! The line page is about the factory on screen, so its title says which.
    private function title(game as GameState) as String {
        if (mPage == Page.UPGRADES) {
            return "UPGRADES";
        }
        if (mPage == Page.STORAGE) {
            return "STORAGE";
        }
        if (mPage == Page.LINE) {
            return game.factory().name();
        }
        if (mPage == Page.REBUILD) {
            return "REBUILD";
        }
        return "OPTIONS";
    }

    //! Build the current page's rows. Cost is a Double; enabled is a Boolean.
    private function rowsFor(game as GameState) as Array<Array<Object> > {
        if (mPage == Page.UPGRADES) {
            return [
                upgradeRow(game, Balance.UPG_HARVEST),
                upgradeRow(game, Balance.UPG_CRAFT),
                upgradeRow(game, Balance.UPG_SELL)
            ] as Array<Array<Object> >;
        }

        if (mPage == Page.STORAGE) {
            return [upgradeRow(game, Balance.UPG_BUFFER)] as Array<Array<Object> >;
        }

        if (mPage == Page.LINE) {
            var here = game.factory();
            if (here.unlocked) {
                // Nothing to buy here: the machines are bought on the board.
                return [] as Array<Array<Object> >;
            }
            return [row("BUILD", here.rawName() + " into " + here.productName(),
                here.unlockCost(), game)] as Array<Array<Object> >;
        }

        if (mPage == Page.REBUILD) {
            var detail = game.canPrestige()
                ? "+" + game.prestigeGain().toString() + " blueprints"
                : Fmt.cash(game.prestigeNeeded()) + " to go";
            // A free row: the cost column stays empty.
            return [
                ["REBUILD", detail, 0.0d, game.canPrestige()] as Array<Object>
            ] as Array<Array<Object> >;
        }

        return [
            ["HAPTICS", game.haptics ? "on" : "off", 0.0d, true] as Array<Object>
        ] as Array<Array<Object> >;
    }

    private function upgradeRow(game as GameState, index as Number) as Array<Object> {
        var step = (Balance.UPG_STEP as Array<Float>)[index];
        var level = game.levels[index];
        var detail = "Lv " + level.toString() + "  x"
            + Fmt.rate((1.0 + step * level).toDouble());
        return row((Balance.UPG_NAME as Array<String>)[index], detail,
            game.upgradeCost(index), game);
    }

    private function row(label as String, detail as String, cost as Double,
                         game as GameState) as Array<Object> {
        return [label, detail, cost, game.gold >= cost] as Array<Object>;
    }

    private function drawRow(dc as Dc, index as Number, data as Array<Object>) as Void {
        var x = mRowX[index];
        var y = mRowY[index];
        var w = mRowW[index];
        var enabled = data[3] as Boolean;
        var cost = data[2] as Double;

        Theme.panel(dc, x, y, w, mRowH, Layout.s(16),
            enabled ? Theme.PANEL_HI : Theme.PANEL,
            enabled ? Theme.GOLD_DIM : null);

        var pad = Layout.s(18);
        dc.setColor(enabled ? Theme.TEXT : Theme.TEXT_DIM, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x + pad, y + Layout.s(8), Graphics.FONT_TINY,
            data[0] as String, Graphics.TEXT_JUSTIFY_LEFT);
        dc.setColor(Theme.TEXT_DIM, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x + pad, y + Layout.s(38), Graphics.FONT_XTINY,
            data[1] as String, Graphics.TEXT_JUSTIFY_LEFT);

        if (cost > 0.0d) {
            dc.setColor(enabled ? Theme.GOLD : Theme.BAD, Graphics.COLOR_TRANSPARENT);
            dc.drawText(x + w - pad, y + mRowH / 2, Graphics.FONT_TINY,
                Fmt.cash(cost),
                Graphics.TEXT_JUSTIFY_RIGHT | Graphics.TEXT_JUSTIFY_VCENTER);
        }
    }

    //! Storage never raises what a line produces, only how long it can run
    //! out of step with itself, so the page says so rather than letting the
    //! player infer it from a multiplier.
    private function drawStorageDetail(dc as Dc, game as GameState) as Void {
        var here = game.factory();
        var y = mRowY[1] + Layout.s(6);
        dc.setColor(Theme.TEXT_DIM, Graphics.COLOR_TRANSPARENT);
        dc.drawText(Layout.cx, y, Graphics.FONT_XTINY,
            here.bufferMax(game.multipliers()).toNumber().toString()
            + " units either side", Graphics.TEXT_JUSTIFY_CENTER);
        dc.drawText(Layout.cx, y + Layout.s(26), Graphics.FONT_XTINY,
            "a full buffer is wasted output", Graphics.TEXT_JUSTIFY_CENTER);
        dc.setColor(Theme.GOLD, Graphics.COLOR_TRANSPARENT);
        dc.drawText(Layout.cx, y + Layout.s(56), Graphics.FONT_TINY,
            Fmt.duration(game.offlineWindow()) + " unattended",
            Graphics.TEXT_JUSTIFY_CENTER);
    }

    //! What the factory on screen is actually doing, in one place: the stage
    //! that is holding it back, what it settles at, and what it has sold.
    private function drawLineDetail(dc as Dc, game as GameState) as Void {
        var here = game.factory();
        if (!here.unlocked) {
            return;
        }
        var mult = game.multipliers();
        var y = mRowY[0] + Layout.s(10);

        dc.setColor(Theme.CHOKE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(Layout.cx, y, Graphics.FONT_SMALL,
            (Balance.STAGE_NAME as Array<String>)[here.bottleneck(mult)]
            + " IS SLOWEST", Graphics.TEXT_JUSTIFY_CENTER);

        dc.setColor(Theme.TEXT_DIM, Graphics.COLOR_TRANSPARENT);
        dc.drawText(Layout.cx, y + Layout.s(40), Graphics.FONT_XTINY,
            Fmt.rate(here.throughput(mult).toDouble()) + " "
            + here.productName() + "/s", Graphics.TEXT_JUSTIFY_CENTER);

        dc.setColor(Theme.GOLD, Graphics.COLOR_TRANSPARENT);
        dc.drawText(Layout.cx, y + Layout.s(66), Graphics.FONT_TINY,
            "+" + Fmt.cash(here.incomePerSecond(mult) * 60.0d
                * game.blueprintBonus().toDouble()) + "/min",
            Graphics.TEXT_JUSTIFY_CENTER);

        dc.setColor(Theme.TEXT_DIM, Graphics.COLOR_TRANSPARENT);
        dc.drawText(Layout.cx, y + Layout.s(104), Graphics.FONT_XTINY,
            Fmt.big(here.sold.toDouble()) + " " + here.productName() + " sold",
            Graphics.TEXT_JUSTIFY_CENTER);
    }

    private function drawRebuildDetail(dc as Dc, game as GameState) as Void {
        var y = mRowY[1] + Layout.s(6);
        dc.setColor(Theme.TEXT_DIM, Graphics.COLOR_TRANSPARENT);
        dc.drawText(Layout.cx, y, Graphics.FONT_XTINY,
            "keeps blueprints, nothing else", Graphics.TEXT_JUSTIFY_CENTER);
        if (game.blueprints <= 0) {
            return;
        }
        dc.setColor(Theme.GOLD, Graphics.COLOR_TRANSPARENT);
        dc.drawText(Layout.cx, y + Layout.s(34), Graphics.FONT_TINY,
            game.blueprints.toString() + " BLUEPRINTS - x"
            + Fmt.rate(game.blueprintBonus().toDouble()),
            Graphics.TEXT_JUSTIFY_CENTER);
    }

    private function drawPageDots(dc as Dc) as Void {
        var spacing = Layout.s(18);
        var y = Layout.s(356);
        var left = Layout.cx - spacing * (Page.COUNT - 1) / 2;
        for (var i = 0; i < Page.COUNT; i += 1) {
            dc.setColor(i == mPage ? Theme.GOLD : Theme.PANEL_HI,
                Graphics.COLOR_TRANSPARENT);
            dc.fillCircle(left + i * spacing, y, Layout.s(4));
        }
    }
}
