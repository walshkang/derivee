#!/usr/bin/env python3
"""CLI for emitting and validating .factory/receipt.json.

Conforms to .factory/schemas/execution_receipt.schema.json.
"""

import argparse
import json
import sys
from pathlib import Path
from typing import Any

import jsonschema


VALID_STATUSES = {"complete", "failed", "killed"}
VALID_ENVIRONMENTS = {"local-mac", "headless-vm"}
VALID_BRANCH_POLICIES = {"wave-branch", "patch-only", "direct-main"}
VALID_TEST_VERDICTS = {"PASS", "FAIL", "NOT_RUN"}
VALID_KILL_REASONS = {
    "budget-exceeded",
    "timeout",
    "scope-violation",
    "attempt-limit",
    "environment-ceiling",
    "manual",
}


def get_repo_root() -> Path:
    """Derive repo root from script location: <repo>/.factory/bin/emit-receipt.py"""
    return Path(__file__).resolve().parent.parent.parent


def get_default_schema_path() -> Path:
    """Resolve schema relative to the script location / repo root."""
    return get_repo_root() / ".factory" / "schemas" / "execution_receipt.schema.json"


def get_default_receipt_path() -> Path:
    """Resolve default receipt path relative to repo root."""
    return get_repo_root() / ".factory" / "receipt.json"


def parse_nullable_str(val: str | None) -> str | None:
    """Normalize CLI string inputs where 'null', 'none', or empty string mean null."""
    if val is None:
        return None
    stripped = val.strip()
    if stripped.lower() in ("null", "none", ""):
        return None
    return stripped


def validate_receipt_dict(data: dict[str, Any], schema_path: Path | None = None) -> list[str]:
    """Validate receipt dictionary against schema and strict business rules.

    Returns a list of error strings (empty if valid).
    """
    if schema_path is None:
        schema_path = get_default_schema_path()

    if not schema_path.exists():
        return [f"Schema file not found at {schema_path}"]

    try:
        with open(schema_path, "r", encoding="utf-8") as f:
            schema = json.load(f)
    except Exception as exc:
        return [f"Failed to read schema from {schema_path}: {exc}"]

    errors: list[str] = []

    # Stricter checks: status and kill_reason
    status = data.get("status")
    kill_reason = data.get("kill_reason")

    if status not in VALID_STATUSES:
        errors.append(
            f"Validation error: invalid status '{status}'. Must be one of: {', '.join(sorted(VALID_STATUSES))}"
        )

    if status == "killed":
        if not kill_reason:
            errors.append(
                "Validation error: status is 'killed' but kill_reason is null or missing. A killed wave must provide a kill_reason."
            )
        elif kill_reason not in VALID_KILL_REASONS:
            errors.append(
                f"Validation error: invalid kill_reason '{kill_reason}'. Must be one of: {', '.join(sorted(VALID_KILL_REASONS))}"
            )
    elif status in ("complete", "failed"):
        if kill_reason is not None:
            errors.append(
                f"Validation error: kill_reason must be null when status is not 'killed' (status is '{status}', got kill_reason '{kill_reason}')"
            )

    # Stricter checks: negative token counts
    if "token_burn" in data:
        tb = data["token_burn"]
        if isinstance(tb, dict):
            in_tokens = tb.get("input")
            out_tokens = tb.get("output")
            if isinstance(in_tokens, (int, float)) and in_tokens < 0:
                errors.append(
                    f"Validation error: negative token count rejected: token_burn.input ({in_tokens}) cannot be negative"
                )
            if isinstance(out_tokens, (int, float)) and out_tokens < 0:
                errors.append(
                    f"Validation error: negative token count rejected: token_burn.output ({out_tokens}) cannot be negative"
                )

    # Stricter checks: diff_stat counts
    if "diff_stat" in data:
        ds = data["diff_stat"]
        if isinstance(ds, dict):
            for k in ("files_changed", "insertions", "deletions"):
                v = ds.get(k)
                if isinstance(v, (int, float)) and v < 0:
                    errors.append(
                        f"Validation error: negative diff_stat count rejected: {k} ({v}) cannot be negative"
                    )

    # Stricter checks: attempts_used
    attempts_used = data.get("attempts_used")
    if isinstance(attempts_used, (int, float)) and attempts_used < 0:
        errors.append(
            f"Validation error: attempts_used ({attempts_used}) cannot be negative"
        )

    # JSON Schema validation
    try:
        validator = jsonschema.Draft7Validator(schema)
        for err in validator.iter_errors(data):
            path_str = ".".join(str(p) for p in err.path)
            # Avoid duplicate messages if custom check already surfaced it cleanly
            if path_str == "status" and any("invalid status" in e for e in errors):
                continue
            if path_str in ("token_burn.input", "token_burn.output") and any(
                "negative token count" in e for e in errors
            ):
                continue
            if path_str in (
                "diff_stat.files_changed",
                "diff_stat.insertions",
                "diff_stat.deletions",
            ) and any("diff_stat" in e for e in errors):
                continue
            if path_str == "attempts_used" and any("attempts_used" in e for e in errors):
                continue
            loc = f" at '{path_str}'" if path_str else ""
            errors.append(f"Schema validation error{loc}: {err.message}")
    except Exception as exc:
        errors.append(f"JSON schema validator failure: {exc}")

    return errors


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Emit or validate .factory/receipt.json conforming to execution_receipt.schema.json."
    )
    parser.add_argument(
        "--receipt",
        type=str,
        default=None,
        help="Path to receipt JSON file (default: .factory/receipt.json relative to repo root).",
    )
    parser.add_argument(
        "--validate-only",
        action="store_true",
        help="Validate existing receipt file against schema and strict rules without writing.",
    )
    parser.add_argument(
        "--schema",
        type=str,
        default=None,
        help="Path to custom schema file (default: derived from script location).",
    )

    # Receipt fields
    parser.add_argument("--wave-id", "--wave_id", type=str, default=None, dest="wave_id", help="Wave identifier.")
    parser.add_argument("--status", type=str, default=None, help="Wave status: complete, failed, killed.")
    parser.add_argument("--environment", type=str, default=None, help="Execution environment: local-mac, headless-vm.")
    parser.add_argument(
        "--branch-policy",
        "--branch_policy",
        type=str,
        default=None,
        dest="branch_policy",
        help="Delivery policy: wave-branch, patch-only, direct-main.",
    )
    parser.add_argument("--branch", type=str, default=None, help="Git branch name (or null).")
    parser.add_argument("--git-commit", "--git_commit", type=str, default=None, dest="git_commit", help="Git commit SHA (or null).")
    parser.add_argument(
        "--diff-stat",
        "--diff_stat",
        nargs=3,
        type=int,
        metavar=("FILES", "INS", "DEL"),
        default=None,
        dest="diff_stat",
        help="Diff stat as 3 integers: files_changed insertions deletions.",
    )
    parser.add_argument("--files-changed", "--files_changed", type=int, default=None, dest="files_changed", help="Files changed count.")
    parser.add_argument("--insertions", type=int, default=None, help="Insertions count.")
    parser.add_argument("--deletions", type=int, default=None, help="Deletions count.")
    parser.add_argument("--patch-file", "--patch_file", type=str, default=None, dest="patch_file", help="Relative path to .patch file (or null).")
    parser.add_argument("--test-verdict", "--test_verdict", type=str, default=None, dest="test_verdict", help="Test verdict: PASS, FAIL, NOT_RUN.")
    parser.add_argument(
        "--token-burn",
        "--token_burn",
        nargs=2,
        type=int,
        metavar=("INPUT", "OUTPUT"),
        default=None,
        dest="token_burn",
        help="Token burn as 2 integers: input output.",
    )
    parser.add_argument("--token-input", "--tokens-in", "--token_input", type=int, default=None, dest="token_input", help="Input tokens.")
    parser.add_argument("--token-output", "--tokens-out", "--token_output", type=int, default=None, dest="token_output", help="Output tokens.")
    parser.add_argument("--blocker-reason", "--blocker_reason", type=str, default=None, dest="blocker_reason", help="Blocker reason (or null).")
    parser.add_argument("--attempts-used", "--attempts_used", type=int, default=1, dest="attempts_used", help="Attempts consumed (default: 1).")
    parser.add_argument("--kill-reason", "--kill_reason", type=str, default=None, dest="kill_reason", help="Kill reason if killed (or null).")
    parser.add_argument(
        "--discoveries",
        type=str,
        default=None,
        help="JSON string or file path containing discoveries array (max 5 items).",
    )
    parser.add_argument(
        "--schema-ref",
        "--schema_ref",
        type=str,
        default="./schemas/execution_receipt.schema.json",
        dest="schema_ref",
        help="Value for $schema field in the emitted receipt.",
    )
    return parser


def run(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)

    schema_path = Path(args.schema) if args.schema else get_default_schema_path()
    receipt_path = Path(args.receipt) if args.receipt else get_default_receipt_path()

    if args.validate_only:
        if not receipt_path.exists():
            sys.stderr.write(f"Validation error: receipt file not found: {receipt_path}\n")
            return 1
        try:
            with open(receipt_path, "r", encoding="utf-8") as f:
                data = json.load(f)
        except Exception as exc:
            sys.stderr.write(f"Validation error: failed to parse JSON in {receipt_path}: {exc}\n")
            return 1

        errors = validate_receipt_dict(data, schema_path=schema_path)
        if errors:
            sys.stderr.write(f"Validation failed for {receipt_path}:\n")
            for err in errors:
                sys.stderr.write(f"  - {err}\n")
            return 1

        print(f"Receipt is valid: {receipt_path}")
        return 0

    # Emission mode
    missing = []
    for req in ("wave_id", "status", "environment", "branch_policy", "test_verdict"):
        if getattr(args, req) is None:
            missing.append(f"--{req.replace('_', '-')}")
    if missing:
        sys.stderr.write(f"Validation error: missing required arguments: {', '.join(missing)}\n")
        return 1

    # Resolve diff_stat
    if args.diff_stat is not None:
        files_changed, insertions, deletions = args.diff_stat
    else:
        files_changed = args.files_changed if args.files_changed is not None else 0
        insertions = args.insertions if args.insertions is not None else 0
        deletions = args.deletions if args.deletions is not None else 0

    # Resolve token_burn
    if args.token_burn is not None:
        token_in, token_out = args.token_burn
    else:
        token_in = args.token_input if args.token_input is not None else 0
        token_out = args.token_output if args.token_output is not None else 0

    # Resolve discoveries
    discoveries = None
    if args.discoveries is not None:
        raw = args.discoveries.strip()
        disc_path = Path(raw)
        if disc_path.is_file():
            try:
                with open(disc_path, "r", encoding="utf-8") as f:
                    discoveries = json.load(f)
            except Exception as exc:
                sys.stderr.write(f"Validation error: failed to parse discoveries file {disc_path}: {exc}\n")
                return 1
        else:
            try:
                discoveries = json.loads(raw)
            except Exception as exc:
                sys.stderr.write(f"Validation error: failed to parse discoveries JSON string: {exc}\n")
                return 1

    receipt: dict[str, Any] = {
        "$schema": args.schema_ref,
        "wave_id": args.wave_id,
        "status": args.status,
        "environment": args.environment,
        "branch": parse_nullable_str(args.branch),
        "branch_policy": args.branch_policy,
        "git_commit": parse_nullable_str(args.git_commit),
        "diff_stat": {
            "files_changed": files_changed,
            "insertions": insertions,
            "deletions": deletions,
        },
        "patch_file": parse_nullable_str(args.patch_file),
        "test_verdict": args.test_verdict,
        "token_burn": {
            "input": token_in,
            "output": token_out,
        },
        "blocker_reason": parse_nullable_str(args.blocker_reason),
        "kill_reason": parse_nullable_str(args.kill_reason),
        "attempts_used": args.attempts_used,
    }

    if discoveries is not None:
        receipt["discoveries"] = discoveries

    errors = validate_receipt_dict(receipt, schema_path=schema_path)
    if errors:
        sys.stderr.write("Validation failed for receipt:\n")
        for err in errors:
            sys.stderr.write(f"  - {err}\n")
        return 1

    receipt_path.parent.mkdir(parents=True, exist_ok=True)
    with open(receipt_path, "w", encoding="utf-8") as f:
        json.dump(receipt, f, indent=2)
        f.write("\n")

    print(f"Receipt written to {receipt_path}")
    return 0


if __name__ == "__main__":
    sys.exit(run())
