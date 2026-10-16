#!/usr/bin/env python3
# K5K1 Prog — reference data for the channel editor tests.
#
# Builds synthetic 8 KB memory images for every firmware profile, decodes them with the
# real CHIRP drivers (mainline uvk5.py for stock firmware, Karina's CHIRP modules for
# Karina) and applies a list of channel edits with the drivers' own set_memory(). The
# results are the golden files the Swift tests compare against:
#
#   Tests/Reference/channels/<profile>.bin          synthetic image (no personal data)
#   Tests/Reference/channels/<profile>.json         CHIRP's decode of every channel 1..200
#   Tests/Reference/channels/<profile>.edits.json   the edits (in CHIRP terms)
#   Tests/Reference/channels/<profile>.edited.bin   the image after CHIRP applied them
#
# Usage (CHIRP from source, github.com/kk7ds/chirp, the next-20261009 build or newer):
#   python3 golden.py --chirp <chirp checkout> --karina-v1 <module.py> --karina-k1 <module.py> --out Tests/Reference/channels
#   python3 golden.py ... --decode <dump.bin> --profile karinaV1      # print CHIRP's decode of a real dump
#
# Only needed when the profiles change; the app and the tests do not need Python.

import argparse, importlib.util, json, os, random, struct, sys, types

ap = argparse.ArgumentParser()
ap.add_argument("--chirp", required=True)
ap.add_argument("--karina-v1", required=True)
ap.add_argument("--karina-k1", required=True)
ap.add_argument("--out")
ap.add_argument("--decode")
ap.add_argument("--profile")
args = ap.parse_args()

sys.path.insert(0, args.chirp)
sys.modules["wx"] = types.ModuleType("wx")          # Karina's modules import wx for one dialog
import builtins; builtins._ = lambda s: s           # CHIRP's gettext hook (normally installed by chirpwx)
import logging; logging.disable(logging.WARNING)
from chirp import chirp_common, memmap, directory   # noqa: E402
from chirp.drivers import uvk5                      # noqa: E402


def load_module(path, name):
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    real = directory.register
    directory.register = lambda cls: cls             # same class ids as mainline: don't register
    try:
        spec.loader.exec_module(mod)
    finally:
        directory.register = real
    return mod


kv1 = load_module(args.karina_v1, "karina_v1")
kk1 = load_module(args.karina_k1, "karina_k1")

PROFILES = {
    "stockV1": dict(cls=uvk5.UVK5Radio, mod=uvk5, scr=uvk5.SCRAMBLER_LIST),
    "stockK1": dict(cls=uvk5.UVK1Radio, mod=uvk5, scr=uvk5.SCRAMBLER_LIST),
    "karinaV1": dict(cls=kv1.UVK5RadioEgzumer, mod=kv1, scr=kv1.SCRAMBLER_LIST),
    "karinaK1": dict(cls=kk1.UVK5RadioEgzumer, mod=kk1, scr=kk1.SCRAMBLER_LIST),
}


def radio_for(profile, data):
    return PROFILES[profile]["cls"](memmap.MemoryMapBytes(bytes(data)))


def extra(mem, key):
    try:
        return str(mem.extra[key].value)
    except (KeyError, TypeError, AttributeError):
        return None


def mem_json(mem):
    if mem.empty:
        return {"n": mem.number, "empty": True}
    (tx, rx) = chirp_common.split_tone_encode(mem)
    return {
        "n": mem.number, "empty": False, "name": mem.name, "freq": mem.freq, "offset": mem.offset,
        "duplex": mem.duplex, "tx": [tx[0], tx[1] if tx[0] else None, tx[2] if tx[0] == "DTCS" else None],
        "rx": [rx[0], rx[1] if rx[0] else None, rx[2] if rx[0] == "DTCS" else None],
        "mode": mem.mode, "step": mem.tuning_step, "power": str(mem.power),
        "scrambler": extra(mem, "scrambler"), "scanlists": extra(mem, "scanlists"),
        "busyLock": extra(mem, "bclo") or extra(mem, "busyChLockout"), "reverse": extra(mem, "frev"),
        "pttid": extra(mem, "pttid"), "dtmfDecode": extra(mem, "dtmfdecode"), "compander": extra(mem, "compander"),
    }


def decode(profile, data):
    r = radio_for(profile, data)
    return [mem_json(r.get_memory(n)) for n in range(1, 201)]


# ---- synthetic image -------------------------------------------------------------------

def synthetic(profile, seed):
    """Every channel field in its valid range for the profile, plus edge values."""
    rnd = random.Random(seed)
    img = bytearray(b"\xff" * 0x2000)
    karina = profile.startswith("karina")
    nmodes = 5 if karina else 2       # Karina: modulation nibble 0..2 (FM/AM/USB); stock: enable_am bit
    nsteps = 13 if karina else 6
    nscr = len(PROFILES[profile]["scr"])
    names = ["PMR %d" % i for i in range(1, 9)] + ["LPD-OV", "R0 TBS", "TBS TWR", "NOAA WX1", "MARINE 16", "A", "1234567890", "x-y_z.!"]
    for i in range(200):
        if i % 7 == 3 or i >= 150:          # empty (FF) channels, all slots after 150
            continue
        freq = rnd.choice([rnd.randrange(14400000, 14600000, 125), rnd.randrange(43000000, 44000000, 625),
                           rnd.randrange(11800000, 13700000, 833), rnd.randrange(2600000, 2800000, 100),
                           rnd.randrange(46000000, 47000000, 625)])
        offdir = rnd.choice([0, 0, 1, 2])
        offset = 0 if offdir == 0 else rnd.choice([60000, 760000, 500000])
        if i % 23 == 5:                      # TX off: offset == freq, minus
            offdir, offset = 2, freq
        ch = bytearray(16)
        struct.pack_into("<II", ch, 0, freq, offset)
        txf, rxf = rnd.choice([0, 1, 2, 3]), rnd.choice([0, 0, 1, 2, 3])
        ch[8] = rnd.randrange(0, 50) if rxf == 1 else rnd.randrange(0, 104)
        ch[9] = rnd.randrange(0, 50) if txf == 1 else rnd.randrange(0, 104)
        ch[10] = (txf << 4) | rxf
        if karina:
            mi = rnd.randrange(0, nmodes)
            mod, bw = mi // 2, mi % 2
            if mi == 4:
                bw = rnd.choice([0, 1])
        else:
            mod, bw = rnd.choice([0, 1]), rnd.choice([0, 1])
        ch[11] = (mod << 4) | offdir
        ch[12] = (rnd.choice([0, 1]) << 4) | (rnd.choice([0, 1, 2]) << 2) | (bw << 1) | rnd.choice([0, 0, 1])
        ch[13] = (rnd.randrange(0, 4) << 1) | rnd.choice([0, 1])
        ch[14] = rnd.randrange(0, nsteps) if i % 31 != 7 else nsteps + 2     # one out-of-range step
        ch[15] = rnd.randrange(0, nscr)
        img[i * 16:i * 16 + 16] = ch
        nm = names[i % len(names)].encode("ascii")
        img[0x0F50 + i * 16:0x0F50 + i * 16 + 16] = (nm + (b" " * 10))[:10] + b"\x00" * 6 if i % 2 else nm + b"\x00" * (16 - len(nm))
        img[0x0D60 + i] = (rnd.randrange(0, 4) << 6) | (rnd.randrange(0, 4) << 4) | rnd.randrange(0, 7)
    img[0x0EB0:0x0EC0] = b"WELCOME\x00" + b"\xff" * 8
    img[0x0EC0:0x0ED0] = b"K5K1 PROG\x00\xff\xff\xff\xff\xff\xff"
    return img


def edits_for(profile):
    karina = profile.startswith("karina")
    scr = PROFILES[profile]["scr"]
    e = [
        dict(n=4, op="set", freq=446006250, name="PMR 1", duplex="", offset=0, tx=["", None, None], rx=["", None, None],
             mode="NFM", step=12.5, power="Low", scrambler=scr[0], scanlists="List1" if karina else "1"),
        dict(n=1, op="set", freq=145600000, name="R0 TBS", duplex="-", offset=600000, tx=["Tone", 88.5, None], rx=["", None, None],
             mode="FM", step=12.5, power="High", scrambler=scr[2], scanlists="List1+2" if karina else "1+2"),
        dict(n=2, op="set", freq=438825000, name="R70", duplex="+", offset=7600000, tx=["DTCS", 23, "N"], rx=["DTCS", 23, "R"],
             mode="AM", step=25.0, power="Med", scrambler=scr[0], scanlists="None"),
        dict(n=5, op="delete"),
        dict(n=160, op="set", freq=26965000, name="CB 1", duplex="off", offset=0, tx=["", None, None], rx=["Tone", 67.0, None],
             mode="NAM", step=5.0, power="Low", scrambler=scr[-1], scanlists="List2" if karina else "2"),
    ]
    if karina:
        e.append(dict(n=161, op="set", freq=14200000, name="20M USB", duplex="", offset=0, tx=["", None, None], rx=["", None, None],
                      mode="USB", step=0.01, power="Low", scrambler=scr[0], scanlists="None"))
    return e


def apply_edits(profile, data, edits):
    r = radio_for(profile, data)
    for ed in edits:
        mem = r.get_memory(ed["n"])
        if ed["op"] == "delete":
            mem.empty = True
            r.set_memory(mem)
            continue
        mem.empty = False
        mem.freq, mem.name, mem.duplex, mem.offset = ed["freq"], ed["name"], ed["duplex"], ed["offset"]
        tx, rx = ed["tx"], ed["rx"]
        chirp_common.split_tone_decode(mem, (tx[0], tx[1], tx[2] or "N"), (rx[0], rx[1], rx[2] or "N"))
        mem.mode, mem.tuning_step = ed["mode"], ed["step"]
        mem.power = [p for p in PROFILES[profile]["mod"].UVK5_POWER_LEVELS if str(p) == ed["power"]][0]
        if mem.extra is not None:
            for key, val in (("scrambler", ed["scrambler"]), ("scanlists", ed["scanlists"])):
                try:
                    mem.extra[key].value = val
                except KeyError:
                    pass
        r.set_memory(mem)
    return bytes(r.get_mmap().get_packed())


if args.decode:
    data = open(args.decode, "rb").read()
    data = data + b"\xff" * (0x2000 - len(data))
    print(json.dumps([m for m in decode(args.profile, data) if not m["empty"]], indent=1))
    sys.exit(0)

os.makedirs(args.out, exist_ok=True)
for i, profile in enumerate(PROFILES):
    img = synthetic(profile, 1000 + i)
    ed = edits_for(profile)
    edited = apply_edits(profile, img, ed)
    open(os.path.join(args.out, profile + ".bin"), "wb").write(img[:0x1D00])
    open(os.path.join(args.out, profile + ".edited.bin"), "wb").write(edited[:0x1D00])
    json.dump(decode(profile, img), open(os.path.join(args.out, profile + ".json"), "w"), indent=0)
    json.dump(ed, open(os.path.join(args.out, profile + ".edits.json"), "w"), indent=0)
    print(profile, "ok")
