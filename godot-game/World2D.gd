extends Node2D
# rigfx world — 100% 2D top-down. Data-driven from the n8n webhook (world.json),
# rigfx pixel-art characters as the hero / NPCs / enemies, collectible coins + score.

const WORLD_URL := "https://n8n-public.balmacefa.com/webhook/rigfx-world"
const SPEED := 230.0
const SPRINT := 420.0
const PX := 16.0  # pixels per world unit

var player: CharacterBody2D
var hero: AnimatedSprite2D
var cam: Camera2D
var content: Node2D
var coins: Array = []
var score := 0
var stamina := 1.0
var hud: Label
var banner: Label
var http: HTTPRequest
var rng := RandomNumberGenerator.new()
var frame_cache := {}
var ground_rect: ColorRect

func _ready() -> void:
	print("W2D_READY_START")
	RenderingServer.set_default_clear_color(Color(0.33, 0.52, 0.28))
	content = Node2D.new()
	add_child(content)
	_setup_player()
	_setup_hud()
	http = HTTPRequest.new()
	add_child(http)
	http.request_completed.connect(_on_world)
	print("W2D_READY_DONE")
	if http.request(WORLD_URL) != OK:
		_build(_defaults())

func _col(a) -> Color:
	if a is Array and a.size() >= 3:
		return Color(a[0], a[1], a[2])
	return Color(0.6, 0.6, 0.6)

func _frames_for(char_name: String) -> SpriteFrames:
	if frame_cache.has(char_name):
		return frame_cache[char_name]
	var sf := SpriteFrames.new()
	sf.add_animation("run")
	sf.set_animation_speed("run", 14.0)
	sf.set_animation_loop("run", true)
	var n := 0
	for i in 17:
		var tex := load("res://char/%s/f%d.png" % [char_name, i]) as Texture2D
		if tex == null:
			break
		sf.add_frame("run", tex)
		n += 1
	if n == 0:
		for i in 17:
			var t2 := load("res://char/f%d.png" % i) as Texture2D
			if t2 == null: break
			sf.add_frame("run", t2)
	frame_cache[char_name] = sf
	return sf

func _rigfx(char_name: String, sc := 0.55) -> AnimatedSprite2D:
	var s := AnimatedSprite2D.new()
	s.sprite_frames = _frames_for(char_name)
	s.animation = "run"
	s.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	s.scale = Vector2(sc, sc)
	s.play("run")
	return s

func _circle(radius: float, color: Color, n := 18) -> Polygon2D:
	var p := Polygon2D.new()
	var pts := PackedVector2Array()
	for i in n:
		pts.append(Vector2(cos(TAU * i / n), sin(TAU * i / n)) * radius)
	p.polygon = pts
	p.color = color
	return p

func _box(w: float, h: float, color: Color) -> Polygon2D:
	var p := Polygon2D.new()
	p.polygon = PackedVector2Array([Vector2(-w / 2, -h / 2), Vector2(w / 2, -h / 2), Vector2(w / 2, h / 2), Vector2(-w / 2, h / 2)])
	p.color = color
	return p

func _diamond(r: float, color: Color) -> Polygon2D:
	var p := Polygon2D.new()
	p.polygon = PackedVector2Array([Vector2(0, -r), Vector2(r * 0.7, 0), Vector2(0, r), Vector2(-r * 0.7, 0)])
	p.color = color
	return p

func _wlabel(pos: Vector2, text: String, color: Color) -> void:
	var l := Label.new()
	l.text = text
	l.position = pos + Vector2(-60, -46)
	l.size = Vector2(120, 20)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	l.add_theme_constant_override("outline_size", 6)
	l.add_theme_font_size_override("font_size", 16)
	content.add_child(l)

func _defaults() -> Dictionary:
	return {"hero": "mantis", "trees": 160, "rocks": 60, "size": 240,
		"env": {"ground": [0.33, 0.52, 0.28]}, "entities": [], "signs": [], "message": "rigfx world"}

func _on_world(_r: int, code: int, _h: PackedStringArray, body: PackedByteArray) -> void:
	print("W2D_WORLD code=", code, " bytes=", body.size())
	var data := _defaults()
	if code == 200:
		var j = JSON.parse_string(body.get_string_from_utf8())
		if j is Dictionary:
			data = j
	_build(data)

func _wp(p) -> Vector2:
	return Vector2(float(p[0]), float(p[1])) * PX

func _tree(pos: Vector2) -> void:
	var trunk := _box(8, 20, Color(0.35, 0.24, 0.14))
	trunk.position = pos + Vector2(0, 10)
	content.add_child(trunk)
	var leaves := _circle(rng.randf_range(16, 28), Color(0.18, 0.42 + rng.randf() * 0.18, 0.2))
	leaves.position = pos - Vector2(0, 6)
	content.add_child(leaves)

func _entity(e: Dictionary, size: float) -> void:
	var px := clamp(float(e.get("pos", [0, 0])[0]), -size, size)
	var pz := clamp(float(e.get("pos", [0, 0])[1]), -size, size)
	var pos := Vector2(px, pz) * PX
	var kind := String(e.get("kind", "pillar"))
	var color := _col(e.get("color", [0.8, 0.7, 0.3]))
	if kind == "campfire":
		var glow := _circle(40, Color(1.0, 0.6, 0.1, 0.25), 20)
		glow.position = pos; content.add_child(glow)
		var fire := _circle(12, Color(1.0, 0.55, 0.1), 14)
		fire.position = pos; content.add_child(fire)
	elif kind == "crystal":
		var d := _diamond(22, color); d.position = pos; content.add_child(d)
	elif kind == "coin":
		var c := _circle(10, Color(1.0, 0.84, 0.2), 16)
		c.position = pos; content.add_child(c)
		coins.append(c)
	elif kind == "npc" or kind == "enemy":
		var cname := String(e.get("char", "knight" if kind == "npc" else "demonlord"))
		var spr := _rigfx(cname, 0.5)
		spr.position = pos
		if kind == "enemy":
			spr.modulate = Color(1.0, 0.65, 0.65)
		content.add_child(spr)
	else:
		var hgt := clamp(float(e.get("height", 8)), 2.0, 20.0)
		var pil := _box(26, hgt * 5.0, color)
		pil.position = pos; content.add_child(pil)
	if e.has("label"):
		_wlabel(pos, String(e["label"]), Color(1, 1, 0.8))

func _build(data: Dictionary) -> void:
	for c in content.get_children():
		c.queue_free()
	coins.clear()
	var env_d: Dictionary = data.get("env", {})
	if env_d.has("ground"):
		RenderingServer.set_default_clear_color(_col(env_d["ground"]))
	var size := clamp(float(data.get("size", 240)), 80.0, 400.0)
	rng.seed = int(data.get("seed", 1337))
	if data.has("hero"):
		hero.sprite_frames = _frames_for(String(data["hero"]))
		hero.play("run")
	for i in int(min(data.get("trees", 160), 400)):
		var p := Vector2(rng.randf_range(-size, size), rng.randf_range(-size, size)) * PX
		if p.length() < 90: continue
		_tree(p)
	for i in int(min(data.get("rocks", 60), 200)):
		var r := _box(rng.randf_range(14, 28), rng.randf_range(12, 22), Color(0.5, 0.5, 0.52))
		r.position = Vector2(rng.randf_range(-size, size), rng.randf_range(-size, size)) * PX
		content.add_child(r)
	var ents = data.get("entities", [])
	for idx in min(ents.size(), 60):
		if ents[idx] is Dictionary: _entity(ents[idx], size)
	for s in data.get("signs", []):
		if s is Dictionary:
			var sx := clamp(float(s.get("pos", [0, 0])[0]), -size, size)
			var sz := clamp(float(s.get("pos", [0, 0])[1]), -size, size)
			_wlabel(Vector2(sx, sz) * PX, String(s.get("text", "?")), Color(1, 0.9, 0.5))
	if banner:
		banner.text = String(data.get("message", "rigfx world"))

func _setup_player() -> void:
	player = CharacterBody2D.new()
	var col := CollisionShape2D.new()
	var cs := CircleShape2D.new(); cs.radius = 14.0
	col.shape = cs
	player.add_child(col)
	hero = _rigfx("mantis", 0.6)
	player.add_child(hero)
	add_child(player)
	cam = Camera2D.new()
	cam.zoom = Vector2(1.1, 1.1)
	cam.position_smoothing_enabled = true
	cam.position_smoothing_speed = 8.0
	player.add_child(cam)

func _setup_hud() -> void:
	var cl := CanvasLayer.new()
	add_child(cl)
	banner = Label.new()
	banner.position = Vector2(16, 10)
	banner.text = "rigfx world (loading...)"
	banner.add_theme_color_override("font_color", Color(1, 0.85, 0.4))
	banner.add_theme_font_size_override("font_size", 20)
	cl.add_child(banner)
	hud = Label.new()
	hud.position = Vector2(16, 44)
	hud.add_theme_color_override("font_color", Color(1, 1, 1))
	hud.add_theme_font_size_override("font_size", 15)
	cl.add_child(hud)

func _physics_process(delta: float) -> void:
	var input := Vector2.ZERO
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP): input.y -= 1.0
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN): input.y += 1.0
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT): input.x -= 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT): input.x += 1.0
	var moving := input.length() > 0.0
	var sprinting := Input.is_key_pressed(KEY_SHIFT) and stamina > 0.0 and moving
	var spd := SPRINT if sprinting else SPEED
	stamina = max(0.0, stamina - delta * 0.35) if sprinting else min(1.0, stamina + delta * 0.25)
	player.velocity = input.normalized() * spd
	player.move_and_slide()
	if absf(input.x) > 0.01:
		hero.flip_h = input.x < 0.0
	hero.speed_scale = 1.6 if sprinting else (1.0 if moving else 0.4)
	var pp := player.global_position
	for i in range(coins.size() - 1, -1, -1):
		var c = coins[i]
		if not is_instance_valid(c):
			coins.remove_at(i); continue
		c.rotation += delta * 2.0
		if pp.distance_to(c.global_position) < 26.0:
			c.queue_free(); coins.remove_at(i); score += 1
	hud.text = "100%% 2D - WASD/arrows move - Shift sprint\npos %d, %d   stamina %d%%   coins %d" % [int(pp.x / PX), int(pp.y / PX), int(stamina * 100), score]
