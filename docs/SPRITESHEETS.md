# rigfx sprite sheets

`python tools/export_sheets.py [--src DIR] [--out DIR] [--only char[:move]]` writes
`dist/sheets/<char>/<move>.png` + `.json` (Aseprite JSON-hash), `dist/sheets/index.json` and `dist/rigfx-sheets.zip`.

- Grid atlas, row-major, untrimmed (every frame has the same size, so pivots stay aligned), 24 fps (`duration` 42 ms).
- Frame keys: `<char>-<move>-NNN`. Tag `<move>` covers all frames.
- `meta.rigfx`: `{char, move, fps, frame_count, transparent, pivot?, body}` (`body` = chars2d/<char>.json).
- `transparent:false` means the frames keep the dark render backdrop (key it out in a shader or crop it).
  `transparent:true` means RGBA frames were used.
- Load with nearest filtering (pixel art), no mipmaps.

## Godot 4 (AnimatedSprite2D + SpriteFrames)

```gdscript
# sheet_loader.gd
static func load_sheet(base: String) -> SpriteFrames:   # base = "res://sheets/knight/sword-combo"
    var data = JSON.parse_string(FileAccess.get_file_as_string(base + ".json"))
    var tex: Texture2D = load(base + ".png")
    var move: String = data.meta.frameTags[0].name
    var fps: float = data.meta.rigfx.fps
    var sf := SpriteFrames.new()
    sf.add_animation(move)
    sf.set_animation_speed(move, fps)
    sf.set_animation_loop(move, true)
    var keys: Array = data.frames.keys()
    keys.sort()
    for k in keys:
        var r = data.frames[k].frame
        var at := AtlasTexture.new()
        at.atlas = tex
        at.region = Rect2(r.x, r.y, r.w, r.h)
        sf.add_frame(move, at)
    return sf
```
```gdscript
$AnimatedSprite2D.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
$AnimatedSprite2D.sprite_frames = SheetLoader.load_sheet("res://sheets/knight/sword-combo")
$AnimatedSprite2D.play("sword-combo")
```

## Phaser 3

```js
// preload
this.load.atlas('knight-sword', 'sheets/knight/sword-combo.png', 'sheets/knight/sword-combo.json');
// create
this.anims.create({
  key: 'sword-combo',
  frames: this.anims.generateFrameNames('knight-sword', { prefix: 'knight-sword-combo-', start: 0, end: N - 1, zeroPad: 3 }),
  frameRate: 24, repeat: -1 });
this.add.sprite(x, y, 'knight-sword').play('sword-combo');
```
Set `pixelArt: true` in the game config. `N` = `meta.frameTags[0].to + 1`.

## Unity (Aseprite importer)

Unity's Aseprite importer reads `.aseprite` files, not JSON, so use the Sprite Editor path:
import the PNG (Sprite Mode Multiple, Filter Point, Compression None, Max Size 8192), then slice by
Grid By Cell Size = frame `sourceSize` (`w`x`h` from the JSON; the PNG is a regular grid) and create the clip by dragging the
sprites in order. Alternatively use a 2D Aseprite-JSON package (e.g. "Aseprite JSON importer" from the Asset Store/OpenUPM),
which consumes this exact format (`frames`, `meta.frameTags`, `duration`). Set the sprite pivot from `meta.rigfx.pivot` if present.

## Plain canvas

```js
const d = await (await fetch('sheets/knight/sword-combo.json')).json();
const img = new Image(); img.src = 'sheets/knight/sword-combo.png'; await img.decode();
const keys = Object.keys(d.frames).sort(), fps = d.meta.rigfx.fps;
const ctx = canvas.getContext('2d'); ctx.imageSmoothingEnabled = false;
(function loop(t) {
  const r = d.frames[keys[Math.floor(t / 1000 * fps) % keys.length]].frame;
  ctx.clearRect(0, 0, canvas.width, canvas.height);
  ctx.drawImage(img, r.x, r.y, r.w, r.h, 0, 0, r.w, r.h);
  requestAnimationFrame(loop);
})(0);
```
