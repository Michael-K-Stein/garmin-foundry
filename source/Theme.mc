import Toybox.Graphics;
import Toybox.Lang;

//! Colours and the handful of shared drawing primitives. The palette is dark
//! on purpose: the Venu 2 is AMOLED, so black pixels cost no battery.
module Theme {

    const BG = 0x000000;
    const PANEL = 0x141416;
    const PANEL_HI = 0x22242A;
    const GOLD = 0xFFC61E;
    const GOLD_DIM = 0x7A5E10;
    const TEXT = 0xFFFFFF;
    const TEXT_DIM = 0x8A8F98;
    const BAD = 0xE04030;
    //! The stage that is holding the line back wears this, everywhere.
    const CHOKE = 0xFF7A3A;

    //! One colour per stage: what comes out of the ground, what is made of
    //! it, and the money it turns into.
    const STAGE_COLOR = [0x8C6A4A, 0x4FC3E8, 0x2ED573];

    //! One colour per factory, so a glance says which line is on screen.
    const FACTORY_COLOR = [0x2E9B4B, 0x9AA3AA, 0xC94A2A, 0x8C6ACC, 0x3AC7C7];

    const GAP = 3;

    function stageColor(stage as Number) as Number {
        return (STAGE_COLOR as Array<Number>)[stage];
    }

    function factoryColor(factory as Number) as Number {
        return (FACTORY_COLOR as Array<Number>)[factory];
    }

    //! Filled panel with a lighter edge, the basic surface of every screen.
    function panel(dc as Dc, x as Number, y as Number, w as Number, h as Number,
                   radius as Number, fill as Number, edge as Number or Null) as Void {
        dc.setColor(fill, Graphics.COLOR_TRANSPARENT);
        dc.fillRoundedRectangle(x, y, w, h, radius);
        if (edge != null) {
            dc.setColor(edge, Graphics.COLOR_TRANSPARENT);
            dc.setPenWidth(2);
            dc.drawRoundedRectangle(x, y, w, h, radius);
            dc.setPenWidth(1);
        }
    }

    //! A pill-shaped button; hit testing lives with the view that placed it.
    function button(dc as Dc, x as Number, y as Number, w as Number, h as Number,
                    label as String, fill as Number, textColor as Number) as Void {
        dc.setColor(fill, Graphics.COLOR_TRANSPARENT);
        dc.fillRoundedRectangle(x, y, w, h, h / 2);
        dc.setColor(textColor, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x + w / 2, y + h / 2, Graphics.FONT_TINY, label,
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    //! Horizontal fill bar, progress 0..1.
    function bar(dc as Dc, x as Number, y as Number, w as Number, h as Number,
                 progress as Float, fill as Number, back as Number) as Void {
        dc.setColor(back, Graphics.COLOR_TRANSPARENT);
        dc.fillRoundedRectangle(x, y, w, h, h / 2);
        var p = progress;
        if (p < 0.0) {
            p = 0.0;
        }
        if (p > 1.0) {
            p = 1.0;
        }
        var filled = (w * p).toNumber();
        if (filled > 0) {
            dc.setColor(fill, Graphics.COLOR_TRANSPARENT);
            dc.fillRoundedRectangle(x, y, filled, h, h / 2);
        }
    }

    //! Large money figure centred at (x, y): the digits in a numeric face,
    //! with the dollar sign and any magnitude suffix beside them in a text
    //! font, all three sharing a baseline.
    //!
    //! They are drawn separately because Garmin's FONT_NUMBER_* faces carry
    //! digits only - a '$' or a 'K' drawn in one comes out as an empty box.
    function bigCash(dc as Dc, x as Number, y as Number, value as Double,
                     color as Number, numberFont as FontType) as Void {
        var p = Fmt.parts(value);
        var sideFont = Graphics.FONT_SMALL;
        var drop = baseline(dc, numberFont) - baseline(dc, sideFont);

        var digits = p[0];
        var suffix = p[1];
        var digitsW = dc.getTextWidthInPixels(digits, numberFont);
        var signW = dc.getTextWidthInPixels("$", sideFont);
        var suffixW = suffix.equals("") ? 0 : dc.getTextWidthInPixels(suffix, sideFont);

        var total = signW + GAP + digitsW;
        if (suffixW > 0) {
            total += GAP + suffixW;
        }
        var left = x - total / 2;

        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.drawText(left, y + drop, sideFont, "$", Graphics.TEXT_JUSTIFY_LEFT);
        dc.drawText(left + signW + GAP, y, numberFont, digits, Graphics.TEXT_JUSTIFY_LEFT);
        if (suffixW > 0) {
            dc.drawText(left + signW + GAP + digitsW + GAP, y + drop, sideFont, suffix,
                Graphics.TEXT_JUSTIFY_LEFT);
        }
    }

    //! Pixels from the top of a font's line box to its baseline.
    function baseline(dc as Dc, font as FontType) as Number {
        if (Graphics has :getFontAscent) {
            return Graphics.getFontAscent(font);
        }
        return dc.getFontHeight(font);
    }
}
