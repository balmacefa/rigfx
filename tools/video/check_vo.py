"""Verify the narration files match project.json (catches the lesson of this project: parallel sessions overwrote segs.json / vo/).

  python <rigfx>/tools/video/check_vo.py [--min 0.72] [--model base]
Checks: unique ids, every segment has vo/<id>.wav, durations are sane, and a faster_whisper transcript of each wav is similar to the
segment text (word-level ratio; STT mishears names like pixelfx, so the default threshold is forgiving). Exit 1 if anything fails.
"""
import argparse, difflib, json, os, re, subprocess, sys, wave
import numpy as np

ap = argparse.ArgumentParser()
ap.add_argument("--dir", default=os.getcwd())
ap.add_argument("--min", type=float, default=0.72)
ap.add_argument("--model", default="base")
a = ap.parse_args()
D = a.dir
P = json.load(open(os.path.join(D, "project.json"), encoding="utf8"))
segs = P["segments"]
ids = [s["id"] for s in segs]
bad = []
dups = sorted({i for i in ids if ids.count(i) > 1})
if dups:
    bad.append(f"duplicate ids: {dups}")

NUMS = {"zero": "0", "one": "1", "two": "2", "three": "3", "four": "4", "five": "5", "six": "6", "seven": "7", "eight": "8", "nine": "9", "ten": "10", "seventeen": "17"}
def norm(t):
    t = t.lower().replace("-", " ")
    t = re.sub(r"[^a-z0-9 ]", " ", t)
    return [NUMS.get(w, w) for w in t.split()]

from faster_whisper import WhisperModel  # pip install faster-whisper
m = WhisperModel(a.model, device="cpu", compute_type="int8")
os.makedirs(os.path.join(D, "stt"), exist_ok=True)
for s in segs:
    wav = os.path.join(D, "vo", s["id"] + ".wav")
    if not os.path.exists(wav):
        bad.append(f"{s['id']}: missing {wav}"); continue
    tmp = os.path.join(D, "stt", s["id"] + ".wav")
    subprocess.run(["ffmpeg", "-y", "-v", "error", "-i", wav, "-ar", "16000", "-ac", "1", "-c:a", "pcm_s16le", tmp], check=True)
    w = wave.open(tmp)
    audio = np.frombuffer(w.readframes(w.getnframes()), dtype=np.int16).astype(np.float32) / 32768
    dur = w.getnframes() / w.getframerate()
    words = len(norm(s["text"]))
    seg, _ = m.transcribe(audio, language="en", vad_filter=True)
    got = "".join(x.text for x in seg)
    r = difflib.SequenceMatcher(None, norm(s["text"]), norm(got)).ratio()
    flag = "ok " if r >= a.min and 0.15 * words <= dur <= 0.8 * words + 3 else "BAD"
    print(f"{flag} {s['id']} ratio={r:.2f} dur={dur:.1f}s words={words}")
    if flag == "BAD":
        bad.append(f"{s['id']}: ratio {r:.2f} (min {a.min}), dur {dur:.1f}s\n   expected: {s['text'][:110]}\n   heard:    {got.strip()[:110]}")
if bad:
    print("\nFAILED:\n" + "\n".join(bad)); sys.exit(1)
print("all narration matches project.json")
