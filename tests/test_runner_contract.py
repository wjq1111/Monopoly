"""测试基础设施的反误报检查。来源：用户要求的需求追踪、逐例状态与证据规则；不计入游戏功能通过数。"""
import copy
import importlib.util
import json
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("self_test_runner", ROOT / "scripts/self_test.py")
runner = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runner)


class RunnerContract(unittest.TestCase):
    def setUp(self):
        self.catalog = runner.load_catalog()
        self.definition = [{"id": "TC-X", "suite": "domain", "evidence_required": False}]
        self.result = {
            "run_id": "unit-run", "suite": "domain", "engine": "4.6.1.test",
            "cases": [{"case_id": "TC-X", "status": "PASSED", "assertions": [{"passed": True}], "evidence": []}]
        }

    def validate(self):
        return runner.validate_suite(self.result, self.definition, "unit-run", ROOT / ".artifacts/nonexistent-test-evidence", "4.6.1.test")

    def test_valid_result(self):
        self.assertEqual(self.validate()[0]["status"], "PASSED")

    def test_unknown_requirement(self):
        self.catalog["cases"][0]["requirement_ids"] = ["REQ-NOT-FOUND"]
        with self.assertRaises(ValueError):
            runner.validate_catalog(self.catalog)

    def test_quote_must_match_requirement(self):
        self.catalog["requirements"][0]["sources"][0]["quote"] = "本句不存在于原需求"
        with self.assertRaises(ValueError):
            runner.validate_catalog(self.catalog)

    def test_duplicate_case(self):
        self.catalog["cases"].append(copy.deepcopy(self.catalog["cases"][0]))
        with self.assertRaises(ValueError):
            runner.validate_catalog(self.catalog)

    def test_failed_assertion_cannot_pass(self):
        self.result["cases"][0]["assertions"][0]["passed"] = False
        with self.assertRaises(ValueError):
            self.validate()

    def test_empty_assertions_cannot_pass(self):
        self.result["cases"][0]["assertions"] = []
        with self.assertRaises(ValueError):
            self.validate()

    def test_missing_case(self):
        self.result["cases"] = []
        with self.assertRaises(ValueError):
            self.validate()

    def test_wrong_run(self):
        self.result["run_id"] = "another-run"
        with self.assertRaises(ValueError):
            self.validate()

    def test_wrong_engine(self):
        self.result["engine"] = "4.5.test"
        with self.assertRaises(ValueError):
            self.validate()

    def test_missing_evidence(self):
        self.definition[0]["evidence_required"] = True
        self.result["cases"][0]["evidence"] = ["does-not-exist.png"]
        with self.assertRaises(ValueError):
            self.validate()

    def test_headless_cannot_claim_gui(self):
        self.definition[0]["suite"] = "gui"
        self.result.update(suite="gui", display_server="headless", metadata={"input_method": "Input.parse_input_event"})
        with self.assertRaises(ValueError):
            self.validate()

    def test_code_comment_is_not_markdown_heading(self):
        text = "## 启动\n\n```powershell\n# 注释\n```\n真正需求\n## 后续\n"
        self.assertIn("真正需求", runner.section_text(text, "启动"))


if __name__ == "__main__":
    unittest.main(verbosity=2)
