#!/usr/bin/env python3
"""Play Foundry on paper and check the progression curve is sane.

An idle game lives on its pacing, and pacing is the one thing you cannot see
by reading a constant. This reads the balance table straight out of Balance.mc,
plays a greedy buyer through it - always buy whatever adds the most income per
gold spent - and reports how long each factory takes to reach and when the
first rebuild pays out.

It fails the build if the curve collapses: a factory that opens in seconds is
as broken as one that never opens at all.

Storage is deliberately left out of the buyer's options. It raises no
throughput at all - it buys buffer headroom and unattended hours - so a buyer
that only values gold per second would never touch it, and pretending
otherwise here would hide a real balance problem behind a fake one.
"""
import math
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
BALANCE = ROOT / "source" / "Balance.mc"

# What "sane" means, in minutes of wall-clock play with the app open.
MIN_MINUTES = 2
MAX_MINUTES = 900
HORIZON_SECS = MAX_MINUTES * 60


def constants(text):
    return dict(re.findall(r"const\s+(\w+)\s*=\s*([^;]+);", text))


def floats(raw):
    return [float(n) for n in re.findall(r"-?\d+(?:\.\d+)?(?:[eE][-+]?\d+)?", raw)]


class Sim:
    """The same arithmetic the Monkey C does, in the same order."""

    STAGES = 3

    def __init__(self, c):
        self.c = c
        self.factories = int(c["FACTORY_COUNT"])
        self.gold = 0.0
        self.run = 0.0
        self.unlocked = [f == 0 for f in range(self.factories)]
        self.counts = [[0, 0, 0] for _ in range(self.factories)]
        self.counts[0] = [int(c["MACHINE_START"])] * self.STAGES
        self.levels = [0, 0, 0]

    # --- stats ----------------------------------------------------------
    def mult(self, stage):
        return 1.0 + self.c["UPG_STEP"][stage] * self.levels[stage]

    def base_rate(self, factory, stage):
        table = ("HARVEST_RATE", "CRAFT_RATE", "SELL_RATE")[stage]
        return self.c[table][factory]

    def stage_flow(self, factory, stage, counts=None):
        """A stage's speed in finished products per second."""
        owned = (counts or self.counts[factory])[stage]
        rate = owned * self.base_rate(factory, stage) * self.mult(stage)
        if stage == 0:
            return rate / self.c["CRAFT_INPUT"]
        return rate

    def throughput(self, factory, counts=None):
        return min(self.stage_flow(factory, s, counts) for s in range(self.STAGES))

    def income(self):
        total = 0.0
        for f in range(self.factories):
            if self.unlocked[f]:
                total += self.throughput(f) * self.c["PRODUCT_VALUE"][f]
        return total

    # --- prices ---------------------------------------------------------
    def machine_cost(self, factory, stage):
        base = self.c["MACHINE_COST"][factory * self.STAGES + stage]
        return base * self.c["COST_GROWTH"] ** self.counts[factory][stage]

    def upgrade_cost(self, index):
        return self.c["UPG_COST"][index] * self.c["UPG_GROWTH"] ** self.levels[index]

    # --- the greedy buyer ----------------------------------------------
    def options(self):
        """Every purchase available now, as (gain_per_gold, cost, apply)."""
        out = []
        before = self.income()

        for f in range(self.factories):
            if not self.unlocked[f]:
                break  # factories open in order; a later one is not on offer

            for s in range(self.STAGES):
                if self.counts[f][s] >= self.c["MACHINE_MAX"]:
                    continue
                counts = list(self.counts[f])
                counts[s] += 1
                gain = ((self.throughput(f, counts) - self.throughput(f))
                        * self.c["PRODUCT_VALUE"][f])
                if gain <= 0.0:
                    continue
                cost = self.machine_cost(f, s)
                out.append((gain / cost, cost, ("machine", f, s)))

        for i in range(self.STAGES):
            self.levels[i] += 1
            gain = self.income() - before
            self.levels[i] -= 1
            if gain <= 0.0:
                continue
            cost = self.upgrade_cost(i)
            out.append((gain / cost, cost, ("upgrade", i, 0)))

        return out

    def apply(self, what):
        kind, a, b = what
        if kind == "unlock":
            self.unlocked[a] = True
            self.counts[a] = [int(self.c["MACHINE_START"])] * self.STAGES
        elif kind == "machine":
            self.counts[a][b] += 1
        else:
            self.levels[a] += 1

    def next_locked(self):
        for f in range(self.factories):
            if not self.unlocked[f]:
                return f
        return None

    def buy_what_we_can(self):
        """Keep buying the best value purchase we can afford.

        Opening the next factory is not put through the value comparison. A
        new factory is worth an order of magnitude more per product than the
        one before it, and no player who can afford one waits - so the buyer
        does not either, and what the sim then measures is the thing that
        actually matters: how long it takes to afford the next unlock.
        """
        while True:
            locked = self.next_locked()
            if locked is not None and self.gold >= self.c["UNLOCK_COST"][locked]:
                self.gold -= self.c["UNLOCK_COST"][locked]
                self.apply(("unlock", locked, 0))
                continue
            best = None
            for value, cost, what in self.options():
                if cost <= self.gold and (best is None or value > best[0]):
                    best = (value, cost, what)
            if best is None:
                return
            self.gold -= best[1]
            self.apply(best[2])


def load_constants():
    text = BALANCE.read_text(encoding="utf-8")
    raw = constants(text)
    scalars = ["CRAFT_INPUT", "COST_GROWTH", "MACHINE_MAX", "MACHINE_START",
               "UPG_GROWTH", "FACTORY_COUNT", "PRESTIGE_MIN", "PRESTIGE_SCALE",
               "BLUEPRINT_STEP", "BUFFER_STEP"]
    tables = ["PRODUCT_VALUE", "UNLOCK_COST", "HARVEST_RATE", "CRAFT_RATE",
              "SELL_RATE", "MACHINE_COST", "UPG_COST"]
    c = {}
    for name in scalars:
        c[name] = floats(raw[name])[0]
    for name in tables:
        c[name] = floats(raw[name])
    # UPG_STEP's last entry is written as the BUFFER_STEP constant, so it is
    # read back by name rather than as a literal.
    c["UPG_STEP"] = floats(raw["UPG_STEP"]) + [c["BUFFER_STEP"]]
    return c


def main():
    c = load_constants()
    sim = Sim(c)

    opened = {0: 0}
    rebuild_at = None

    for second in range(1, HORIZON_SECS + 1):
        earned = sim.income()
        sim.gold += earned
        sim.run += earned
        sim.buy_what_we_can()

        for f in range(sim.factories):
            if sim.unlocked[f] and f not in opened:
                opened[f] = second
        if rebuild_at is None and sim.run >= c["PRESTIGE_MIN"]:
            rebuild_at = second
        if len(opened) == sim.factories and rebuild_at is not None:
            break

    errors = []
    names = re.findall(r'"([^"]+)"', constants(BALANCE.read_text(encoding="utf-8"))
                       ["FACTORY_NAME"])

    print("factory          opens at   machines at open")
    last = -1
    for f in range(sim.factories):
        when = opened.get(f)
        if when is None:
            errors.append("%s never opens inside %d minutes"
                          % (names[f], MAX_MINUTES))
            print("  %-14s never" % names[f])
            continue
        print("  %-14s %6.1f min   %s"
              % (names[f], when / 60.0, sim.counts[f]))
        if when <= last:
            errors.append("%s opens before the factory ahead of it" % names[f])
        last = when
        if f > 0 and when / 60.0 < MIN_MINUTES:
            errors.append("%s opens after only %.1f minutes; the curve collapsed"
                          % (names[f], when / 60.0))

    if rebuild_at is None:
        errors.append("a rebuild never becomes available inside %d minutes"
                      % MAX_MINUTES)
    else:
        blueprints = int(math.sqrt(sim.run / c["PRESTIGE_SCALE"]))
        print("first rebuild    %6.1f min   +%d blueprints (x%.2f)"
              % (rebuild_at / 60.0, blueprints,
                 1.0 + c["BLUEPRINT_STEP"] * blueprints))
        if blueprints < 1:
            errors.append("the first rebuild pays no blueprints")

    if errors:
        for line in errors:
            print("economy: " + line, file=sys.stderr)
        return 1

    print("economy: %d factories open in order, first rebuild at %.0f min"
          % (sim.factories, rebuild_at / 60.0))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
