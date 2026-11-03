from pathlib import Path
from unittest.mock import patch
import tempfile
import unittest

from bridge import (
    classify_window, crc_x25, data_snapshot, decode_output, output_complete,
    output_counts, output_has_new_evidence,
    required_editors_ready, task_lock, verify_runtime_dependencies,
)


class BridgeTest(unittest.TestCase):
    def test_both_rich_text_boxes_must_be_ready(self):
        class Info:
            def __init__(self, automation_id, control_type="Edit"):
                self.automation_id = automation_id
                self.control_type = control_type

        class Control:
            def __init__(self, automation_id, control_type="Edit"):
                self.element_info = Info(automation_id, control_type)

        self.assertFalse(required_editors_ready([Control("RichTextBox1")]))
        self.assertTrue(required_editors_ready([
            Control("RichTextBox1"), Control("RichTextBox2")
        ]))

    def test_old_output_requires_new_evidence(self):
        old = "完整的旧输出"
        self.assertFalse(output_has_new_evidence(old, old, False, 0))
        self.assertTrue(output_has_new_evidence(old, "新输出", False, 0))
        self.assertTrue(output_has_new_evidence(old, old, True, 0))
        self.assertTrue(output_has_new_evidence(old, old, False, 1))

    def test_window_state_requires_dialog_evidence(self):
        self.assertEqual(classify_window(True, True, False, []), "disabled")
        self.assertEqual(classify_window(True, True, False, ["提示"]), "modal")
        self.assertEqual(classify_window(False, False, False, []), "closed")

    def test_crc_known_official_sample(self):
        self.assertEqual(crc_x25(bytes.fromhex("05010000")), 0xC855)

    def test_complete_output_accepts_official_error_packages(self):
        text = "原始数据:78 78\nParsing Time:10ms\n序列号段丢失共有:0段\n共有错误的数据包:9个"
        self.assertTrue(output_complete(text))
        self.assertEqual(output_counts(text), {"output_packets": 1, "official_error_packets": 9})
        self.assertFalse(output_complete("旧的半截输出"))

    def test_progress_survives_invalid_noconsole_stdout(self):
        class InvalidOutput:
            def write(self, _):
                raise OSError(22, "Invalid argument")
            def flush(self):
                raise OSError(22, "Invalid argument")
        from bridge import progress
        with patch("bridge.sys.stdout", InvalidOutput()):
            progress("仍应写入文件或安全忽略控制台")

    def test_encodings(self):
        text = "原始数据:78 78\n包类型:心跳包"
        for encoding in ("utf-8-sig", "gb18030"):
            self.assertEqual(decode_output(text.encode(encoding)), text)

    def test_runtime_dependencies_available(self):
        verify_runtime_dependencies()

    def test_snapshot_and_single_task_lock(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            before = data_snapshot(root)
            (root / "new.txt").write_text("new")
            self.assertNotEqual(before, data_snapshot(root))
            exe = root / "ProtocolAnalysis.exe"
            with task_lock(exe):
                with self.assertRaisesRegex(RuntimeError, "另一个桥接任务"):
                    with task_lock(exe):
                        pass
            with task_lock(exe):
                pass


if __name__ == "__main__":
    unittest.main()
