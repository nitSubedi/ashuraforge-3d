extends Node
## Signature-power slots + the Blood meter (the combat resource: landing hits and
## kills fills it, powers spend it). Keys ability_1..ability_3.

signal blood_changed(value: float, max_value: float)
signal slots_changed()

const BLOOD_MAX := 100.0
const BLOOD_PER_HIT := 6.0
const BLOOD_PER_KILL := 15.0
const PhantomBlade := preload("res://scripts/abilities/phantom_blade.gd")
const HellfireRain := preload("res://scripts/abilities/hellfire_rain.gd")
const Wraithwing := preload("res://scripts/abilities/wraithwing.gd")

var player: CharacterBody3D
var blood := 30.0
var slots: Array = []

func setup(p: CharacterBody3D) -> void:
	player = p
	for script in [PhantomBlade, HellfireRain, Wraithwing]:
		var a: Node = script.new()
		a.player = p
		add_child(a)
		slots.append(a)
	var hud := preload("res://scripts/abilities/ability_hud.gd").new()
	hud.system = self
	add_child(hud)
	blood_changed.emit(blood, BLOOD_MAX)

func gain_blood(amount: float) -> void:
	blood = clampf(blood + amount, 0.0, BLOOD_MAX)
	blood_changed.emit(blood, BLOOD_MAX)

func try_activate(i: int) -> bool:
	if i >= slots.size():
		return false
	var a = slots[i]
	if a.active:
		a.reactivate()
		return true
	if a.cooldown_left > 0.0 or blood < a.cost or not a.can_activate():
		return false
	gain_blood(-a.cost)
	a.cooldown_left = a.cooldown
	a.activate()
	slots_changed.emit()
	return true

func _unhandled_input(event: InputEvent) -> void:
	for i in slots.size():
		var action := StringName("ability_%d" % (i + 1))
		var a = slots[i]
		if event.is_action_pressed(action):
			if a.aimable and not a.active:
				if _affordable(a):
					a.begin_aim()        # hold to place the target...
			else:
				try_activate(i)
		elif event.is_action_released(action) and a.aimable and a.aiming:
			try_activate(i)              # ...release to cast there
			a.cancel_aim()

func _affordable(a) -> bool:
	return a.cooldown_left <= 0.0 and blood >= a.cost and a.can_activate()

func _process(delta: float) -> void:
	for a in slots:
		if a.cooldown_left > 0.0 and not a.active:
			a.cooldown_left = maxf(0.0, a.cooldown_left - delta)
