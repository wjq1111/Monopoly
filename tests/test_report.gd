extends RefCounted
## 每例分别记录，不以总断言数替代需求覆盖率。

var suite: String
var run_id: String = "quick"
var evidence_dir: String = "res://.artifacts/checks"
var cases: Array[Dictionary] = []
var current: Dictionary = {}
var metadata: Dictionary = {}


func _init(suite_name: String) -> void:
	suite = suite_name
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--evidence-dir="):
			evidence_dir = argument.trim_prefix("--evidence-dir=")
		elif argument.begins_with("--run-id="):
			run_id = argument.trim_prefix("--run-id=")
	DirAccess.make_dir_recursive_absolute(evidence_dir)


func begin(case_id: String) -> void:
	current = {
		"case_id": case_id, "status": "PASSED", "assertions": [],
		"evidence": [], "reason": "",
	}
	cases.append(current)


func check(condition: bool, detail: String, actual: Variant = null) -> void:
	current["assertions"].append({"passed": condition, "detail": detail, "actual": actual})
	if not condition:
		current["status"] = "FAILED"
		printerr("FAIL: %s: %s" % [current["case_id"], detail])


func attach(relative_path: String) -> void:
	current["evidence"].append(relative_path)


func finish() -> int:
	var failure_count := 0
	var assertion_count := 0
	for result in cases:
		if result["assertions"].is_empty():
			result["status"] = "NOT_RUN"
			result["reason"] = "没有执行断言"
		assertion_count += result["assertions"].size()
		if result["status"] != "PASSED":
			failure_count += 1
	var output := {
		"schema_version": 1, "run_id": run_id, "suite": suite,
		"engine": Engine.get_version_info()["string"],
		"engine_hash": Engine.get_version_info()["hash"],
		"display_server": DisplayServer.get_name(),
		"metadata": metadata, "cases": cases,
	}
	var file := FileAccess.open(evidence_dir.path_join(suite + ".json"), FileAccess.WRITE)
	if file == null:
		printerr("ERROR: Cannot write test report")
		return 1
	file.store_string(JSON.stringify(output, "\t") + "\n")
	file.close()
	if failure_count == 0:
		print("CHECKS PASSED: %d assertions, %d cases (%s)" % [assertion_count, cases.size(), suite])
	else:
		printerr("CHECKS FAILED: %d cases (%s)" % [failure_count, suite])
	return 0 if failure_count == 0 else 1
