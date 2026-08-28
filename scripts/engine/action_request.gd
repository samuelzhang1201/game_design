class_name ActionRequest
extends RefCounted

var action_code: String = ""
var params: Dictionary = {}
var target: String = ""

static func make(code: String, p: Dictionary = {}, t: String = "") -> ActionRequest:
	var r := ActionRequest.new()
	r.action_code = code; r.params = p; r.target = t
	return r

func to_dict() -> Dictionary:
	return {"action_code": action_code, "params": params.duplicate(), "target": target}

static func from_dict(d: Dictionary) -> ActionRequest:
	return make(d.get("action_code", ""), d.get("params", {}), d.get("target", ""))
