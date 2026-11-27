extends Node3D
# rigfx world — open-world explorer whose MAIN CHARACTER is a rigfx pixel-art
# character (billboard sprite built from the generated frames in res://char/).

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
var rng := RandomNumberGenerator.new()

func _ready() -> void:
	rng.seed = 1337
	_setup_env()
	_setup_ground()
	_scatter_world()
	_setup_player()
	_setup_hud()

func _mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.9
	return m

func _setup_env() -> void:
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

func _setup_ground() -> void:
	var body := StaticBody3D.new()
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(600, 600)
	mi.mesh = pm
	mi.material_override = _mat(Color(0.33, 0.52, 0.28))
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
	add_child(root)

func _rock(pos: Vector3) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	var s := rng.randf_range(0.6, 1.6)
	bm.size = Vector3(s, s * 0.7, s)
	mi.mesh = bm
	mi.position = pos + Vector3(0, s * 0.35, 0)
	mi.rotation.y = rng.randf() * TAU
	mi.material_override = _mat(Color(0.5, 0.5, 0.52))
	add_child(mi)

func _mountain(pos: Vector3) -> void:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.0; cm.bottom_radius = rng.randf_range(18, 32)
	cm.height = rng.randf_range(30, 55)
	mi.mesh = cm
	mi.position = pos + Vector3(0, cm.height * 0.5, 0)
	mi.material_override = _mat(Color(0.42, 0.40, 0.38))
	add_child(mi)

func _scatter_world() -> void:
	for i in 180:
		var p := Vector3(rng.randf_range(-240, 240), 0, rng.randf_range(-240, 240))
		if p.length() < 8: continue
		_tree(p)
	for i in 70:
		_rock(Vector3(rng.randf_range(-240, 240), 0, rng.randf_range(-240, 240)))
	for i in 10:
		var a := rng.randf() * TAU
		_mountain(Vector3(cos(a) * 320, 0, sin(a) * 320))

func _setup_player() -> void:
	player = CharacterBody3D.new()
	player.position = Vector3(0, 2, 0)
	var col := CollisionShape3D.new()
	var cs := CapsuleShape3D.new()
	cs.radius = 0.4; cs.height = 1.8
	col.shape = cs
	col.position = Vector3(0, 0.9, 0)
	player.add_child(col)
	# rigfx hero billboard built from generated frames
	var frames := SpriteFrames.new()
	frames.add_animation("run")
	frames.set_animation_speed("run", 14.0)
	frames.set_animation_loop("run", true)
	for i in FRAMES:
		var tex := load("res://char/f%d.png" % i) as Texture2D
		if tex:
			frames.add_frame("run", tex)
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
	hud = Label.new()
	hud.position = Vector2(16, 12)
	hud.add_theme_color_override("font_color", Color(1, 1, 1))
	hud.add_theme_font_size_override("font_size", 16)
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
	hud.text = "rigfx world  -  hero: mantis (rigfx)\nWASD move - Shift sprint - Space jump - Mouse look - Esc cursor\npos %d, %d   stamina %d%%" % [int(p.x), int(p.z), int(stamina * 100)]
