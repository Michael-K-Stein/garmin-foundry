#!/usr/bin/env python3
"""Check the board against the round screen it has to live on.

The layout in Balance.mc is authored as bare numbers in a 416x416 design
space, which is easy to nudge and easy to break: a row that runs past the
bezel, or one that slides under the contextual button, only shows up on a
watch. This reads the constants back out of the source and asserts the things
a round touchscreen needs to be true.

Every factory shares one set of rows, so one pass covers the whole game.
"""
import math
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
BALANCE = ROOT / "source" / "Balance.mc"

DESIGN = 416
CENTRE = DESIGN / 2
# A row is a tap target the thumb has to hit without looking.
MIN_ROW_H = 56
MIN_ROW_W = 200
# The buffer bar drawn in the gap under a row must not touch the next one.
MIN_GAP = 2
# Rows must clear both text lines that share the screen with them.


def constants(text):
    """Every `const NAME = ...;` in Balance.mc, as raw source strings."""
    return dict(re.findall(r"const\s+(\w+)\s*=\s*([^;]+);", text))


def numbers(raw):
    return [int(n) for n in re.findall(r"-?\d+", raw)]


def chord_half(y):
    """Half the width of the glass at a distance |y - centre| from the middle."""
    dy = abs(y - CENTRE)
    if dy >= CENTRE:
        return 0.0
    return math.sqrt(CENTRE ** 2 - dy ** 2)


def row_width(top, height, inset):
    """The widest a row of this height can be at this position, as drawn."""
    return 2 * min(chord_half(top), chord_half(top + height)) - 2 * inset


def main():
    text = BALANCE.read_text(encoding="utf-8")
    const = constants(text)

    tops = numbers(const["ROW_TOP"])
    row_h = numbers(const["ROW_H"])[0]
    bar_h = numbers(const["BAR_H"])[0]
    bar_drop = numbers(const["BAR_DROP"])[0]
    inset = numbers(const["ROW_INSET"])[0]
    button_top = numbers(const["BUTTON_TOP"])[0]
    button_h = numbers(const["BUTTON_H"])[0]
    dots_y = numbers(const["DOTS_Y"])[0]
    gold_bottom = numbers(const["GOLD_TOP"])[0] + numbers(const["GOLD_H"])[0]
    income_y = numbers(const["INCOME_Y"])[0]
    income_h = numbers(const["INCOME_H"])[0]
    stages = numbers(const["STAGE_COUNT"])[0]
    factories = numbers(const["FACTORY_COUNT"])[0]

    errors = []

    if len(tops) != stages:
        errors.append(
            "ROW_TOP has %d entries but there are %d stages" % (len(tops), stages)
        )

    if row_h < MIN_ROW_H:
        errors.append("rows are %dpx tall; a thumb wants at least %d"
                      % (row_h, MIN_ROW_H))

    for i, top in enumerate(tops):
        width = row_width(top, row_h, inset)
        if width < MIN_ROW_W:
            errors.append(
                "row %d at y=%d is only %.0fpx wide inside the bezel; wanted %d"
                % (i, top, width, MIN_ROW_W)
            )
        if top < gold_bottom:
            errors.append(
                "row %d starts at y=%d, under the wallet which ends at y=%d"
                % (i, top, gold_bottom)
            )
        if top + row_h > income_y:
            errors.append(
                "row %d ends at y=%d, over the income line at y=%d"
                % (i, top + row_h, income_y)
            )

    # Rows must not overlap each other, and the buffer bar drawn in each gap
    # has to fit in the gap it is drawn in.
    for i in range(len(tops) - 1):
        gap = tops[i + 1] - (tops[i] + row_h)
        if gap < MIN_GAP:
            errors.append("rows %d and %d are %dpx apart; they will touch"
                          % (i, i + 1, gap))
        elif gap < bar_drop + bar_h:
            errors.append(
                "the buffer bar under row %d needs %dpx but the gap is %dpx"
                % (i, bar_drop + bar_h, gap)
            )

    if income_y + income_h > button_top:
        errors.append(
            "the income line ends at y=%d, under the button at y=%d"
            % (income_y + income_h, button_top)
        )

    # The button and the factory dots have to fit the chords they sit on.
    button_w = row_width(button_top, button_h, 8)
    if button_w < 180:
        errors.append("the contextual button is only %.0fpx wide at y=%d; move it up"
                      % (button_w, button_top))

    dots_w = 18 * (factories - 1) + 8
    if dots_w > 2 * chord_half(dots_y):
        errors.append(
            "%d factory dots need %dpx but the glass is %.0fpx wide at y=%d"
            % (factories, dots_w, 2 * chord_half(dots_y), dots_y)
        )
    if dots_y < button_top + button_h:
        errors.append("the factory dots at y=%d sit under the button" % dots_y)

    if errors:
        for line in errors:
            print("layout: " + line, file=sys.stderr)
        return 1

    print("layout: %d rows fit the glass, button is %.0fpx wide, %d dots fit under it"
          % (len(tops), button_w, factories))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
