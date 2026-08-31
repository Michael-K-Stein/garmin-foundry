import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;

//! The people and the machinery.
//!
//! Everything here is drawn from primitives rather than shipped as bitmaps:
//! the same figure has to work at 416px and at 360px, and a handful of
//! circles and polygons scales where a PNG does not. Nothing in this module
//! reads game state - it takes a position, a size, a colour and a phase, so
//! the same worker can be drawn on a row, on a card, or at half size in a
//! corner without any of them knowing about the others.
//!
//! `phase` is a free-running number of turns, 0..1 repeating. Callers scale
//! it by how fast the thing being drawn is actually working, so a line with
//! twenty extractors on it visibly swings harder than one with a single
//! machine.
module Sprites {

    //! sin/cos of a phase in turns, since Math wants radians.
    function wave(phase as Float) as Float {
        return Math.sin(phase * 6.2831853).toFloat();
    }

    // --------------------------------------------------------------- people

    //! A worker with a pick, mid-swing. The whole body leans into the swing
    //! rather than just the arm, because at 40px a moving arm alone reads as
    //! a twitch instead of as work.
    function harvester(dc as Dc, cx as Number, cy as Number, size as Number,
                       phase as Float, color as Number, tool as Number) as Void {
        var swing = wave(phase);
        var unit = size / 10.0;
        var lean = (unit * 1.2 * swing).toNumber();

        var headR = (unit * 1.6).toNumber();
        var top = cy - size / 2;
        var hipY = cy + (unit * 2.0).toNumber();
        var headX = cx + lean;

        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth((unit * 0.9).toNumber() + 1);

        // Head, spine, legs.
        dc.fillCircle(headX, top + headR, headR);
        dc.drawLine(headX, top + headR * 2, cx, hipY);
        dc.drawLine(cx, hipY, cx - (unit * 1.8).toNumber(), cy + size / 2);
        dc.drawLine(cx, hipY, cx + (unit * 1.8).toNumber(), cy + size / 2);

        // The arm and the tool it is holding, swinging together.
        var shoulderX = headX;
        var shoulderY = top + (unit * 4.0).toNumber();
        var handX = cx + (unit * (2.6 + 1.8 * swing)).toNumber();
        var handY = shoulderY + (unit * (2.2 - 1.4 * swing)).toNumber();
        dc.drawLine(shoulderX, shoulderY, handX, handY);

        dc.setPenWidth((unit * 0.8).toNumber() + 1);
        var headTool = tool;
        if (headTool == 0) {
            // A pick: a haft with a crossed head at the far end.
            var tipX = handX + (unit * 2.4).toNumber();
            var tipY = handY - (unit * (2.4 - 1.6 * swing)).toNumber();
            dc.drawLine(handX, handY, tipX, tipY);
            dc.drawLine(tipX - (unit * 1.4).toNumber(), tipY,
                tipX + (unit * 1.0).toNumber(), tipY + (unit * 1.2).toNumber());
        } else {
            // An axe: a haft with a blade wedge on it.
            var bx = handX + (unit * 2.2).toNumber();
            var by = handY - (unit * (2.0 - 1.4 * swing)).toNumber();
            dc.drawLine(handX, handY, bx, by);
            dc.fillPolygon([
                [bx, by - (unit * 1.4).toNumber()],
                [bx + (unit * 1.8).toNumber(), by],
                [bx, by + (unit * 1.4).toNumber()]
            ] as Array<[Numeric, Numeric]>);
        }
        dc.setPenWidth(1);
    }

    //! A worker at a bench, arms working up and down over it, with the cog of
    //! whatever they are assembling turning behind them.
    function crafter(dc as Dc, cx as Number, cy as Number, size as Number,
                     phase as Float, color as Number, accent as Number) as Void {
        var unit = size / 10.0;
        var pump = wave(phase);

        // The machine behind: one cog, turning at the working rate.
        cog(dc, cx + (unit * 3.0).toNumber(), cy - (unit * 1.4).toNumber(),
            (unit * 2.8).toNumber(), 6, phase, accent);

        var headR = (unit * 1.6).toNumber();
        var top = cy - size / 2;
        var benchY = cy + (unit * 2.4).toNumber();

        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth((unit * 0.9).toNumber() + 1);
        dc.fillCircle(cx - (unit * 1.4).toNumber(), top + headR, headR);
        dc.drawLine(cx - (unit * 1.4).toNumber(), top + headR * 2,
            cx - (unit * 1.4).toNumber(), benchY);

        // Both arms reach for the bench, out of step with each other.
        var reach = (unit * (1.4 + 0.8 * pump)).toNumber();
        var shoulderY = top + (unit * 4.0).toNumber();
        dc.drawLine(cx - (unit * 1.4).toNumber(), shoulderY,
            cx + (unit * 0.6).toNumber(), shoulderY + reach);
        dc.drawLine(cx - (unit * 1.4).toNumber(), shoulderY,
            cx - (unit * 3.2).toNumber(), shoulderY + (unit * 2.2).toNumber() - reach);

        // The bench itself.
        dc.setColor(accent, Graphics.COLOR_TRANSPARENT);
        dc.fillRectangle(cx - (unit * 4.0).toNumber(), benchY,
            (unit * 8.0).toNumber(), (unit * 1.2).toNumber() + 1);
        dc.setPenWidth(1);
    }

    //! A trader holding up what they have just sold, with a coin rising off
    //! it. The coin's climb is the phase, so a fast line rains money.
    function trader(dc as Dc, cx as Number, cy as Number, size as Number,
                    phase as Float, color as Number, accent as Number) as Void {
        var unit = size / 10.0;
        var headR = (unit * 1.6).toNumber();
        var top = cy - size / 2;
        var hipY = cy + (unit * 2.0).toNumber();

        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth((unit * 0.9).toNumber() + 1);
        dc.fillCircle(cx, top + headR + (unit * 1.4).toNumber(), headR);
        dc.drawLine(cx, top + headR * 2 + (unit * 1.4).toNumber(), cx, hipY);
        dc.drawLine(cx, hipY, cx - (unit * 1.8).toNumber(), cy + size / 2);
        dc.drawLine(cx, hipY, cx + (unit * 1.8).toNumber(), cy + size / 2);

        // One arm held up, offering.
        var shoulderY = top + (unit * 5.0).toNumber();
        dc.drawLine(cx, shoulderY, cx + (unit * 2.6).toNumber(),
            shoulderY - (unit * 1.8).toNumber());

        // The coin, climbing and shrinking as it goes.
        var climb = phase - phase.toNumber();
        var coinY = shoulderY - (unit * (2.6 + 3.6 * climb)).toNumber();
        var coinR = (unit * (1.6 - 0.7 * climb)).toNumber();
        if (coinR > 0) {
            coin(dc, cx + (unit * 3.0).toNumber(), coinY, coinR, accent);
        }
        dc.setPenWidth(1);
    }

    // ------------------------------------------------------------ machinery

    //! A cog: a filled disc, a ring of teeth around it, and a bore through the
    //! middle. `phase` in turns, so it visibly rotates between frames.
    function cog(dc as Dc, cx as Number, cy as Number, radius as Number,
                 teeth as Number, phase as Float, color as Number) as Void {
        if (radius < 3) {
            return;
        }
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(cx, cy, radius);

        var step = 360.0 / teeth;
        var turn = phase * step;   // one tooth per turn of phase
        var toothR = radius + (radius * 0.45).toNumber() + 1;
        var half = (radius * 0.30) + 1.0;
        for (var i = 0; i < teeth; i += 1) {
            var deg = turn + i * step;
            var rad = deg * 0.0174533;
            var nx = Math.cos(rad).toFloat();
            var ny = Math.sin(rad).toFloat();
            // Each tooth is a stubby quad standing on the rim.
            dc.fillPolygon([
                [cx + (nx * radius - ny * half).toNumber(),
                 cy + (ny * radius + nx * half).toNumber()],
                [cx + (nx * radius + ny * half).toNumber(),
                 cy + (ny * radius - nx * half).toNumber()],
                [cx + (nx * toothR + ny * half * 0.6).toNumber(),
                 cy + (ny * toothR - nx * half * 0.6).toNumber()],
                [cx + (nx * toothR - ny * half * 0.6).toNumber(),
                 cy + (ny * toothR + nx * half * 0.6).toNumber()]
            ] as Array<[Numeric, Numeric]>);
        }

        dc.setColor(Theme.BG, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(cx, cy, (radius * 0.38).toNumber() + 1);
    }

    function coin(dc as Dc, cx as Number, cy as Number, radius as Number,
                  color as Number) as Void {
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(cx, cy, radius);
        if (radius >= 4) {
            dc.setColor(Theme.BG, Graphics.COLOR_TRANSPARENT);
            dc.setPenWidth(1);
            dc.drawLine(cx, cy - radius / 2, cx, cy + radius / 2);
        }
    }

    // ------------------------------------------------------------ the world

    //! What comes out of the ground here, drawn small: a log, a boulder, an
    //! ore chunk, a barrel, a wafer. Used on the locked card so an unbuilt
    //! factory still says what it is for.
    function resource(dc as Dc, cx as Number, cy as Number, size as Number,
                      factory as Number, color as Number) as Void {
        var unit = size / 10.0;
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);

        if (factory == Balance.LUMBER) {
            dc.fillRoundedRectangle(cx - (unit * 4.0).toNumber(),
                cy - (unit * 2.0).toNumber(), (unit * 8.0).toNumber(),
                (unit * 4.0).toNumber(), (unit * 1.6).toNumber());
            dc.setColor(Theme.BG, Graphics.COLOR_TRANSPARENT);
            dc.drawCircle(cx - (unit * 2.6).toNumber(), cy, (unit * 1.2).toNumber());
            return;
        }
        if (factory == Balance.STONE) {
            dc.fillPolygon([
                [cx - (unit * 4.0).toNumber(), cy + (unit * 2.6).toNumber()],
                [cx - (unit * 2.4).toNumber(), cy - (unit * 2.6).toNumber()],
                [cx + (unit * 2.6).toNumber(), cy - (unit * 2.0).toNumber()],
                [cx + (unit * 4.0).toNumber(), cy + (unit * 2.6).toNumber()]
            ] as Array<[Numeric, Numeric]>);
            return;
        }
        if (factory == Balance.IRON) {
            dc.fillPolygon([
                [cx - (unit * 3.6).toNumber(), cy + (unit * 2.4).toNumber()],
                [cx - (unit * 1.6).toNumber(), cy - (unit * 2.8).toNumber()],
                [cx + (unit * 3.6).toNumber(), cy - (unit * 0.6).toNumber()],
                [cx + (unit * 1.4).toNumber(), cy + (unit * 2.8).toNumber()]
            ] as Array<[Numeric, Numeric]>);
            dc.setColor(Theme.BG, Graphics.COLOR_TRANSPARENT);
            dc.fillCircle(cx, cy - (unit * 0.4).toNumber(), (unit * 0.8).toNumber());
            return;
        }
        if (factory == Balance.OIL) {
            // A barrel: a body with two hoops.
            dc.fillRoundedRectangle(cx - (unit * 2.8).toNumber(),
                cy - (unit * 3.2).toNumber(), (unit * 5.6).toNumber(),
                (unit * 6.4).toNumber(), (unit * 1.2).toNumber());
            dc.setColor(Theme.BG, Graphics.COLOR_TRANSPARENT);
            dc.setPenWidth((unit * 0.6).toNumber() + 1);
            dc.drawLine(cx - (unit * 2.8).toNumber(), cy - (unit * 1.0).toNumber(),
                cx + (unit * 2.8).toNumber(), cy - (unit * 1.0).toNumber());
            dc.drawLine(cx - (unit * 2.8).toNumber(), cy + (unit * 1.2).toNumber(),
                cx + (unit * 2.8).toNumber(), cy + (unit * 1.2).toNumber());
            dc.setPenWidth(1);
            return;
        }
        // A wafer: a square die with legs down two sides.
        dc.fillRectangle(cx - (unit * 2.6).toNumber(), cy - (unit * 2.6).toNumber(),
            (unit * 5.2).toNumber(), (unit * 5.2).toNumber());
        dc.setPenWidth((unit * 0.6).toNumber() + 1);
        for (var i = -1; i <= 1; i += 1) {
            var y = cy + (unit * 1.6 * i).toNumber();
            dc.drawLine(cx - (unit * 4.4).toNumber(), y,
                cx - (unit * 2.6).toNumber(), y);
            dc.drawLine(cx + (unit * 2.6).toNumber(), y,
                cx + (unit * 4.4).toNumber(), y);
        }
        dc.setPenWidth(1);
    }

    //! A works with a chimney, for the card shown over a factory that has not
    //! been built. The smoke is drawn only when it is running.
    function works(dc as Dc, cx as Number, cy as Number, size as Number,
                   color as Number, smoke as Number or Null,
                   phase as Float) as Void {
        var unit = size / 10.0;
        var baseY = cy + (unit * 3.4).toNumber();
        var roofY = cy - (unit * 0.6).toNumber();

        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        // Two sheds and a chimney.
        dc.fillRectangle(cx - (unit * 5.0).toNumber(), roofY,
            (unit * 4.4).toNumber(), baseY - roofY);
        dc.fillRectangle(cx - (unit * 0.2).toNumber(),
            roofY + (unit * 1.2).toNumber(), (unit * 5.2).toNumber(),
            baseY - roofY - (unit * 1.2).toNumber());
        dc.fillRectangle(cx - (unit * 4.2).toNumber(),
            cy - (unit * 4.6).toNumber(), (unit * 1.6).toNumber(),
            (unit * 4.0).toNumber());

        if (smoke == null) {
            return;
        }
        // Three puffs climbing out of the chimney on the phase.
        dc.setColor(smoke, Graphics.COLOR_TRANSPARENT);
        var climb = phase - phase.toNumber();
        for (var i = 0; i < 3; i += 1) {
            var t = climb + i * 0.33;
            if (t > 1.0) {
                t -= 1.0;
            }
            var puffY = cy - (unit * (5.0 + 4.0 * t)).toNumber();
            var puffR = (unit * (0.7 + 0.9 * t)).toNumber();
            if (puffR > 0) {
                dc.fillCircle(cx - (unit * 3.4).toNumber()
                    + (unit * 1.4 * t).toNumber(), puffY, puffR);
            }
        }
    }
}
