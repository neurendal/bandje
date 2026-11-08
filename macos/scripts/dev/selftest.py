#!/usr/bin/env python3
"""Live end-to-end tests for Bandje. Stdlib only. Run via scripts/selftest.sh.

Usage: selftest.py [static] [record] [lr] [long] [leaks]
"""
import array
import json
import math
import os
import plistlib
import shutil
import subprocess
import sys
import time
import wave

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
APP = os.path.join(ROOT, "build", "Bandje.app")
SELFTEST_DIR = os.path.expanduser("~/Music/Bandje/selftest")
TMP = os.path.join(ROOT, "build", "selftest-tmp")
FIX = os.path.join(ROOT, "tests", "fixtures")
VOLUME = "0.5"  # never above 1

results = []
skipped = []


def report(name, ok, detail=""):
    results.append((name, ok, detail))
    print(("PASS " if ok else "FAIL ") + name + (": " + detail if detail else ""), flush=True)


def skip(name, reason):
    """Not testable in the current hardware state; goes to OCHTEND.md, not a failure."""
    skipped.append((name, reason))
    print("SKIP " + name + ": " + reason, flush=True)


# The selftests check Dutch transcript texts; run the app in Dutch whatever the system language is.
LANG_ARGS = ["-AppleLanguages", "(nl)"]


def run(cmd, **kw):
    # errors="replace": other processes can put invalid UTF-8 in e.g. `pmset -g assertions`.
    return subprocess.run(cmd, capture_output=True, text=True, errors="replace", **kw)


def lid_closed():
    """The built-in microphone is switched off by macOS while the lid is closed."""
    return '"AppleClamshellState" = Yes' in run(["ioreg", "-r", "-k", "AppleClamshellState", "-d", "1"]).stdout


def staged(name):
    """Copies a fixture to ~/Music/Bandje/selftest/fixtures, which the sandboxed app may read
    (the repo is outside its sandbox). Returns the staged path."""
    dst_dir = os.path.join(SELFTEST_DIR, "fixtures")
    os.makedirs(dst_dir, exist_ok=True)
    dst = os.path.join(dst_dir, name)
    shutil.copyfile(os.path.join(FIX, name), dst)
    return dst


def read_json(name):
    try:
        with open(os.path.join(SELFTEST_DIR, name)) as f:
            return json.load(f)
    except (OSError, ValueError):
        return None


def wav_duration(path):
    with wave.open(path) as w:
        return w.getnframes() / w.getframerate()


def load_mono(path, rate=16000):
    """Converts any audio file to 16-bit mono WAV at `rate` and returns (samples, rate)."""
    os.makedirs(TMP, exist_ok=True)
    out = os.path.join(TMP, os.path.basename(path) + ".wav")
    r = run(["afconvert", "-f", "WAVE", "-d", "LEI16@%d" % rate, "-c", "1", path, out])
    if r.returncode != 0:
        raise RuntimeError("afconvert failed: " + r.stderr)
    data = array.array("h", wav_data(out)[1])
    os.remove(out)
    return data, rate


def wav_data(path):
    """Returns (channels, raw PCM bytes) of a WAV file. Unlike `wave`, this also accepts
    WAVE_FORMAT_EXTENSIBLE, which afconvert writes when the source (AAC) has a channel layout."""
    with open(path, "rb") as f:
        blob = f.read()
    if blob[:4] != b"RIFF" or blob[8:12] != b"WAVE":
        raise RuntimeError("not a WAV file: " + path)
    pos, channels = 12, None
    while pos + 8 <= len(blob):
        cid, size = blob[pos:pos + 4], int.from_bytes(blob[pos + 4:pos + 8], "little")
        body = blob[pos + 8:pos + 8 + size]
        if cid == b"fmt ":
            channels = int.from_bytes(body[2:4], "little")
        elif cid == b"data":
            return channels, body
        pos += 8 + size + (size & 1)
    raise RuntimeError("no data chunk in " + path)


def load_stereo(path, rate=16000):
    """Converts a stereo file to 32-bit stereo WAV at `rate`; returns (left, right, rate) as
    16-bit-scaled floats (so rms_db works on both). 32-bit keeps quiet mic noise above zero."""
    os.makedirs(TMP, exist_ok=True)
    out = os.path.join(TMP, os.path.basename(path) + ".st.wav")
    r = run(["afconvert", "-f", "WAVE", "-d", "LEI32@%d" % rate, "-c", "2", path, out])
    if r.returncode != 0:
        raise RuntimeError("afconvert failed: " + r.stderr)
    channels, raw = wav_data(out)
    if channels != 2:
        raise RuntimeError("expected 2 channels, got %d" % channels)
    data = array.array("i", raw)
    os.remove(out)
    scale = 1.0 / 65536.0
    left = array.array("d", (v * scale for v in data[0::2]))
    right = array.array("d", (v * scale for v in data[1::2]))
    return left, right, rate


def rms_db(samples, rate, start, end):
    a, b = max(0, int(start * rate)), min(len(samples), int(end * rate))
    if b <= a:
        return None
    acc = 0
    for i in range(a, b):
        acc += samples[i] * samples[i]
    rms = math.sqrt(acc / (b - a)) / 32768.0
    return 20 * math.log10(rms) if rms > 0 else -200.0


def fmt(db):
    return "%.1f dBFS" % db if db is not None else "n/a"


def onset(samples, rate, start, threshold_db=-40.0, frame=0.01):
    """Start of the first 10 ms frame after `start` whose RMS exceeds the threshold."""
    n = int(frame * rate)
    i = max(0, int(start * rate))
    while i + n <= len(samples):
        db = rms_db(samples, rate, i / rate, (i + n) / rate)
        if db is not None and db > threshold_db:
            return i / rate
        i += n
    return None


def start_recording(seconds, extra=()):
    state = os.path.join(SELFTEST_DIR, "state.json")
    if os.path.exists(state):
        os.remove(state)
    proc = subprocess.Popen(["open", "-W", "-n", APP, "--args", *LANG_ARGS, "--selftest-record", str(seconds), *extra])
    deadline = time.time() + 30
    while time.time() < deadline:
        s = read_json("state.json")
        if s and s.get("state") in ("recording", "done"):
            return proc, s
        time.sleep(0.1)
    return proc, None


def play(name):
    t = time.time()
    subprocess.run(["afplay", "-v", VOLUME, os.path.join(FIX, name)], check=True)
    return t


def no_network(pid):
    r = run(["lsof", "-i", "-a", "-p", str(pid)])
    return r.stdout.strip() == ""


def afinfo(path):
    """Returns (format line, estimated duration) from afinfo."""
    out = run(["afinfo", path]).stdout
    fmt_line, dur = "", None
    for line in out.splitlines():
        if line.startswith("Data format:"):
            fmt_line = line
        if "estimated duration" in line:
            dur = float(line.split(":")[1].split()[0])
    return fmt_line, dur


def check_m4a(name, last):
    """M3: after stop the .caf is converted to AAC 48 kHz stereo .m4a and removed."""
    path = last.get("path", "")
    f, dur = afinfo(path)
    ok = path.endswith(".m4a") and "aac" in f and "2 ch" in f and "48000 Hz" in f
    report(name + ": .m4a is AAC, 2 ch, 48 kHz", ok, "%s | %s" % (os.path.basename(path), f.strip()))
    caf = last.get("cafPath", "")
    report(name + ": .caf removed after conversion", bool(last.get("cafRemoved")) and not os.path.exists(caf), caf)
    wall = last.get("stoppedAt", 0) - last.get("startedAt", 0)
    report(name + ": .m4a duration within 1 s of wall clock", dur is not None and abs(dur - wall) < 1.0,
           "m4a %s s, wall %.2f s, convert %.2f s" % (dur, wall, last.get("convertSeconds", -1)))


def test_outputdir():
    """The `outputDir` default, set inside the sandboxed app (its container preferences domain,
    see PROGRESS M3: `defaults write com.neurendal.bandje` from Terminal does not reach it).
    A path under ~/Music is writable, a path outside it is refused by the sandbox."""
    default = os.path.expanduser("~/Music/Bandje")
    inside = os.path.join(SELFTEST_DIR, "custom-outputdir")
    outside = os.path.join(ROOT, "build", "outputdir-outside-music")
    cases = [("~/Music/Bandje/selftest/custom-outputdir", inside, True),
             (outside, outside, False)]
    for value, expected, writable in cases:
        proc, state = start_recording(1, ["--selftest-output-dir", value])
        proc.wait()
        last = read_json("last.json") or {}
        report("outputdir: %s resolved" % value, last.get("outputDir") == expected, str(last.get("outputDir")))
        report("outputdir: %s writable=%s" % (value, writable), last.get("outputDirWritable") == writable,
               str(last.get("outputDirWritable")))
    report("outputdir: sandbox did not create dir outside ~/Music", not os.path.exists(outside), outside)
    proc, state = start_recording(1)
    proc.wait()
    last = read_json("last.json") or {}
    report("outputdir: default when unset", last.get("outputDir") == default, str(last.get("outputDir")))


# ---------------------------------------------------------------------------

def test_static():
    ent = run(["codesign", "-d", "--entitlements", "-", "--xml", APP]).stdout
    report("entitlements: sandbox on", "com.apple.security.app-sandbox" in ent)
    report("entitlements: never network.server", "com.apple.security.network.server" not in ent)
    report("entitlements: network.client (only for the SDK license check)", "com.apple.security.network.client" in ent)
    report("entitlements: no screen capture", "screen-capture" not in ent.lower())
    with open(os.path.join(APP, "Contents", "Info.plist"), "rb") as f:
        info = plistlib.load(f)
    keys = [k for k in info if "Screen" in k]
    report("Info.plist: no screen-capture keys", not keys, ", ".join(keys))
    report("Info.plist: NSAudioCaptureUsageDescription", "NSAudioCaptureUsageDescription" in info)
    libs = run(["otool", "-L", os.path.join(APP, "Contents", "MacOS", "Bandje")]).stdout
    report("not linked: ScreenCaptureKit", "ScreenCaptureKit" not in libs)


def test_record():
    """Real microphone + system audio: fixture played via afplay must be on R, silence around
    it on R, and the microphone must deliver samples on L."""
    fixture = "nl_xander.wav"
    dur = wav_duration(os.path.join(FIX, fixture))
    lead, tail = 2.0, 3.0
    proc, state = start_recording(lead + dur + tail)
    if not state or state.get("state") != "recording":
        proc.wait()
        report("record: started", False, json.dumps(read_json("last.json")))
        return
    pid = state["pid"]
    time.sleep(lead)
    report("record: no network sockets during recording", no_network(pid))
    # M4: sleep prevention (replaces "20 minutes without input: Mac does not sleep").
    pm = run(["pmset", "-g", "assertions"]).stdout
    lines = [l.strip() for l in pm.splitlines() if "Bandje neemt op" in l]
    report("record: pmset shows PreventUserIdleSystemSleep 'Bandje neemt op'",
           any("PreventUserIdleSystemSleep" in l for l in lines), " | ".join(lines)[:300])
    t_play = play(fixture)
    proc.wait()
    last = read_json("last.json") or {}
    errs = last.get("errors", ["no last.json"])
    report("record: no errors", not errs, "; ".join(errs))
    report("record: ran sandboxed", bool(last.get("sandboxed")))
    if errs:
        return
    report("record: no dropped samples", last.get("droppedSamples") == 0, str(last.get("droppedSamples")))
    req = last.get("requestedSeconds", 0)
    wall = last.get("stoppedAt", 0) - last.get("startedAt", 0)
    report("record: recording length within 0.5 s of requested (no App Nap stretch)", abs(wall - req) < 0.5,
           "requested %.2f s, wall %.2f s" % (req, wall))
    check_m4a("record", last)
    report("record: global hotkey registered", last.get("hotkeyStatus") == 0, str(last.get("hotkeyStatus")))
    left, right, rate = load_stereo(last["path"])
    file_dur = len(right) / rate
    expected = last["stoppedAt"] - last["startedAt"]
    report("record: file duration", abs(file_dur - expected) < 1.0, "file %.2fs, wall %.2fs" % (file_dur, expected))
    off = t_play - last["startedAt"]
    inside = rms_db(right, rate, off + 0.3, off + dur - 0.3)
    before = rms_db(right, rate, 0.3, off - 0.3)
    after = rms_db(right, rate, off + dur + 0.7, file_dur - 0.3)
    report("record: R RMS in playback window > -45 dBFS", inside is not None and inside > -45, fmt(inside))
    report("record: R RMS before playback < -60 dBFS", before is not None and before < -60, fmt(before))
    report("record: R RMS after playback < -60 dBFS", after is not None and after < -60, fmt(after))
    mic_all = rms_db(left, rate, 0.3, file_dur - 0.3)
    mic_play = rms_db(left, rate, off + 0.3, off + dur - 0.3)
    mic_ok = mic_all is not None and mic_all > -150 and last.get("micPeak", 0) > 0
    mic_detail = "L %s overall, %s during playback (speaker->mic), mic '%s'" % (
        fmt(mic_all), fmt(mic_play), last.get("micName"))
    if not mic_ok and lid_closed() and "MacBook" in last.get("micName", ""):
        skip("record: L (real mic) delivers samples", "lid closed, built-in mic is off; " + mic_detail)
    else:
        report("record: L (real mic) delivers samples, not digital silence", mic_ok, mic_detail)
    print("  sampleRate %s, layout %s, callbacks %s, tap peak %.3f, mic peak %.3f, startDelay %.2fs, file %s" % (
        last.get("sampleRate"), last.get("bufferLayout"), last.get("callbacks"), last.get("peak", 0),
        last.get("micPeak", 0), last.get("startDelay", -1), last["path"]))


def test_lr():
    """Fake mic plays fixture A (must land on L only), afplay plays fixture B afterwards
    (must land on R only). Crosstalk below -30 dB both ways."""
    fa, fb = "nl_xander.wav", "nl_ellen.wav"
    da, db = wav_duration(os.path.join(FIX, fa)), wav_duration(os.path.join(FIX, fb))
    gap, tail = 1.0, 2.0
    proc, state = start_recording(da + gap + db + tail, ["--selftest-fake-mic", staged(fa)])
    if not state or state.get("state") != "recording":
        proc.wait()
        report("lr: started", False, json.dumps(read_json("last.json")))
        return
    wait_until = state["startedAt"] + da + gap
    time.sleep(max(0, wait_until - time.time()))
    t_play = play(fb)
    proc.wait()
    last = read_json("last.json") or {}
    errs = last.get("errors", ["no last.json"])
    report("lr: no errors", not errs, "; ".join(errs))
    if errs:
        return
    report("lr: no dropped samples", last.get("droppedSamples") == 0, str(last.get("droppedSamples")))
    left, right, rate = load_stereo(last["path"])
    a0, a1 = 0.3, da - 0.3
    off = t_play - last["startedAt"]
    b0, b1 = off + 0.3, off + db - 0.3
    la, ra = rms_db(left, rate, a0, a1), rms_db(right, rate, a0, a1)
    lb, rb = rms_db(left, rate, b0, b1), rms_db(right, rate, b0, b1)
    report("lr: fake mic A on L > -45 dBFS", la > -45, fmt(la))
    report("lr: A not on R (R < -60 dBFS)", ra < -60, fmt(ra))
    report("lr: crosstalk A L->R < -30 dB", ra - la < -30, "%.1f dB" % (ra - la))
    report("lr: afplay B on R > -45 dBFS", rb > -45, fmt(rb))
    report("lr: B not on L (L < -60 dBFS)", lb < -60, fmt(lb))
    report("lr: crosstalk B R->L < -30 dB", lb - rb < -30, "%.1f dB" % (lb - rb))
    o = onset(left, rate, 0.0)
    exp = onset(load_mono(os.path.join(FIX, fa), rate)[0], rate, 0.0)
    report("lr: fake mic starts at file start (onset within 20 ms)", o is not None and exp is not None and abs(o - exp) <= 0.02,
           "file %.3fs, fixture %.3fs" % (o or -1, exp or -1))
    print("  layout %s, sampleRate %s, mic '%s', file %s" % (last.get("bufferLayout"), last.get("sampleRate"),
                                                          last.get("micName"), last["path"]))


def test_long(seconds=600):
    """Long recording with the microphone as clock: fake mic fixture at the start on L,
    afplay fixture at start and end on R; file duration and R marker timing vs wall clock."""
    fa, fixture = "nl_xander.wav", "nl_ellen.wav"
    da = wav_duration(os.path.join(FIX, fa))
    dur = wav_duration(os.path.join(FIX, fixture))
    proc, state = start_recording(seconds, ["--selftest-fake-mic", staged(fa)])
    if not state or state.get("state") != "recording":
        proc.wait()
        report("long: started", False)
        return
    started = state["startedAt"]
    time.sleep(max(0, started + da + 1.0 - time.time()))
    t1 = play(fixture)
    end_at = started + seconds - dur - 3
    while time.time() < end_at:
        time.sleep(min(10, max(0.05, end_at - time.time())))
    t2 = play(fixture)
    proc.wait()
    last = read_json("last.json") or {}
    errs = last.get("errors", ["no last.json"])
    report("long: no errors", not errs, "; ".join(errs))
    if errs:
        return
    report("long: no dropped samples", last.get("droppedSamples") == 0, str(last.get("droppedSamples")))
    check_m4a("long", last)
    info = run(["afinfo", last["path"]]).stdout
    afinfo_dur = None
    for line in info.splitlines():
        if "estimated duration" in line:
            afinfo_dur = float(line.split(":")[1].split()[0])
    wall = last["stoppedAt"] - last["startedAt"]
    report("long: afinfo duration within 1 s of wall clock", afinfo_dur is not None and abs(afinfo_dur - wall) < 1.0,
           "afinfo %s s, wall %.2f s" % (afinfo_dur, wall))
    left, right, rate = load_stereo(last["path"], rate=8000)
    o1 = onset(right, rate, t1 - started - 1.0)
    o2 = onset(right, rate, t2 - started - 1.0)
    if o1 is None or o2 is None:
        report("long: R markers found", False, "%s %s" % (o1, o2))
        return
    drift = (o2 - o1) - (t2 - t1)
    report("long: R end marker within 50 ms", abs(drift) <= 0.05, "drift %+.1f ms over %.0f s" % (drift * 1000, t2 - t1))
    la = rms_db(left, rate, 0.3, da - 0.3)
    lend = rms_db(left, rate, o2, o2 + dur - 0.3)
    report("long: L marker at start, L silent at end marker", la > -45 and lend < -60,
           "L start %s, L at end %s" % (fmt(la), fmt(lend)))


def test_rebuild():
    """M4 microphone switch (replaces "AirPods on/off during recording"): the capture is rebuilt
    twice while recording, first as if no input device is left (output device as clock), then
    back to the microphone; the same code path the default-input listener uses. The file must
    continue, gaps filled with silence: markers played via afplay before, between and after
    the rebuilds land on R at their wall-clock offsets."""
    fixture = "nl_ellen.wav"
    d = wav_duration(os.path.join(FIX, fixture))
    t1, r1 = 1.0, 1.0 + d + 0.7
    t2 = r1 + 1.0
    r2 = t2 + d + 0.7
    t3 = r2 + 1.0
    total = t3 + d + 2.0
    proc, state = start_recording(total, ["--selftest-fake-mic", staged("nl_xander.wav"),
                                          "--selftest-rebuild", "%.2f:nomic,%.2f:mic" % (r1, r2)])
    if not state or state.get("state") != "recording":
        proc.wait()
        report("rebuild: started", False, json.dumps(read_json("last.json")))
        return
    started = state["startedAt"]
    plays = []
    for t in (t1, t2, t3):
        time.sleep(max(0, started + t - time.time()))
        plays.append(play(fixture))
    proc.wait()
    last = read_json("last.json") or {}
    errs = last.get("errors", ["no last.json"])
    report("rebuild: no errors", not errs, "; ".join(errs))
    if errs:
        return
    rb = last.get("rebuilds", [])
    report("rebuild: two rebuilds done", len(rb) == 2, json.dumps(rb))
    if len(rb) == 2:
        report("rebuild: no-mic capture has only the tap buffer, then mic again",
               rb[0].get("mic") == "" and len(rb[0].get("layout", [])) >= 1 and rb[1].get("mic") != ""
               and len(rb[1].get("layout", [])) >= 2,
               "1: %s %s Hz %s, 2: '%s' %s Hz %s" % (rb[0].get("mic") or "(geen mic)", rb[0].get("sampleRate"),
                                                     rb[0].get("layout"), rb[1].get("mic"), rb[1].get("sampleRate"),
                                                     rb[1].get("layout")))
    gap_s = last.get("gapFrames", 0) / max(last.get("sampleRate", 48000), 1)
    report("rebuild: gaps filled with silence", last.get("gapFrames", 0) > 0,
           "%d frames (%.0f ms), rebuild times %s" % (last.get("gapFrames", 0), gap_s * 1000,
                                                     ", ".join("%.0f ms" % (r.get("seconds", 0) * 1000) for r in rb)))
    report("rebuild: no dropped samples", last.get("droppedSamples") == 0, str(last.get("droppedSamples")))
    check_m4a("rebuild", last)
    left, right, rate = load_stereo(last["path"], rate=8000)
    onsets = [onset(right, rate, p - started - 0.5) for p in plays]
    if None in onsets:
        report("rebuild: R markers found", False, str(onsets))
        return
    base = onsets[0] - (plays[0] - started)
    errs_ms = [((o - (p - started)) - base) * 1000 for o, p in zip(onsets, plays)]
    # With the output device as clock the tap timestamps carry another device latency
    # (measured -50..-60 ms on built-in speakers); back on the microphone it must be within 50 ms.
    detail = "offsets vs first marker: %s ms" % ", ".join("%+.0f" % e for e in errs_ms)
    report("rebuild: marker in no-mic phase within 100 ms of wall clock", abs(errs_ms[1]) <= 100, detail)
    report("rebuild: marker after switching back to the mic within 50 ms of wall clock", abs(errs_ms[2]) <= 50, detail)
    rms = [rms_db(right, rate, o + 0.3, o + d - 0.3) for o in onsets]
    report("rebuild: R level of each marker > -45 dBFS", all(r is not None and r > -45 for r in rms),
           ", ".join(fmt(r) for r in rms))
    print("  rebuilds %s, file %s" % (json.dumps(rb), last["path"]))


def test_kill():
    """M4 crash recovery (replaces "force quit during recording, restart: message and usable
    file"): SIGKILL after 5 s, then the .caf must be readable up to (almost) the kill moment,
    and the app's recovery path converts it to .m4a and removes the .caf."""
    for f in os.listdir(SELFTEST_DIR):
        if f.endswith(".caf"):
            os.remove(os.path.join(SELFTEST_DIR, f))  # only the file of this test may be recovered
    kill_after = 5.0
    proc, state = start_recording(30, ["--selftest-kill-after", str(kill_after)])
    if not state or state.get("state") != "recording":
        proc.wait()
        report("kill: started", False, json.dumps(read_json("last.json")))
        return
    caf = state["path"]
    time.sleep(1.0)
    t_play = play("nl_xander.wav")  # 1 s .. ~5 s; the kill comes during or just after it
    proc.wait()
    alive = run(["pgrep", "-f", "Bandje.app/Contents/MacOS/Bandje"]).stdout.strip()
    report("kill: process is gone", alive == "", alive)
    f, dur = afinfo(caf)
    report("kill: .caf left behind and readable", os.path.exists(caf) and dur is not None and "2 ch" in f,
           "%s | %s | %s s" % (os.path.basename(caf), f.strip(), dur))
    report("kill: .caf holds audio up to the kill (within 0.5 s)", dur is not None and kill_after - 0.5 <= dur <= kill_after + 0.3,
           "%s s, kill after %.1f s" % (dur, kill_after))
    r = subprocess.run(["open", "-W", "-n", APP, "--args", *LANG_ARGS, "--selftest-recover"])
    last = read_json("last.json") or {}
    conv = last.get("converted", [])
    report("kill: recovery converted the .caf", r.returncode == 0 and not last.get("errors") and len(conv) == 1
           and conv[0].get("caf") == caf, json.dumps(last)[:300])
    if len(conv) != 1:
        return
    m4a = conv[0]["m4a"]
    mf, mdur = afinfo(m4a)
    report("kill: recovered .m4a is AAC 2 ch 48 kHz, .caf removed",
           "aac" in mf and "2 ch" in mf and "48000 Hz" in mf and not os.path.exists(caf), mf.strip())
    report("kill: recovered .m4a duration matches .caf", mdur is not None and dur is not None and abs(mdur - dur) < 0.1,
           "m4a %s s, caf %s s" % (mdur, dur))
    left, right, rate = load_stereo(m4a)
    off = t_play - state["startedAt"]
    inside = rms_db(right, rate, off + 0.3, min(off + 3.0, (mdur or 0) - 0.1))
    report("kill: recovered audio has the marker on R > -45 dBFS", inside is not None and inside > -45, fmt(inside))


def test_diskfull():
    """M4 disk-space messages, simulated by raising the thresholds above the real free space:
    (1) start refused with a message, (2) a running recording stops with a message and what
    was recorded so far is kept as .m4a."""
    proc, state = start_recording(5, ["--selftest-min-free-start-mb", "1000000000"])
    proc.wait()
    last = read_json("last.json") or {}
    errs = last.get("errors", [])
    report("diskfull: start refused with message", any("Te weinig schijfruimte" in e for e in errs), "; ".join(errs))
    report("diskfull: no file when start was refused", not os.path.exists(last.get("path", "/nonexistent")),
           last.get("path", ""))
    proc, state = start_recording(20, ["--selftest-min-free-mb", "1000000000"])
    proc.wait()
    last = read_json("last.json") or {}
    why = last.get("stoppedBecause", "")
    report("diskfull: running recording stopped with message", "schijf is bijna vol" in why, why)
    wall = last.get("stoppedAt", 0) - last.get("startedAt", 0)
    report("diskfull: stopped at the first check, not after 20 s", 0 <= wall < 2.0, "%.2f s" % wall)
    f, dur = afinfo(last.get("path", ""))
    report("diskfull: recording so far kept as .m4a", not last.get("errors") and "aac" in f, "%s | %s s" % (f.strip(), dur))


# --- M5: transcription ------------------------------------------------------

def words_of(text):
    out = []
    for w in text.lower().split():
        w = "".join(ch for ch in w if ch.isalnum())
        if w:
            out.append(w)
    return out


def wer(ref, hyp):
    """Word error rate (Levenshtein on normalised words)."""
    r, h = words_of(ref), words_of(hyp)
    d = list(range(len(h) + 1))
    for i in range(1, len(r) + 1):
        prev, d[0] = d[0], i
        for j in range(1, len(h) + 1):
            cur = min(d[j] + 1, d[j - 1] + 1, prev + (r[i - 1] != h[j - 1]))
            prev, d[j] = d[j], cur
    return d[len(h)] / max(1, len(r))


def fixture_text(name):
    with open(os.path.join(FIX, name.replace(".wav", ".txt"))) as f:
        return f.read().strip()


def read_pcm16_mono(path):
    with wave.open(path) as w:
        assert w.getnchannels() == 1 and w.getsampwidth() == 2
        return array.array("h", w.readframes(w.getnframes())), w.getframerate()


def make_stereo(name, left_parts, right_parts, total):
    """Writes a 48 kHz 16-bit stereo WAV to the staged fixture folder. Parts are
    (fixture, start seconds, gain)."""
    rate = 48000
    n = int(total * rate)
    ch = [array.array("d", bytes(8 * n)), array.array("d", bytes(8 * n))]
    for c, parts in ((0, left_parts), (1, right_parts)):
        for fixture, start, gain in parts:
            data, r = read_pcm16_mono(os.path.join(FIX, fixture))
            assert r == rate
            o = int(start * rate)
            for i, v in enumerate(data):
                if o + i < n:
                    ch[c][o + i] += v * gain
    out = array.array("h", bytes(4 * n))
    for i in range(n):
        out[2 * i] = max(-32768, min(32767, int(ch[0][i])))
        out[2 * i + 1] = max(-32768, min(32767, int(ch[1][i])))
    d = os.path.join(SELFTEST_DIR, "fixtures")
    os.makedirs(d, exist_ok=True)
    path = os.path.join(d, name)
    with wave.open(path, "wb") as w:
        w.setnchannels(2)
        w.setsampwidth(2)
        w.setframerate(rate)
        w.writeframes(out.tobytes())
    return path


def run_transcribe(audio, extra=()):
    """Runs --selftest-transcribe; polls lsof on the app while it works. Returns (last, sockets_seen)."""
    state = os.path.join(SELFTEST_DIR, "state.json")
    if os.path.exists(state):
        os.remove(state)
    for ext in (".md", ".json"):
        p = os.path.splitext(audio)[0] + ext
        if os.path.exists(p):
            os.remove(p)
    proc = subprocess.Popen(["open", "-W", "-n", APP, "--args", *LANG_ARGS, "--selftest-transcribe", audio, *extra])
    sockets, polls = False, 0
    while proc.poll() is None:
        s = read_json("state.json")
        if s and s.get("state") == "transcribing":
            polls += 1
            if not no_network(s["pid"]):
                sockets = True
        time.sleep(0.5)
    return read_json("last.json") or {}, sockets, polls


def text_of(last, speaker):
    return " ".join(s["text"] for s in last.get("segments", []) if s["speaker"] == speaker)


def check_transcript(name, last, sockets, polls, left_fixture, right_fixture, max_wer=0.25):
    errs = last.get("errors", ["no last.json"])
    report(name + ": no errors", not errs, "; ".join(errs))
    if errs:
        return None
    report(name + ": ran sandboxed", bool(last.get("sandboxed")))
    # The SDK may check its license while transcribing (network.client): a note, not a failure.
    print("note %s: network sockets while transcribing: %s (%d polls; only the SDK license check may use the network)"
          % (name, "yes" if sockets else "no", polls))
    md, js = last.get("md", ""), last.get("json", "")
    report(name + ": .md and .json written next to the audio", os.path.exists(md) and os.path.exists(js), md)
    w_l = wer(fixture_text(left_fixture), text_of(last, "Ik"))
    w_r = wer(fixture_text(right_fixture), text_of(last, "Andere kant"))
    report(name + ": WER L (Ik) < %d%%" % (max_wer * 100), w_l < max_wer, "%.1f%%: %s" % (w_l * 100, text_of(last, "Ik")))
    report(name + ": WER R (Andere kant) < %d%%" % (max_wer * 100), w_r < max_wer,
           "%.1f%%: %s" % (w_r * 100, text_of(last, "Andere kant")))
    speakers = [s["speaker"] for s in last.get("segments", [])]
    first_other = speakers.index("Andere kant") if "Andere kant" in speakers else len(speakers)
    order_ok = speakers and speakers[0] == "Ik" and "Ik" not in speakers[first_other:] and first_other < len(speakers)
    report(name + ": labels in order (Ik first, then Andere kant)", bool(order_ok), " ".join(speakers))
    st = last.get("statusUpdates", {})
    report(name + ": progress reported 0..1, monotonic", st.get("count", 0) >= 2 and st.get("last") == 1 and st.get("monotonic"),
           json.dumps(st))
    print("  load %.1f s, total %.1f s for %.1f s audio, crosstalk removed %s, Who on R: %s, mode %s" % (
        last.get("loadSeconds", -1), last.get("seconds", -1), last.get("duration", -1), last.get("crosstalkRemoved"),
        last.get("whoRaw"), last.get("transcriptMode")))
    return w_l, w_r


def test_nomodels():
    """M5 'model folder renamed': an empty model folder gives the Dutch message, no crash, no download."""
    empty = os.path.join(SELFTEST_DIR, "no-models")
    os.makedirs(empty, exist_ok=True)
    audio = make_stereo("nomodels.wav", [("nl_xander.wav", 0.2, 1.0)], [], 8.0)
    t0 = time.time()
    last, sockets, _ = run_transcribe(audio, ["--selftest-model-dir", empty])
    errs = last.get("errors", [])
    report("nomodels: message tells to run fetch-models.sh", any("fetch-models.sh" in e for e in errs), "; ".join(errs))
    report("nomodels: app finished normally (no crash), quickly", last.get("mode") == "selftest-transcribe" and time.time() - t0 < 30,
           "%.1f s" % (time.time() - t0))
    report("nomodels: nothing written to the empty model folder (no download attempt)", os.listdir(empty) == [], str(os.listdir(empty)))
    report("nomodels: no transcript written", not os.path.exists(os.path.splitext(audio)[0] + ".md"))
    report("nomodels: no network sockets", not sockets)


def test_transcribe():
    """M5 'Dutch test call with headphones', end to end: a real recording (fake mic Xander on L,
    afplay Ellen on R) through --selftest-record, then the app's transcription on the .m4a."""
    fa, fb = "nl_xander.wav", "nl_ellen.wav"
    da, db = wav_duration(os.path.join(FIX, fa)), wav_duration(os.path.join(FIX, fb))
    gap, tail = 1.0, 2.0
    proc, state = start_recording(da + gap + db + tail, ["--selftest-fake-mic", staged(fa)])
    if not state or state.get("state") != "recording":
        proc.wait()
        report("transcribe: recording started", False, json.dumps(read_json("last.json")))
        return
    time.sleep(max(0, state["startedAt"] + da + gap - time.time()))
    play(fb)
    proc.wait()
    rec = read_json("last.json") or {}
    if rec.get("errors") or not rec.get("path", "").endswith(".m4a"):
        report("transcribe: recording ok", False, json.dumps(rec)[:300])
        return
    last, sockets, polls = run_transcribe(rec["path"])
    check_transcript("transcribe (NL, recorded)", last, sockets, polls, fa, fb)
    if os.path.exists(last.get("md", "")):
        with open(last["md"]) as f:
            md = f.read()
        print("  --- %s ---\n%s  ---" % (os.path.basename(last["md"]), md))
        # The iPhone's layout: title, 📼 line, "Opgenomen met Band·je · band.je", a rule.
        report("transcribe: .md has the title, the 📼 line and 'Opgenomen met Band·je', then a rule",
               md.startswith("# ") and "\n📼 " in md and "Opgenomen met Band·je · band.je" in md and "\n---\n" in md,
               "\n".join(md.splitlines()[:5]))


def test_crosstalk():
    """M5 'without headphones': L carries the other side at -12 dB while R speaks, plus my own
    speech. Without the filter Ellen's words would appear twice; with it, once."""
    fa, fb = "nl_xander.wav", "nl_ellen.wav"
    da, db = wav_duration(os.path.join(FIX, fa)), wav_duration(os.path.join(FIX, fb))
    start_b = da + 1.0
    audio = make_stereo("crosstalk.wav", [(fa, 0.3, 1.0), (fb, start_b, 0.25)], [(fb, start_b, 1.0)], start_b + db + 1.5)
    last, sockets, polls = run_transcribe(audio)
    res = check_transcript("crosstalk", last, sockets, polls, fa, fb)
    removed = last.get("crosstalkRemoved", 0)
    report("crosstalk: leaked segments removed (L copy of R at -12 dB)", removed >= 1, "%s removed" % removed)
    ellen_only = set(words_of(fixture_text(fb))) - set(words_of(fixture_text(fa)))

    def leaked(l):
        return [w for w in words_of(text_of(l, "Ik")) if w in ellen_only]
    report("crosstalk: none of Ellen's words left under Ik", not leaked(last), " ".join(leaked(last)))
    # Same file with the filter effectively off, for comparison (for comparison in the report).
    last2, _, _ = run_transcribe(audio, ["--selftest-crosstalk-db", "1000"])
    print("  without filter: %d of Ellen's words under Ik (of %d), WER Ik vs Xander %.0f%%" % (
        len(leaked(last2)), len(words_of(fixture_text(fb))), wer(fixture_text(fa), text_of(last2, "Ik")) * 100))
    # And with the real default again: the override must not stick (it lives in the app's preferences).
    last3, _, _ = run_transcribe(audio)
    report("crosstalk: settings back to default after an override run", last3.get("crosstalkSettings", {}).get("db") == 6
           and last3.get("crosstalkRemoved", 0) >= 1, json.dumps(last3.get("crosstalkSettings")))


def test_english():
    """M5 'English call': synthetic stereo, Samantha on L, Daniel on R."""
    fa, fb = "en_samantha.wav", "en_daniel.wav"
    da, db = wav_duration(os.path.join(FIX, fa)), wav_duration(os.path.join(FIX, fb))
    audio = make_stereo("english.wav", [(fa, 0.3, 1.0)], [(fb, da + 1.0, 1.0)], da + db + 2.5)
    last, sockets, polls = run_transcribe(audio)
    check_transcript("english", last, sockets, polls, fa, fb)


# --- M6: speakers (Who), import, recording during transcription -------------

def alternating(voices=("nl_xander.wav", "nl_ellen.wav"), turns=4, gap=0.7, lead=0.3):
    """Placements (fixture, start, gain) with the two voices taking turns, and the total length."""
    parts, t = [], lead
    for i in range(turns):
        f = voices[i % 2]
        parts.append((f, t, 1.0))
        t += wav_duration(os.path.join(FIX, f)) + gap
    return parts, t + 1.0


def write_mono(name, parts, total):
    """48 kHz 16-bit mono WAV in the staged fixture folder (a 'voice memo')."""
    rate = 48000
    n = int(total * rate)
    acc = array.array("d", bytes(8 * n))
    for fixture, start, gain in parts:
        data, r = read_pcm16_mono(os.path.join(FIX, fixture))
        assert r == rate
        o = int(start * rate)
        for i, v in enumerate(data):
            if o + i < n:
                acc[o + i] += v * gain
    out = array.array("h", (max(-32768, min(32767, int(v))) for v in acc))
    d = os.path.join(SELFTEST_DIR, "fixtures")
    os.makedirs(d, exist_ok=True)
    path = os.path.join(d, name)
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(rate)
        w.writeframes(out.tobytes())
    return path


def speaker_score(segments, parts):
    """Share of words whose label matches the voice actually speaking at that moment, with each
    label mapped to the voice it mostly covers. Returns (score, mapping, words counted)."""
    windows = [(f, s, s + wav_duration(os.path.join(FIX, f))) for f, s, _ in parts]
    pairs = []
    for seg in segments:
        for w in seg.get("words", []):
            mid = (w["start"] + w["end"]) / 2
            voice = next((f for f, a, b in windows if a - 0.3 <= mid <= b + 0.3), None)
            pairs.append((seg["speaker"], voice))
    counts = {}
    for label, voice in pairs:
        counts.setdefault(label, {}).setdefault(voice, 0)
        counts[label][voice] += 1
    mapping = {label: max(c, key=c.get) for label, c in counts.items()}
    correct = sum(1 for label, voice in pairs if voice is not None and mapping[label] == voice)
    return correct / max(1, len(pairs)), mapping, len(pairs)


def check_speakers(name, last, parts, labels_prefix="Spreker "):
    segs = [s for s in last.get("segments", []) if s["speaker"].startswith(labels_prefix)]
    labels = sorted(set(s["speaker"] for s in segs))
    report(name + ": Who found 2 speakers", last.get("speakerCount") == 2 and labels == ["Spreker 1", "Spreker 2"],
           "speakerCount %s, labels %s" % (last.get("speakerCount"), labels))
    score, mapping, n = speaker_score(segs, parts)
    report(name + ": >= 80% of words labelled with the right speaker", score >= 0.8 and len(set(mapping.values())) == 2,
           "%.1f%% of %d words, %s" % (score * 100, n, json.dumps(mapping)))
    order = [s["speaker"] for s in TranscriptJoin(segs)]
    report(name + ": speakers alternate like the turns", order == ["Spreker 1", "Spreker 2"] * (len(parts) // 2),
           " ".join(order))
    expected = " ".join(fixture_text(f) for f, _, _ in parts)
    got = " ".join(s["text"] for s in segs)
    w = wer(expected, got)
    report(name + ": WER over all turns < 25%", w < 0.25, "%.1f%%" % (w * 100))
    return score


def TranscriptJoin(segs):
    """Consecutive segments of one speaker joined, as in the .md."""
    out = []
    for s in segs:
        if out and out[-1]["speaker"] == s["speaker"]:
            continue
        out.append(s)
    return out


def test_group():
    """M6 mode B (replaces 'group call with 2 people at the other side'): R alternates Xander and
    Ellen, L has my own line (Xander) first. Who on R: Spreker 1 / Spreker 2, Ik stays Ik."""
    parts, total = alternating()
    shift = wav_duration(os.path.join(FIX, "nl_xander.wav")) + 1.0
    right = [(f, s + shift, g) for f, s, g in parts]
    audio = make_stereo("groupcall.wav", [("nl_xander.wav", 0.3, 1.0)], right, total + shift)
    last, sockets, polls = run_transcribe(audio)
    errs = last.get("errors", ["no last.json"])
    report("group: no errors", not errs, "; ".join(errs))
    if errs:
        return
    report("group: no network sockets while transcribing (lsof)", not sockets and polls > 0, "%d polls" % polls)
    report("group: mode B, Who version in header", last.get("transcriptMode") == "kanaalscheiding + sprekers"
           and last.get("whoVersion") == "v0.3.4", "%s, Who %s" % (last.get("transcriptMode"), last.get("whoVersion")))
    ik = text_of(last, "Ik")
    w_l = wer(fixture_text("nl_xander.wav"), ik)
    report("group: L stays 'Ik' (WER < 25%)", w_l < 0.25, "%.1f%%: %s" % (w_l * 100, ik))
    report("group: Ik comes first", last["segments"][0]["speaker"] == "Ik", last["segments"][0]["speaker"])
    check_speakers("group", last, right)
    with open(last["md"]) as f:
        md = f.read()
    report("group: .md has 'Spreker 1'/'Spreker 2' turns", " · Spreker 2**  \n" in md and " · Spreker 1**  \n" in md,
           md.splitlines()[2] if len(md.splitlines()) > 2 else md)
    print("  --- %s ---\n%s  ---" % (os.path.basename(last["md"]), md))
    print("  total %.1f s for %.1f s audio" % (last.get("seconds", -1), last.get("duration", -1)))


def test_room():
    """Several people around one Mac (a meeting at a table): Xander and Ellen take turns on the
    microphone (L). Who on L gives Spreker 1 / Spreker 2 instead of one 'Ik'. With one voice at the
    other side as well (Daniel on R), R stays 'Andere kant'."""
    parts, total = alternating()
    audio = make_stereo("room.wav", parts, [], total)
    last, sockets, polls = run_transcribe(audio)
    errs = last.get("errors", ["no last.json"])
    report("room: no errors", not errs, "; ".join(errs))
    if errs:
        return
    report("room: no 'Ik', mode with speakers", "Ik" not in [s["speaker"] for s in last["segments"]]
           and last.get("transcriptMode") == "kanaalscheiding + sprekers",
           "%s, Who %s" % (last.get("transcriptMode"), last.get("whoRaw")))
    check_speakers("room", last, parts)
    with open(last["json"]) as f:
        js = json.load(f)
    report("room: .json segments on the microphone channel (L) with speaker numbers 1 and 2",
           all(s.get("channel") == "L" for s in js.get("segments", []))
           and sorted(set(s.get("speakerNumber") for s in js.get("segments", []))) == [1, 2],
           json.dumps([(s.get("channel"), s.get("speakerNumber")) for s in js.get("segments", [])]))
    print("  total %.1f s for %.1f s audio" % (last.get("seconds", -1), last.get("duration", -1)))
    # The same table plus one person at the other side of the call, after the table's turns.
    fd = "en_daniel.wav"
    audio2 = make_stereo("room-call.wav", parts, [(fd, total, 1.0)], total + wav_duration(os.path.join(FIX, fd)) + 1.5)
    last2, _, _ = run_transcribe(audio2)
    labels = sorted(set(s["speaker"] for s in last2.get("segments", [])))
    report("room + call: L Spreker 1 / Spreker 2, R stays 'Andere kant'", not last2.get("errors")
           and labels == ["Andere kant", "Spreker 1", "Spreker 2"],
           "labels %s, Who %s, errors %s" % (labels, last2.get("whoRaw"), last2.get("errors")))


def test_onevoice():
    """M6: a normal call with one person at the other side stays plain mode A labels. Run on a short
    file (one turn) and a longer one (the same voice three times)."""
    fa, fb = "nl_xander.wav", "nl_ellen.wav"
    da, db = wav_duration(os.path.join(FIX, fa)), wav_duration(os.path.join(FIX, fb))
    for name, turns in (("short", 1), ("long", 3)):
        right = [(fb, da + 1.0 + i * (db + 0.7), 1.0) for i in range(turns)]
        audio = make_stereo("onevoice-%s.wav" % name, [(fa, 0.3, 1.0)], right, da + turns * (db + 0.7) + 2.0)
        last, sockets, polls = run_transcribe(audio)
        labels = sorted(set(s["speaker"] for s in last.get("segments", [])))
        report("onevoice (%s): one voice on R keeps 'Andere kant', Who ran" % name, not last.get("errors")
               and labels == ["Andere kant", "Ik"] and last.get("whoVersion") == "v0.3.4",
               "labels %s, speakerCount %s, Who raw: %s, mode %s, errors %s" % (
                   labels, last.get("speakerCount"), last.get("whoRaw"), last.get("transcriptMode"), last.get("errors")))


def test_memo():
    """M6 mode C (replaces 'voice memo of a 2-person conversation imported'): a mono file through the
    import path; Who + Voz, labels Spreker 1 / Spreker 2."""
    parts, total = alternating()
    audio = write_mono("memo-twee-sprekers.wav", parts, total)
    last, sockets, polls = run_transcribe(audio, ["--selftest-as-import"])
    errs = last.get("errors", ["no last.json"])
    report("memo: no errors", not errs, "; ".join(errs))
    if errs:
        return
    report("memo: no network sockets while transcribing (lsof)", not sockets and polls > 0, "%d polls" % polls)
    report("memo: mode C ('sprekers'), no channels", last.get("transcriptMode") == "sprekers"
           and not last.get("ownRecording"), "%s" % last.get("transcriptMode"))
    report("memo: .md and .json written", os.path.exists(last.get("md", "")) and os.path.exists(last.get("json", "")), last.get("md", ""))
    check_speakers("memo", last, parts)
    with open(last["json"]) as f:
        js = json.load(f)
    report("memo: .json has speaker numbers and no channel", all(s.get("speakerNumber") in (1, 2) and s.get("channel") is None
                                                                  for s in js.get("segments", [])), "")
    # A stereo file with a foreign name is also mode C (downmix), e.g. a stereo voice memo.
    stereo = make_stereo("memo-stereo.wav", parts, parts, total)
    last2, _, _ = run_transcribe(stereo, ["--selftest-as-import"])
    report("memo: stereo file with a foreign name is downmixed (mode C)", last2.get("transcriptMode") == "sprekers"
           and last2.get("speakerCount") == 2, "%s, %s speakers, errors %s" % (last2.get("transcriptMode"),
                                                                             last2.get("speakerCount"), last2.get("errors")))


INTERVIEW_NL = [
    ("Ik", "Goedemiddag Sanne, fijn dat je er bent. Ik ben Roeland, ik leid het team. Zullen we beginnen met jouw huidige baan?"),
    ("Andere kant", "Goedemiddag. Ja, ik werk nu vier jaar als backend developer bij Coolblue in Rotterdam, vooral aan het betaalsysteem in Kotlin en Go."),
    ("Ik", "Wat is het mooiste project dat je daar hebt gedaan?"),
    ("Andere kant", "De migratie van het oude betaalplatform naar een nieuwe dienst. Ik leidde een team van drie en we haalden de storingen met zestig procent omlaag."),
    ("Ik", "Mooi. Waarom wil je weg bij Coolblue?"),
    ("Andere kant", "Het team wordt verplaatst naar Antwerpen en ik wil meer verantwoordelijkheid voor architectuur. Jullie product op het gebied van zorg spreekt me erg aan."),
    ("Ik", "Hoe zit het met je salariswens?"),
    ("Andere kant", "Ik zit nu op 5200 euro bruto per maand. Ik zoek iets tussen de 5800 en 6200 euro, afhankelijk van het opleidingsbudget en de leaseregeling."),
    ("Ik", "Wij hebben een opleidingsbudget van 2000 euro per jaar. Een leaseauto hebben we niet, wel een NS Business Card."),
    ("Andere kant", "Dat is prima, ik kom toch met de trein. Mijn opzegtermijn is twee maanden, dus ik kan op zijn vroegst per 1 februari beginnen."),
    ("Ik", "Solliciteer je nog ergens anders?"),
    ("Andere kant", "Ja, bij Bol in Utrecht. Daar heb ik volgende week de tweede ronde."),
    ("Ik", "Duidelijk. Heb jij nog vragen voor ons?"),
    ("Andere kant", "Hoeveel dagen per week werken jullie op kantoor?"),
    ("Ik", "Twee dagen op kantoor in Utrecht, de rest mag thuis."),
    ("Andere kant", "Fijn, dat past goed."),
    ("Ik", "Dan plannen we de tweede ronde met de CTO, Mark, op donderdag 12 november om tien uur. Ik stuur je vandaag nog een uitnodiging."),
    ("Andere kant", "Top, dank je wel. Tot donderdag."),
]

INTERVIEW_EN = [
    ("Ik", "Good afternoon James, thanks for coming in. Shall we start with your current role?"),
    ("Andere kant", "Sure. I have been a product designer at Monzo in London for three years, mostly on the savings app."),
    ("Ik", "Why are you looking for a new job?"),
    ("Andere kant", "I want to work on healthcare, and I would like to lead a small design team."),
    ("Ik", "What are your salary expectations?"),
    ("Andere kant", "I am looking for around 65,000 pounds a year. My notice period is one month."),
    ("Ik", "Great. We will send you the design case on Friday, and you can present it to the team the week after."),
    ("Andere kant", "Perfect, thank you. Talk to you on Friday."),
]

MEETING_NL = [
    ("Ik", "Goedemorgen allemaal, we bespreken vandaag de lancering van de nieuwe app voor de huisartsen."),
    ("Andere kant", "Goedemorgen. Ik heb de cijfers van de pilot: tweeënveertig praktijken doen mee en ze gebruiken de app gemiddeld elf keer per dag."),
    ("Ik", "Mooi. Wat zijn de grootste klachten?"),
    ("Andere kant", "Het inloggen duurt te lang en de koppeling met het patiëntendossier valt soms weg, vooral op maandagochtend."),
    ("Ik", "Dan besluiten we dat de inlog eerst wordt verbeterd. Pieter, kun jij dat oppakken voor 20 november?"),
    ("Andere kant", "Ja, dat lukt. Ik heb wel hulp nodig van iemand van het platformteam."),
    ("Ik", "Lisa van het platformteam helpt je. Dan de koppeling: wie onderzoekt waarom die wegvalt?"),
    ("Andere kant", "Dat doe ik, ik stuur voor vrijdag een analyse rond."),
    ("Ik", "Prima. De lanceringsdatum blijft voorlopig 1 december, tenzij de koppeling dan nog niet stabiel is."),
    ("Andere kant", "En het budget voor de marketing? Daar hebben we nog geen besluit over."),
    ("Ik", "Dat blijft open, dat bespreek ik met de directie. We zien elkaar volgende week dinsdag om negen uur weer."),
]


def transcript_json(name, turns, repeat=1, gap=6.0):
    """A transcript .json as Bandje writes it (mode A), for summarizing without transcribing."""
    segs, t = [], 1.0
    for r in range(repeat):
        for who, text in turns:
            words = []
            for w in text.split():
                words.append({"text": w, "start": round(t, 2), "end": round(t + 0.3, 2)})
                t += 0.38
            segs.append({"speaker": who, "channel": "L" if who == "Ik" else "R", "speakerNumber": None,
                         "start": words[0]["start"], "end": words[-1]["end"], "text": text, "words": words})
            t += 1.2
        t += gap
    folder = os.path.join(SELFTEST_DIR, name)
    os.makedirs(folder, exist_ok=True)
    for f in os.listdir(folder):
        os.remove(os.path.join(folder, f))
    path = os.path.join(folder, name + ".json")
    with open(path, "w") as f:
        json.dump({"title": name, "duration": t, "mode": "kanaalscheiding", "crosstalkRemoved": 0, "segments": segs,
                   "models": {"voz": "v0.5.0", "who": None, "sdk": "test"}, "speakerNames": {"Andere kant": "Sanne"},
                   "audio": None}, f)
    return path


def run_summarize(json_path, extra=()):
    if os.path.exists(os.path.join(SELFTEST_DIR, "last.json")):
        os.remove(os.path.join(SELFTEST_DIR, "last.json"))
    run(["open", "-W", "-n", APP, "--args", *LANG_ARGS, "--selftest-summarize", json_path, *extra])
    return read_json("last.json") or {}


def test_summary():
    """M8: the four example templates on a fixed Dutch interview, a long meeting in parts, and the
    player next to it (M9). Skipped when Apple Intelligence is not available on this Mac."""
    path = transcript_json("summary-interview", INTERVIEW_NL)
    last = run_summarize(path)
    if not last.get("available"):
        skip("summary", "Apple Intelligence not available (macOS 26 + Apple Intelligence on)")
        return
    report("summary: no errors", not last.get("errors"), "; ".join(last.get("errors", [])))
    report("summary: language detected as nl", last.get("language") == "nl", str(last.get("language")))
    runs = {r["template"]: r for r in last.get("runs", [])}
    report("summary: four example templates ran", sorted(runs) == ["Algemene samenvatting", "Klantinterview (productvalidatie)", "Sollicitatiegesprek", "Vergadering"], str(sorted(runs)))
    for name, r in runs.items():
        text = r.get("text", "")
        missing = [h for h in r.get("headings", []) if h.lower() not in text.lower()]
        print("  --- %s (%.0f s) ---\n%s\n  ---" % (name, r.get("seconds", 0), text))
        report("summary %s: every template heading present" % name, text and not missing, "missing: %s" % missing)
        report("summary %s: file written" % name, os.path.exists(r.get("file", "")), r.get("file", ""))
    job = runs.get("Sollicitatiegesprek", {}).get("text", "").lower()
    facts = {"salary range 5800-6200": ("5800" in job or "5.800" in job) and ("6200" in job or "6.200" in job),
             "other application (Bol)": "bol" in job, "training budget 2000": "2000" in job or "2.000" in job,
             "next round 12 november": "12 november" in job, "notice two months / 1 februari": "februari" in job or "twee maanden" in job}
    for fact, ok in facts.items():
        report("summary Sollicitatiegesprek: %s" % fact, ok, "")
    report("summary: written in Dutch (no English headings)", "not discussed" not in job and "salary" not in job, "")
    html = last.get("html", "")
    page = open(html).read() if os.path.exists(html) else ""
    report("summary: shared web page has the four summaries and the transcript as tabs", page.count('role="tab"') == 5, html)
    import re as _re
    urls = _re.findall(r"https?://[^\s\"'<]+", page)
    report("summary: shared web page links only to band.je, once", urls == ["https://band.je"], " ".join(urls))
    # English conversation, Dutch template: the text is in English (the headings stay the template's).
    path = transcript_json("summary-english", INTERVIEW_EN)
    last = run_summarize(path, ["--template", "Sollicitatiegesprek"])
    r = (last.get("runs") or [{}])[0]
    text = r.get("text", "")
    print("  --- english (%.0f s) ---\n%s\n  ---" % (r.get("seconds", 0), text))
    report("summary english: language detected as en", last.get("language") == "en", str(last.get("language")))
    words = text.lower().split()
    body = [w for line in text.lower().splitlines() if not line.startswith("#") for w in line.split()]
    report("summary english: text written in English",
           body and body.count("the") + body.count("and") + body.count("is") > body.count("de") + body.count("en") + body.count("het"), "")
    report("summary english: salary and next step kept", "65" in text and "friday" in text.lower(), "")
    # Long: the meeting fourteen times is past the context window, so it goes in parts.
    path = transcript_json("summary-long", MEETING_NL, repeat=14)
    last = run_summarize(path, ["--template", "Vergadering"])
    r = (last.get("runs") or [{}])[0]
    report("summary long: estimated tokens above the context size", last.get("estimatedTokens", 0) > last.get("contextSize", 1),
           "%s tokens, context %s" % (last.get("estimatedTokens"), last.get("contextSize")))
    report("summary long: summarized in parts without error", r.get("text") and not last.get("errors"),
           "%.0f s; %s" % (r.get("seconds", 0), "; ".join(last.get("errors", []))))
    print("  --- long (%.0f s) ---\n%s\n  ---" % (r.get("seconds", 0), r.get("text", "")))
    long = r.get("text", "").lower()
    report("summary long: decisions and deadlines kept", "20 november" in long and "1 december" in long, "")


def test_nowho():
    """M6 without the Who model: mode A still works (no speakers), mode C gives the Dutch message
    and does not download. Uses a model folder holding only Voz (a symlink to the real one)."""
    d = os.path.join(SELFTEST_DIR, "voz-only-models")
    os.makedirs(d, exist_ok=True)
    link = os.path.join(d, "voz")
    if not os.path.islink(link):
        os.symlink(os.path.expanduser("~/Music/Bandje/.models/voz"), link)
    parts, total = alternating()
    audio = make_stereo("nowho.wav", [("nl_xander.wav", 0.3, 1.0)], [(f, s + 10, g) for f, s, g in parts], total + 10)
    last, sockets, _ = run_transcribe(audio, ["--selftest-model-dir", d])
    labels = sorted(set(s["speaker"] for s in last.get("segments", [])))
    report("nowho: stereo without Who = mode A, no error", not last.get("errors") and labels == ["Andere kant", "Ik"]
           and last.get("whoVersion") is None, "labels %s, errors %s" % (labels, last.get("errors")))
    memo = write_mono("nowho-memo.wav", parts, total)
    last, sockets2, _ = run_transcribe(memo, ["--selftest-model-dir", d, "--selftest-as-import"])
    errs = last.get("errors", [])
    report("nowho: mono without Who gives the fetch-models.sh message", any("Who" in e and "fetch-models.sh" in e for e in errs),
           "; ".join(errs))
    report("nowho: nothing downloaded into the model folder", sorted(os.listdir(d)) == ["voz"], str(os.listdir(d)))
    report("nowho: no network sockets", not sockets and not sockets2)


def test_concurrent():
    """M6 'start recording while a transcription runs': the transcription starts 1 s into a
    recording, in the background like in the app. The recording must not drop anything and the
    marker played during it must be on R; the transcription finishes too."""
    parts, total = alternating()
    audio = make_stereo("concurrent.wav", [("nl_xander.wav", 0.3, 1.0)], parts, total)
    for ext in (".md", ".json"):
        p = os.path.splitext(audio)[0] + ext
        if os.path.exists(p):
            os.remove(p)
    fixture = "nl_ellen.wav"
    d = wav_duration(os.path.join(FIX, fixture))
    proc, state = start_recording(1.5 + d + 2.0, ["--selftest-transcribe-during", audio])
    if not state or state.get("state") != "recording":
        proc.wait()
        report("concurrent: recording started", False, json.dumps(read_json("last.json"))[:300])
        return
    time.sleep(max(0, state["startedAt"] + 1.5 - time.time()))
    t_play = play(fixture)
    proc.wait()
    last = read_json("last.json") or {}
    errs = last.get("errors", ["no last.json"])
    report("concurrent: recording no errors", not errs, "; ".join(errs))
    if errs:
        return
    report("concurrent: no dropped samples while transcribing", last.get("droppedSamples") == 0, str(last.get("droppedSamples")))
    tr = last.get("transcription", {})
    report("concurrent: transcription finished with transcript", "error" not in tr and os.path.exists(tr.get("md", "")),
           tr.get("error", tr.get("md", "")))
    overlap = tr.get("startedAt", 1e18) < last.get("stoppedAt", 0)
    report("concurrent: transcription ran during the recording", overlap,
           "transcription %.2f-%.2f s, recording 0-%.2f s" % (tr.get("startedAt", 0) - last["startedAt"],
                                                              tr.get("finishedAt", 0) - last["startedAt"],
                                                              last["stoppedAt"] - last["startedAt"]))
    check_m4a("concurrent", last)
    left, right, rate = load_stereo(last["path"])
    off = t_play - last["startedAt"]
    inside = rms_db(right, rate, off + 0.3, off + d - 0.3)
    report("concurrent: marker during transcription on R > -45 dBFS", inside is not None and inside > -45, fmt(inside))


def test_dictate():
    """M7: the dictation path (48 kHz mono -> resample -> Voz) on NL and EN fixtures, hotkeys registrable,
    nothing written next to the fixture."""
    for fixture in ("nl_ellen.wav", "en_daniel.wav"):
        audio = staged(fixture)
        before = set(os.listdir(os.path.dirname(audio)))
        if os.path.exists(os.path.join(SELFTEST_DIR, "last.json")):
            os.remove(os.path.join(SELFTEST_DIR, "last.json"))
        run(["open", "-W", "-n", APP, "--args", *LANG_ARGS, "--selftest-dictate", audio])
        last = read_json("last.json") or {}
        with open(os.path.join(FIX, fixture.replace(".wav", ".txt"))) as f:
            ref = f.read()
        w = wer(ref, last.get("text", ""))
        report("dictate %s: no errors" % fixture, last.get("mode") == "selftest-dictate" and not last.get("errors"),
               json.dumps(last.get("errors")))
        report("dictate %s: WER <= 15%%" % fixture, w <= 0.15, "%.1f%%: %s" % (w * 100, last.get("text", "")))
        report("dictate %s: warm run under 2 s" % fixture, last.get("secondsWarm", 99) < 2, "%.2f s" % last.get("secondsWarm", 99))
        report("dictate %s: hotkeys D/Return/Enter/Esc registrable" % fixture,
               last.get("hotkeys") == {"dictate": 0, "return": 0, "enter": 0, "escape": 0}, json.dumps(last.get("hotkeys")))
        report("dictate %s: nothing written to disk" % fixture, set(os.listdir(os.path.dirname(audio))) == before)


def test_help():
    """Bandje Help: the help book is in the bundle for every language with a source, and opens in Help Viewer."""
    res = os.path.join(APP, "Contents", "Resources", "Bandje.help", "Contents", "Resources")
    for lang in ("en", "nl"):
        d = os.path.join(res, lang + ".lproj")
        ok = all(os.path.exists(os.path.join(d, f)) for f in ("index.html", "Bandje.helpindex", "Bandje.cshelpindex", "dictation.html"))
        report("help: %s book with index" % lang, ok, d)
    if os.path.exists(os.path.join(SELFTEST_DIR, "last.json")):
        os.remove(os.path.join(SELFTEST_DIR, "last.json"))
    run(["open", "-W", "-n", APP, "--args", *LANG_ARGS, "--selftest-help"])
    last = read_json("last.json") or {}
    report("help: Help Viewer opens the book", last.get("helpViewer") is True and last.get("book") == "com.neurendal.bandje.help", json.dumps(last))
    subprocess.run(["osascript", "-e", 'tell application id "com.apple.helpviewer" to quit'], capture_output=True)
    # Hoe maak ik een template? opens an anchor. helpd serves its cached copy of the book, which
    # must be the one just built (make-help.py clears stale copies), or the page is missing.
    run(["open", "-W", "-n", APP, "--args", *LANG_ARGS, "--selftest-help", "templates"])
    last = read_json("last.json") or {}
    cache = os.path.expanduser("~/Library/Group Containers/group.com.apple.helpviewer.content/Library/Caches")
    copies = [n for n in (os.listdir(cache) if os.path.isdir(cache) else []) if "com.neurendal.bandje.help*" in n]
    built = sorted(f for f in os.listdir(os.path.join(res, "nl.lproj")) if f.endswith(".html"))
    cached = sorted(f for f in os.listdir(os.path.join(cache, copies[0], "Contents", "Resources", "nl.lproj")) if f.endswith(".html")) if copies else []
    report("help: anchor 'templates' opens, Help Viewer has the current book", last.get("helpViewer") is True and cached == built,
           "cached %d pages, built %d" % (len(cached), len(built)))
    subprocess.run(["osascript", "-e", 'tell application id "com.apple.helpviewer" to quit'], capture_output=True)


def test_menu():
    """M10: the menu in Dutch, in the owner's order, with Recente opnames, Instellingen and Help; the settings
    window opens; the help page that 'Hoe maak ik een template?' opens exists."""
    if os.path.exists(os.path.join(SELFTEST_DIR, "last.json")):
        os.remove(os.path.join(SELFTEST_DIR, "last.json"))
    run(["open", "-W", "-n", APP, "--args", *LANG_ARGS, "--selftest-snapshot", "menu"])
    menu = (read_json("last.json") or {}).get("menu", [])
    # The owner's order: actions, the current recording and Recente opnames, devices, then the window,
    # Instellingen (⌘,), Help, Over and Stop. The header is "Opname · …" or "Laatste opname · …", or
    # "Nog geen opname" on a Mac without recordings.
    want = ["Start opname", "Start dicteren", "Transcribeer bestand…", "----", "[",
            "  Benoem sprekers…", "  Samenvatten ▸", "  Open in Band·je", "  Deel als webpagina…", "Recente opnames ▸",
            "----", "Microfoon ▸", "Geluidsuitvoer ▸", "Zet automatisch plakken aan…", "----",
            "Open Band·je", "Instellingen…", "Help", "Over Band·je", "Stop Band·je"]
    ok = bool(menu)  # Samenvatten is hidden without Apple Intelligence (skipped below)
    it = iter(menu)
    for w in want:
        if w == "  Samenvatten ▸" and not any(m.startswith("  Samenvatten") for m in menu):
            continue
        if not any(m.startswith(w) for m in it):
            ok = False
            break
    report("menu: order with Recente opnames, Instellingen and Help", ok, " | ".join(menu))
    png = os.path.join(SELFTEST_DIR, "snapshot-settings.png")
    if os.path.exists(png):
        os.remove(png)
    run(["open", "-W", "-n", APP, "--args", *LANG_ARGS, "--selftest-snapshot", "settings"])
    report("menu: settings window opens", os.path.exists(png) and os.path.getsize(png) > 1000, png)
    page = os.path.join(APP, "Contents", "Resources", "Bandje.help", "Contents", "Resources", "nl.lproj", "templates.html")
    report("menu: help page for 'Hoe maak ik een template?'", os.path.exists(page), page)


def test_micswitch():
    """M7: the sandboxed app can set the macOS default input (menu Microfoon) and restores it;
    lid detection matches ioreg; with the lid closed a non-built-in microphone is suggested."""
    if os.path.exists(os.path.join(SELFTEST_DIR, "last.json")):
        os.remove(os.path.join(SELFTEST_DIR, "last.json"))
    run(["open", "-W", "-n", APP, "--args", *LANG_ARGS, "--selftest-set-input"])
    last = read_json("last.json") or {}
    if "setStatus" not in last:
        skip("micswitch: only one input device, nothing to switch to")
        return
    report("micswitch: default input set from the sandbox", last.get("setStatus") == 0 and last.get("after") == last.get("target"),
           "%s -> %s (status %s)" % (last.get("before"), last.get("after"), last.get("setStatus")))
    report("micswitch: original input restored", last.get("restored") is True, str(last.get("before")))
    report("micswitch: lid state matches ioreg", last.get("lidClosed") == lid_closed(), str(last.get("lidClosed")))
    if "outputSetStatus" in last:
        report("micswitch: default output set from the sandbox (menu Geluidsuitvoer)",
               last.get("outputSetStatus") == 0 and last.get("outputAfter") == last.get("outputTarget"),
               "%s -> %s (status %s)" % (last.get("outputBefore"), last.get("outputAfter"), last.get("outputSetStatus")))
        report("micswitch: original output restored", last.get("outputRestored") is True, str(last.get("outputBefore")))
    else:
        skip("micswitch: output", "only one output device, nothing to switch to: %s" % last.get("outputDevices"))
    if last.get("lidClosed") and last.get("beforeBuiltIn"):
        report("micswitch: lid closed + built-in mic: an external mic is suggested", bool(last.get("suggested")), str(last.get("suggested")))


LANGUAGE_FIXTURES = ["de_anna.wav", "fr_thomas.wav", "es_paulina.wav", "it_alice.wav", "pt_luciana.wav",
                     "pt_joana.wav", "pl_zosia.wav", "ru_milena.wav", "uk_lesya.wav"]


def test_languages():
    """M7: the UI languages besides nl/en, through the dictation path, without telling Voz the language.
    TTS audio is clean, so real speech scores worse; numbers written as digits count as errors."""
    for fixture in LANGUAGE_FIXTURES:
        audio = staged(fixture)
        if os.path.exists(os.path.join(SELFTEST_DIR, "last.json")):
            os.remove(os.path.join(SELFTEST_DIR, "last.json"))
        run(["open", "-W", "-n", APP, "--args", *LANG_ARGS, "--selftest-dictate", audio])
        last = read_json("last.json") or {}
        with open(os.path.join(FIX, fixture.replace(".wav", ".txt"))) as f:
            ref = f.read()
        w = wer(ref, last.get("text", ""))
        report("language %s: WER <= 20%%" % fixture, not last.get("errors") and w <= 0.20,
               "%.1f%%: %s" % (w * 100, last.get("text", "") or json.dumps(last.get("errors"))))


def test_leaks():
    """No Bandje aggregate device or tap left behind after the app quit."""
    r = run(["swift", os.path.join(ROOT, "scripts", "dev", "list-devices.swift"), "--leaks"])
    last = (r.stdout.strip().splitlines() or ["?"])[-1]
    report("no leaked Bandje devices/taps", r.returncode == 0, last)


def main():
    tests = sys.argv[1:] or ["static", "record", "lr", "outputdir", "rebuild", "kill", "diskfull",
                             "nomodels", "transcribe", "crosstalk", "english",
                             "group", "room", "onevoice", "memo", "nowho", "concurrent", "dictate", "languages", "summary", "help", "menu", "micswitch", "leaks"]
    for t in tests:
        {"static": test_static, "record": test_record, "lr": test_lr, "long": test_long,
         "outputdir": test_outputdir, "rebuild": test_rebuild, "kill": test_kill,
         "diskfull": test_diskfull, "nomodels": test_nomodels, "transcribe": test_transcribe,
         "crosstalk": test_crosstalk, "english": test_english, "group": test_group, "room": test_room,
         "onevoice": test_onevoice, "memo": test_memo, "nowho": test_nowho,
         "concurrent": test_concurrent, "dictate": test_dictate, "languages": test_languages, "summary": test_summary, "help": test_help, "menu": test_menu, "micswitch": test_micswitch, "leaks": test_leaks}[t]()
    failed = [r for r in results if not r[1]]
    print("\n%d checks, %d failed, %d skipped" % (len(results), len(failed), len(skipped)))
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
