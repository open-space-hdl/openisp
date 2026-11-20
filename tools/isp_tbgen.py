# ---------------------------------------------------------------------------------------------------
# Copyright (c) 2026 by Julian Schneider
# Authors: Julian Schneider
# ---------------------------------------------------------------------------------------------------
"""Stimulus generation for the OpenISP testbenches (docs/testbench.md).

A test is a list of input items (see tools/isp_model.py): beats ('B', pixel, last, user) and directives
('G', n) pause, ('T', n) wait cycles, ('W',) wait for the sink, ('P',) probe, ('H', 0/1) hold the sink,
('M', n) marker, ('K', n) wait for the acknowledge, ('R', drop, mode, cycles) reset, ('A', marker, entries) register
accesses, ('J', marker, pattern) error injection, ('S', marker, 0 or 1) scrubber enable. `write_test` runs the model
of the module over the items and writes the stimulus file, the expected file and, where the test needs them, the
register script, the injection script and the timing file.
"""

import random
import zlib
from pathlib import Path

from isp_model import SEQ_CONT, SEQ_FIRST, SEQ_LAST, SEQ_ONLY


def rng_for(*names):
    """Random generator with a seed derived from the names (module, configuration, test)."""
    return random.Random(zlib.crc32("/".join(str(n) for n in names).encode()))


def seed_for(*names):
    """Positive seed for the VHDL source and sink."""
    return zlib.crc32("/".join(str(n) for n in names).encode()) % 2_000_000_000 + 1


def hexw(value, bits):
    """Value in hexadecimal with the digits of `bits` bits."""
    return format(value, "0{}x".format((bits + 3) // 4))


def random_image(rng, width, height, bits):
    """Pixels of an image in raster order, random over the full range."""
    return [rng.getrandbits(bits) for _ in range(width * height)]


def packets(pixels, lengths, first=True, last=True):
    """Beats of pixels divided into packets of the given lengths, with the sequence flags of an image: "01" for the
    first packet, "10" for the last, "00" between, "11" for a single packet. `first` / `last` false: the packets are
    the beginning / the end of a longer sequence."""
    assert sum(lengths) == len(pixels), (sum(lengths), len(pixels))
    beats = []
    pos = 0
    count = len(lengths)
    for k, length in enumerate(lengths):
        is_first = first and k == 0
        is_last = last and k == count - 1
        if is_first and is_last:
            flags = SEQ_ONLY
        elif is_first:
            flags = SEQ_FIRST
        elif is_last:
            flags = SEQ_LAST
        else:
            flags = SEQ_CONT
        for j in range(length):
            beats.append(("B", pixels[pos + j], 1 if j == length - 1 else 0, flags))
        pos += length
    return beats


def raw_packet(pixels, flags):
    """One packet with the given flags on every beat."""
    return [("B", p, 1 if j == len(pixels) - 1 else 0, flags) for j, p in enumerate(pixels)]


def split(rng, total, width, mode):
    """Packet lengths for `total` pixels of an image of lines of `width` pixels."""
    if mode == "lines":
        return [width] * (total // width)
    if mode == "one":
        return [total]
    if mode == "pixel":
        return [1] * total
    if mode == "wplus1":
        lengths = [width + 1] * (total // (width + 1))
        if total % (width + 1):
            lengths.append(total % (width + 1))
        return lengths
    if mode == "random":
        lengths = []
        left = total
        while left:
            n = min(left, rng.randint(1, 2 * width + 1))
            lengths.append(n)
            left -= n
        return lengths
    if mode == "line_end":
        lines = total // width
        if lines < 2:
            return [total]
        k = rng.randint(1, lines - 1)
        return [k * width, total - k * width]
    raise ValueError(mode)


def image_beats(rng, width, height, bits, mode):
    """A complete image in the given division into packets."""
    pixels = random_image(rng, width, height, bits)
    return packets(pixels, split(rng, width * height, width, mode))


def watchdog_us(*files):
    """Watchdog of a test in microseconds: 1 ms plus 0.5 us per entry of its files. An entry takes a few cycles of
    10 ns, also with gaps, stalls and pauses, so the margin is more than tenfold (docs/testbench.md, section 6)."""
    entries = sum(len(Path(f).read_text(encoding="ascii").splitlines()) for f in files)
    return 1000 + entries // 2


def write_test(stim_path, exp_path, items, model, data_bits, side=None, regs_path=None, inj_path=None,
               tim_path=None):
    """Runs `model(items)` -> (out, errors, annot[, extra]) and writes the files. Returns a dict with the number of
    framing errors ("errors") and the counts of the extra results of the model ("config", "sec", "ded").
    `side(entry)` formats the sideband of an output beat (hexadecimal), default "0"."""
    res = model(items)
    out, errors, annot = res[0], res[1], res[2]
    extra = res[3] if len(res) > 3 else {}
    stim = []
    for i, it in enumerate(items):
        before = annot[i - 1] if i > 0 else (0, False)
        kind = it[0]
        if kind == "B":
            stim.append("B {} {} {}".format(hexw(it[1], data_bits), it[2], it[3]))
        elif kind in ("G", "T", "H", "M", "K"):
            stim.append("{} {}".format(kind, it[1]))
        elif kind == "W":
            stim.append("W {}".format(before[0]))
        elif kind == "P":
            stim.append("P {}".format(1 if before[1] else 0))
        elif kind == "R":
            _, drop, mode, cycles = it
            stim.append("R {} {} {}".format(before[0] - drop, mode, cycles))
        elif kind in ("A", "J", "S"):
            stim.append("M {}".format(it[1]))
            stim.append("K {}".format(it[1]))
        else:
            raise ValueError(kind)
    exp = []
    for o in out:
        if o[0] == "B":
            exp.append("B {} {} {} {}".format(hexw(o[1], data_bits), o[2], o[3], side(o) if side else "0"))
        else:
            exp.append("R {}".format(o[1]))
    Path(stim_path).parent.mkdir(parents=True, exist_ok=True)
    Path(stim_path).write_text("\n".join(stim) + "\n", encoding="ascii", newline="\n")
    Path(exp_path).write_text("\n".join(exp) + "\n", encoding="ascii", newline="\n")
    result = {"errors": errors}
    result.update({k: v for k, v in extra.items() if k not in ("regs", "timing")})
    if regs_path:
        lines = []
        for marker, entries in extra.get("regs", []):
            for op, addr, data, strobes in entries:
                if op == "W":
                    lines.append("{} W {:x} {:x} {:x}".format(marker, addr, data, strobes))
                else:
                    lines.append("{} C {:x} {:x}".format(marker, addr, data))
        Path(regs_path).write_text("\n".join(lines) + "\n", encoding="ascii", newline="\n")
    if inj_path:
        lines = ["{} {} {:x}".format(it[1], it[0], it[2]) for it in items if it[0] in ("J", "S")]
        Path(inj_path).write_text("\n".join(lines) + "\n", encoding="ascii", newline="\n")
    if tim_path:
        Path(tim_path).write_text("\n".join(str(n) for n in extra["timing"]) + "\n", encoding="ascii",
                                  newline="\n")
    return result


class RegScript:
    """Markers of the register script of a test (docs/testbench.md, section 7), from 100 on."""

    def __init__(self, first=100):
        self.markers = iter(range(first, 1 << 30))

    def access(self, *entries):
        """Register accesses after every pixel sent so far has passed the module: wait for the sink, a pause, then
        the accesses at the next marker."""
        return [("W",), ("T", 8), ("A", next(self.markers), list(entries))]


def write(addr, data, strobes=0xF):
    """A register write of the register script."""
    return ("W", addr, data, strobes)


def check(addr, data=None):
    """A register read of the register script; the model gives the expected data unless the test does."""
    return ("C", addr, data, 0xF)


def status():
    """Wait for the sink, give the module time for discards, probe the status of the source (Stat_ImageOpen)."""
    return [("W",), ("T", 8), ("P",)]


def short_image(rng, width, height, bits, k):
    """The first k pixels of an image, without the last flags (the image is cut)."""
    pix = random_image(rng, width, height, bits)[:k]
    return packets(pix, split(rng, k, width, "random"), last=False)


def open_image(width, height, bits):
    """An image cut after half of its pixels, without its last flags: the image stays open until the next image start
    completes it (E1). The pixels come from a generator of their own, so that the items that follow are those of the
    stream without it. Empty for an image of one pixel."""
    n = width * height
    if n < 2:
        return []
    gen = rng_for("open_image", width, height, bits)
    k = n // 2
    pix = [gen.getrandbits(bits) for _ in range(k)]
    return packets(pix, split(gen, k, width, "random"), last=False)


def open_image_probe(width, height, bits):
    """An open image (open_image) and a probe of the source while it is open: Stat_ImageOpen 1 at the port of the
    module, after every output of its pixels has passed the sink."""
    items = open_image(width, height, bits)
    return items + [("W",), ("T", 8), ("P",)] if items else []


def malformed_streams(rng, width, height, bits, packets_count=60):
    """Malformed input streams for the frame sync of a module: an image cut short and probed while it is open, short
    images completed at the next image start, pixels without an image start, wrong end flags (E3, E4), random packets
    with random flags."""
    n = width * height
    items = open_image_probe(width, height, bits) + image_beats(rng, width, height, bits, "random")
    if n >= 2:
        for k in sorted({1, n // 2, n - 1} - {0}):
            items += short_image(rng, width, height, bits, k) + image_beats(rng, width, height, bits, "random")
            items += status()
    items += raw_packet([rng.getrandbits(bits) for _ in range(3)], SEQ_CONT)
    items += raw_packet([rng.getrandbits(bits) for _ in range(2)], SEQ_LAST)
    items += image_beats(rng, width, height, bits, "lines") + status()
    if n >= 2:
        items += raw_packet([rng.getrandbits(bits) for _ in range(n)], SEQ_FIRST)
        items += raw_packet([rng.getrandbits(bits)], SEQ_ONLY)
        items += raw_packet([rng.getrandbits(bits) for _ in range(n - 1)], SEQ_LAST)
    for _ in range(packets_count):
        if rng.random() < 0.2:
            items += image_beats(rng, width, height, bits, rng.choice(["lines", "one", "random"]))
            continue
        length = rng.randint(1, 2 * n)
        items += raw_packet([rng.getrandbits(bits) for _ in range(length)], rng.randint(0, 3))
    items += image_beats(rng, width, height, bits, "random") + image_beats(rng, width, height, bits, "lines")
    return items + status()

