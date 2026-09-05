"""旧 M0（legacy_m0）完整回归编排，固定 GUI 场景 src/app/main.tscn。新联机入口与棋盘使用 board_check.ps1；Python 只校验追踪关系、运行真实 Godot 和整理证据。"""
from __future__ import annotations
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
from datetime import datetime, timezone

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")
    sys.stderr.reconfigure(encoding="utf-8")

ROOT = Path(__file__).resolve().parents[1]
CATALOG = ROOT / "tests/test_catalog.json"
VALID_STATUSES = {"PASSED", "FAILED", "BLOCKED", "NOT_RUN"}
SCOPE = "legacy_m0"
SCENE_PATH = "res://src/app/main.tscn"


def write_json(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def project_path(relative):
    path = (ROOT / relative).resolve()
    if not path.is_relative_to(ROOT):
        raise ValueError("路径必须留在项目内：" + str(relative))
    return path


def section_text(text, wanted):
    lines = text.splitlines()
    headings = []
    fence = None
    for index, line in enumerate(lines):
        marker = re.match(r"^\s*(`{3,}|~{3,})", line)
        if marker:
            char = marker[1][0]
            if fence is None:
                fence = char
            elif fence == char:
                fence = None
            continue
        if fence:
            continue
        match = re.match(r"^(#{1,6})\s+(.+)$", line)
        if match:
            title = re.sub(r"^\d+(?:\.\d+)*[.：:]?\s+", "", match[2]).strip()
            headings.append((index, len(match[1]), title))
    for offset, (start, level, title) in enumerate(headings):
        if title == wanted:
            end = len(lines)
            for next_start, next_level, _ in headings[offset + 1:]:
                if next_level <= level:
                    end = next_start
                    break
            return "\n".join(lines[start:end])
    raise ValueError("需求来源小节不存在：" + wanted)

def load_catalog():
    catalog = json.loads(CATALOG.read_text(encoding="utf-8"))
    validate_catalog(catalog)
    return catalog


def validate_catalog(catalog):
    if catalog.get("schema_version") != 1:
        raise ValueError("不支持的用例目录版本")
    reqs = catalog["requirements"]
    ids = [item["id"] for item in reqs]
    if len(set(ids)) != len(ids):
        raise ValueError("需求编号重复")
    for requirement in reqs:
        if not requirement.get("sources"):
            raise ValueError("需求没有来源：" + requirement["id"])
        for parent in requirement.get("parent_ids", []):
            if parent not in ids:
                raise ValueError("派生需求的父需求不存在：" + parent)
        for source in requirement["sources"]:
            text = project_path(source["path"]).read_text(encoding="utf-8")
            if not source["quote"].strip() or source["quote"] not in section_text(text, source["section"]):
                raise ValueError("需求摘录不在指定小节：" + requirement["id"])
    case_ids = []
    for case in catalog["cases"]:
        case_ids.append(case["id"])
        for field in ["title", "requirement_ids", "suite", "preconditions", "steps", "expected", "cleanup"]:
            if not case.get(field):
                raise ValueError("用例缺字段：" + case["id"] + " / " + field)
        if case["suite"] not in ("domain", "gui", "manual"):
            raise ValueError("未知测试层次")
        if not set(case["requirement_ids"]).issubset(ids):
            raise ValueError("用例引用未知需求：" + case["id"])
    if len(set(case_ids)) != len(case_ids):
        raise ValueError("用例编号重复")


def input_files(catalog):
    paths = {CATALOG, ROOT / "project.godot"}
    for folder in ["src", "data", "tests", "scripts"]:
        for path in (ROOT / folder).rglob("*"):
            if path.is_file() and path.suffix in (".gd", ".tscn", ".tres", ".json", ".ps1", ".py", ".uid"):
                paths.add(path)
    for requirement in catalog["requirements"]:
        for source in requirement["sources"]:
            paths.add(project_path(source["path"]))
    for name in ["docs/testing/M0测试用例.md", "docs/testing/策划测试用例.md",
                 "docs/testing/需求追踪矩阵.md", "docs/testing/测试流程与用例规范.md",
                 "AGENTS.md", ".agents/skills/our-home-workflow/SKILL.md"]:
        paths.add(ROOT / name)
    return sorted(paths)


def signature(paths):
    return {path.relative_to(ROOT).as_posix(): sha(path) for path in paths}


def contained_evidence(run_dir, relative):
    path = (run_dir / relative).resolve()
    if not path.is_relative_to(run_dir.resolve()):
        raise ValueError("证据路径超出本次运行目录")
    if not path.is_file() or path.stat().st_size == 0:
        raise ValueError("证据缺失或为空：" + str(relative))
    if path.suffix == ".png" and path.read_bytes()[:8] != b"\x89PNG\r\n\x1a\n":
        raise ValueError("截图不是有效 PNG 文件")
    return path


def validate_suite(data, expected, run_id, run_dir, engine_version):
    reported = re.match(r"^\d+\.\d+\.\d+", str(data.get("engine", "")))
    actual_version = re.match(r"^\d+\.\d+\.\d+", engine_version)
    if not reported or not actual_version or reported[0] != actual_version[0]:
        raise ValueError("结果引擎版本与实际执行不一致")
    expected_hash = engine_version.rsplit(".", 1)[-1]
    if re.fullmatch(r"[0-9a-f]{9,40}", expected_hash) and not str(data.get("engine_hash", "")).startswith(expected_hash):
        raise ValueError("结果引擎构建哈希与实际执行不一致")
    if data.get("run_id") != run_id:
        raise ValueError("结果来自其他运行")
    results = data["cases"]
    ids = [case["case_id"] for case in results]
    if len(ids) != len(set(ids)) or set(ids) != {case["id"] for case in expected}:
        raise ValueError("实际用例缺失、重复或不在目录中")
    definitions = {case["id"]: case for case in expected}
    if data.get("suite") != expected[0]["suite"]:
        raise ValueError("结果层次与目录不一致")
    if data["suite"] == "gui":
        if data.get("display_server") == "headless":
            raise ValueError("GUI 结果不能来自无头渲染")
        if data.get("metadata", {}).get("input_method") != "Input.parse_input_event":
            raise ValueError("GUI 输入方式未声明")
    for result in results:
        if result["status"] not in VALID_STATUSES:
            raise ValueError("未知执行状态")
        assertions = result.get("assertions", [])
        if result["status"] == "PASSED":
            if not assertions or not all(item.get("passed") is True for item in assertions):
                raise ValueError("无断言或失败断言被标为通过")
            if definitions[result["case_id"]]["evidence_required"] and not result.get("evidence"):
                raise ValueError("通过的界面用例缺少证据")
        for evidence in result.get("evidence", []):
            contained_evidence(run_dir, evidence)
    return results


def run_engine(engine, args, log_path, timeout=60):
    command = [str(engine), "--path", str(ROOT), "--log-file", str(log_path.with_suffix(".engine.log"))] + args
    flags = subprocess.CREATE_NO_WINDOW if os.name == "nt" else 0
    try:
        completed = subprocess.run(command, cwd=ROOT, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                   timeout=timeout, creationflags=flags)
        output = completed.stdout.decode("utf-8", errors="replace")
        log_path.write_text(output, encoding="utf-8")
        print(output[-2500:].strip())
        errors = bool(re.search(r"(?m)^\s*(SCRIPT ERROR:|ERROR:|FAIL:)", output))
        return {"exit_code": completed.returncode, "errors": errors, "command": command, "log": log_path.name}
    except subprocess.TimeoutExpired as error:
        log_path.write_bytes((error.stdout or b"") + b"\nTIMEOUT\n")
        return {"exit_code": -1, "errors": True, "command": command, "log": log_path.name, "reason": "60秒超时"}
    except OSError as error:
        log_path.write_text(str(error), encoding="utf-8")
        return {"exit_code": -1, "errors": True, "command": command, "log": log_path.name, "reason": str(error)}


def blocked(case, reason):
    return {"case_id": case["id"], "status": "BLOCKED", "assertions": [], "evidence": [], "reason": reason}


def refresh_summary(summary):
    automatic = [item for item in summary["cases"] if item["suite"] != "manual"]
    def status(items):
        states = {item["status"] for item in items}
        if "FAILED" in states:
            return "FAILED"
        if "BLOCKED" in states:
            return "BLOCKED"
        return "PASSED" if states == {"PASSED"} else "NOT_RUN"
    summary["automatic_status"] = status(automatic)
    summary["m0_status"] = status(summary["cases"]) if summary["input_consistent"] else "BLOCKED"
    summary["full_game_status"] = "NOT_ACCEPTED"
    summary["counts"] = {state: sum(item["status"] == state for item in summary["cases"]) for state in sorted(VALID_STATUSES)}


def save_report(run_dir, summary):
    refresh_summary(summary)
    write_json(run_dir / "summary.json", summary)
    report_dir = ROOT / "docs/testing/执行记录"
    report_dir.mkdir(parents=True, exist_ok=True)
    artifact_relative = "../../../.artifacts/self-tests/" + summary["run_id"]
    lines = [
        "# Godot 自测记录 " + summary["run_id"], "",
        "- 范围：legacy_m0，固定旧本地预览场景 res://src/app/main.tscn；完整游戏尚未验收。",
        "- 开始时间：" + summary["started_at"],
        "- 引擎：" + summary["engine"],
        "- 自动用例：" + summary["automatic_status"] + "；含视觉审阅的 M0 状态：" + summary["m0_status"],
        "- 输入基线一致：" + str(summary["input_consistent"]),
        "- 逐例计数：" + "，".join(f"{key}={value}" for key, value in summary["counts"].items()),
        "- 边界：GUI 使用真实 Godot 渲染和引擎输入注入；不覆盖新主场景 game_shell.tscn、联机入口与棋盘，未验证操作系统鼠标、三台设备联网、导出包、月份、战斗、剧情与音频。",
        "- 全范围缺口见[需求追踪矩阵](../需求追踪矩阵.md)，不能将本页的 M0 通过率当作全需求通过率。", "",
        f"[完整结果]({artifact_relative}/summary.json) · [版本与命令记录]({artifact_relative}/manifest.json)", "",
        "证据保存在本机被忽略的 .artifacts 目录；文档报告保留在项目内。移动或分享报告时需另行带上证据目录。", "",
        "| 用例 | 需求 | 测试点 | 状态 | 实测与证据 |", "|---|---|---|---|---|"
    ]
    for result in summary["cases"]:
        evidence = " ".join(f"[{Path(path).name}]({artifact_relative}/{path})" for path in result.get("evidence", []))
        failed = [item["detail"] for item in result.get("assertions", []) if item["passed"] is not True]
        note = result.get("reason", "") or ("；".join(failed) if failed else f'{len(result.get("assertions", []))} 项断言')
        note = note.replace("|", "/").replace("\n", " ")
        lines.append(f'| {result["case_id"]} | {", ".join(result["requirement_ids"])} | {result["title"]} | {result["status"]} | {note} {evidence} |')
    if summary.get("movie"):
        lines += ["", f'[Godot 过程录像]({artifact_relative}/{summary["movie"]})：引擎 Movie Maker 输出，不是桌面录屏，不用于证明真实耗时。']
    lines += ["", "需求及源文件原始副本位于证据目录 baseline/；开始与结束哈希在 manifest.json。修改来源后旧报告只代表旧版本，需要重跑受影响用例。", ""]
    (report_dir / (summary["run_id"] + ".md")).write_text("\n".join(lines), encoding="utf-8")


def execute(args):
    catalog = load_catalog()
    paths = input_files(catalog)
    before = signature(paths)
    run_id = datetime.now().strftime("%Y%m%d-%H%M%S-%f")
    run_dir = ROOT / ".artifacts/self-tests" / run_id
    run_dir.mkdir(parents=True, exist_ok=False)
    for path in paths:
        destination = run_dir / "baseline" / path.relative_to(ROOT)
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(path, destination)
    flags = subprocess.CREATE_NO_WINDOW if os.name == "nt" else 0
    version = subprocess.check_output([str(args.godot), "--version"], creationflags=flags, timeout=15).decode().strip()
    if not version.startswith("4.6.1."):
        raise ValueError("当前基线要求 Godot 4.6.1，实际为 " + version)
    started_at = datetime.now(timezone.utc).isoformat()
    harness = subprocess.run([sys.executable, str(ROOT / "tests/test_runner_contract.py")], cwd=ROOT, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=30, creationflags=flags)
    (run_dir / "harness.log").write_bytes(harness.stdout)
    stages = {"harness": {"exit_code": harness.returncode, "log": "harness.log"}}
    stages["import"] = run_engine(args.godot, ["--headless", "--editor", "--import"], run_dir / "import.log") if harness.returncode == 0 else {"exit_code": -1, "errors": True, "reason": "追踪校验器自检失败"}
    collected = []
    for suite, script in [("domain", "res://tests/run_tests.gd"), ("gui", "res://tests/run_gui_tests.gd")]:
        definitions = [case for case in catalog["cases"] if case["suite"] == suite]
        if stages["import"]["exit_code"] != 0 or stages["import"]["errors"]:
            collected.extend(blocked(case, "项目导入失败，未执行该用例") for case in definitions)
            continue
        engine_args = ["--headless"] if suite == "domain" else ["--rendering-method", "gl_compatibility", "--position", args.position]
        if suite == "gui" and args.record_movie:
            engine_args += ["--write-movie", str(run_dir / "gui.avi"), "--fixed-fps", "30"]
        engine_args += ["--script", script, "--", "--evidence-dir=" + run_dir.as_posix(), "--run-id=" + run_id]
        stages[suite] = run_engine(args.godot, engine_args, run_dir / (suite + ".log"))
        try:
            data = json.loads((run_dir / (suite + ".json")).read_text(encoding="utf-8"))
            results = validate_suite(data, definitions, run_id, run_dir, version)
            if (stages[suite]["exit_code"] != 0 or stages[suite]["errors"]) and not any(item["status"] == "FAILED" for item in results):
                raise ValueError("引擎报告错误，不能采用看似通过的结果")
            collected.extend(results)
        except (ValueError, KeyError, OSError, TypeError) as error:
            collected.extend(blocked(case, "结果无效：" + str(error)) for case in definitions)
    for definition in catalog["cases"]:
        if definition["suite"] == "manual":
            collected.append({"case_id": definition["id"], "status": "NOT_RUN", "assertions": [], "evidence": [], "reason": "尚未实际查看本轮截图；需另行记录视觉审阅"})
    definitions = {case["id"]: case for case in catalog["cases"]}
    for result in collected:
        definition = definitions[result["case_id"]]
        result.update(title=definition["title"], requirement_ids=definition["requirement_ids"], suite=definition["suite"])
    after = signature(input_files(catalog))
    consistent = before == after
    if not consistent:
        for result in collected:
            result["status"] = "BLOCKED"
            result["reason"] = "测试过程中输入发生变化；保留原始结果但本次汇总不可用于验收"
    movie = "gui.avi" if (run_dir / "gui.avi").is_file() else None
    if args.record_movie and (not movie or (run_dir / movie).stat().st_size < 12):
        for result in collected:
            if result["suite"] == "gui":
                result["status"] = "BLOCKED"
                result["reason"] = "已要求录像，但有效录像文件未生成"
    manifest = {
        "run_id": run_id, "started_at": started_at, "engine": version,
        "engine_path": str(args.godot), "engine_sha256": sha(args.godot),
        "git_head": subprocess.run(["git", "rev-parse", "HEAD"], cwd=ROOT, capture_output=True, text=True).stdout.strip(),
        "inputs_before": before, "inputs_after": after, "input_consistent": consistent, "stages": stages,
        "movie_requested": args.record_movie, "scope": SCOPE, "scene_path": SCENE_PATH,
    }
    manifest["git_status"] = subprocess.run(["git", "status", "--short"], cwd=ROOT, capture_output=True).stdout.decode("utf-8", errors="replace")
    manifest["evidence_sha256"] = {path.relative_to(run_dir).as_posix(): sha(path) for path in run_dir.rglob("*") if path.is_file() and not path.is_relative_to(run_dir / "baseline")}
    write_json(run_dir / "manifest.json", manifest)
    summary = {"schema_version": 1, "run_id": run_id, "started_at": started_at, "engine": version,
               "input_consistent": consistent, "cases": collected, "movie": movie, "scope": SCOPE, "scene_path": SCENE_PATH}
    save_report(run_dir, summary)
    print("RUN_ID=" + run_id)
    print("REPORT=" + str(ROOT / "docs/testing/执行记录" / (run_id + ".md")))
    print("SCOPE=" + SCOPE + " AUTO=" + summary["automatic_status"] + " M0=" + summary["m0_status"] + " FULL_GAME=NOT_ACCEPTED")
    return 0 if summary["m0_status"] == "PASSED" else (2 if summary["automatic_status"] == "PASSED" else 1)


def review(args):
    if not re.fullmatch(r"[0-9-]+", args.run_id):
        raise ValueError("运行编号无效")
    run_dir = ROOT / ".artifacts/self-tests" / args.run_id
    manifest = json.loads((run_dir / "manifest.json").read_text(encoding="utf-8"))
    for relative, digest in manifest.get("evidence_sha256", {}).items():
        if sha(contained_evidence(run_dir, relative)) != digest:
            raise ValueError("运行后证据发生变化：" + relative)
    catalog = load_catalog()
    if signature(input_files(catalog)) != manifest["inputs_before"]:
        raise ValueError("来源或代码已改变，不能将旧运行审阅为当前版本通过")
    summary = json.loads((run_dir / "summary.json").read_text(encoding="utf-8"))
    if summary["automatic_status"] != "PASSED":
        raise ValueError("自动用例尚未通过，先处理失败或阻塞")
    for path in args.evidence:
        contained_evidence(run_dir, path)
    if args.status == "PASSED" and not set(["screenshots/01_initial.png", "screenshots/02_partial.png", "screenshots/03_selected.png", "screenshots/05_reset.png", "screenshots/06_reselected.png"]).issubset(args.evidence):
        raise ValueError("视觉通过须覆盖用例要求的五类画面")
    visual = {"case_id": "TC-VIS-001", "status": args.status, "reviewer": args.reviewer,
              "reviewed_at": datetime.now(timezone.utc).isoformat(), "notes": args.notes,
              "evidence": args.evidence, "method": "人工查看实际Godot截图；不代表OS鼠标或音频验收"}
    review_path = run_dir / "visual_review.json"
    if review_path.exists():
        archive = run_dir / ("visual_review-" + datetime.now().strftime("%H%M%S%f") + ".json")
        shutil.copy2(review_path, archive)
    write_json(review_path, visual)
    for result in summary["cases"]:
        if result["case_id"] == "TC-VIS-001":
            result.update(status=args.status, evidence=args.evidence + ["visual_review.json"], reason=args.notes)
    save_report(run_dir, summary)
    print("M0=" + summary["m0_status"] + " FULL_GAME=NOT_ACCEPTED")
    return 0 if summary["m0_status"] == "PASSED" else 1


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)
    run = sub.add_parser("run")
    run.add_argument("--godot", type=Path, required=True)
    run.add_argument("--record-movie", action="store_true")
    run.add_argument("--position", default="80,80")
    inspect = sub.add_parser("review")
    inspect.add_argument("--run-id", required=True)
    inspect.add_argument("--status", choices=["PASSED", "FAILED", "BLOCKED"], required=True)
    inspect.add_argument("--reviewer", required=True)
    inspect.add_argument("--notes", required=True)
    inspect.add_argument("--evidence", action="append", default=[])
    sub.add_parser("validate")
    args = parser.parse_args()
    if args.command == "validate":
        load_catalog()
        print("Catalog sources and case links valid.")
        return 0
    return execute(args) if args.command == "run" else review(args)


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (ValueError, KeyError, OSError, subprocess.SubprocessError) as error:
        print("ERROR: " + str(error), file=sys.stderr)
        sys.exit(1)
