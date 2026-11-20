# ---------------------------------------------------------------------------------------------------
# Copyright (c) 2026 by Julian Schneider
# Authors: Julian Schneider
# ---------------------------------------------------------------------------------------------------
"""VUnit configurations of isp_replace_tb (verification plan, sections 2 and 3).

For every configuration and test, the image stream, the register script (defect map and register checks) and the
injection script are built here, the reference model (tools/isp_model.py) computes the expected output pixels, the
pulse counts and the expected register reads, and the files are written to the vector directory. Every test that
depends on the defect map clears it or writes it completely first, instead of relying on the initial content of the
RAM.
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[3] / "tools"))

from isp_model import (RPL_CTRL, RPL_ID, RPL_IMAGE, RPL_MAP_ADDR, RPL_MAP_DATA, RPL_MAP_LINE,  # noqa: E402
                       RPL_MAP_WORDS, RPL_PARAM, RPL_STATUS, SEQ_CONT, SEQ_LAST, ecc_codeword_width,
                       ecc_data_positions, replace, replace_pixel)
from isp_tbgen import (RegScript, check, image_beats, malformed_streams, open_image, packets,  # noqa: E402
                       random_image, raw_packet, rng_for, seed_for, status, watchdog_us, write, write_test)

MODULE = "isp_replace"
SWEEP_STEPS = 12
ALL = ["test_static", "test_input_stream", "test_map_update", "test_ecc", "test_scrub", "test_registers",
       "test_reset"]
CW = ecc_codeword_width(32)
POS = ecc_data_positions(32)
HAMMING = [1 << k for k in range(CW.bit_length()) if 0 < (1 << k) < CW]


def cfg(name, w, h, bits, g, lat=1, ecc=0, gap=20, stall=20, tests=None, clk=150000000, period=0):
    return dict(name=name, w=w, h=h, bits=bits, g=g, lat=lat, ecc=ecc, gap=gap, stall=stall, tests=tests or ALL,
                clk=clk, period=period)


CONFIGS = [
    cfg("g2", 40, 6, 12, 2),
    # The flag sweeps need a stream without gaps and stalls, so that the pulse moves by one cycle per step
    cfg("flags", 40, 6, 12, 2, gap=0, stall=0, tests=["test_flag_coincidence"]),
    cfg("g1_min", 3, 5, 8, 1, 3, 2, 30, 40),
    cfg("w33", 33, 6, 12, 1, 3, 2, 0, 0),
    cfg("g7", 15, 4, 12, 7, 2, 1),
    cfg("g7_wide", 100, 4, 24, 7, 1, 1),
    cfg("w64", 64, 3, 12, 3, 1, 2),
    cfg("bits1", 10, 3, 1, 2),
    cfg("one_word", 20, 1, 12, 2),
    cfg("clear", 64, 40, 12, 2, gap=0, stall=0, tests=["test_clear", "test_static"]),
    cfg("w65536", 65536, 2, 12, 2, gap=10, stall=10, tests=["test_static"]),
    cfg("h65536", 5, 65536, 12, 2, gap=10, stall=10, tests=["test_static"]),
    cfg("exhaustive", 120, 256, 4, 7, gap=0, stall=0, tests=["test_exhaustive"]),
    # Every pair of 6-bit values: at this width the division with one bit less of K fails for d = 13
    cfg("exhaustive_p6", 120, 4096, 6, 7, gap=0, stall=0, tests=["test_exhaustive"]),
    # The pacer of the scrubber counts milliseconds of ClkFreqHz_g: with 1000 Hz one millisecond is one clock cycle
    cfg("scrub_period", 40, 6, 12, 2, gap=0, stall=0, tests=["test_scrub"], clk=1000, period=300),
    cfg("scrub_overrun", 40, 6, 12, 2, gap=0, stall=0, tests=["test_scrub"], clk=1000, period=5),
    cfg("rate_g2", 40, 6, 12, 2, gap=0, stall=0, tests=["test_rate"]),
    cfg("rate_g7", 15, 6, 12, 7, 2, 1, gap=0, stall=0, tests=["test_rate"]),
    cfg("rate_w33", 33, 6, 12, 1, 3, 2, gap=0, stall=0, tests=["test_rate"]),
    # The module at the defaults of its entity (DutDefaults_g): G 2, RamRdLatency_g 2, EccPipeline_g 1, the scrubber
    # free running; the timing of test_rate shows the read path of the map (line 0 holds 5 cycles, the period
    # H x (W + G) + 3)
    cfg("defaults", 40, 6, 12, 2, 2, 1, tests=["test_static", "test_registers", "test_ecc", "test_reset"]),
    cfg("defaults_rate", 40, 6, 12, 2, 2, 1, gap=0, stall=0, tests=["test_rate"]),
]
# Sweeps: every G, every read latency of the map with the shortest word
CONFIGS += [cfg("gap_{}".format(g), 4 * g + 5, 6, 10, g, tests=["test_static"]) for g in range(1, 8)]
CONFIGS += [cfg("lat_{}_{}".format(lat, ecc), 33, 4, 12, 1, lat, ecc, tests=["test_static"])
            for lat in range(1, 4) for ecc in range(3)]

BIG = ("w65536", "h65536")


class Ctx:
    def __init__(self, c):
        self.c = c
        self.w, self.h, self.bits, self.g = c["w"], c["h"], c["bits"], c["g"]
        self.wl = -(-self.w // 32)
        self.words = self.h * self.wl
        self.map = [0] * self.words
        self.regs = RegScript()

    # Stream
    def image(self, rng, mode="lines"):
        return image_beats(rng, self.w, self.h, self.bits, mode)

    # Register and injection script entries, after every pixel sent so far has passed the module
    def marker(self, kind, value):
        return [("W",), ("T", 8), (kind, next(self.regs.markers), value)]

    def inject(self, pattern):
        return self.marker("J", pattern)

    def scrub(self, enable):
        return self.marker("S", enable)

    def clear(self):
        """CTRL.CLEAR and a pause for the whole clear."""
        self.map = [0] * self.words
        return self.regs.access(write(RPL_CTRL, 1)) + [("T", self.words + 16)]

    # Defect maps
    def rand_marks(self, rng):
        """Marks of one line: isolated defects, a group of 2 to 2 x G, a longer group, groups at the borders; one
        line in ten has no operational pixel."""
        w, g = self.w, self.g
        if rng.random() < 0.1:
            return [1] * w
        m = [0] * w
        for _ in range(max(1, w // 16)):
            m[rng.randrange(w)] = 1
        n = min(rng.randint(2, 2 * g), w)
        s = rng.randint(0, w - n)
        m[s:s + n] = [1] * n
        n = rng.randint(2 * g + 1, 2 * g + 3)
        if n <= w and rng.random() < 0.7:
            s = rng.randint(0, w - n)
            m[s:s + n] = [1] * n
        if rng.random() < 0.5:
            n = rng.randint(1, g + 1)
            m[:n] = [1] * n
        if rng.random() < 0.5:
            n = rng.randint(1, g + 1)
            m[w - n:] = [1] * n
        return m

    def words_of(self, rng, marks):
        """Words of the map from the marks of every line; the bits beyond the last pixel of a line are random,
        because they have no meaning."""
        out = []
        for line in marks:
            for j in range(self.wl):
                v = 0
                for b in range(32):
                    x = 32 * j + b
                    bit = line[x] if x < self.w else rng.getrandbits(1)
                    v |= bit << b
                out.append(v)
        return out

    def write_words(self, start, values):
        for k, v in enumerate(values):
            self.map[start + k] = v
        return [write(RPL_MAP_ADDR, start)] + [write(RPL_MAP_DATA, v) for v in values]

    def unreplaced(self, xo, y):
        """Pixel (xo, y) is not operational and has no operational pixel within G, with the map as written."""
        flags = [not (self.map[y * self.wl + x // 32] >> (x % 32) & 1) for x in range(self.w)]
        return replace_pixel([0] * self.w, flags, xo, self.g)[1]

    def write_map(self, rng):
        """A random map, written word by word with the counting MAP_ADDR."""
        values = self.words_of(rng, [self.rand_marks(rng) for _ in range(self.h)])
        return self.regs.access(*self.write_words(0, values))

    def write_sparse(self, rng, count=64):
        """Random words of the map, each with its own MAP_ADDR (the large configurations)."""
        entries = []
        for k in sorted(rng.sample(range(self.words), min(count, self.words))):
            entries += self.write_words(k, [rng.getrandbits(32)])
        return self.regs.access(*entries)


def build_static(rng, x):
    # The map cleared first; the first image passes unchanged
    items = x.clear() + x.image(rng)
    big = x.c["name"] in BIG
    for _ in range(1 if big else 3):
        items += x.write_sparse(rng) if big else x.write_map(rng)
        for mode in ("lines", "random") if big else ("lines", "one", "random", "lines", "random"):
            items += x.image(rng, mode)
    return items + status()


def build_input_stream(rng, x):
    return x.clear() + x.write_map(rng) + malformed_streams(rng, x.w, x.h, x.bits)


def build_map_update(rng, x):
    w, h, words = x.w, x.h, x.words
    items = x.clear() + x.write_map(rng) + x.image(rng)
    # Between two images: words 0, 1, 2 and the last word; the next image uses them all
    first = [rng.getrandbits(32) for _ in range(min(3, words))]
    items += x.regs.access(*x.write_words(0, first), *x.write_words(words - 1, [rng.getrandbits(32)]),
                           check(RPL_MAP_ADDR))
    items += x.image(rng)
    # During an image: after pixel n, the words from the third after the word of pixel n on
    for _ in range(3):
        n = rng.randrange(w * h - 1)
        k = (n // w) * x.wl + (n % w) // 32
        beats = packets(random_image(rng, w, h, x.bits), [w] * h)
        if k + 3 < words:
            new = [rng.getrandbits(32) for _ in range(words - k - 3)]
            items += beats[:n + 1] + x.regs.access(*x.write_words(k + 3, new)) + beats[n + 1:]
        else:
            items += beats
    # MAP_ADDR outside the map: a write of MAP_DATA changes neither the map nor MAP_ADDR
    for addr in (words, 0xFFFFFFFF):
        items += x.regs.access(write(RPL_MAP_ADDR, addr), write(RPL_MAP_DATA, 0xFFFFFFFF), check(RPL_MAP_ADDR))
        items += x.image(rng)
    return items + status()


def build_clear(rng, x):
    items = x.write_map(rng) + x.image(rng)
    # CTRL.CLEAR: STATUS.BUSY high during the clear; MAP_DATA without effect and MAP_ADDR unchanged by it; a
    # second CTRL.CLEAR does not restart the clear: STATUS.BUSY is low after the first clear ends (the pause places
    # the read between the end of the first clear and the end of a restarted one)
    x.map = [0] * x.words
    items += x.regs.access(write(RPL_CTRL, 1), check(RPL_STATUS), write(RPL_MAP_ADDR, 5),
                           write(RPL_MAP_DATA, 0xFFFFFFFF), check(RPL_MAP_ADDR), check(RPL_STATUS),
                           write(RPL_CTRL, 1))
    items += [("T", 50)] + x.regs.access(check(RPL_STATUS), check(RPL_MAP_ADDR)) + [("T", x.words)]
    items += x.image(rng)
    # A map written before a reset of the module still applies after it
    items += x.write_map(rng) + x.image(rng) + [("W",), ("T", 4), ("R", 0, 0, 1)] + x.image(rng)
    return items + status()


def build_ecc(rng, x):
    words = x.words
    items = x.scrub(0) + x.clear() + x.write_map(rng) + x.image(rng)
    # Single errors on a data bit, a Hamming parity bit and the overall parity bit of three words: corrected, one
    # Stat_EccSec per image that uses the word
    single = rng.sample(range(words), min(3, words))
    for k, pattern in zip(single, [1 << POS[rng.randrange(32)], rng.choice(HAMMING), 1]):
        items += x.inject(pattern) + x.regs.access(*x.write_words(k, [x.map[k]]))
    items += x.image(rng) + x.image(rng, "random")
    items += x.regs.access(check(RPL_STATUS), write(RPL_STATUS, 0x10000), check(RPL_STATUS))
    # A double error on two data bits, one of them the mark of a pixel of the image: the word is used as read
    k = rng.randrange(words)
    bit = rng.randrange(min(x.w, 32))
    other = rng.choice([b for b in range(32) if b != bit])
    items += x.inject((1 << POS[bit]) | (1 << POS[other])) + x.regs.access(*x.write_words(k, [x.map[k]]))
    items += x.image(rng) + x.image(rng)
    items += x.regs.access(check(RPL_STATUS), write(RPL_STATUS, 0x20000), check(RPL_STATUS))
    # A new write of the words ends the reports
    entries = []
    for j in single + [k]:
        entries += x.write_words(j, [x.map[j]])
    items += x.regs.access(*entries) + x.image(rng)
    # A word read ahead but not used (a reset while word 0 is in use) reports nothing; the next image reports it
    if words >= 3:
        items += x.inject(1 << POS[rng.randrange(32)]) + x.regs.access(*x.write_words(2, [x.map[2]]))
        m = rng.randint(x.g + 1, min(x.w, 32) - 1) if min(x.w, 32) - 1 > x.g + 1 else min(x.w, 32) - 1
        beats = packets(random_image(rng, x.w, x.h, x.bits), [x.w] * x.h)
        items += beats[:m] + [("W",), ("T", 4), ("R", 0, 0, 1)] + x.image(rng)
        # The registered read request (RPL-IF-04): a single error in word 2, which the image reads ahead in its first
        # cycles and uses many pixels later; a reset 0 to 6 cycles after pixel (0, 0), before, in and after the cycles
        # in which the reads of words 0 to 2 are decided and requested, drops the words read ahead: no report for the
        # cut image, one report of word 2 in every following image that uses it
        for k in range(7):
            items += x.inject(1 << POS[rng.randrange(32)]) + x.regs.access(*x.write_words(2, [x.map[2]]))
            pix = random_image(rng, x.w, x.h, x.bits)
            items += packets(pix[:1], [1], last=False) + [("T", k), ("R", 0, 0, 1)] + x.image(rng)
    return items + status()


def build_scrub(rng, x):
    # The scrubber is off from the start of the test (ScrubAtStart_g false)
    words = x.words
    items = x.clear() + x.write_map(rng) + x.image(rng)
    if words >= 3:
        # The double error in the last word, which a pass of the scrubber reads just before Scrub_PassDone; single
        # errors in two of the others
        singles, doubles = rng.sample(range(words - 1), 2), [words - 1]
    elif words == 2:
        singles, doubles = [0], [1]
    else:
        singles, doubles = [0], []
    for k in singles:
        items += x.inject(1 << POS[rng.randrange(32)]) + x.regs.access(*x.write_words(k, [x.map[k]]))
    for k in doubles:
        a, b = rng.sample(range(32), 2)
        items += x.inject((1 << POS[a]) | (1 << POS[b])) + x.regs.access(*x.write_words(k, [x.map[k]]))
    # The scrubber on without images for several passes: it corrects the single errors and reports both
    on = 3000 if x.c["period"] else 64 * max(2, words) + 200
    items += x.scrub(1) + [("T", on)] + x.scrub(0)
    # An image with the scrubber off: no Stat_EccSec, Stat_EccDed for the double error
    items += x.image(rng) + x.regs.access(check(RPL_STATUS))
    if not x.c["period"]:
        # Images with the scrubber running
        items += x.scrub(1) + x.image(rng) + x.image(rng, "random") + x.scrub(0)
    # Scrub_EccSec once per single error (corrected in the first pass); Scrub_EccDed once per pass for the word with
    # the double error, which is never rewritten (verification plan, section 5)
    expect = {"ExpScrubSec_g": len(singles), "ScrubDedWords_g": len(doubles)}
    if x.c["period"] == 300:
        # One pass per period of 300 cycles while the scrubber is on (the pause and the markers around it)
        expect.update({"MinPassDone_g": (on + 10) // 300 - 1, "MaxPassDone_g": (on + 10) // 300 + 1})
    elif x.c["period"]:
        expect.update({"ExpOverrun_g": True})
    else:
        expect.update({"MinPassDone_g": 1})
    return items + status(), expect


def build_registers(rng, x):
    regs = (RPL_ID, RPL_IMAGE, RPL_PARAM, RPL_MAP_LINE, RPL_MAP_WORDS, RPL_CTRL, RPL_STATUS, RPL_MAP_ADDR,
            RPL_MAP_DATA)
    items = x.regs.access(*[check(a) for a in regs])
    items += x.regs.access(*[write(a, 0xFFFFFFFF) for a in (RPL_ID, RPL_IMAGE, RPL_PARAM, RPL_MAP_LINE,
                                                             RPL_MAP_WORDS)], *[check(a) for a in regs[:5]])
    # Byte strobes on MAP_ADDR
    for b in range(4):
        items += x.regs.access(write(RPL_MAP_ADDR, rng.getrandbits(32), 1 << b), check(RPL_MAP_ADDR))
    # A write of MAP_DATA with partial strobes writes all 32 bits: an image shows the marks of every byte
    value = rng.getrandbits(32)
    items += x.clear() + x.regs.access(write(RPL_MAP_ADDR, 0), write(RPL_MAP_DATA, value, 0x1),
                                       check(RPL_MAP_ADDR)) + x.image(rng)
    x.map[0] = value
    # STATUS.IMAGE_OPEN read while an image is open (an image cut after half of its pixels); the next image start
    # completes it (E1)
    items += open_image(x.w, x.h, x.bits) + x.regs.access(check(RPL_STATUS)) + x.image(rng)
    # Unused addresses read 0
    items += x.regs.access(check(0x24), check(0x40), check(0xFC), write(0x24, 0xFFFFFFFF), check(0x24))
    # Every STATUS flag: set by its event, kept by a write of 0 and by a write without the strobe of its byte,
    # cleared by a write of 1
    def flag(bit, strobe_byte):
        others = 0xF & ~(1 << strobe_byte)
        return x.regs.access(check(RPL_STATUS), write(RPL_STATUS, 0), check(RPL_STATUS),
                             write(RPL_STATUS, 1 << bit, others), check(RPL_STATUS),
                             write(RPL_STATUS, 1 << bit), check(RPL_STATUS))
    items += raw_packet([rng.getrandbits(x.bits)], SEQ_CONT) + flag(8, 1)
    items += x.regs.access(*x.write_words(0, [(1 << min(x.w, 32)) - 1])) + x.image(rng) + flag(10, 1)
    items += x.scrub(0) + x.inject(1 << POS[0]) + x.regs.access(*x.write_words(0, [x.map[0]])) + x.image(rng)
    items += flag(16, 2)
    items += x.inject((1 << POS[1]) | (1 << POS[2])) + x.regs.access(*x.write_words(0, [x.map[0]])) + x.image(rng)
    items += flag(17, 2)
    return items + status()


def build_flag_coincidence(rng, x):
    # Pixels 0 to G of line 0 marked: pixel 0 has no operational pixel within G and pulses Stat_Unreplaced
    g = x.g
    items = x.clear() + x.regs.access(*x.write_words(0, [(1 << (g + 1)) - 1]))
    for d in range(SWEEP_STEPS):
        # A pixel without an image start after a complete image pulses Err_Framing
        items += x.image(rng) + [("W",), ("T", 4), ("M", 300 + d), ("K", 300 + d), ("T", 4)]
        items += raw_packet([rng.getrandbits(x.bits)], SEQ_CONT) + [("T", 40)]
    for d in range(SWEEP_STEPS):
        # The marker before p(G, 0), the last pixel the window of pixel 0 needs, so that the pulse falls into the
        # range of the clears of the sweep
        beats = x.image(rng)
        items += [("W",), ("T", 4)] + beats[:g] + [("M", 400 + d), ("K", 400 + d)] + beats[g:] + [("T", 40)]
    return items + status()


def build_exhaustive(rng, x):
    # Every line: a D^1 b D^2 a ... D^13 (a or b), then the rest of the line defects at the right border; with P-bit
    # pixels a = y mod 2^P, b = y / 2^P over 2^(2P) lines. The groups of 1 to 13 meet every pair (dl, dr) with
    # dl + dr = length + 1, the pairs of values in both orders over the lines; the border group gives the one-sided
    # and the unreplaced pixels.
    bits = x.bits
    assert x.h == 1 << (2 * bits) and x.g == 7
    pix, marks = [], []
    for y in range(x.h):
        a, b = y % (1 << bits), y >> bits
        line, m = [a], [0]
        for n in range(1, 14):
            line += [rng.getrandbits(bits) for _ in range(n)]
            m += [1] * n
            line.append(b if n % 2 else a)
            m.append(0)
        rest = x.w - len(line)
        line += [rng.getrandbits(bits) for _ in range(rest)]
        m += [1] * rest
        pix += line
        marks.append(m)
    items = x.regs.access(*x.write_words(0, x.words_of(rng, marks)))
    items += packets(pix, [x.w] * x.h)
    return items + status()


def build_reset(rng, x):
    w, h, g = x.w, x.h, x.g
    n = w * h
    items = x.clear() + x.write_map(rng) + x.image(rng)
    # Idle reset of two cycles: the registers return to their reset values, the map stays
    items += [("W",), ("T", 4), ("R", 0, 0, 2)] + x.regs.access(check(RPL_MAP_ADDR), check(RPL_STATUS))
    items += x.image(rng)
    # During a line (held, running), at the end of a line while the window outputs its virtual columns, and between
    # two images
    mid = [k for k in range(g + 3, n) if k % w not in (0, w - 1)] or [n]
    line_end = w * rng.randrange(h)

    def dropped(k, drop):
        """The last `drop` output pixels that the model emits for the first k pixels of an image."""
        out = []
        for i in range(k):
            y, xi = divmod(i, w)
            out += [(xo, y) for xo in (range(xi - g, xi - g + 1) if xi < w - 1 else range(xi - g, w)) if xo >= 0]
        return out[len(out) - drop:] if drop else []

    # A running reset takes a random number of the dropped beats out of the module before the reset, so it is placed
    # where no dropped pixel is unreplaced: Stat_Unreplaced counts the pixels that leave the module
    running = [k for k in mid if k < n and not any(x.unreplaced(xo, y) for xo, y in dropped(k, 2))]
    run_case = (rng.choice(running), 2, 1, 2) if running else (rng.choice(mid), 0, 1, 2)
    cases = [(rng.choice(mid), 0, 0, 1), run_case, (line_end + w, rng.randint(1, g), 0, 1), (n, 0, 1, 2)]
    for k, drop, mode, cycles in cases:
        beats = packets(random_image(rng, w, h, x.bits), [w] * h)
        items += beats[:k] + [("R", drop, mode, cycles)]
        if k < n:
            items += raw_packet([b[1] for b in beats[k:]], SEQ_LAST)
        items += x.image(rng)
    # A reset of one cycle in the cycles in which pixel (0, 0) issues the reads of words 0 to 2 and they return
    # (swept over the read latency), with the first beat of the next image right after the reset
    lat = x.c["lat"] + x.c["ecc"]
    for delay in range(lat + 5):
        beats = packets(random_image(rng, w, h, x.bits), [w] * h)
        items += [("W",), ("T", 4)] + beats[:1] + ([("T", delay)] if delay else []) + [("R", 0, 0, 1)]
        items += x.image(rng)
    # A pixel lost by a reset reports nothing: the last G + 1 pixels of line 0 marked make pixel W - 1 unreplaced;
    # a held reset after line 0 drops q(W - 1), which waits in the output register (RPL-IF-04)
    marks = [[0] * (w - g - 1) + [1] * (g + 1)] + [[0] * w for _ in range(h - 1)]
    items += x.clear() + x.regs.access(*x.write_words(0, x.words_of(rng, marks)))
    beats = packets(random_image(rng, w, h, x.bits), [w] * h)
    items += beats[:w] + [("R", 1, 0, 1)]
    if w < n:
        items += raw_packet([b[1] for b in beats[w:]], SEQ_LAST)
    items += x.regs.access(check(RPL_STATUS)) + x.image(rng)
    return items + status()


def build_rate(rng, x):
    items = x.clear() + x.write_map(rng) + [("W",), ("T", 8), ("M", 1)]
    for _ in range(3):
        items += x.image(rng)
    items += [("W",), ("M", 2)]
    return items + status()


BUILDERS = {
    "test_static": build_static,
    "test_input_stream": build_input_stream,
    "test_map_update": build_map_update,
    "test_clear": build_clear,
    "test_ecc": build_ecc,
    "test_scrub": build_scrub,
    "test_registers": build_registers,
    "test_flag_coincidence": build_flag_coincidence,
    "test_exhaustive": build_exhaustive,
    "test_reset": build_reset,
    "test_rate": build_rate,
}


def configure(lib, out_dir):
    tb = lib.test_bench("isp_replace_tb")
    for c in CONFIGS:
        for test in c["tests"]:
            rng = rng_for(MODULE, c["name"], test)
            x = Ctx(c)
            built = BUILDERS[test](rng, x)
            items, expect = built if isinstance(built, tuple) else (built, {})
            folder = Path(out_dir) / MODULE / c["name"]
            files = {ext: folder / (test + "." + ext) for ext in ("stim", "exp", "regs", "inj", "tim")}
            res = write_test(files["stim"], files["exp"], items,
                             lambda it: replace(it, c["w"], c["h"], c["bits"], c["g"]), c["bits"],
                             regs_path=files["regs"], inj_path=files["inj"], tim_path=files["tim"])
            generics = {
                "ImageWidth_g": c["w"], "ImageHeight_g": c["h"], "PixelBits_g": c["bits"], "MaxGap_g": c["g"],
                "RamRdLatency_g": c["lat"], "EccPipeline_g": c["ecc"], "ClkFreqHz_g": c["clk"],
                "ScrubPeriodMs_g": c["period"], "ScrubAtStart_g": test != "test_scrub",
                "StimFile_g": files["stim"].as_posix(), "ExpFile_g": files["exp"].as_posix(),
                "RegsFile_g": files["regs"].as_posix(), "InjFile_g": files["inj"].as_posix(),
                "TimFile_g": files["tim"].as_posix(), "GapPct_g": c["gap"], "StallPct_g": c["stall"],
                "Seed_g": seed_for(MODULE, c["name"], test), "ExpFraming_g": res["errors"],
                "ExpUnreplaced_g": res["unreplaced"], "ExpSec_g": res["sec"], "ExpDed_g": res["ded"],
                "SweepSteps_g": SWEEP_STEPS, "DutDefaults_g": c["name"].startswith("defaults"),
                "WatchdogUs_g": watchdog_us(files["stim"], files["exp"])}
            generics.update(expect)
            tb.test(test).add_config(name=c["name"], generics=generics)
