# ---------------------------------------------------------------------------------------------------
# Copyright (c) 2026 by Julian Schneider
# Authors: Julian Schneider
# ---------------------------------------------------------------------------------------------------
"""Reference models of the OpenISP modules, written from their specifications, not from the RTL.

Every model takes a list of input items and the generics of the module and returns the expected output items, the
number of error pulses and an annotation per input item:

- ('B', pixel, last, user): one input beat; user is the integer value of the sequence flags (bit 1 = User(1))
- ('R', drop, mode, cycles): a reset of the module; the last `drop` output beats before it are lost
- any other item ('G', 'T', 'H', 'M', 'W', 'P') passes through without effect on the model

Output items: ('B', pixel, last, user, x, y) and ('R', mode). The annotation of an input item is the state after it:
(number of output beats so far, image open).
"""

SEQ_CONT, SEQ_FIRST, SEQ_LAST, SEQ_ONLY = 0, 1, 2, 3


def line_flags(y, height):
    """Sequence flags of output line y of an image of `height` lines (one packet per line)."""
    if height == 1:
        return SEQ_ONLY
    if y == 0:
        return SEQ_FIRST
    if y == height - 1:
        return SEQ_LAST
    return SEQ_CONT


def frame_sync(items, width, height):
    """isp_frame_sync (specification, section 3): the pixel count from the image start decides the end of an image.

    E1: an image start while an image is open completes it with pixels of value 0 (one error).
    E2: pixels while no image is open, other than an image start, are discarded (one error per run).
    E3: pixel W x H - 1 not on the last beat of a packet with the flags "10" or "11" ends the image (one error).
    E4: the last beat of a packet with the flags "10" or "11" before pixel W x H - 1 does not end it (one error).
    """
    total = width * height
    out = []
    annot = []
    errors = 0
    count = 0
    st = {"open": False, "n": 0, "first": True, "run": False}

    def emit(pixel, n):
        nonlocal count
        x, y = n % width, n // width
        out.append(("B", pixel, 1 if x == width - 1 else 0, line_flags(y, height), x, y))
        count += 1

    for it in items:
        if it[0] == "B":
            _, pixel, last, user = it
            start = st["first"] and (user & 1) == 1
            end_flags = last == 1 and (user & 2) == 2
            if st["open"] and start:
                errors += 1                                   # E1
                for n in range(st["n"], total):
                    emit(0, n)
                st["open"] = False
                st["run"] = False
            if st["open"]:
                n = st["n"]
                emit(pixel, n)
                if n == total - 1:
                    if not end_flags:
                        errors += 1                           # E3
                    st["open"] = False
                    st["run"] = False
                else:
                    if end_flags:
                        errors += 1                           # E4
                    st["n"] = n + 1
            elif start:
                st["run"] = False
                emit(pixel, 0)
                if total == 1:
                    if not end_flags:
                        errors += 1                           # E3
                else:
                    if end_flags:
                        errors += 1                           # E4
                    st["open"] = True
                    st["n"] = 1
            elif not st["run"]:
                errors += 1                                   # E2, once per run
                st["run"] = True
            st["first"] = last == 1
        elif it[0] == "R":
            _, drop, mode, _cycles = it
            assert drop <= count, "reset drops more beats than were produced"
            for _ in range(drop):
                assert out[-1][0] == "B", "reset drops beats of an earlier reset"
                out.pop()
                count -= 1
            out.append(("R", mode))
            st = {"open": False, "n": 0, "first": True, "run": False}
        annot.append((count, st["open"]))
    return out, errors, annot
