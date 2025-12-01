extends Node3D
class_name Shnarken

## Shnarken - Satyr/Faun shopkeeper NPC
## Half-man, half-goat creature like Mr. Tumnus from Narnia

signal interaction_requested(shnarken: Shnarken)

@export var shnarken_name: String = "Shnarken"
@export var biome_id: int = 1  # Which biome this Shnarken serves

# Visual components
var body_container: Node3D
var torso: Node3D
var head: Node3D
var left_leg: Node3D
var right_leg: Node3D
var left_arm: Node3D
var right_arm: Node3D

# Animation state
var idle_time: float = 0.0
var blink_timer: float = 0.0
var next_blink: float = 3.0
var is_blinking: bool = false
var is_talking: bool = false
var ear_twitch_timer: float = 0.0

# Walking movement
var home_position: Vector3 = Vector3.ZERO
var walk_target: Vector3 = Vector3.ZERO
var is_walking: bool = false
var walk_timer: float = 0.0
var next_walk_time: float = 3.0
var walk_start_pos: Vector3 = Vector3.ZERO
var walk_speed: float = 1.8
var walk_radius: float = 4.0
var leg_phase: float = 0.0
var prev_leg_sin: float = 0.0  # For footstep detection

# Interaction
var player_nearby: bool = false
var interaction_area: Area3D
var collision_body: CharacterBody3D

func _ready() -> void:
	_setup_collision()
	_setup_body()
	_setup_interaction_area()
	call_deferred("_initialize_walking")

func _initialize_walking() -> void:
	home_position = global_position
	walk_target = global_position
	next_walk_time = randf_range(2.0, 5.0)

func _process(delta: float) -> void:
	idle_time += delta
	_update_idle_animation(delta)
	_update_blink(delta)
	_update_walking(delta)
	_update_ear_twitch(delta)

# =============================================================================
# COLLISION SETUP - Like Gahnome
# =============================================================================

func _setup_collision() -> void:
	collision_body = get_node_or_null("CollisionBody")
	if collision_body:
		return

	collision_body = CharacterBody3D.new()
	collision_body.name = "CollisionBody"
	collision_body.collision_layer = 4  # Same as enemies
	collision_body.collision_mask = 3   # Detect terrain (1) and players (2)
	add_child(collision_body)

	var shape = CollisionShape3D.new()
	var capsule = CapsuleShape3D.new()
	capsule.radius = 0.25
	capsule.height = 1.4
	shape.shape = capsule
	shape.position = Vector3(0, 0.7, 0)
	collision_body.add_child(shape)

# =============================================================================
# BODY SETUP - Satyr/Faun (half-man, half-goat)
# =============================================================================

func _setup_body() -> void:
	body_container = get_node_or_null("BodyContainer")
	if body_container:
		head = body_container.get_node_or_null("Torso/Head")
		torso = body_container.get_node_or_null("Torso")
		left_leg = body_container.get_node_or_null("LegL")
		right_leg = body_container.get_node_or_null("LegR")
		left_arm = body_container.get_node_or_null("Torso/ArmL")
		right_arm = body_container.get_node_or_null("Torso/ArmR")
		print("[Shnarken] Using scene-based Satyr mesh")
		return

	print("[Shnarken] Generating procedural Satyr mesh")
	body_container = Node3D.new()
	body_container.name = "BodyContainer"
	add_child(body_container)

	var scale_factor: float = 1.0

	# === MATERIALS (Gahnome-style earthy tones) ===

	# Skin - greenish like Gahnome
	var skin_mat = StandardMaterial3D.new()
	skin_mat.albedo_color = Color(0.45, 0.55, 0.35, 1)
	skin_mat.roughness = 0.7

	# Fur - brown goat fur
	var fur_mat = StandardMaterial3D.new()
	fur_mat.albedo_color = Color(0.4, 0.3, 0.2, 1)
	fur_mat.roughness = 0.9

	# Clothes - brown leather/cloth vest
	var clothes_mat = StandardMaterial3D.new()
	clothes_mat.albedo_color = Color(0.4, 0.25, 0.15, 1)
	clothes_mat.roughness = 0.8

	# Hooves - dark grey/black
	var hoof_mat = StandardMaterial3D.new()
	hoof_mat.albedo_color = Color(0.15, 0.12, 0.1, 1)
	hoof_mat.roughness = 0.5

	# Horns - cream/bone colored
	var horn_mat = StandardMaterial3D.new()
	horn_mat.albedo_color = Color(0.7, 0.65, 0.5, 1)
	horn_mat.roughness = 0.4

	# Eyes - dark
	var eye_mat = StandardMaterial3D.new()
	eye_mat.albedo_color = Color(0.05, 0.05, 0.05, 1)

	# Gold trim (merchant)
	var gold_mat = StandardMaterial3D.new()
	gold_mat.albedo_color = Color(0.85, 0.7, 0.2, 1)
	gold_mat.metallic = 0.8
	gold_mat.roughness = 0.3

	# Hair - darker brown
	var hair_mat = StandardMaterial3D.new()
	hair_mat.albedo_color = Color(0.3, 0.2, 0.15, 1)
	hair_mat.roughness = 0.9

	# === GOAT LEGS (furry with hooves) ===
	var leg_y_offset = 0.0  # Ground level

	for side in [-1, 1]:
		var leg = Node3D.new()
		leg.name = "Leg" + ("L" if side == -1 else "R")
		leg.position = Vector3(0.12 * side * scale_factor, 0.5 * scale_factor, 0)
		body_container.add_child(leg)

		if side == -1:
			left_leg = leg
		else:
			right_leg = leg

		# Upper leg (thigh) - furry
		var thigh = MeshInstance3D.new()
		var thigh_mesh = CapsuleMesh.new()
		thigh_mesh.radius = 0.08 * scale_factor
		thigh_mesh.height = 0.28 * scale_factor
		thigh.mesh = thigh_mesh
		thigh.material_override = fur_mat
		thigh.position = Vector3(0, -0.1 * scale_factor, 0)
		leg.add_child(thigh)

		# Knee joint
		var knee = Node3D.new()
		knee.name = "Knee"
		knee.position = Vector3(0, -0.25 * scale_factor, 0)
		leg.add_child(knee)

		# Lower leg (shin) - furry, backwards-bending like goat
		var shin = MeshInstance3D.new()
		var shin_mesh = CapsuleMesh.new()
		shin_mesh.radius = 0.05 * scale_factor
		shin_mesh.height = 0.25 * scale_factor
		shin.mesh = shin_mesh
		shin.material_override = fur_mat
		shin.position = Vector3(0, -0.12 * scale_factor, 0.04 * scale_factor)
		shin.rotation.x = 0.3  # Slight backward angle
		knee.add_child(shin)

		# Hoof
		var hoof = MeshInstance3D.new()
		var hoof_mesh = CylinderMesh.new()
		hoof_mesh.top_radius = 0.035 * scale_factor
		hoof_mesh.bottom_radius = 0.04 * scale_factor
		hoof_mesh.height = 0.06 * scale_factor
		hoof.mesh = hoof_mesh
		hoof.material_override = hoof_mat
		hoof.position = Vector3(0, -0.28 * scale_factor, 0.06 * scale_factor)
		knee.add_child(hoof)

		# Fur tufts at ankle
		var tuft = MeshInstance3D.new()
		var tuft_mesh = SphereMesh.new()
		tuft_mesh.radius = 0.045 * scale_factor
		tuft_mesh.height = 0.09 * scale_factor  # radius * 2 for proper sphere
		tuft.mesh = tuft_mesh
		tuft.material_override = fur_mat
		tuft.position = Vector3(0, -0.22 * scale_factor, 0.04 * scale_factor)
		knee.add_child(tuft)

	# === TORSO (human-like upper body) ===
	torso = Node3D.new()
	torso.name = "Torso"
	torso.position = Vector3(0, 0.55 * scale_factor, 0)
	body_container.add_child(torso)

	# Hips (transition from fur to skin)
	var hips = MeshInstance3D.new()
	var hips_mesh = CylinderMesh.new()
	hips_mesh.top_radius = 0.12 * scale_factor
	hips_mesh.bottom_radius = 0.14 * scale_factor
	hips_mesh.height = 0.12 * scale_factor
	hips.mesh = hips_mesh
	hips.material_override = fur_mat
	hips.position = Vector3(0, 0, 0)
	torso.add_child(hips)

	# Main torso
	var chest = MeshInstance3D.new()
	var chest_mesh = CapsuleMesh.new()
	chest_mesh.radius = 0.14 * scale_factor
	chest_mesh.height = 0.35 * scale_factor
	chest.mesh = chest_mesh
	chest.material_override = clothes_mat
	chest.position = Vector3(0, 0.22 * scale_factor, 0)
	torso.add_child(chest)

	# Shoulders
	var shoulders = MeshInstance3D.new()
	var shoulder_mesh = BoxMesh.new()
	shoulder_mesh.size = Vector3(0.38, 0.1, 0.14) * scale_factor
	shoulders.mesh = shoulder_mesh
	shoulders.material_override = clothes_mat
	shoulders.position = Vector3(0, 0.38 * scale_factor, 0)
	torso.add_child(shoulders)

	# Neck
	var neck = MeshInstance3D.new()
	var neck_mesh = CapsuleMesh.new()
	neck_mesh.radius = 0.05 * scale_factor
	neck_mesh.height = 0.1 * scale_factor
	neck.mesh = neck_mesh
	neck.material_override = skin_mat
	neck.position = Vector3(0, 0.48 * scale_factor, 0)
	torso.add_child(neck)

	# Vest buttons
	for i in range(3):
		var button = MeshInstance3D.new()
		var button_mesh = SphereMesh.new()
		button_mesh.radius = 0.018 * scale_factor
		button_mesh.height = 0.036 * scale_factor  # radius * 2 for proper sphere
		button.mesh = button_mesh
		button.material_override = gold_mat
		button.position = Vector3(0, 0.12 * scale_factor + i * 0.09 * scale_factor, 0.12 * scale_factor)
		torso.add_child(button)

	# === HEAD ===
	head = Node3D.new()
	head.name = "Head"
	head.position = Vector3(0, 0.58 * scale_factor, 0.02 * scale_factor)
	torso.add_child(head)

	var head_mesh_inst = MeshInstance3D.new()
	var head_mesh = SphereMesh.new()
	head_mesh.radius = 0.12 * scale_factor
	head_mesh.height = 0.24 * scale_factor
	head_mesh_inst.mesh = head_mesh
	head_mesh_inst.material_override = skin_mat
	head.add_child(head_mesh_inst)

	# Nose
	var nose = MeshInstance3D.new()
	var nose_mesh = SphereMesh.new()
	nose_mesh.radius = 0.025 * scale_factor
	nose_mesh.height = 0.05 * scale_factor  # radius * 2 for proper sphere
	nose.mesh = nose_mesh
	nose.material_override = skin_mat
	nose.position = Vector3(0, -0.02 * scale_factor, 0.1 * scale_factor)
	head.add_child(nose)

	# Eyes
	for side in [-1, 1]:
		var eye = MeshInstance3D.new()
		var eye_mesh = SphereMesh.new()
		eye_mesh.radius = 0.022 * scale_factor
		eye_mesh.height = 0.044 * scale_factor  # radius * 2 for proper sphere
		eye.mesh = eye_mesh
		eye.material_override = eye_mat
		eye.name = "Eye" + ("L" if side == -1 else "R")
		eye.position = Vector3(0.045 * side * scale_factor, 0.04 * scale_factor, 0.085 * scale_factor)
		head.add_child(eye)

	# Goat horns (curved backwards)
	for side in [-1, 1]:
		# Horn base
		var horn_base = MeshInstance3D.new()
		var base_mesh = CylinderMesh.new()
		base_mesh.top_radius = 0.025 * scale_factor
		base_mesh.bottom_radius = 0.04 * scale_factor
		base_mesh.height = 0.1 * scale_factor
		horn_base.mesh = base_mesh
		horn_base.material_override = horn_mat
		horn_base.position = Vector3(0.06 * side * scale_factor, 0.12 * scale_factor, -0.02 * scale_factor)
		horn_base.rotation.x = -0.4
		horn_base.rotation.z = 0.2 * side
		head.add_child(horn_base)

		# Horn tip (curved part)
		var horn_tip = MeshInstance3D.new()
		var tip_mesh = CylinderMesh.new()
		tip_mesh.top_radius = 0.008 * scale_factor
		tip_mesh.bottom_radius = 0.025 * scale_factor
		tip_mesh.height = 0.12 * scale_factor
		horn_tip.mesh = tip_mesh
		horn_tip.material_override = horn_mat
		horn_tip.position = Vector3(0.08 * side * scale_factor, 0.2 * scale_factor, -0.08 * scale_factor)
		horn_tip.rotation.x = -0.8
		horn_tip.rotation.z = 0.3 * side
		head.add_child(horn_tip)

	# Goat ears (floppy, horizontal)
	for side in [-1, 1]:
		var ear = MeshInstance3D.new()
		var ear_mesh = CapsuleMesh.new()
		ear_mesh.radius = 0.025 * scale_factor
		ear_mesh.height = 0.1 * scale_factor
		ear.mesh = ear_mesh
		ear.material_override = skin_mat
		ear.name = "Ear" + ("L" if side == -1 else "R")
		ear.position = Vector3(0.12 * side * scale_factor, 0.05 * scale_factor, 0)
		ear.rotation.z = 1.4 * side  # Nearly horizontal
		ear.rotation.x = 0.2
		head.add_child(ear)

	# Goatee/beard
	var beard = MeshInstance3D.new()
	var beard_mesh = CylinderMesh.new()
	beard_mesh.top_radius = 0.03 * scale_factor
	beard_mesh.bottom_radius = 0.01 * scale_factor
	beard_mesh.height = 0.1 * scale_factor
	beard.mesh = beard_mesh
	beard.material_override = hair_mat
	beard.position = Vector3(0, -0.12 * scale_factor, 0.06 * scale_factor)
	beard.rotation.x = 0.3
	head.add_child(beard)

	# Curly hair on top
	var hair = MeshInstance3D.new()
	var hair_mesh = SphereMesh.new()
	hair_mesh.radius = 0.1 * scale_factor
	hair_mesh.height = 0.2 * scale_factor  # radius * 2 for proper sphere
	hair.mesh = hair_mesh
	hair.material_override = hair_mat
	hair.position = Vector3(0, 0.1 * scale_factor, -0.02 * scale_factor)
	head.add_child(hair)

	# === ARMS ===
	for side in [-1, 1]:
		var arm = Node3D.new()
		arm.name = "Arm" + ("L" if side == -1 else "R")
		arm.position = Vector3(0.2 * side * scale_factor, 0.35 * scale_factor, 0)
		torso.add_child(arm)

		if side == -1:
			left_arm = arm
		else:
			right_arm = arm

		# Upper arm
		var upper_arm = MeshInstance3D.new()
		var upper_mesh = CapsuleMesh.new()
		upper_mesh.radius = 0.04 * scale_factor
		upper_mesh.height = 0.18 * scale_factor
		upper_arm.mesh = upper_mesh
		upper_arm.material_override = skin_mat
		upper_arm.position = Vector3(0.03 * side * scale_factor, -0.08 * scale_factor, 0)
		upper_arm.rotation.z = 0.25 * side
		arm.add_child(upper_arm)

		# Elbow
		var elbow = Node3D.new()
		elbow.name = "Elbow"
		elbow.position = Vector3(0.05 * side * scale_factor, -0.18 * scale_factor, 0)
		arm.add_child(elbow)

		# Forearm
		var forearm = MeshInstance3D.new()
		var fore_mesh = CapsuleMesh.new()
		fore_mesh.radius = 0.035 * scale_factor
		fore_mesh.height = 0.16 * scale_factor
		forearm.mesh = fore_mesh
		forearm.material_override = skin_mat
		forearm.position = Vector3(0, -0.08 * scale_factor, 0)
		elbow.add_child(forearm)

		# Hand
		var hand = MeshInstance3D.new()
		var hand_mesh = SphereMesh.new()
		hand_mesh.radius = 0.035 * scale_factor
		hand_mesh.height = 0.07 * scale_factor  # radius * 2 for proper sphere
		hand.mesh = hand_mesh
		hand.material_override = skin_mat
		hand.position = Vector3(0, -0.18 * scale_factor, 0)
		elbow.add_child(hand)

	# === MERCHANT POUCH/BAG ===
	var pouch = MeshInstance3D.new()
	var pouch_mesh = BoxMesh.new()
	pouch_mesh.size = Vector3(0.12, 0.1, 0.06) * scale_factor
	pouch.mesh = pouch_mesh
	pouch.material_override = clothes_mat
	pouch.position = Vector3(0.18 * scale_factor, 0.05 * scale_factor, 0)
	torso.add_child(pouch)

	# Belt
	var belt = MeshInstance3D.new()
	var belt_mesh = TorusMesh.new()
	belt_mesh.inner_radius = 0.11 * scale_factor
	belt_mesh.outer_radius = 0.13 * scale_factor
	belt.mesh = belt_mesh
	belt.material_override = clothes_mat
	belt.position = Vector3(0, 0.02 * scale_factor, 0)
	belt.rotation.x = PI / 2
	belt.scale.y = 0.25
	torso.add_child(belt)

	# Belt buckle
	var buckle = MeshInstance3D.new()
	var buckle_mesh = BoxMesh.new()
	buckle_mesh.size = Vector3(0.06, 0.05, 0.02) * scale_factor
	buckle.mesh = buckle_mesh
	buckle.material_override = gold_mat
	buckle.position = Vector3(0, 0.02 * scale_factor, 0.12 * scale_factor)
	torso.add_child(buckle)

# =============================================================================
# INTERACTION
# =============================================================================

func _setup_interaction_area() -> void:
	interaction_area = get_node_or_null("InteractionArea")
	if not interaction_area:
		interaction_area = Area3D.new()
		interaction_area.name = "InteractionArea"
		add_child(interaction_area)

		var shape = CollisionShape3D.new()
		var sphere = SphereShape3D.new()
		sphere.radius = 2.5
		shape.shape = sphere
		interaction_area.add_child(shape)

	interaction_area.body_entered.connect(_on_body_entered)
	interaction_area.body_exited.connect(_on_body_exited)

func _on_body_entered(body: Node3D) -> void:
	if body.is_in_group("players") and body.get("is_local_player"):
		player_nearby = true
		print("[Shnarken] Player entered interaction range")

func _on_body_exited(body: Node3D) -> void:
	if body.is_in_group("players") and body.get("is_local_player"):
		player_nearby = false
		print("[Shnarken] Player left interaction range")

func interact() -> void:
	if player_nearby:
		interaction_requested.emit(self)

func _input(event: InputEvent) -> void:
	if player_nearby and event.is_action_pressed("interact"):
		interact()

# =============================================================================
# ANIMATIONS
# =============================================================================

func _update_idle_animation(delta: float) -> void:
	# Gentle body sway when not walking
	if not is_walking:
		if body_container:
			body_container.rotation.z = sin(idle_time * 0.8) * 0.015
		# Gentle weight shift
		if left_leg and right_leg:
			var shift = sin(idle_time * 0.5) * 0.03
			left_leg.rotation.x = shift
			right_leg.rotation.x = -shift

	# Head looking around
	if head:
		head.rotation.y = sin(idle_time * 0.5) * 0.12
		head.rotation.x = sin(idle_time * 0.35) * 0.04

	# Arm sway
	if left_arm and right_arm and not is_walking:
		left_arm.rotation.x = sin(idle_time * 0.6) * 0.05
		right_arm.rotation.x = sin(idle_time * 0.6 + PI) * 0.05

func _update_ear_twitch(delta: float) -> void:
	ear_twitch_timer += delta
	if ear_twitch_timer > 3.0 + randf() * 4.0:
		ear_twitch_timer = 0.0
		# Twitch an ear
		if head:
			var ear = head.get_node_or_null("EarL" if randf() > 0.5 else "EarR")
			if ear:
				var tween = create_tween()
				tween.tween_property(ear, "rotation:x", ear.rotation.x + 0.3, 0.1)
				tween.tween_property(ear, "rotation:x", ear.rotation.x, 0.15)

func _update_walking(delta: float) -> void:
	if is_walking:
		var direction = (walk_target - global_position)
		direction.y = 0
		var distance = direction.length()

		if distance < 0.15:
			# Reached target
			is_walking = false
			global_position.x = walk_target.x
			global_position.z = walk_target.z
			next_walk_time = randf_range(3.0, 7.0)
			walk_timer = 0.0
			leg_phase = 0.0
			prev_leg_sin = 0.0
		else:
			# Walk toward target
			direction = direction.normalized()
			global_position += direction * walk_speed * delta

			# Face movement direction
			var target_rot = atan2(direction.x, direction.z)
			rotation.y = lerp_angle(rotation.y, target_rot, 5.0 * delta)

			# Animate legs and detect footsteps
			leg_phase += delta * 10.0
			_animate_walk(leg_phase)
	else:
		# Idle - wait for next walk
		walk_timer += delta
		if walk_timer >= next_walk_time:
			_start_walk()

func _start_walk() -> void:
	var angle := randf() * TAU
	var distance := randf_range(1.5, walk_radius)
	var offset := Vector3(cos(angle) * distance, 0, sin(angle) * distance)

	walk_start_pos = global_position
	walk_target = home_position + offset
	walk_target.y = home_position.y

	is_walking = true
	leg_phase = 0.0
	prev_leg_sin = 0.0

func _animate_walk(phase: float) -> void:
	var leg_sin = sin(phase)
	var leg_angle = leg_sin * 0.35

	# Animate legs
	if left_leg:
		left_leg.rotation.x = leg_angle
	if right_leg:
		right_leg.rotation.x = -leg_angle

	# Arm swing (opposite to legs)
	if left_arm:
		left_arm.rotation.x = -leg_angle * 0.5
	if right_arm:
		right_arm.rotation.x = leg_angle * 0.5

	# Detect footstep via zero-crossing
	if prev_leg_sin != 0.0:
		if (prev_leg_sin > 0 and leg_sin <= 0) or (prev_leg_sin < 0 and leg_sin >= 0):
			_play_hoofstep()
	prev_leg_sin = leg_sin

	# Slight body bob
	if body_container:
		body_container.position.y = abs(sin(phase)) * 0.02

func _play_hoofstep() -> void:
	# Play hoof sound (use stone/hard footstep)
	if SoundManager:
		SoundManager.play_sound_varied("footstep_grass", global_position, -8.0, 0.2)

func _update_blink(delta: float) -> void:
	blink_timer += delta

	if not is_blinking and blink_timer >= next_blink:
		is_blinking = true
		blink_timer = 0.0
		next_blink = randf_range(2.0, 5.0)

		if head:
			var eye_l = head.get_node_or_null("EyeL")
			var eye_r = head.get_node_or_null("EyeR")
			if eye_l:
				var tween = create_tween()
				tween.tween_property(eye_l, "scale:y", 0.1, 0.07)
				tween.tween_property(eye_l, "scale:y", 1.0, 0.07)
				tween.tween_callback(func(): is_blinking = false)
			if eye_r:
				var tween2 = create_tween()
				tween2.tween_property(eye_r, "scale:y", 0.1, 0.07)
				tween2.tween_property(eye_r, "scale:y", 1.0, 0.07)

func start_talking() -> void:
	is_talking = true

func stop_talking() -> void:
	is_talking = false

# =============================================================================
# DIALOGUE - Snarky shopkeeper who mocks player and hints at next gear
# =============================================================================

func get_greeting_dialogue(player: Node) -> String:
	var equipment = player.get_node_or_null("Equipment")
	if not equipment:
		return _get_naked_dialogue()

	var has_armor = false
	var has_weapon = false
	var armor_set = ""
	var armor_count = 0

	for slot in [1, 2, 3, 4]:
		var item_id = equipment.get_equipped_item(slot)
		if not item_id.is_empty():
			has_armor = true
			armor_count += 1
			if "pig" in item_id:
				armor_set = "pig"
			elif "deer" in item_id:
				armor_set = "deer"
			elif "tank" in item_id:
				armor_set = "tank"

	var weapon_id = equipment.get_equipped_item(0)
	if not weapon_id.is_empty() and weapon_id != "fists":
		has_weapon = true

	if not has_armor and not has_weapon:
		return _get_naked_dialogue()
	elif not has_armor:
		return _get_no_armor_dialogue()
	else:
		return _get_armor_dialogue(armor_set, armor_count)

func _get_naked_dialogue() -> String:
	# Mock the naked player, hint at flying pigs for first armor
	var lines = [
		"Poor, poor peasant. Do you even have armor? You're a muddy nudist!",
		"Oh look, a naked ape stumbled into my shop. The Gahnomes will eat well tonight!",
		"No armor? No weapon? Did you CRAWL here from the spawn point? The flying pigs have better fashion sense than you.",
		"*laughs* You call yourself an adventurer? My grandmother's goat has thicker skin! Maybe kill a flying pig or two?",
		"Ahhh, fresh meat walks in! And I don't mean for my shop. Have you SEEN the monsters out there, nudist?",
	]
	return lines[randi() % lines.size()]

func _get_no_armor_dialogue() -> String:
	# Has weapon but no armor - still basically naked
	var lines = [
		"Ooh, a pointy stick! That'll help when a Gahnome tears your naked flesh off. Ever heard of ARMOR?",
		"Armed but not armored? Bold strategy. Stupid, but bold. Those flying pigs aren't just for looking at, you know.",
		"*snorts* You wave that around while your soft pink belly hangs out? Pathetic. Kill some pigs, make some leather!",
		"A weapon! How quaint. Now if only you had something to stop yourself from DYING. Flying pigs, genius. Flying pigs.",
	]
	return lines[randi() % lines.size()]

func _get_armor_dialogue(armor_set: String, armor_count: int) -> String:
	match armor_set:
		"pig":
			return _get_pig_armor_dialogue(armor_count)
		"deer":
			return _get_deer_armor_dialogue(armor_count)
		"tank":
			return _get_tank_armor_dialogue(armor_count)
		_:
			return _get_mixed_armor_dialogue()

func _get_pig_armor_dialogue(count: int) -> String:
	# Mock pig armor, hint at deer for speed/stamina
	if count < 4:
		var lines = [
			"*snickers* Nice pig outfit. Incomplete pig outfit, but still... you smell like bacon. Finish the set or don't bother.",
			"Half-dressed in pig leather? Commit to the look or go home! You need all four pieces, genius.",
		]
		return lines[randi() % lines.size()]
	else:
		# Full pig set - hint at deer
		var lines = [
			"*slow clap* A full pig set! You can double jump now. Adorable. Too bad you still run like a pregnant sow. Ever heard of DEER leather?",
			"Oink oink! The flying pig cosplay is complete! Shame about your stamina though. The deer in the forest look MUCH faster than you.",
			"Congratulations, you're a bouncy pink nightmare. But can you RUN? Deer leather might help with that wheezing problem.",
			"Full pig armor! How... cute. You hop around like a piglet. Meanwhile, the deer laugh at your pathetic sprint speed.",
		]
		return lines[randi() % lines.size()]

func _get_deer_armor_dialogue(count: int) -> String:
	# Mock deer armor, hint at tank armor from shop
	if count < 4:
		var lines = [
			"*yawns* Deer leather? An upgrade, I suppose. But only %d pieces? You're half-deer, half-idiot." % count,
			"Incomplete deer set? You run fast but die faster. Finish the set, bambi.",
		]
		return lines[randi() % lines.size()]
	else:
		# Full deer set - hint at tank armor
		var lines = [
			"Oh my, full deer armor! You can run AND run away! But when running fails... well, I happen to sell something MUCH tougher.",
			"*slow clap* The graceful deer look. You prance, you leap, you... still die to hard hits. My tank armor could fix that. For a price.",
			"Speedy little deer! Too bad speed won't save you from everything. Maybe browse my REAL armor sometime?",
			"Full deer set! Now you can sprint away from your problems! Or... you could buy some REAL protection from me.",
		]
		return lines[randi() % lines.size()]

func _get_tank_armor_dialogue(count: int) -> String:
	# They bought from us - still mock them
	if count < 4:
		var lines = [
			"*sighs* You bought my armor but didn't finish the set? I'm insulted AND you're still vulnerable.",
			"Partial tank armor? You're like a turtle missing half its shell. Pathetic. Buy the rest.",
		]
		return lines[randi() % lines.size()]
	else:
		var lines = [
			"*inspects you* Full tank armor from MY shop! You're slow as molasses but at least you won't die immediately. You're welcome.",
			"Ah, a walking fortress! My finest work. You move like a glacier, but glaciers don't DIE, do they?",
			"The complete tank set! Now you can stand there and take hits like the stubborn rock you are. Beautiful.",
		]
		return lines[randi() % lines.size()]

func _get_mixed_armor_dialogue() -> String:
	var lines = [
		"*stares* What ARE you wearing? A bit of this, a bit of that... you look like a patchwork disaster.",
		"Mixed armor? No set bonus for you! Just a confused fashion victim stumbling through the wilderness.",
		"*laughs* Did you get dressed in the dark? Pick a SET and commit, you chaotic mess!",
	]
	return lines[randi() % lines.size()]

func get_max_upgrade_dialogue() -> String:
	var lines = [
		"*rolls eyes* It's already maxed out. What, you want me to sprinkle magic fairy dust on it?",
		"That's as good as it gets, genius. Even I can't improve perfection. Well... MY perfection.",
		"*sighs dramatically* Maxed. Done. Finished. Stop wasting my time with things I can't upgrade!",
	]
	return lines[randi() % lines.size()]

func get_purchase_dialogue() -> String:
	var lines = [
		"*counts coins* Pleasure doing business. Try not to die immediately, it's bad for repeat customers.",
		"Sold! Now get out there and make me look good. Or at least, less embarrassing.",
		"*smirks* Another satisfied customer. Well, YOU'RE satisfied. I just tolerate you.",
	]
	return lines[randi() % lines.size()]

func get_no_money_dialogue() -> String:
	var lines = [
		"*stares* You're broke? Then why are you in my shop? Go kill things and come back with MONEY.",
		"No coins? No deal. I don't run a charity for poorly-dressed adventurers.",
		"*laughs* You can't afford that. Maybe if you spent less time dying and more time looting...",
	]
	return lines[randi() % lines.size()]
