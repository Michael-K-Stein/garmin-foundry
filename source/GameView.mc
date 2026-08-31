import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.Timer;
import Toybox.WatchUi;

//! The board. One factory at a time, drawn as its three stages stacked down
//! the glass with the buffer between each pair shown in the gap, and one
//! contextual button under them. No camera, no scrolling: swiping sideways
//! changes which of the five factories is on screen.
class GameView extends WatchUi.View {

    private var mGame as GameState or Null = null;
    private var mTimer as Timer.Timer or Null = null;

    // Row geometry in device pixels, filled in by onLayout().
    private var mRowY as Array<Number> = [] as Array<Number>;
    private var mRowX as Array<Number> = [] as Array<Number>;
    private var mRowW as Array<Number> = [] as Array<Number>;
    private var mRowH as Number = 0;

    // Bottom button, in device pixels.
    private var mBtnX as Number = 0;
    private var mBtnY as Number = 0;
    private var mBtnW as Number = 0;
    private var mBtnH as Number = 0;

    //! Free-running animation clock, in turns. Every moving thing on screen
    //! is a function of this and of how fast the stage it belongs to is
    //! actually working, so the board speeds up as the line does.
    private var mPhase as Float = 0.0;

    // The action the button is currently offering.
    const ACT_NONE = 0;
    const ACT_UNLOCK = 1;
    const ACT_BUY = 2;

    function initialize() {
        View.initialize();
    }

    function onLayout(dc as Dc) as Void {
        Layout.measure(dc);
        mRowH = Layout.s(Balance.ROW_H);
        var tops = Balance.ROW_TOP as Array<Number>;
        mRowY = new [tops.size()] as Array<Number>;
        mRowX = new [tops.size()] as Array<Number>;
        mRowW = new [tops.size()] as Array<Number>;
        for (var i = 0; i < tops.size(); i += 1) {
            var y = Layout.s(tops[i]);
            var row = Layout.fitRow(y, mRowH, Layout.s(Balance.ROW_INSET));
            mRowY[i] = y;
            mRowX[i] = row[0];
            mRowW[i] = row[1];
        }

        mBtnH = Layout.s(Balance.BUTTON_H);
        mBtnY = Layout.s(Balance.BUTTON_TOP);
        var button = Layout.fitRow(mBtnY, mBtnH, Layout.s(8));
        mBtnX = button[0];
        mBtnW = button[1];
    }

    function onShow() as Void {
        mGame = FoundryApp.game();
        Events.subscribe(method(:onGameEvent));
        if (mTimer == null) {
            mTimer = new Timer.Timer();
            (mTimer as Timer.Timer).start(method(:onTick), Balance.TICK_MS, true);
        }
    }

    function onHide() as Void {
        Events.unsubscribe();
        if (mTimer != null) {
            (mTimer as Timer.Timer).stop();
            mTimer = null;
        }
        var game = mGame;
        if (game != null) {
            game.save();
        }
    }

    function onTick() as Void {
        var game = mGame;
        if (game == null) {
            return;
        }
        game.tick();
        mPhase += Balance.TICK_MS / 1000.0;
        if (mPhase > 3600.0) {
            mPhase -= 3600.0;   // keep the float small enough to stay precise
        }
        WatchUi.requestUpdate();
    }

    //! The board redraws on its own timer, so an event only has to make sure
    //! the next frame is not waiting on it.
    function onGameEvent(name as Number, value as Double) as Void {
        WatchUi.requestUpdate();
    }

    // ------------------------------------------------------------------ input

    function changeFactory(delta as Number) as Void {
        var game = mGame;
        if (game == null) {
            return;
        }
        game.moveTo(delta);
        Haptics.tap();
        WatchUi.requestUpdate();
    }

    //! A tap in device pixels. A row buys one machine for its stage; anything
    //! on the button does whatever the button says.
    function onTapAt(px as Number, py as Number) as Void {
        if (py >= mBtnY && py <= mBtnY + mBtnH) {
            doAction(action());
            return;
        }
        var game = mGame;
        if (game == null || !game.factory().unlocked) {
            // There are no stage rows on an unbuilt factory, so a tap where
            // they would be is a tap on nothing rather than a refusal.
            return;
        }
        for (var s = 0; s < mRowY.size(); s += 1) {
            var y = mRowY[s];
            if (py >= y && py <= y + mRowH && px >= mRowX[s] && px <= mRowX[s] + mRowW[s]) {
                buy(s);
                return;
            }
        }
    }

    private function buy(stage as Number) as Void {
        var game = mGame;
        if (game == null) {
            return;
        }
        if (game.buyMachine(stage)) {
            Haptics.confirm();
            game.save();
        } else {
            Haptics.deny();
        }
        WatchUi.requestUpdate();
    }

    //! What the bottom button is offering: open this factory if it is shut,
    //! otherwise one more machine at whichever stage is holding the line
    //! back. Never more than one choice, and never a choice the player could
    //! not have worked out from the rows above it.
    function action() as Number {
        var game = mGame;
        if (game == null) {
            return ACT_NONE;
        }
        var here = game.factory();
        if (!here.unlocked) {
            return ACT_UNLOCK;
        }
        return here.canBuy(here.bottleneck(game.multipliers())) ? ACT_BUY : ACT_NONE;
    }

    function doAction(what as Number) as Void {
        var game = mGame;
        if (game == null) {
            return;
        }
        if (what == ACT_UNLOCK) {
            if (game.unlockFactory()) {
                Haptics.confirm();
                game.save();
            } else {
                Haptics.deny();
            }
            WatchUi.requestUpdate();
            return;
        }
        if (what == ACT_BUY) {
            buy(game.factory().bottleneck(game.multipliers()));
            return;
        }
        Haptics.deny();
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
        var here = game.factory();

        dc.setColor(Theme.factoryColor(here.id), Graphics.COLOR_TRANSPARENT);
        dc.drawText(Layout.cx, Layout.s(Balance.NAME_Y), Graphics.FONT_XTINY, here.name(),
            Graphics.TEXT_JUSTIFY_CENTER);

        // MILD rather than MEDIUM: the medium numeric face is over 70px tall
        // on a 416px screen and puts the wallet through the first row.
        Theme.bigCash(dc, Layout.cx, Layout.s(Balance.GOLD_TOP), game.gold, Theme.GOLD,
            Graphics.FONT_NUMBER_MILD);

        if (here.unlocked) {
            drawStages(dc, game, here);
        } else {
            drawLocked(dc, game, here);
        }

        drawIncome(dc, game);
        drawButton(dc, game);
        drawDots(dc, game);
    }

    private function drawStages(dc as Dc, game as GameState, here as Factory) as Void {
        var mult = game.multipliers();
        var choke = here.bottleneck(mult);
        var cap = here.bufferMax(mult);

        for (var s = 0; s < mRowY.size(); s += 1) {
            drawRow(dc, game, here, s, s == choke, mult);
        }

        // The buffer between two stages lives in the gap under the stage that
        // fills it, so a backed-up line reads top to bottom.
        drawBuffer(dc, 0, here.raw, cap, Theme.stageColor(Balance.HARVEST));
        drawBuffer(dc, 1, here.product, cap, Theme.stageColor(Balance.CRAFT));
    }

    private function drawRow(dc as Dc, game as GameState, here as Factory,
                             stage as Number, choke as Boolean,
                             mult as Array<Float>) as Void {
        var x = mRowX[stage];
        var y = mRowY[stage];
        var w = mRowW[stage];
        var cost = here.cost(stage);
        var affordable = here.canBuy(stage) && game.gold >= cost;

        Theme.panel(dc, x, y, w, mRowH, Layout.s(14),
            affordable ? Theme.PANEL_HI : Theme.PANEL,
            choke ? Theme.CHOKE : null);

        drawWorker(dc, here, stage, x + Layout.s(38), y + mRowH / 2, mult);

        var pad = Layout.s(Balance.ROW_TEXT_X);
        dc.setColor(choke ? Theme.CHOKE : Theme.stageColor(stage),
            Graphics.COLOR_TRANSPARENT);
        dc.drawText(x + pad, y + Layout.s(2), Graphics.FONT_TINY,
            (Balance.STAGE_NAME as Array<String>)[stage],
            Graphics.TEXT_JUSTIFY_LEFT);

        dc.setColor(Theme.TEXT_DIM, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x + pad, y + Layout.s(28), Graphics.FONT_XTINY,
            "x" + here.counts[stage].toString() + "  "
            + Fmt.rate(here.stageRate(stage, mult).toDouble()) + "/s",
            Graphics.TEXT_JUSTIFY_LEFT);

        if (!here.canBuy(stage)) {
            dc.setColor(Theme.TEXT_DIM, Graphics.COLOR_TRANSPARENT);
            dc.drawText(x + w - pad, y + mRowH / 2, Graphics.FONT_TINY, "MAX",
                Graphics.TEXT_JUSTIFY_RIGHT | Graphics.TEXT_JUSTIFY_VCENTER);
            return;
        }
        dc.setColor(affordable ? Theme.GOLD : Theme.BAD, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x + w - pad, y + mRowH / 2, Graphics.FONT_TINY, Fmt.cash(cost),
            Graphics.TEXT_JUSTIFY_RIGHT | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    //! The character working this stage, animated at the pace the stage is
    //! actually running: a single machine plods, twenty of them race.
    private function drawWorker(dc as Dc, here as Factory, stage as Number,
                                cx as Number, cy as Number,
                                mult as Array<Float>) as Void {
        var size = Layout.s(Balance.WORKER_SIZE);
        var color = Theme.stageColor(stage);
        var pace = mPhase * workRate(here, stage, mult);

        if (stage == Balance.HARVEST) {
            // The lumber yard is worked with an axe; everywhere else a pick.
            Sprites.harvester(dc, cx, cy, size, pace, color,
                (here.id == Balance.LUMBER) ? 1 : 0);
        } else if (stage == Balance.CRAFT) {
            Sprites.crafter(dc, cx, cy, size, pace, color,
                Theme.factoryColor(here.id));
        } else {
            Sprites.trader(dc, cx, cy, size, pace, color, Theme.GOLD);
        }
    }

    //! Turns per second for a stage's animation. It follows the stage's real
    //! throughput but flattens out, because past a certain speed more frames
    //! of the same swing read as noise rather than as more work.
    private function workRate(here as Factory, stage as Number,
                              mult as Array<Float>) as Float {
        var rate = here.stageFlow(stage, mult) * Balance.ANIM_PER_UNIT;
        if (rate > Balance.ANIM_MAX) {
            rate = Balance.ANIM_MAX;
        }
        return Balance.ANIM_MIN + rate;
    }

    private function drawBuffer(dc as Dc, above as Number, held as Float,
                                cap as Float, color as Number) as Void {
        var y = mRowY[above] + mRowH + Layout.s(Balance.BAR_DROP);
        var h = Layout.s(Balance.BAR_H);
        var x = mRowX[above] + Layout.s(24);
        var w = mRowW[above] - Layout.s(48);
        var full = (cap > 0.0) ? held / cap : 0.0;
        // A buffer at the ceiling is output going in the bin, so it stops
        // wearing its own colour and starts wearing the warning one.
        Theme.bar(dc, x, y, w, h, full, (full >= 0.995) ? Theme.CHOKE : color,
            Theme.PANEL);
    }

    //! An unbuilt factory gets the works itself, dark and cold, with what it
    //! would turn out sitting beside it - so the price on the button is
    //! attached to a picture of what it buys.
    private function drawLocked(dc as Dc, game as GameState, here as Factory) as Void {
        var y = mRowY[0];
        // The works stands cold and unlit, with what it would turn out beside
        // it in the factory's own colour: the only lit thing on the card is
        // the thing the price buys.
        Sprites.works(dc, Layout.cx - Layout.s(26), y + Layout.s(40),
            Layout.s(120), Theme.TEXT_DIM, null, 0.0);
        Sprites.resource(dc, Layout.cx + Layout.s(78), y + Layout.s(52),
            Layout.s(52), here.id, Theme.factoryColor(here.id));

        var textY = y + Layout.s(92);
        dc.setColor(Theme.TEXT, Graphics.COLOR_TRANSPARENT);
        dc.drawText(Layout.cx, textY, Graphics.FONT_SMALL, "NOT BUILT",
            Graphics.TEXT_JUSTIFY_CENTER);

        dc.setColor(Theme.TEXT_DIM, Graphics.COLOR_TRANSPARENT);
        dc.drawText(Layout.cx, textY + Layout.s(36), Graphics.FONT_XTINY,
            here.rawName() + " into " + here.productName() + ", "
            + Fmt.cash(here.value().toDouble()) + " each",
            Graphics.TEXT_JUSTIFY_CENTER);
    }

    //! What the whole operation makes per minute, hands off. It sits under
    //! the rows rather than beside the wallet because it is the number the
    //! player is trying to grow, not the one they are spending.
    private function drawIncome(dc as Dc, game as GameState) as Void {
        dc.setColor(Theme.GOLD_DIM, Graphics.COLOR_TRANSPARENT);
        dc.drawText(Layout.cx, Layout.s(Balance.INCOME_Y), Graphics.FONT_XTINY,
            "+" + Fmt.cash(game.incomePerSecond() * 60.0d) + "/min",
            Graphics.TEXT_JUSTIFY_CENTER);
    }

    private function drawButton(dc as Dc, game as GameState) as Void {
        var here = game.factory();
        var what = action();
        var label = "NOTHING TO BUY";
        var cost = 0.0d;

        if (what == ACT_UNLOCK) {
            cost = here.unlockCost();
            label = "BUILD " + Fmt.cash(cost);
        } else if (what == ACT_BUY) {
            var stage = here.bottleneck(game.multipliers());
            cost = here.cost(stage);
            label = (Balance.STAGE_NAME as Array<String>)[stage] + " "
                + Fmt.cash(cost);
        }

        var live = (what != ACT_NONE) && game.gold >= cost;
        Theme.button(dc, mBtnX, mBtnY, mBtnW, mBtnH, label,
            live ? Theme.GOLD_DIM : Theme.PANEL,
            live ? Theme.TEXT : Theme.TEXT_DIM);
    }

    private function drawDots(dc as Dc, game as GameState) as Void {
        var spacing = Layout.s(18);
        var y = Layout.s(Balance.DOTS_Y);
        var left = Layout.cx - spacing * (Balance.FACTORY_COUNT - 1) / 2;
        for (var f = 0; f < Balance.FACTORY_COUNT; f += 1) {
            var color = Theme.PANEL_HI;
            if (f == game.current) {
                color = Theme.factoryColor(f);
            } else if (game.factories[f].unlocked) {
                color = Theme.GOLD_DIM;
            }
            dc.setColor(color, Graphics.COLOR_TRANSPARENT);
            dc.fillCircle(left + f * spacing, y, Layout.s(4));
        }
    }
}
