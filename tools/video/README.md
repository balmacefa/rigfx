# tools/video — 2-minute promo video from a project.json

GPU (pennies) makes the narration and the backgrounds; CPU makes everything else (rig frames, scene compositing, ffmpeg).
The first rigfx video (113 s, 12 scenes, 17 characters) cost under $0.5 of GPU in total.

```bash
# 0. a project dir anywhere (not in the repo; video-work/ is git-ignored)
mkdir video-work/demo && cd video-work/demo && cp ../../tools/video/example/project.json .   # edit segments, text, scenes
R=C:/Users/fabia/rigfx                                    # path to this repo
export PIXELFX_DIR=C:/Users/fabia/OneDrive/Escritorio/pixelfx-demo/pixelfx   # the patched pixelfx clone

# 1. GPU assets (skips files that already exist; --dry prints the estimate first)
node $R/tools/video/gen.mjs --dry
node $R/tools/video/gen.mjs                 # bg/<key>.jpg (FLUX schnell, $0.003 each) + vo/<id>.wav (Chatterbox)

# 2. check the narration really says what project.json says (catches overwritten/mixed vo files)
python $R/tools/video/check_vo.py           # needs: pip install faster-whisper

# 3. CPU: transparent rig frames for every clip named in project.json, then the scenes (parallel)
node $R/tools/video/vidframes.mjs --jobs 7
python $R/tools/video/build.py --still s03:40   # fast layout check -> still_s03.png (open it, fix scale/x/y, repeat)
python $R/tools/video/build.py --workers 7      # seg/<id>.mp4

# 4. voice + music + burned subtitles -> out/master.mp4 (1080p), out/web.mp4 (720p), out/poster.jpg, out/subs.srt
python $R/tools/video/assemble.py
ffmpeg -v error -i out/web.mp4 -f null -        # must print nothing
```

## project.json
`segments[]` = `{id, bg, text, scene}`; ids must be unique (gen/build/check/assemble refuse duplicates). `bg` names a key of `bg{}` (the FLUX prompt).
`scene` keys, any combination (`type` is only a label: title, clip, grid, 4up, code, outro): `title`, `clips`, `grid`, `panel` — see the docstring at the top of `build.py`.
A clip is `"char:move"`, e.g. `"giant:sword-combo"`. `subs_replace` fixes spoken forms in subtitles ("rigfx dot balmacefa dot com" -> `rigfx.balmacefa.com`).
Write numbers and URLs the way they should be *spoken* in `text` (the voice reads digits and dots badly).

## RunPod endpoints that worked
| use | endpoint | input -> output | cost |
|---|---|---|---|
| narration | serverless `dovnz0ml2w3kqa` (Chatterbox) | `{text, exaggeration, cfg_weight, temperature}` -> `output.audio_base64` (wav) | cold start ~90 s, ~12 s per segment, cents total |
| backgrounds | `black-forest-labs-flux-1-schnell` | `{prompt, width:1344, height:768, num_inference_steps:4}` -> `output.result` (jpeg URL) | $0.003 each |

The key lives in the pwmgr vault: `node C:/Users/fabia/OneDrive/Escritorio/pwmgr/cli.mjs get runpod-api-key`. `rp.mjs` reads it at call time; never print or commit it.
Every call is appended to `cost.json` (`usd` is null for the voice endpoint, which doesn't report a price).

## Speed
Scene compositing is the CPU-bound part: ~40 s for 21 s of video on 4 workers (8 cores). For a full 2-minute video use `--workers 7`, or rent a pod:
an RTX 3090 SECURE pod with 32 vCPU ($0.50/h) rendered all 12 scenes in ~90 s (~$0.12 for ~14 min including setup). Delete the pod when done (`GET /pods` must return `[]`).

## Traps
- Two sessions writing the same project dir corrupted `segs.json` and `vo/` once: one writer per folder, run `check_vo.py` before assembling.
- Subtitle timing is by character share inside each segment's speech (not word-aligned); good enough, keep sentences short.
- Serve the final mp4 from GitHub Pages (`https://balmacefa.github.io/<repo>/media/x.mp4`), not from Coolify: Coolify answers 200 without Range, iOS needs 206. The landing's CSP needs `media-src 'self' https://balmacefa.github.io`.
