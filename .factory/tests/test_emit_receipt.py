#!/usr/bin/env python3
"""Tests for .factory/bin/emit-receipt.py.

Uses stdlib unittest (no pytest).
Covers:
- valid emission for each of complete/failed/killed
- rejection of bad status enum
- rejection of killed-with-null-kill_reason
- rejection of negative token counts
- --validate-only accepting valid receipt and rejecting deliberately broken receipts
"""

import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parent.parent.parent
EMIT_RECEIPT_BIN = REPO_ROOT / ".factory" / "bin" / "emit-receipt.py"
SCHEMA_PATH = REPO_ROOT / ".factory" / "schemas" / "execution_receipt.schema.json"


class TestEmitReceiptCLI(unittest.TestCase):
    def setUp(self) -> None:
        self.temp_dir = tempfile.TemporaryDirectory()
        self.work_dir = Path(self.temp_dir.name)

    def tearDown(self) -> None:
        self.temp_dir.cleanup()

    def run_cli(
        self,
        args: list[str],
        cwd: Path | None = None,
    ) -> subprocess.CompletedProcess[str]:
        cmd = [sys.executable, str(EMIT_RECEIPT_BIN)] + args
        return subprocess.run(
            cmd,
            cwd=str(cwd or REPO_ROOT),
            capture_output=True,
            text=True,
            check=False,
        )

    def test_emit_valid_complete(self) -> None:
        """Valid emission with status=complete produces a valid receipt."""
        receipt_file = self.work_dir / "receipt_complete.json"
        res = self.run_cli(
            [
                "--receipt",
                str(receipt_file),
                "--wave-id",
                "test-complete-wave",
                "--status",
                "complete",
                "--environment",
                "headless-vm",
                "--branch-policy",
                "wave-branch",
                "--branch",
                "wave/test-complete",
                "--git-commit",
                "0123456789abcdef",
                "--diff-stat",
                "2",
                "15",
                "3",
                "--patch-file",
                ".factory/diffs/test.patch",
                "--test-verdict",
                "PASS",
                "--token-burn",
                "12000",
                "850",
                "--attempts-used",
                "1",
            ]
        )
        self.assertEqual(res.returncode, 0, f"CLI failed: {res.stderr}")
        self.assertTrue(receipt_file.exists())

        with open(receipt_file, "r", encoding="utf-8") as f:
            data = json.load(f)

        self.assertEqual(data["status"], "complete")
        self.assertEqual(data["wave_id"], "test-complete-wave")
        self.assertEqual(data["diff_stat"], {"files_changed": 2, "insertions": 15, "deletions": 3})
        self.assertEqual(data["token_burn"], {"input": 12000, "output": 850})
        self.assertIsNone(data["blocker_reason"])
        self.assertIsNone(data["kill_reason"])

        # Also verify with --validate-only
        v_res = self.run_cli(["--validate-only", "--receipt", str(receipt_file)])
        self.assertEqual(v_res.returncode, 0, f"Validate-only failed: {v_res.stderr}")

    def test_emit_valid_failed(self) -> None:
        """Valid emission with status=failed records blocker_reason."""
        receipt_file = self.work_dir / "receipt_failed.json"
        res = self.run_cli(
            [
                "--receipt",
                str(receipt_file),
                "--wave-id",
                "test-failed-wave",
                "--status",
                "failed",
                "--environment",
                "headless-vm",
                "--branch-policy",
                "wave-branch",
                "--branch",
                "wave/test-failed",
                "--git-commit",
                "abcdef0123456789",
                "--files-changed",
                "1",
                "--insertions",
                "5",
                "--deletions",
                "0",
                "--patch-file",
                ".factory/diffs/fail.patch",
                "--test-verdict",
                "FAIL",
                "--token-input",
                "30000",
                "--token-output",
                "1200",
                "--blocker_reason",
                "Integration test suite timed out waiting for backend",
                "--attempts-used",
                "1",
            ]
        )
        self.assertEqual(res.returncode, 0, f"CLI failed: {res.stderr}")
        self.assertTrue(receipt_file.exists())

        with open(receipt_file, "r", encoding="utf-8") as f:
            data = json.load(f)

        self.assertEqual(data["status"], "failed")
        self.assertEqual(data["test_verdict"], "FAIL")
        self.assertIn("timed out", data["blocker_reason"])
        self.assertIsNone(data["kill_reason"])

        v_res = self.run_cli(["--validate-only", "--receipt", str(receipt_file)])
        self.assertEqual(v_res.returncode, 0, f"Validate-only failed: {v_res.stderr}")

    def test_emit_valid_killed(self) -> None:
        """Valid emission with status=killed requires and stores a structured kill_reason."""
        receipt_file = self.work_dir / "receipt_killed.json"
        res = self.run_cli(
            [
                "--receipt",
                str(receipt_file),
                "--wave-id",
                "test-killed-wave",
                "--status",
                "killed",
                "--environment",
                "headless-vm",
                "--branch-policy",
                "wave-branch",
                "--branch",
                "wave/test-killed",
                "--git-commit",
                "none",
                "--files-changed",
                "0",
                "--insertions",
                "0",
                "--deletions",
                "0",
                "--patch-file",
                "null",
                "--test-verdict",
                "NOT_RUN",
                "--token-burn",
                "405000",
                "1200",
                "--kill-reason",
                "budget-exceeded",
                "--attempts-used",
                "1",
            ]
        )
        self.assertEqual(res.returncode, 0, f"CLI failed: {res.stderr}")
        self.assertTrue(receipt_file.exists())

        with open(receipt_file, "r", encoding="utf-8") as f:
            data = json.load(f)

        self.assertEqual(data["status"], "killed")
        self.assertEqual(data["kill_reason"], "budget-exceeded")
        self.assertIsNone(data["git_commit"])
        self.assertIsNone(data["patch_file"])

        v_res = self.run_cli(["--validate-only", "--receipt", str(receipt_file)])
        self.assertEqual(v_res.returncode, 0, f"Validate-only failed: {v_res.stderr}")

    def test_rejection_bad_status_enum(self) -> None:
        """Rejects bad status enum with non-zero exit code and named error."""
        receipt_file = self.work_dir / "bad_status.json"
        # Negative test: invalid status
        res = self.run_cli(
            [
                "--receipt",
                str(receipt_file),
                "--wave-id",
                "bad-status-wave",
                "--status",
                "in-progress",
                "--environment",
                "headless-vm",
                "--branch-policy",
                "wave-branch",
                "--test-verdict",
                "PASS",
            ]
        )
        self.assertNotEqual(res.returncode, 0)
        self.assertIn("invalid status", res.stderr)
        self.assertFalse(receipt_file.exists())

        # Positive counterpart: changing status to complete succeeds
        res_ok = self.run_cli(
            [
                "--receipt",
                str(receipt_file),
                "--wave-id",
                "bad-status-wave",
                "--status",
                "complete",
                "--environment",
                "headless-vm",
                "--branch-policy",
                "wave-branch",
                "--test-verdict",
                "PASS",
            ]
        )
        self.assertEqual(res_ok.returncode, 0)
        self.assertTrue(receipt_file.exists())

    def test_rejection_killed_with_null_kill_reason(self) -> None:
        """Rejects status=killed when kill_reason is null or omitted."""
        receipt_file = self.work_dir / "killed_no_reason.json"
        # Negative test 1: kill-reason omitted
        res1 = self.run_cli(
            [
                "--receipt",
                str(receipt_file),
                "--wave-id",
                "killed-wave",
                "--status",
                "killed",
                "--environment",
                "headless-vm",
                "--branch-policy",
                "wave-branch",
                "--test-verdict",
                "NOT_RUN",
            ]
        )
        self.assertNotEqual(res1.returncode, 0)
        self.assertIn("kill_reason is null or missing", res1.stderr)
        self.assertFalse(receipt_file.exists())

        # Negative test 2: kill-reason explicit null
        res2 = self.run_cli(
            [
                "--receipt",
                str(receipt_file),
                "--wave-id",
                "killed-wave",
                "--status",
                "killed",
                "--environment",
                "headless-vm",
                "--branch-policy",
                "wave-branch",
                "--test-verdict",
                "NOT_RUN",
                "--kill-reason",
                "null",
            ]
        )
        self.assertNotEqual(res2.returncode, 0)
        self.assertIn("kill_reason is null or missing", res2.stderr)
        self.assertFalse(receipt_file.exists())

        # Positive counterpart: providing kill-reason succeeds
        res_ok = self.run_cli(
            [
                "--receipt",
                str(receipt_file),
                "--wave-id",
                "killed-wave",
                "--status",
                "killed",
                "--environment",
                "headless-vm",
                "--branch-policy",
                "wave-branch",
                "--test-verdict",
                "NOT_RUN",
                "--kill-reason",
                "timeout",
            ]
        )
        self.assertEqual(res_ok.returncode, 0)
        self.assertTrue(receipt_file.exists())

    def test_rejection_negative_token_counts(self) -> None:
        """Rejects negative token counts with non-zero exit and named error."""
        receipt_file = self.work_dir / "neg_tokens.json"

        # Negative test 1: negative token input
        res1 = self.run_cli(
            [
                "--receipt",
                str(receipt_file),
                "--wave-id",
                "neg-tokens-wave",
                "--status",
                "complete",
                "--environment",
                "headless-vm",
                "--branch-policy",
                "wave-branch",
                "--test-verdict",
                "PASS",
                "--token-input",
                "-100",
                "--token-output",
                "50",
            ]
        )
        self.assertNotEqual(res1.returncode, 0)
        self.assertIn("negative token count rejected", res1.stderr)
        self.assertFalse(receipt_file.exists())

        # Negative test 2: negative token burn output via --token-burn
        res2 = self.run_cli(
            [
                "--receipt",
                str(receipt_file),
                "--wave-id",
                "neg-tokens-wave",
                "--status",
                "complete",
                "--environment",
                "headless-vm",
                "--branch-policy",
                "wave-branch",
                "--test-verdict",
                "PASS",
                "--token-burn",
                "1000",
                "-25",
            ]
        )
        self.assertNotEqual(res2.returncode, 0)
        self.assertIn("negative token count rejected", res2.stderr)
        self.assertFalse(receipt_file.exists())

        # Positive counterpart: non-negative token counts succeed
        res_ok = self.run_cli(
            [
                "--receipt",
                str(receipt_file),
                "--wave-id",
                "neg-tokens-wave",
                "--status",
                "complete",
                "--environment",
                "headless-vm",
                "--branch-policy",
                "wave-branch",
                "--test-verdict",
                "PASS",
                "--token-burn",
                "1000",
                "25",
            ]
        )
        self.assertEqual(res_ok.returncode, 0)
        self.assertTrue(receipt_file.exists())

    def test_rejection_kill_reason_when_not_killed(self) -> None:
        """Rejects non-null kill_reason when status is complete or failed."""
        receipt_file = self.work_dir / "invalid_kill_reason.json"
        res = self.run_cli(
            [
                "--receipt",
                str(receipt_file),
                "--wave-id",
                "bad-kill-wave",
                "--status",
                "complete",
                "--environment",
                "headless-vm",
                "--branch-policy",
                "wave-branch",
                "--test-verdict",
                "PASS",
                "--kill-reason",
                "budget-exceeded",
            ]
        )
        self.assertNotEqual(res.returncode, 0)
        self.assertIn("kill_reason must be null when status is not 'killed'", res.stderr)
        self.assertFalse(receipt_file.exists())

    def test_validate_only_accepts_valid_receipt(self) -> None:
        """--validate-only accepts an existing valid receipt."""
        # Default receipt in repo
        res = self.run_cli(["--validate-only", "--receipt", ".factory/receipt.json"])
        self.assertEqual(res.returncode, 0, f"Failed to validate existing receipt: {res.stderr}")
        self.assertIn("Receipt is valid", res.stdout)

    def test_validate_only_rejects_broken_receipts(self) -> None:
        """--validate-only rejects various deliberately broken receipt structures."""
        # Broken case 1: missing required field (wave_id)
        broken_1 = self.work_dir / "missing_wave_id.json"
        with open(broken_1, "w", encoding="utf-8") as f:
            json.dump(
                {
                    "$schema": "./schemas/execution_receipt.schema.json",
                    "status": "complete",
                    "environment": "headless-vm",
                    "branch_policy": "wave-branch",
                    "git_commit": "abc",
                    "diff_stat": {"files_changed": 1, "insertions": 1, "deletions": 0},
                    "patch_file": None,
                    "test_verdict": "PASS",
                    "blocker_reason": None,
                    "attempts_used": 1,
                },
                f,
            )
        res1 = self.run_cli(["--validate-only", "--receipt", str(broken_1)])
        self.assertNotEqual(res1.returncode, 0)
        self.assertIn("required property", res1.stderr)

        # Broken case 2: killed status with null kill_reason
        broken_2 = self.work_dir / "killed_null_reason.json"
        with open(broken_2, "w", encoding="utf-8") as f:
            json.dump(
                {
                    "$schema": "./schemas/execution_receipt.schema.json",
                    "wave_id": "test-killed-null",
                    "status": "killed",
                    "environment": "headless-vm",
                    "branch_policy": "wave-branch",
                    "git_commit": None,
                    "diff_stat": {"files_changed": 0, "insertions": 0, "deletions": 0},
                    "patch_file": None,
                    "test_verdict": "NOT_RUN",
                    "blocker_reason": None,
                    "kill_reason": None,
                    "attempts_used": 1,
                },
                f,
            )
        res2 = self.run_cli(["--validate-only", "--receipt", str(broken_2)])
        self.assertNotEqual(res2.returncode, 0)
        self.assertIn("kill_reason is null or missing", res2.stderr)

        # Broken case 3: negative token counts in receipt file
        broken_3 = self.work_dir / "negative_tokens.json"
        with open(broken_3, "w", encoding="utf-8") as f:
            json.dump(
                {
                    "$schema": "./schemas/execution_receipt.schema.json",
                    "wave_id": "test-neg-tokens",
                    "status": "complete",
                    "environment": "headless-vm",
                    "branch_policy": "wave-branch",
                    "git_commit": "abc",
                    "diff_stat": {"files_changed": 1, "insertions": 1, "deletions": 0},
                    "patch_file": None,
                    "test_verdict": "PASS",
                    "token_burn": {"input": -50, "output": 10},
                    "blocker_reason": None,
                    "attempts_used": 1,
                },
                f,
            )
        res3 = self.run_cli(["--validate-only", "--receipt", str(broken_3)])
        self.assertNotEqual(res3.returncode, 0)
        self.assertIn("negative token count rejected", res3.stderr)

        # Broken case 4: non-existent receipt file
        res4 = self.run_cli(["--validate-only", "--receipt", str(self.work_dir / "does_not_exist.json")])
        self.assertNotEqual(res4.returncode, 0)
        self.assertIn("receipt file not found", res4.stderr)

    def test_schema_path_relative_to_script(self) -> None:
        """Tool resolves schema correctly even when run from an arbitrary working directory."""
        external_dir = self.work_dir / "some_other_dir"
        external_dir.mkdir()
        receipt_file = external_dir / "out.json"

        res = self.run_cli(
            [
                "--receipt",
                str(receipt_file),
                "--wave-id",
                "rel-path-wave",
                "--status",
                "complete",
                "--environment",
                "local-mac",
                "--branch-policy",
                "direct-main",
                "--test-verdict",
                "PASS",
            ],
            cwd=external_dir,
        )
        self.assertEqual(res.returncode, 0, f"Failed when invoked from outside dir: {res.stderr}")
        self.assertTrue(receipt_file.exists())


if __name__ == "__main__":
    unittest.main()
