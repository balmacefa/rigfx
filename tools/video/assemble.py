"""seg/*.mp4 + vo/*.wav + project.json -> out/master.mp4 (1080p), out/web.mp4 (720p), out/poster.jpg, out/subs.srt.
Narration is padded to each clip's duration (lockstep), music is a soft synthetic pad ducked under the voice, subtitles are timed by
character share inside each segment's speech and burned in. Run from the project dir:  python <rigfx>/tools/video/assemble.py [--poster-at 52]
"""
import argparse, json, os, re, subprocess

ap = argparse.ArgumentParser()
ap.add_argument("--dir", default=os.getcwd())
ap.add_argument("--poster-at", type=float, default=52)
ap.add_argument("--no-music", action="store_true")
a = ap.parse_args()
os.chdir(a.dir)
P = json.load(open("project.json", encoding="utf8"))
segs = P["segments"]
ORDER = [s["id"] for s in segs]
assert len(set(ORDER)) == len(ORDER), "duplicate segment ids in project.json"
TEXT = {s["id"]: s["text"] for s in segs}
durs = json.load(open("seg/durs.json"))
for d in ("out", "aud"):
    os.makedirs(d, exist_ok=True)
def run(*c): subprocess.run(list(c), check=True)

# 1. video concat
open("seg/list.txt", "w").write("".join(f"file '{s}.mp4'\n" for s in ORDER))
run("ffmpeg", "-y", "-v", "error", "-f", "concat", "-safe", "0", "-i", "seg/list.txt", "-c", "copy", "out/video_nosound.mp4")

# 2. narration, padded per segment, polished
for s in ORDER:
    run("ffmpeg", "-y", "-v", "error", "-i", f"vo/{s}.wav", "-af", f"apad=whole_dur={durs[s]:.3f},aresample=48000", "-ac", "2", f"aud/{s}.wav")
open("aud/list.txt", "w").write("".join(f"file '{s}.wav'\n" for s in ORDER))
run("ffmpeg", "-y", "-v", "error", "-f", "concat", "-safe", "0", "-i", "aud/list.txt", "-af",
    "highpass=f=80,equalizer=f=200:t=q:w=1.0:g=1.5,acompressor=threshold=-20dB:ratio=3:attack=6:release=140:makeup=2,equalizer=f=6800:t=q:w=2.0:g=-3,treble=g=2.5:f=8500", "aud/vo_all.wav")
total = sum(durs[s] for s in ORDER)

# 3. music bed ducked under the voice (or voice only)
if a.no_music:
    run("ffmpeg", "-y", "-v", "error", "-i", "aud/vo_all.wav", "-af", "loudnorm=I=-16:TP=-1.5:LRA=11", "-ar", "48000", "aud/mix.wav")
else:
    cmd = ["ffmpeg", "-y", "-v", "error"]
    for f in (110, 110.7, 164.8, 220.4, 277.2):
        cmd += ["-f", "lavfi", "-i", f"sine=f={f}:d={total:.2f}"]
    cmd += ["-filter_complex", "[0][1][2][3][4]amix=inputs=5:normalize=0,tremolo=f=0.18:d=0.45,lowpass=f=1400,volume=0.55,aformat=channel_layouts=stereo,aresample=48000[m]", "-map", "[m]", "aud/music.wav"]
    run(*cmd)
    run("ffmpeg", "-y", "-v", "error", "-i", "aud/vo_all.wav", "-i", "aud/music.wav", "-filter_complex",
        "[0]asplit=2[v1][v2];[1][v1]sidechaincompress=threshold=0.03:ratio=8:attack=20:release=500[duck];[v2][duck]amix=inputs=2:weights=1 0.35:normalize=0,loudnorm=I=-16:TP=-1.5:LRA=11[a]",
        "-map", "[a]", "-ar", "48000", "aud/mix.wav")

# 4. subtitles
def srt_time(t):
    return f"{int(t // 3600):02d}:{int(t % 3600 // 60):02d}:{int(t % 60):02d},{int((t % 1) * 1000):03d}"
cues, t0, idx = [], 0.0, 1
for s in ORDER:
    text = TEXT[s]
    for k, v in (P.get("subs_replace") or {}).items():
        text = text.replace(k, v)
    parts = []
    for sent in [p.strip() for p in re.split(r"(?<=[.!?:])\s+", text) if p.strip()]:
        if len(sent) <= 70:
            parts.append(sent); continue
        chunk = ""
        for w in sent.split():
            chunk = (chunk + " " + w).strip()
            if len(chunk) > 55 and chunk[-1] in ",;":
                parts.append(chunk); chunk = ""
        if chunk:
            parts.append(chunk)
    speech, tot, t = durs[s] - 0.75, sum(len(p) for p in parts), t0 + 0.1
    for p in parts:
        d = speech * len(p) / tot
        cues.append((idx, t, t + d, p)); idx += 1; t += d
    t0 += durs[s]
with open("out/subs.srt", "w", encoding="utf8") as f:
    for i, s, e, p in cues:
        w = p.split(); h = (len(w) + 1) // 2
        f.write(f"{i}\n{srt_time(s)} --> {srt_time(e)}\n{p if len(p) < 48 else ' '.join(w[:h]) + chr(10) + ' '.join(w[h:])}\n\n")

# 5. mux + burn subs, web version, poster
sty = "FontName=Segoe UI Semibold,FontSize=20,Outline=2,Shadow=0,Alignment=2,MarginV=22,PrimaryColour=&H00FFFFFF&,OutlineColour=&H00100808&"
run("ffmpeg", "-y", "-v", "error", "-i", "out/video_nosound.mp4", "-i", "aud/mix.wav", "-vf", f"subtitles=out/subs.srt:force_style='{sty}'", "-c:v", "libx264", "-crf", "19", "-preset", "medium", "-pix_fmt", "yuv420p",
    "-c:a", "aac", "-b:a", "192k", "-shortest", "-movflags", "+faststart", "out/master.mp4")
run("ffmpeg", "-y", "-v", "error", "-i", "out/master.mp4", "-vf", "scale=1280:-2", "-c:v", "libx264", "-crf", "24", "-preset", "medium", "-pix_fmt", "yuv420p", "-c:a", "aac", "-b:a", "128k", "-movflags", "+faststart", "out/web.mp4")
run("ffmpeg", "-y", "-v", "error", "-ss", str(min(a.poster_at, total / 2)), "-i", "out/web.mp4", "-frames:v", "1", "-q:v", "3", "out/poster.jpg")
print("total", round(total, 1), "s,", os.path.getsize("out/web.mp4") // 1024, "KB web")
print("verify:  ffmpeg -v error -i out/web.mp4 -f null -   (must print nothing)")
print("publish: copy web.mp4 + poster.jpg to the repo site/media and serve the mp4 from GitHub Pages (Coolify has no Range/206 -> iOS fails)")
