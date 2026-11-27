extends Node3D
# rigfx world — DATA-DRIVEN. The world is fetched at runtime from an n8n webhook
# (world.json). The EGM system edits that JSON; reloading the page shows the new
# world with NO rebuild/redeploy. Main character is a rigfx pixel-art billboard.

const WORLD_URL := "https://n8n-public.balmacefa.com/webhook/rigfx-world"
const SPEED := 6.0
const SPRINT := 11.0
const JUMP := 7.5
const GRAV := 20.0
const MOUSE_SENS := 0.0025
const FRAMES := 17

var player: CharacterBody3D
var yaw_pitch: Node3D
var hero: AnimatedSprite3D
var pitch := -0.25
var stamina := 1.0
var hud: Label
var banner: Label
var rng := RandomNumberGenerator.new()
var http: HTTPRequest
var content_root: Node3D

func _ready() -> void:
	_setup_env_default()
	_setup_ground()
	_setup_player()
	_setup_hud()
	content_root = Node3D.new()
	add_child(content_root)
	http = HTTPRequest.new()
	add_child(http)
	http.request_completed.connect(_on_world)
	var err := http.request(WORLD_URL)
	if err != OK:
		_build_world(_defaults())

func _mat(c: Color, emis := false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.9
	if emis:
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = 2.0
	return m

func _col(a) -> Color:
	if a is Array and a.size() >= 3:
		return Color(a[0], a[1], a[2])
	return Color(0.6, 0.6, 0.6)

func _defaults() -> Dictionary:
	return {"trees": 160, "rocks": 60, "mountains": 10, "size": 240,
		"env": {"fog": 0.0022, "sky_top": [0.30, 0.55, 0.95], "ground": [0.33, 0.52, 0.28]},
		"entities": [], "signs": [], "message": "rigfx world"}

func _on_world(_r: int, code: int, _h: PackedStringArray, body: PackedByteArray) -> void:
	var data := _defaults()
	if code == 200:
		var j = JSON.parse_string(body.get_string_from_utf8())
		if j is Dictionary:
			data = j
	_build_world(data)

func _setup_env_default() -> void:
	var we := WorldEnvironment.new()
	var env := Environment.new()
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color(0.30, 0.55, 0.95)
	sm.sky_horizon_color = Color(0.78, 0.86, 0.96)
	sm.ground_horizon_color = Color(0.55, 0.65, 0.55)
	sky.sky_material = sm
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.7
	env.fog_enabled = true
	env.fog_light_color = Color(0.78, 0.86, 0.96)
	env.fog_density = 0.0022
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -35, 0)
	sun.light_energy = 1.1
	sun.shadow_enabled = true
	add_child(sun)
	we.name = "WE"

func _setup_ground() -> void:
	var body := StaticBody3D.new()
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(800, 800)
	mi.mesh = pm
	mi.material_override = _mat(Color(0.33, 0.52, 0.28))
	mi.name = "GroundMesh"
	body.add_child(mi)
	var col := CollisionShape3D.new()
	col.shape = WorldBoundaryShape3D.new()
	body.add_child(col)
	add_child(body)

func _tree(pos: Vector3) -> void:
	var root := Node3D.new()
	root.position = pos
	var h := rng.randf_range(2.5, 5.0)
	var trunk := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.25; cm.bottom_radius = 0.35; cm.height = h
	trunk.mesh = cm
	trunk.position = Vector3(0, h * 0.5, 0)
	trunk.material_override = _mat(Color(0.35, 0.24, 0.14))
	root.add_child(trunk)
	var leaves := MeshInstance3D.new()
	var sp := SphereMesh.new()
	sp.radius = rng.randf_range(1.2, 2.2); sp.height = sp.radius * 2.0
	leaves.mesh = sp
	leaves.position = Vector3(0, h + sp.radius * 0.5, 0)
	leaves.material_override = _mat(Color(0.18, 0.45 + rng.randf() * 0.15, 0.2))
	root.add_child(leaves)
	content_root.add_child(root)

func _rock(pos: Vector3) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	var s := rng.randf_range(0.6, 1.6)
	bm.size = Vector3(s, s * 0.7, s)
	mi.mesh = bm
	mi.position = pos + Vector3(0, s * 0.35, 0)
	mi.rotation.y = rng.randf() * TAU
	mi.material_override = _mat(Color(0.5, 0.5, 0.52))
	content_root.add_child(mi)

func _mountain(pos: Vector3) -> void:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.0; cm.bottom_radius = rng.randf_range(18, 32)
	cm.height = rng.randf_range(30, 55)
	mi.mesh = cm
	mi.position = pos + Vector3(0, cm.height * 0.5, 0)
	mi.material_override = _mat(Color(0.42, 0.40, 0.38))
	content_root.add_child(mi)

func _label3d(pos: Vector3, text: String, color: Color) -> void:
	var l := Label3D.new()
	l.text = text
	l.position = pos
	l.font_size = 48
	l.pixel_size = 0.02
	l.modulate = color
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = false
	l.outline_size = 12
	content_root.add_child(l)

func _entity(e: Dictionary) -> void:
	var pos := Vector3(float(e.get("pos", [0, 0])[0]), 0, float(e.get("pos", [0, 0])[1]))
	var kind := String(e.get("kind", "pillar"))
	var color := _col(e.get("color", [0.8, 0.7, 0.3]))
	if kind == "campfire":
		var light := OmniLight3D.new()
		light.position = pos + Vector3(0, 1.2, 0)
		light.light_color = Color(1.0, 0.6, 0.2)
		light.omni_range = 14.0
		light.light_energy = 3.0
		content_root.add_child(light)
		var logs := MeshInstance3D.new()
		var bm := BoxMesh.new(); bm.size = Vector3(1.2, 0.4, 1.2)
		logs.mesh = bm; logs.position = pos + Vector3(0, 0.2, 0)
		logs.material_override = _mat(Color(0.3, 0.18, 0.1))
		content_root.add_child(logs)
	elif kind == "crystal":
		var mi := MeshInstance3D.new()
		var pm := PrismMesh.new(); pm.size = Vector3(1.4, 4.0, 1.4)
		mi.mesh = pm; mi.position = pos + Vector3(0, 2.0, 0)
		mi.material_override = _mat(color, true)
		content_root.add_child(mi)
	elif kind == "npc":
		var mi := MeshInstance3D.new()
		var cap := CapsuleMesh.new(); cap.radius = 0.4; cap.height = 1.8
		mi.mesh = cap; mi.position = pos + Vector3(0, 0.9, 0)
		mi.material_override = _mat(color)
		content_root.add_child(mi)
	else:  # pillar / tower
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new(); bm.size = Vector3(2.0, float(e.get("height", 8)), 2.0)
		mi.mesh = bm; mi.position = pos + Vector3(0, float(e.get("height", 8)) * 0.5, 0)
		mi.material_override = _mat(color)
		content_root.add_child(mi)
	if e.has("label"):
		_label3d(pos + Vector3(0, 3.2, 0), String(e["label"]), Color(1, 1, 0.8))

func _build_world(data: Dictionary) -> void:
	for c in content_root.get_children():
		c.queue_free()
	var env_d: Dictionary = data.get("env", {})
	var we := get_node_or_null("WE") as WorldEnvironment
	if we and we.environment:
		if env_d.has("fog"):
			we.environment.fog_density = float(env_d["fog"])
		if env_d.has("sky_top") and we.environment.sky:
			(we.environment.sky.sky_material as ProceduralSkyMaterial).sky_top_color = _col(env_d["sky_top"])
	var gm := get_node_or_null("StaticBody3D/GroundMesh")
	if env_d.has("ground") and gm:
		(gm as MeshInstance3D).material_override = _mat(_col(env_d["ground"]))
	var size := float(data.get("size", 240))
	var seed_v := int(data.get("seed", 1337))
	rng.seed = seed_v
	for i in int(data.get("trees", 160)):
		var p := Vector3(rng.randf_range(-size, size), 0, rng.randf_range(-size, size))
		if p.length() < 8: continue
		_tree(p)
	for i in int(data.get("rocks", 60)):
		_rock(Vector3(rng.randf_range(-size, size), 0, rng.randf_range(-size, size)))
	for i in int(data.get("mountains", 10)):
		var a := rng.randf() * TAU
		_mountain(Vector3(cos(a) * (size + 80), 0, sin(a) * (size + 80)))
	for e in data.get("entities", []):
		if e is Dictionary: _entity(e)
	for s in data.get("signs", []):
		if s is Dictionary:
			var sp := Vector3(float(s.get("pos", [0, 0])[0]), 2.2, float(s.get("pos", [0, 0])[1]))
			_label3d(sp, String(s.get("text", "?")), Color(1, 0.9, 0.5))
	if banner:
		banner.text = String(data.get("message", "rigfx world"))

func _setup_player() -> void:
	player = CharacterBody3D.new()
	player.position = Vector3(0, 2, 0)
	var col := CollisionShape3D.new()
	var cs := CapsuleShape3D.new()
	cs.radius = 0.4; cs.height = 1.8
	col.shape = cs
	col.position = Vector3(0, 0.9, 0)
	player.add_child(col)
	var frames := SpriteFrames.new()
	frames.add_animation("run")
	frames.set_animation_speed("run", 14.0)
	frames.set_animation_loop("run", true)
	for i in FRAMES:
		var tex := load("res://char/f%d.png" % i) as Texture2D
		if tex: frames.add_frame("run", tex)
	hero = AnimatedSprite3D.new()
	hero.sprite_frames = frames
	hero.animation = "run"
	hero.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	hero.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	hero.pixel_size = 0.012
	hero.position = Vector3(0, 1.1, 0)
	hero.shaded = false
	hero.play("run")
	player.add_child(hero)
	yaw_pitch = Node3D.new()
	yaw_pitch.position = Vector3(0, 1.4, 0)
	player.add_child(yaw_pitch)
	var arm := SpringArm3D.new()
	arm.spring_length = 6.0
	yaw_pitch.add_child(arm)
	var cam := Camera3D.new()
	cam.position = Vector3(0, 0, 6)
	arm.add_child(cam)
	yaw_pitch.rotation.x = pitch
	add_child(player)

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

func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.pressed:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if e is InputEventKey and e.pressed and e.keycode == KEY_ESCAPE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if e is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		player.rotate_y(-e.relative.x * MOUSE_SENS)
		pitch = clamp(pitch - e.relative.y * MOUSE_SENS, -1.2, 0.4)
		yaw_pitch.rotation.x = pitch

func _physics_process(delta: float) -> void:
	var input := Vector3.ZERO
	if Input.is_key_pressed(KEY_W): input.z -= 1.0
	if Input.is_key_pressed(KEY_S): input.z += 1.0
	if Input.is_key_pressed(KEY_A): input.x -= 1.0
	if Input.is_key_pressed(KEY_D): input.x += 1.0
	var moving := input.length() > 0.0
	var sprinting := Input.is_key_pressed(KEY_SHIFT) and stamina > 0.0 and moving
	var spd := SPRINT if sprinting else SPEED
	stamina = max(0.0, stamina - delta * 0.35) if sprinting else min(1.0, stamina + delta * 0.25)
	var dir := (player.transform.basis * input).normalized()
	player.velocity.x = dir.x * spd
	player.velocity.z = dir.z * spd
	if not player.is_on_floor():
		player.velocity.y -= GRAV * delta
	elif Input.is_key_pressed(KEY_SPACE):
		player.velocity.y = JUMP
	player.move_and_slide()
	hero.speed_scale = 1.6 if sprinting else (1.0 if moving else 0.35)
	var p := player.global_position
	hud.text = "WASD move - Shift sprint - Space jump - Mouse look - Esc cursor\npos %d, %d   stamina %d%%" % [int(p.x), int(p.z), int(stamina * 100)]
