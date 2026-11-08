#!/usr/bin/env python3
"""Concatenate mono 16-bit WAV files with a gap, and write the expected speaker timeline.

  concat_wav.py <out.wav> <gap seconds> <speaker>=<in.wav> [<speaker>=<in.wav> ...]

Writes <out.wav> and <out>.timeline.json: [{"speaker", "start", "end", "text"}] where text is
read from the <in>.txt next to each input (if present). Optional env LOOP_TO=<seconds> repeats
the whole sequence until at least that duration (for 10/60 min fixtures).
"""
import json
import os
import sys
import wave


def main():
    out, gap = sys.argv[1], float(sys.argv[2])
    parts = [a.split("=", 1) for a in sys.argv[3:]]
    loop_to = float(os.environ.get("LOOP_TO", "0"))
    frames, timeline, params, t = [], [], None, 0.0
    while True:
        for speaker, path in parts:
            with wave.open(path, "rb") as w:
                if params is None:
                    params = w.getparams()
                assert w.getnchannels() == 1 and w.getsampwidth() == 2 and w.getframerate() == params.framerate, path
                data = w.readframes(w.getnframes())
            dur = len(data) / 2 / params.framerate
            txt = os.path.splitext(path)[0] + ".txt"
            text = open(txt).read().strip() if os.path.exists(txt) else ""
            timeline.append({"speaker": speaker, "start": round(t, 3), "end": round(t + dur, 3), "text": text})
            frames.append(data)
            silence = b"\x00\x00" * int(gap * params.framerate)
            frames.append(silence)
            t += dur + gap
        if t >= loop_to:
            break
    with wave.open(out, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(params.framerate)
        w.writeframes(b"".join(frames))
    with open(os.path.splitext(out)[0] + ".timeline.json", "w") as f:
        json.dump(timeline, f, indent=1, ensure_ascii=False)
    with open(os.path.splitext(out)[0] + ".txt", "w") as f:
        f.write(" ".join(p["text"] for p in timeline) + "\n")
    print(f"{out}: {t:.1f} s, {len(timeline)} turns")


if __name__ == "__main__":
    main()
