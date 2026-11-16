extends RefCounted

const NAMES = ["일반검", "대검", "세검"]
const GROUND = [
	[[5,3,12], [6,4,14], [9,5,20]],
	[[12,5,22], [13,5,25], [14,5,27], [18,6,32]],
	[[4,2,9], [4,2,9], [5,2,11], [8,3,17]]
]
const RECOVERY_CANCEL = [4,10,2]
const CHARGE_FIRST = [18.0,30.0,12.0]
const CHARGE_FULL = [36.0,60.0,30.0]
const CHARGE_ADVANCE = [0.50,0.65,2.80]
const DAMAGE = [18.0,32.0,11.0]
const REACH = [1.35,1.75,1.48]
const HITSTOP = [3.0,5.0,2.0]

static func chain_count(weapon: int, kind: String) -> int:
	if kind in ["air", "up", "wall", "release"]:
		return 1 if weapon == 1 else 2
	if kind in ["wire", "strong", "plunge", "counter"]:
		return 1
	return GROUND[weapon].size()

static func attack(weapon: int, kind: String, index: int, charge: float = 0.0) -> Dictionary:
	var safe_index: int = clampi(index, 0, GROUND[weapon].size() - 1)
	var f: Array = GROUND[weapon][safe_index].duplicate()
	var damage: float = DAMAGE[weapon]
	var force: float = [1.0, 1.65, 0.65][weapon]
	var reach: float = REACH[weapon]
	match kind:
		"run":
			f = [[8,4,16],[13,6,25],[6,3,16]][weapon]
			damage *= 1.2
		"air":
			f = [[5,3,14],[11,5,20],[4,2,12]][weapon]
		"up":
			f = [[6,4,14],[12,6,18],[5,3,16]][weapon]
		"wall":
			f = [[8,4,16],[14,6,20],[6,3,19]][weapon]
		"wire":
			f = [[6,3,15],[12,5,22],[4,2,13]][weapon]
			damage *= 0.85
		"release":
			f = [[8,4,16],[14,6,22],[6,3,19]][weapon]
			damage *= 1.2
		"strong":
			f = [[10,5,17],[15,7,26],[8,3,17]][weapon]
			if weapon == 2 and charge > 0.0:
				f = [8,16,18]
			damage *= 1.4 + charge * 0.8
			force *= 1.25 + charge * 0.5
			reach += 0.12
		"counter":
			f = [[4,4,20],[8,6,22],[3,3,14]][weapon]
			damage *= 1.8
			force *= 1.5
		"plunge":
			f = [[8,5,22],[12,7,34],[8,3,22]][weapon]
			damage *= 1.5
			force *= 1.5
	if safe_index == GROUND[weapon].size() - 1 and kind in ["ground", "run"]:
		damage *= 1.25
		force *= 1.2
	return {
		"startup": float(f[0]) / 60.0,
		"active": float(f[1]) / 60.0,
		"recovery": float(f[2]) / 60.0,
		"total": float(f[0]+f[1]+f[2]) / 60.0,
		"cancel_recovery": float(RECOVERY_CANCEL[weapon]) / 60.0,
		"damage": damage, "strength": force, "reach": reach,
		"hitstop": minf(7.0, HITSTOP[weapon] + (1.0 if charge > 0.9 else 0.0)) / 60.0,
		"kind": kind, "index": safe_index, "weapon": weapon,
		"charge": charge,
		"advance_distance": CHARGE_ADVANCE[weapon] if kind == "strong" and charge > 0.0 else 0.0,
		"advance_start": maxf(0.0,float(f[0]-(0 if weapon == 2 else 2))/60.0),
		"advance_end": float(f[0]+f[1])/60.0
	}
