# ---------------------------------------------------------------------------------------------------
# Copyright (c) 2026 by Julian Schneider
# Authors: Julian Schneider
# ---------------------------------------------------------------------------------------------------
"""VUnit configurations of isp_chain_tb (verification plan of isp_chain, sections 2, 3 and 5).

For every chain and test the stimulus, the register script (the slot of the module in address bits 15 to 12), the
injection scripts of the ECC ports, the module reset script, the expected output and the timing file are built here
from the composed model (tools/isp_model.py, chain): the output stream of every module model is the input stream of
the next. The design values of test_rate and test_fifo follow the derivations of the verification plan (section 5).
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[3] / "tools"))

from isp_model import (CNV_COEF, CNV_CTRL, CNV_ID, CNV_PARAM, CNV_STATUS, CRP_ID, CRP_IMAGE, CRP_ROI_POS,  # noqa: E402
                       CRP_ROI_SIZE, CRP_STATUS, PNT_CTRL, PNT_GAIN, PNT_HIGH, PNT_ID, PNT_IMAGE, PNT_LOW,
                       PNT_OFFSET_HI, PNT_OFFSET_LO, PNT_PARAM, PNT_SHIFT, PNT_STATUS, RPL_CTRL, RPL_ID, RPL_IMAGE,
                       RPL_MAP_ADDR, RPL_MAP_DATA, RPL_MAP_LINE, RPL_MAP_WORDS, RPL_PARAM, RPL_STATUS, SEQ_LAST,
                       bin_count, bin_model, chain, conv_full_bits, crop, ecc_codeword_width, ecc_data_positions,
                       filter2d, log2ceil, point, replace)
from isp_tbgen import (hexw, malformed_streams, packets, random_image, raw_packet, rng_for, seed_for,  # noqa: E402
                       split, watchdog_us)

MODULE = "isp_chain"
GAIN_BITS = 16
KINDS = 8                       # pulse counters per position (isp_chain_tb)
MTF3 = [-1, -2, -1, -2, 28, -2, -1, -2, -1]
MTF5 = [0, -1, -1, -1, 0, -1, -2, -4, -2, -1, -1, -4, 44, -4, -1, -1, -2, -4, -2, -1, 0, -1, -1, -1, 0]
SMALL_COEF = [1, -1, 1, 1, 1, -2, 0, 1, 1]
SLOT = {"replace": 0, "point1": 1, "crop": 2, "filter2d": 3, "point2": 4}
TYPICAL_TESTS = ["test_static", "test_input_stream", "test_registers", "test_ecc", "test_reset", "test_rate",
                 "test_fifo", "neg_seam_dimension", "neg_seam_beat", "neg_pulse_count", "neg_fifo_depth",
                 "neg_fifo_drain"]

# Chains of the verification plan (section 2)
CHAINS = [
    dict(name="typical", order="typical", w=40, h=20, bits=12, gap=20, stall=20,
         rpl=dict(g=2, lat=1, ecc=0),
         p1=dict(bits=12, stages=2),
         crp=dict(w=32, h=16, x=4, y=2, runtime=True),
         flt=dict(win=3, border="replicate", cb=16, coef=MTF3, runtime=True, ob=16, resource="AUTO", ecc=1),
         bin=dict(x=2, y=2, border="valid", resource="AUTO", ecc=1),
         p2=dict(bits=12, shift=6, runtime=True, stages=2),
         tests=TYPICAL_TESTS),
    dict(name="reordered", order="reordered", w=33, h=12, bits=12, gap=20, stall=20,
         bin=dict(x=2, y=1, border="zero", resource="AUTO", ecc=1),
         flt=dict(win=5, border="mirror", cb=16, coef=MTF5, runtime=False, ob=16, resource="BRAM", ecc=1),
         crp=dict(w=12, h=8, x=3, y=2, runtime=False),
         p2=dict(bits=12, shift=4, runtime=False, stages=2),
         tests=["test_static", "test_input_stream", "test_reset", "test_rate"]),
    dict(name="small", order="typical", w=5, h=3, bits=1, gap=20, stall=20,
         rpl=dict(g=2, lat=1, ecc=0),
         p1=dict(bits=1, stages=1),
         crp=dict(w=3, h=3, x=1, y=0, runtime=True),
         flt=dict(win=3, border="replicate", cb=2, coef=SMALL_COEF, runtime=True, ob=0, resource="SRL", ecc=0),
         bin=dict(x=3, y=3, border="valid", resource="SRL", ecc=0),
         p2=dict(bits=1, shift=4, runtime=True, stages=1),
         tests=["test_static", "test_input_stream", "test_registers", "test_ecc", "test_reset"]),
]


def win_out(n, win, border):
    """isp_pkg ispWinOut with stride 1."""
    if border == "valid":
        return max(n - win + 1, 0)
    return n


class Chain:
    """The modules of a chain with the generics that follow from the module before (CHN-FN-04, user guide 5.1)."""

    def __init__(self, c):
        self.c = c
        self.typical = c["order"] == "typical"
        f, b = c["flt"], c["bin"]
        taps = f["win"] * f["win"]

        def flt_bits(inb):
            return f["ob"] if f["ob"] else conv_full_bits(inb, f["cb"], taps)

        # Each stage: (name, input width, input height, input bits, output width, output height, output bits)
        if self.typical:
            w, h, bits = c["w"], c["h"], c["bits"]
            p1 = c["p1"]["bits"]
            cw, ch = c["crp"]["w"], c["crp"]["h"]
            fw, fh, fb = win_out(cw, f["win"], f["border"]), win_out(ch, f["win"], f["border"]), flt_bits(p1)
            bw, bh = bin_count(fw, b["x"], b["border"]), bin_count(fh, b["y"], b["border"])
            bb = fb + log2ceil(b["x"] * b["y"])
            self.stages = [("replace", w, h, bits, w, h, bits), ("point1", w, h, bits, w, h, p1),
                           ("crop", w, h, p1, cw, ch, p1), ("filter2d", cw, ch, p1, fw, fh, fb),
                           ("bin", fw, fh, fb, bw, bh, bb), ("point2", bw, bh, bb, bw, bh, c["p2"]["bits"])]
        else:
            w, h, bits = c["w"], c["h"], c["bits"]
            bw, bh = bin_count(w, b["x"], b["border"]), bin_count(h, b["y"], b["border"])
            bb = bits + log2ceil(b["x"] * b["y"])
            fw, fh, fb = win_out(bw, f["win"], f["border"]), win_out(bh, f["win"], f["border"]), flt_bits(bb)
            cw, ch = c["crp"]["w"], c["crp"]["h"]
            self.stages = [("bin", w, h, bits, bw, bh, bb), ("filter2d", bw, bh, bb, fw, fh, fb),
                           ("crop", fw, fh, fb, cw, ch, fb), ("point2", cw, ch, fb, cw, ch, c["p2"]["bits"])]
        self.names = [s[0] for s in self.stages]
        self.out_w, self.out_h = self.stages[-1][4], self.stages[-1][5]
        self.models = [self.model(s) for s in self.stages]

    def pos(self, name):
        return self.names.index(name)

    def model(self, s):
        c = self.c
        name, w, h, inb, _ow, _oh, outb = s
        if name == "replace":
            return lambda it: replace(it, w, h, inb, c["rpl"]["g"])
        if name == "point1":
            return lambda it: point(it, w, h, inb, outb, GAIN_BITS, inb + GAIN_BITS, 0, 1, 0, 0, -1, True)
        if name == "point2":
            p = c["p2"]
            return lambda it: point(it, w, h, inb, outb, GAIN_BITS, inb + GAIN_BITS, 0, 1, p["shift"], 0, -1,
                                    p["runtime"])
        if name == "crop":
            r = c["crp"]
            return lambda it: crop(it, w, h, r["x"], r["y"], r["w"], r["h"], r["runtime"])
        if name == "filter2d":
            f = c["flt"]
            return lambda it: filter2d(it, w, h, inb, f["win"], f["win"], None, None, 1, 1, f["border"], f["cb"],
                                       f["coef"], f["runtime"], f["ob"])
        b = c["bin"]
        return lambda it: bin_model(it, w, h, inb, b["x"], b["y"], b["border"])

    def run(self, items, stages=None):
        return chain(items, stages or self.models)


class Ctx:
    """Items of a test of the chain: the stream at its input and the scripts, with markers from 100 on."""

    def __init__(self, ch):
        self.ch = ch
        self.c = ch.c
        self.w, self.h, self.bits = self.c["w"], self.c["h"], self.c["bits"]
        self.n = self.w * self.h
        self.markers = iter(range(100, 1 << 30))
        if ch.typical:
            self.wl = -(-self.w // 32)
            self.words = self.h * self.wl
            self.map = [0] * self.words

    # Stream
    def image(self, rng, mode="lines", pix=None):
        if pix is None:
            pix = random_image(rng, self.w, self.h, self.bits)
        return packets(pix, split(rng, self.n, self.w, mode))

    def settle(self, cycles=64):
        """Wait until every output of the pixels sent has passed the sink, then the time for the internal events
        (line buffers, sums) that make no output."""
        return [("W",), ("T", cycles)]

    # Scripts
    def access(self, *pairs):
        """Register accesses (stage name, entry) after the chain has settled."""
        return self.settle(8) + [("A", next(self.markers), [(self.ch.pos(s), e) for s, e in pairs])]

    def access_now(self, *pairs):
        """Register accesses while the source goes on; returns (items, marker) for the later ("K", marker)."""
        m = next(self.markers)
        return [("AC", m, [(self.ch.pos(s), e) for s, e in pairs])], m

    def inject(self, stage, pattern):
        return self.settle() + [("J", next(self.markers), pattern, self.ch.pos(stage))]

    def scrub(self, enable):
        return self.settle(8) + [("S", next(self.markers), enable)]

    def module_reset(self, stage):
        return self.settle() + [("RM", next(self.markers), self.ch.pos(stage))]

    # Defect map of isp_replace
    def clear(self):
        self.map = [0] * self.words
        return self.access(("replace", wr(RPL_CTRL, 1))) + [("T", self.words + 16)]

    def write_words(self, start, values):
        for k, v in enumerate(values):
            self.map[start + k] = v
        return [("replace", wr(RPL_MAP_ADDR, start))] + [("replace", wr(RPL_MAP_DATA, v)) for v in values]

    def rand_map(self, rng):
        """A random map: isolated defects, a group that the interpolation bridges, one in four lines a group longer
        than 2 x G (unreplaced pixels); the bits beyond the last pixel of a line are random."""
        g = self.c["rpl"]["g"]
        values = []
        for _ in range(self.h):
            m = [0] * self.w
            for _ in range(max(1, self.w // 10)):
                m[rng.randrange(self.w)] = 1
            n = min(rng.randint(2, 2 * g), self.w)
            s = rng.randint(0, self.w - n)
            m[s:s + n] = [1] * n
            if rng.random() < 0.25 and 2 * g + 1 <= self.w:
                n = 2 * g + 1
                s = rng.randint(0, self.w - n)
                m[s:s + n] = [1] * n
            for j in range(self.wl):
                v = 0
                for bit in range(32):
                    x = 32 * j + bit
                    v |= (m[x] if x < self.w else rng.getrandbits(1)) << bit
                values.append(v)
        return values

    def write_map(self, rng):
        return self.access(*self.write_words(0, self.rand_map(rng)))

    def start(self, rng):
        """The defect map cleared and written before the first image (user guide, section 7)."""
        return self.clear() + self.write_map(rng) if self.ch.typical else []


def wr(addr, data, strobes=0xF):
    return ("W", addr, data, strobes)


def rd(addr, data=None):
    return ("C", addr, data, 0xF)


# ---------------------------------------------------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------------------------------------------------
def build_static(rng, x):
    items = x.start(rng)
    for mode in ("lines", "random", "one", "lines"):
        items += x.image(rng, mode)
    # Pauses between and within images
    items += [("G", 37)] + x.image(rng, "random") + [("G", 5)] + x.image(rng, "lines")
    if x.ch.typical:
        items += x.write_map(rng) + x.image(rng, "random")
    # The largest pixels: the saturation of the filter and of the last isp_point
    items += x.image(rng, "lines", [(1 << x.bits) - 1] * x.n) + x.image(rng, "one")
    return items + x.settle(8) + [("P",)]


def build_input_stream(rng, x):
    return x.start(rng) + malformed_streams(rng, x.w, x.h, x.bits)


def point_set(rng, bits_in, bits_out, shift):
    """A parameter set of isp_point that keeps the pixels in range: offset, gain about 1 at the shift, low < high."""
    off = rng.randint(-(1 << max(bits_in - 4, 0)), (1 << max(bits_in - 4, 0)))
    gain = rng.randint(3 << max(shift - 2, 0), 5 << max(shift - 2, 0)) if shift >= 2 else rng.randint(1, 2)
    full = (1 << bits_out) - 1
    low, high = sorted((rng.randint(0, full // 8), rng.randint(full - full // 8, full)))
    return off, gain, shift, low, high


def point_writes(stage, s):
    off, gain, shift, low, high = s
    return [(stage, wr(PNT_OFFSET_LO, off & 0xFFFFFFFF)), (stage, wr(PNT_OFFSET_HI, (off >> 32) & 0xFFFFFFFF)),
            (stage, wr(PNT_GAIN, gain)), (stage, wr(PNT_SHIFT, shift)), (stage, wr(PNT_LOW, low)),
            (stage, wr(PNT_HIGH, high))]


def point_reads(stage):
    return [(stage, rd(a)) for a in (PNT_OFFSET_LO, PNT_OFFSET_HI, PNT_GAIN, PNT_SHIFT, PNT_LOW, PNT_HIGH, PNT_CTRL)]


def coef_set(rng, x):
    f = x.c["flt"]
    t = f["win"] * f["win"]
    lo, hi = -(1 << (f["cb"] - 1)), (1 << (f["cb"] - 1)) - 1
    if f["cb"] <= 4:
        return [rng.randint(lo, hi) for _ in range(t)]
    # A sharpening kernel with the sum 16, as the MTF kernel of the chain
    k = [rng.randint(-3, 0) for _ in range(t)]
    k[t // 2] = 16 - (sum(k) - k[t // 2])
    return k


def coef_writes(s):
    return [("filter2d", wr(CNV_COEF + 4 * k, v & 0xFFFFFFFF)) for k, v in enumerate(s)]


def roi_pos(x, y):
    return (y << 16) | x


def build_registers(rng, x):
    """TC-CHN-03: the registers of every module through the decoder; the procedure of section 5.4."""
    ch, c = x.ch, x.c
    p1b, p2s = ch.stages[ch.pos("point1")], c["p2"]["shift"]
    p2b = ch.stages[ch.pos("point2")]
    items = x.start(rng)
    # The identification and the static registers of every module
    items += x.access(("replace", rd(RPL_ID)), ("replace", rd(RPL_IMAGE)), ("replace", rd(RPL_PARAM)),
                      ("replace", rd(RPL_MAP_LINE)), ("replace", rd(RPL_MAP_WORDS)),
                      ("point1", rd(PNT_ID)), ("point1", rd(PNT_IMAGE)), ("point1", rd(PNT_PARAM)),
                      ("crop", rd(CRP_ID)), ("crop", rd(CRP_IMAGE)), ("crop", rd(CRP_ROI_SIZE)),
                      ("crop", rd(CRP_ROI_POS)), ("filter2d", rd(CNV_ID)), ("filter2d", rd(CNV_PARAM)),
                      ("point2", rd(PNT_ID)), ("point2", rd(PNT_IMAGE)), ("point2", rd(PNT_PARAM)),
                      ("replace", rd(RPL_STATUS)), ("point1", rd(PNT_STATUS)), ("crop", rd(CRP_STATUS)),
                      ("filter2d", rd(CNV_STATUS)), ("point2", rd(PNT_STATUS)))
    items += x.image(rng)
    # Step 1 of the procedure: CTRL.HOLD 1 and the new sets, read back
    s1 = point_set(rng, p1b[3], p1b[6], 4)
    s2 = point_set(rng, p2b[3], p2b[6], p2s + 4)
    k = coef_set(rng, x)
    items += x.access(("point1", wr(PNT_CTRL, 1)), ("filter2d", wr(CNV_CTRL, 1)), ("point2", wr(PNT_CTRL, 1)),
                      *point_writes("point1", s1), *coef_writes(k), *point_writes("point2", s2),
                      *point_reads("point1"), *point_reads("point2"),
                      *[("filter2d", rd(CNV_COEF + 4 * j)) for j in range(len(k))], ("filter2d", rd(CNV_CTRL)))
    items += x.image(rng)
    # Step 2 at the time of section 5.4: CTRL.HOLD 0 and ROI_POS while image k passes, images back to back; image
    # k keeps the old sets, image k + 1 takes the new ones in every module
    rx, ry = rng.randint(0, x.w - c["crp"]["w"]), rng.randint(0, x.h - c["crp"]["h"])
    release = [("point1", wr(PNT_CTRL, 0)), ("crop", wr(CRP_ROI_POS, roi_pos(rx, ry))), ("filter2d", wr(CNV_CTRL, 0)),
               ("point2", wr(PNT_CTRL, 0))]
    if c["name"] == "typical":
        # Input pixel (0, 10): S_last < t < S_first + P (section 5.4)
        k_rel = 10 * x.w
        pix = random_image(rng, x.w, x.h, x.bits)
        acc, m = x.access_now(*release)
        items += packets(pix[:k_rel], [k_rel], last=False) + acc + packets(pix[k_rel:], [x.n - k_rel], first=False)
        items += [("K", m)] + x.image(rng) + x.image(rng, "random")
        # A release of the two isp_point alone at input pixel (37, 2), between s_first(k) and s_last(k): image k has
        # the old set in the first isp_point and the new one in the second (the mixed image)
        t1 = point_set(rng, p1b[3], p1b[6], 4)
        t2 = point_set(rng, p2b[3], p2b[6], p2s + 4)
        items += x.access(("point1", wr(PNT_CTRL, 1)), ("point2", wr(PNT_CTRL, 1)), *point_writes("point1", t1),
                          *point_writes("point2", t2))
        k_mix = 2 * x.w + 37
        pix = random_image(rng, x.w, x.h, x.bits)
        acc, m = x.access_now(("point1", wr(PNT_CTRL, 0)), ("point2", wr(PNT_CTRL, 0)))
        items += packets(pix[:k_mix], [k_mix], last=False) + acc + packets(pix[k_mix:], [x.n - k_mix], first=False)
        items += [("K", m)] + x.image(rng)
    else:
        # small: Delta = S_last - S_first is not shorter than P, back-to-back images leave no window (section 5.4).
        # The source stops after the last pixel of image k, sets the release S_last + 1 cycles after the image start
        # and starts image k + 1 only after the writes: the pause is at least Delta - P plus the time of the writes
        s_first, s_last, period, last_pixel = release_times(c)
        assert s_last - s_first >= period
        acc, m = x.access_now(*release)
        items += x.image(rng) + [("T", s_last + 1 - (last_pixel + 1))] + acc + [("K", m)]
        items += x.image(rng) + x.image(rng, "random")
    items += x.access(*point_reads("point1"), *point_reads("point2"), ("crop", rd(CRP_ROI_POS)),
                      ("filter2d", rd(CNV_CTRL)), ("filter2d", rd(CNV_STATUS)), ("point1", rd(PNT_STATUS)),
                      ("point2", rd(PNT_STATUS)), ("crop", rd(CRP_STATUS)))
    return items + x.settle(8) + [("P",)]


def release_times(c):
    """S_first and S_last of section 5.4 (the delays of the image start to the first and the last isp_point, from the
    design values of the module plans: S_first with the lower latency of isp_replace for the end of the window,
    S_last with the upper latencies for its start), the image period P and the cycle of the last pixel of an image
    after its start at the input, for the order typical with images back to back."""
    w, h, g = c["w"], c["h"], c["rpl"]["g"]
    rd_lat = c["rpl"]["lat"] + c["rpl"]["ecc"]
    line = w + g
    first_line = max(0, rd_lat + 2 - g)       # the longer interval of line 0 (the wait for word 0 of the map)
    s_first = g + 10
    s = g + 12 + rd_lat + c["p1"]["stages"] + 5
    r, f, b = c["crp"], c["flt"], c["bin"]
    s += r["y"] * line + r["x"] + 4
    rr = rb = (f["win"] - 1) // 2
    s += rb * line + rr + 8 + log2ceil(f["win"] * f["win"])
    lx, ly = log2ceil(b["x"]), log2ceil(b["y"])
    s += (b["y"] - 1) * line + (b["x"] - 1) + 16 + lx + ly
    period = h * line + first_line
    return s_first, s, period, (h - 1) * line + first_line + w - 1


def build_ecc(rng, x):
    """TC-CHN-04: single and double errors in the defect map, in the line buffers of isp_filter2d and of isp_bin.
    Returns (items, expectations of the scrubber)."""
    ch, c = x.ch, x.c
    pos32 = ecc_data_positions(32)
    items = x.scrub(0) + x.start(rng) + x.image(rng)
    # isp_replace: a single error in word k1; a double error on the mark of a pixel inside the region of the crop in
    # word k2 (the word is used as read: the replaced pixels change through every module behind it), rewritten
    # after two images; a double error in the last word, which a pass of the scrubber reads just before
    # Scrub_PassDone (verification plan of isp_replace, section 5)
    r = c["crp"]
    last = x.words - 1
    rows = [y for y in range(r["y"], r["y"] + r["h"]) if y * x.wl + (r["x"] + r["w"] - 1) // 32 < last]
    ys, xs = rng.choice(rows), rng.randint(r["x"], r["x"] + r["w"] - 1)
    k2 = ys * x.wl + xs // 32
    k1 = rng.choice([k for k in range(last) if k != k2])

    def double(bit):
        return (1 << pos32[bit]) | (1 << pos32[rng.choice([b for b in range(32) if b != bit])])

    items += x.inject("replace", 1 << pos32[rng.randrange(32)]) + x.access(*x.write_words(k1, [x.map[k1]]))
    items += x.inject("replace", double(xs % 32)) + x.access(*x.write_words(k2, [x.map[k2]]))
    items += x.image(rng) + x.image(rng, "random")
    items += x.access(("replace", rd(RPL_STATUS)), *x.write_words(k2, [x.map[k2]]))
    items += x.inject("replace", double(rng.randrange(32))) + x.access(*x.write_words(last, [x.map[last]]))
    items += x.image(rng) + x.access(("replace", rd(RPL_STATUS)))

    # isp_filter2d and isp_bin: an injection before the pixel (col, line) of the module input; the pattern applies to
    # the next write of its line buffer
    def chain_index(col, line):
        """The input pixel of the chain that brings pixel (col, line) of the crop output."""
        return (line + r["y"]) * x.w + col + r["x"]

    def inject_image(stage, pattern, k):
        """An image with the injection before its input pixel k. For a double error, the pixels are drawn until the
        error changes the chain output (a 1-bit output hides most changes of a sum)."""
        nonlocal items
        for _ in range(200):
            pix = random_image(rng, x.w, x.h, x.bits)
            inj = x.inject(stage, pattern)
            cand = packets(pix[:k], [k], last=False) + inj + packets(pix[k:], [x.n - k], first=False)
            if bin(pattern).count("1") == 1:
                break
            plain = [it for it in cand if it[0] != "J"]
            if ch.run(items + cand)[0] != ch.run(items + plain)[0]:
                break
        else:
            raise AssertionError("no image shows the double error of " + stage)
        items += cand

    f = c["flt"]
    fb = ch.stages[ch.pos("filter2d")][3]
    fcw, fpos = ecc_codeword_width(fb), ecc_data_positions(fb)
    for t in range(1, f["win"]):
        shift = (t - 1) * fcw
        line = min(t, r["h"] - 1)
        d1 = rng.choice(fpos)
        inject_image("filter2d", (1 << d1) << shift, chain_index(rng.randrange(r["w"]), line))
        second = 1 << rng.choice([p for p in fpos if p != d1]) if len(fpos) > 1 else 1
        inject_image("filter2d", ((1 << max(fpos)) | second) << shift, chain_index(rng.randrange(r["w"]), line))
    # isp_bin: its vertical sum keeps the horizontal sums of BinY - 1 lines. A value written in line l of the bin
    # input is read in line l + 1, which completes a bin only when l + 1 = BinY - 1 modulo BinY; the window of any
    # other line is not output, and a double error there is reported without changing a pixel. The injection comes
    # before a pixel of the crop line l + Rb, while isp_filter2d makes its output line l.
    b = c["bin"]
    bb = ch.stages[ch.pos("bin")][3] + log2ceil(b["x"])
    bcw, bpos = ecc_codeword_width(bb), ecc_data_positions(bb)
    rb = (f["win"] - 1) // 2
    out_line = min(l for l in range(1, r["h"] - rb) if (l + 1) % b["y"] == b["y"] - 1)
    for t in range(1, b["y"]):
        shift = (t - 1) * bcw
        line = out_line + rb
        d1 = rng.choice(bpos)
        inject_image("bin", (1 << d1) << shift, chain_index(rng.randrange(r["w"]), line))
        second = 1 << rng.choice([p for p in bpos if p != d1])
        inject_image("bin", ((1 << max(bpos)) | second) << shift, chain_index(rng.randrange(r["w"]), line))
    # The scrubber of isp_replace for several passes without images: it corrects the single error in word k1 and
    # reports the double error in the last word once per pass
    items += x.scrub(1) + [("T", 64 * max(2, x.words) + 200)] + x.scrub(0)
    items += x.image(rng) + x.access(("replace", rd(RPL_STATUS)), ("filter2d", rd(CNV_STATUS)))
    return items + x.settle(8) + [("P",)], {"ScrubSec": 1, "ScrubDedWords_g": 1}


def reset_pause(x, inside):
    """The input pixel at which the source pauses for the reset of isp_crop alone (verification plan, section 5.5):
    the crop has its image open and has delivered whole lines (inside False) or a cut line (inside True)."""
    ch = x.ch
    upto = ch.models[:ch.pos("crop") + 1]
    rw, rh = x.c["crp"]["w"], x.c["crp"]["h"]
    pix = [0] * x.n
    for y in range(x.h // 2, x.h):
        # Whole lines: the pause after the region in the line; a cut line: inside the region
        for xx in (range(x.w) if inside else range(x.w - 1, -1, -1)):
            k = y * x.w + xx
            items = packets(pix[:k], [k], last=False)
            cnt = chain(items, upto)[2][-1][0] if items else 0
            if 0 < cnt < rw * rh and (cnt % rw != 0) == inside:
                return k
    raise AssertionError("no pause for the module reset")


def build_reset(rng, x):
    """TC-CHN-05: the common reset idle, during an image and during the lower border; the reset of isp_crop alone."""
    ch = x.ch
    items = x.start(rng) + x.image(rng)
    # Idle, two cycles (the reset keeps the defect map)
    items += x.settle() + [("R", 0, 0, 2)]
    items += x.image(rng, "random")
    # Held reset of one cycle in the middle of an image; the rest of it without an image start
    pix = random_image(rng, x.w, x.h, x.bits)
    k = x.n // 2
    items += packets(pix[:k], [k], last=False) + [("T", 3), ("R", 0, 0, 1)] + raw_packet(pix[k:], SEQ_LAST)
    items += x.image(rng)
    # Running reset of two cycles while the chain makes its last output line (the lower border of the filters)
    items += x.image(rng) + [("R", min(ch.out_w + 2, ch.out_w * ch.out_h), 1, 2)]
    items += x.image(rng) + x.image(rng, "random")
    # isp_crop alone (section 5.5): whole lines delivered, then a cut line
    for inside in (False, True):
        k = reset_pause(x, inside)
        pix = random_image(rng, x.w, x.h, x.bits)
        items += packets(pix[:k], [k], last=False) + x.module_reset("crop")
        items += packets(pix[k:], [x.n - k], first=False) + x.image(rng) + x.image(rng, "random")
    return items + x.settle(8) + [("P",)]


def build_rate(rng, x):
    items = x.start(rng) + [("M", 1)]
    for mode in ("lines", "random", "one", "lines"):
        items += x.image(rng, mode)
    return items + [("W",), ("M", 2)] + x.settle(8) + [("P",)]


FIFO_L, FIFO_F = 1, 30


def build_fifo(rng, x, blank=None):
    """TC-CHN-07: a source that cannot wait: W pixels per line in W cycles, a line blanking L and an image blanking F
    (section 5.3): F at the drain condition of the rule, or `blank`."""
    f = fifo_drain(x.c) if blank is None else blank
    items = x.start(rng)
    for _ in range(4):
        pix = random_image(rng, x.w, x.h, x.bits)
        for y in range(x.h):
            items += packets(pix[y * x.w:(y + 1) * x.w], [x.w], first=y == 0, last=y == x.h - 1)
            items += [("G", f if y == x.h - 1 else FIFO_L)]
    return items + x.settle(8) + [("P",)]


def build_negative(rng, x):
    return x.start(rng) + x.image(rng) + x.image(rng, "random") + x.settle(8) + [("P",)]


BUILDERS = {
    "test_static": build_static,
    "test_input_stream": build_input_stream,
    "test_registers": build_registers,
    "test_ecc": build_ecc,
    "test_reset": build_reset,
    "test_rate": build_rate,
    "test_fifo": build_fifo,
    "neg_seam_dimension": build_negative,
    "neg_seam_beat": build_negative,
    "neg_pulse_count": build_negative,
    "neg_fifo_depth": lambda rng, x: build_fifo(rng, x, FIFO_F),
    "neg_fifo_drain": lambda rng, x: build_fifo(rng, x, fifo_drain(x.c) - 1),
}


# ---------------------------------------------------------------------------------------------------------------------
# Design values (verification plan, section 5)
# ---------------------------------------------------------------------------------------------------------------------
def rate_values(c):
    """Hold cycles per line, between lines 0 and 1 of the first image and of the images after it, the first and the
    further image intervals at the chain input, and the latency range of an output pixel (sections 5.1 and 5.2). The
    virtual columns of a line hold the input in the interval of the next line: the frame sync of the module takes
    three pixels first (its output register and the two entries of its input stage)."""
    w, h = c["w"], c["h"]
    if c["order"] == "typical":
        g, rd_lat = c["rpl"]["g"], c["rpl"]["lat"] + c["rpl"]["ecc"]
        # isp_replace sets the pace (RPL-PF-01, RPL-PF-02): the wait for word 0 of the map is RamRdLatency_g +
        # EccPipeline_g + 2 (the registered read request); the waits of isp_filter2d are absorbed by isp_crop
        hold, hold_first, wait = g, rd_lat + 2, max(g, rd_lat + 2)
        first = h * w + (h - 1) * g + rd_lat + 2
        period = h * (w + g) + max(0, rd_lat + 2 - g)
        t = c["flt"]["win"] ** 2
        lx, ly = log2ceil(c["bin"]["x"]), log2ceil(c["bin"]["y"])
        p1, p2 = c["p1"]["stages"] + 5, c["p2"]["stages"] + 5
        lat_min = 10 + p1 + 4 + (6 + log2ceil(t)) + (12 + lx + ly) + p2
        lat_max = (12 + rd_lat) + p1 + 4 + (8 + log2ceil(t)) + (16 + lx + ly) + p2 + 1
        return dict(HoldLine_g=hold, HoldFirst_g=hold_first, HoldWait_g=wait, PerFirst_g=first, Per_g=period,
                    LatMin_g=lat_min, LatMax_g=lat_max)
    # reordered: the virtual columns of isp_bin (zero border, W odd), and the wait of the filter behind the binning
    # (the case rate_tall of isp_bin with isp_filter2d as the vertical filter)
    bx = c["bin"]["x"]
    win = c["flt"]["win"]
    rr = rb = (win - 1) // 2
    wb = bin_count(w, bx, c["bin"]["border"])
    hold = bin_count(w, bx, c["bin"]["border"]) * bx - w
    lx = log2ceil(bx)
    n_ev = rr + rb * (wb + rr)
    cc = -(-(3 + lx) // bx)
    assert bx * (4 + cc) + 3 < w, "the exact wait needs the buffers to fill within line 0"
    # The plan of isp_bin derives the wait for W a multiple of BinX_g, where the PIX event of the last pixel completes
    # the last bin. Otherwise the e-th HCOL event after it completes the bin, and the vertical filter (here
    # isp_filter2d) starts its virtual pixels e cycles later
    e = (bx - w % bx) % bx
    wait = n_ev + 8 + lx + e - bx * (5 + cc)
    # The first image after an idle chain: no virtual column before its line 1, H - 1 in its interval; every
    # further interval also holds the virtual column of the last line of the image before and the wait
    first = h * w + (h - 1) * hold
    period = h * (w + hold) + wait
    t = win * win
    p2 = c["p2"]["stages"] + 5
    lat_min = (6 + lx) + (6 + log2ceil(t)) + 4 + p2
    lat_max = (8 + lx) + (8 + log2ceil(t)) + 4 + p2 + rr
    return dict(HoldLine_g=hold, HoldFirst_g=0, HoldWait_g=hold + wait, PerFirst_g=first, Per_g=period,
                LatMin_g=lat_min, LatMax_g=lat_max)


def fifo_level(c):
    """Largest In_Level of the FIFO in front of the chain typical (section 5.3). r_y are the hold cycles of the chain
    input between the first pixels of lines y and y + 1: the wait of isp_replace for word 0 of the map in line 0
    (RamRdLatency_g + EccPipeline_g + 2; every image follows an idle input, the image blanking drains the FIFO), G
    in every further line. D_y = max(0, D_(y-1) + r_y - L); the FIFO holds D_(y-1) + r_y pixels more than in a
    continuous flow. In a continuous flow In_Level is 3: olo_base_fifo_sync shows a write at its output one cycle
    after it registered it, so a pixel is read two edges after its write, and In_Level counts it until the edge
    after its read."""
    g, rd_lat = c["rpl"]["g"], c["rpl"]["lat"] + c["rpl"]["ecc"]
    d, most, last = 0, 0, 0
    for y in range(c["h"]):
        r = rd_lat + 2 if y == 0 else g
        most = max(most, d + r)
        last = d + r
        d = max(0, d + r - FIFO_L)
    assert last + g <= FIFO_F, "the image blanking does not drain the FIFO"
    return 3 + most


def fifo_drain(c):
    """The image blanking of the rule (section 5.3): after the last write the FIFO holds what the last line leaves,
    D_(H-2) + r_(H-1), and the pixel written the cycle before (a pixel is read two edges after its write); it reads one
    per cycle, the virtual columns of the last line hold the input of isp_replace only after its last pixel, and a
    read in the cycle of the first write of the next image counts: F >= D_(H-2) + r_(H-1) + 1."""
    g, rd_lat = c["rpl"]["g"], c["rpl"]["lat"] + c["rpl"]["ecc"]
    d, last = 0, 0
    for y in range(c["h"]):
        r = rd_lat + 2 if y == 0 else g
        last = d + r
        d = max(0, d + r - FIFO_L)
    return last + 1


def fifo_depth(c):
    """The depth of the user guide (section 5, step 3): the largest number of pixels the waits leave in the FIFO plus
    4, the 3 of In_Level in a continuous flow and one more, because the FIFO holds the source when In_Level equals
    Depth_g before a write."""
    return fifo_level(c) + 1


# ---------------------------------------------------------------------------------------------------------------------
# Files
# ---------------------------------------------------------------------------------------------------------------------
def write_chain_test(files, items, ch, bits_in, bits_out):
    """Runs the composed model and writes the files of a test. Returns the model result."""
    out, _errors, annot, extra = ch.run(items)
    stim, mod_rst = [], []
    inj = {"replace": [], "filter2d": [], "bin": []}
    for i, it in enumerate(items):
        before = annot[i - 1] if i > 0 else (0, False)
        kind = it[0]
        if kind == "B":
            stim.append("B {} {} {}".format(hexw(it[1], bits_in), it[2], it[3]))
        elif kind in ("G", "T", "H", "M", "K"):
            stim.append("{} {}".format(kind, it[1]))
        elif kind == "W":
            stim.append("W {}".format(before[0]))
        elif kind == "P":
            stim.append("P {}".format(1 if before[1] else 0))
        elif kind == "R":
            _, drop, mode, cycles = it
            stim.append("R {} {} {}".format(before[0] - drop, mode, cycles))
        elif kind == "AC":
            stim.append("M {}".format(it[1]))
        elif kind in ("A", "J", "S", "RM"):
            stim += ["M {}".format(it[1]), "K {}".format(it[1])]
            if kind == "J":
                inj[ch.names[it[3]]].append("{} J {:x}".format(it[1], it[2]))
            elif kind == "S":
                inj["replace"].append("{} S {:x}".format(it[1], it[2]))
            elif kind == "RM":
                mod_rst.append("{} {} 2".format(it[1], it[2]))
        else:
            raise ValueError(kind)
    exp = ["B {} {} {} 0".format(hexw(o[1], bits_out), o[2], o[3]) if o[0] == "B" else "R {}".format(o[1])
           for o in out]
    regs = []
    for marker, entries in extra["regs"]:
        for stage, (op, addr, data, strobes) in entries:
            name = ch.names[stage]
            slot = SLOT["point1" if name == "point2" and not ch.typical else name]
            a = (slot << 12) | addr
            regs.append("{} W {:x} {:x} {:x}".format(marker, a, data, strobes) if op == "W" else
                        "{} C {:x} {:x}".format(marker, a, data))
    texts = {"stim": stim, "exp": exp, "regs": regs, "inj_rpl": inj["replace"], "inj_flt": inj["filter2d"],
             "inj_bin": inj["bin"], "modrst": mod_rst, "tim": [str(n) for n in extra["timing"]]}
    for key, lines in texts.items():
        files[key].parent.mkdir(parents=True, exist_ok=True)
        files[key].write_text("\n".join(lines) + "\n", encoding="ascii", newline="\n")
    return out, annot, extra


def pulses(ch, extra, scrub_sec=0):
    """The pulse counts of every position in the order of isp_chain_tb."""
    vec = []
    for p, info in enumerate(extra["stages"]):
        vec += [info["errors"], info.get("config", 0), info.get("sec", 0), info.get("ded", 0),
                info.get("unreplaced", 0), scrub_sec if ch.names[p] == "replace" else 0, 0, 0]
    return vec


def seam_beat_errors(ch, items):
    """neg_seam_beat: the beat between isp_crop and isp_filter2d and the bit whose inversion changes the chain output;
    returns (beat, mask, number of output beats that differ)."""
    cut = ch.pos("crop") + 1
    head = chain(items, ch.models[:cut])
    crop_out = [o for o in head[0] if o[0] == "B"]
    ref = [o[1:4] for o in ch.run(items)[0] if o[0] == "B"]
    bits = ch.stages[cut - 1][6]
    for beat in range(len(crop_out) // 3, len(crop_out)):
        for bit in [0, bits - 1]:
            tail = [("B", o[1] ^ (1 << bit) if j == beat else o[1], o[2], o[3]) for j, o in enumerate(crop_out)]
            got = [o[1:4] for o in chain(tail, ch.models[cut:])[0] if o[0] == "B"]
            assert len(got) == len(ref)
            diff = sum(1 for a, b in zip(got, ref) if a != b)
            if diff:
                return beat, 1 << bit, diff
    raise AssertionError("no visible beat for neg_seam_beat")


def configure(lib, out_dir):
    tb = lib.test_bench("isp_chain_tb")
    for c in CHAINS:
        ch = Chain(c)
        out_bits = ch.stages[-1][6]
        base = {
            "Chain_g": c["order"], "Width_g": c["w"], "Height_g": c["h"], "Bits_g": c["bits"],
            "CrpWidth_g": c["crp"]["w"], "CrpHeight_g": c["crp"]["h"], "CrpX_g": c["crp"]["x"],
            "CrpY_g": c["crp"]["y"], "CrpRuntime_g": c["crp"]["runtime"],
            "FltWin_g": c["flt"]["win"], "FltBorder_g": c["flt"]["border"], "FltCoefBits_g": c["flt"]["cb"],
            "FltCoef_g": ",".join(str(v) for v in c["flt"]["coef"]), "FltRuntime_g": c["flt"]["runtime"],
            "FltOutBits_g": c["flt"]["ob"], "FltResource_g": c["flt"]["resource"], "FltEcc_g": c["flt"]["ecc"],
            "BinX_g": c["bin"]["x"], "BinY_g": c["bin"]["y"], "BinBorder_g": c["bin"]["border"],
            "BinResource_g": c["bin"]["resource"], "BinEcc_g": c["bin"]["ecc"],
            "P2Bits_g": c["p2"]["bits"], "P2Shift_g": c["p2"]["shift"], "P2Runtime_g": c["p2"]["runtime"],
            "P2Stages_g": c["p2"]["stages"], "GainBits_g": GAIN_BITS}
        if ch.typical:
            base.update({"RplGap_g": c["rpl"]["g"], "RplLat_g": c["rpl"]["lat"], "RplEcc_g": c["rpl"]["ecc"],
                         "P1Bits_g": c["p1"]["bits"], "P1Stages_g": c["p1"]["stages"]})
        for test in c["tests"]:
            rng = rng_for(MODULE, c["name"], test)
            x = Ctx(ch)
            built = BUILDERS[test](rng, x)
            items, expect = built if isinstance(built, tuple) else (built, {})
            folder = Path(out_dir) / MODULE / c["name"]
            files = {k: folder / "{}.{}".format(test, k) for k in ("stim", "exp", "regs", "inj_rpl", "inj_flt",
                                                                   "inj_bin", "modrst", "tim")}
            _out, _annot, extra = write_chain_test(files, items, ch, c["bits"], out_bits)
            vec = pulses(ch, extra, expect.get("ScrubSec", 0))
            if test == "test_input_stream":
                # CHN-FN-03: only the first module reports a malformed input stream
                assert vec[0] > 0 and all(vec[p * KINDS] == 0 for p in range(1, len(ch.names))), vec
            if test == "test_ecc":
                ref = [o[1:4] for o in _out if o[0] == "B"]
                for name in ("replace", "filter2d", "bin"):
                    p = ch.pos(name)
                    assert vec[p * KINDS + 2] > 0 and vec[p * KINDS + 3] > 0, (name, vec)
                    # CHN-FN-01: a double error of the module changes the chain output
                    doubles = [j for j, it in enumerate(items) if it[0] == "J" and it[3] == p and
                               bin(it[2]).count("1") == 2]
                    without = [it for j, it in enumerate(items) if j not in doubles]
                    assert [o[1:4] for o in ch.run(without)[0] if o[0] == "B"] != ref, name
            generics = dict(base)
            generics.update({
                "StimFile_g": files["stim"].as_posix(), "ExpFile_g": files["exp"].as_posix(),
                "RegsFile_g": files["regs"].as_posix(), "InjRplFile_g": files["inj_rpl"].as_posix(),
                "InjFltFile_g": files["inj_flt"].as_posix(), "InjBinFile_g": files["inj_bin"].as_posix(),
                "ModRstFile_g": files["modrst"].as_posix(), "TimFile_g": files["tim"].as_posix(),
                "Seed_g": seed_for(MODULE, c["name"], test), "ScrubAtStart_g": test != "test_ecc",
                "ScrubDedWords_g": expect.get("ScrubDedWords_g", 0),
                "WatchdogUs_g": watchdog_us(files["stim"], files["exp"])})
            if test in ("test_registers", "test_rate", "test_fifo"):
                generics.update({"GapPct_g": 0, "StallPct_g": 0})
            else:
                generics.update({"GapPct_g": c["gap"], "StallPct_g": c["stall"]})
            if test == "test_rate":
                generics.update(rate_values(c))
            if test == "test_fifo":
                generics.update({"FifoDepth_g": fifo_depth(c), "FifoLevel_g": fifo_level(c)})
            if test == "neg_fifo_drain":
                # One cycle of image blanking less than the rule: every further image finds a pixel of the image
                # before in the FIFO (one error of the count); the depth and the largest level as in test_fifo
                generics.update({"FifoDepth_g": fifo_depth(c), "FifoLevel_g": fifo_level(c), "ExpErrors_g": 1,
                                 "GapPct_g": 0, "StallPct_g": 0})
            if test == "neg_fifo_depth":
                # One entry less than the rule: the FIFO holds the source (one error of the held cycles); In_Level
                # reaches the depth, the largest level of the rule
                generics.update({"FifoDepth_g": fifo_depth(c) - 1, "FifoLevel_g": fifo_level(c), "ExpErrors_g": 1,
                                 "GapPct_g": 0, "StallPct_g": 0})
            if test == "neg_seam_dimension":
                p = ch.pos("crop")
                images = 2
                generics.update({"NegSeam_g": p, "ExpErrors_g": 2 * ch.stages[p][5] * images})
            if test == "neg_seam_beat":
                beat, mask, diff = seam_beat_errors(ch, items)
                generics.update({"NegBeat_g": beat, "NegMask_g": mask, "ExpErrors_g": diff})
            if test == "neg_pulse_count":
                vec[0] += 1
                generics.update({"ExpErrors_g": 1})
            generics["ExpPulses_g"] = ",".join(str(v) for v in vec)
            tb.test(test).add_config(name=c["name"], generics=generics)
