from __future__ import annotations

import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SKIP_DIRS = {
    ".git",
    ".build",
    ".mypy_cache",
    ".pytest_cache",
    ".ruff_cache",
    ".swiftpm",
    ".venv",
    "__pycache__",
    "build",
    "dist",
}
SKIP_SUFFIXES = {".pyc", ".pyo", ".so", ".dylib", ".png", ".jpg", ".jpeg", ".gif", ".pdf", ".whl"}
SECRET_PATTERNS = [
    re.compile(r"sk-ant-[A-Za-z0-9_-]{20,}"),
    re.compile(r"sk-[A-Za-z0-9]{32,}"),
    re.compile(r"ghp_[A-Za-z0-9]{30,}"),
    re.compile(r"github_pat_[A-Za-z0-9_]{40,}"),
    re.compile(r"xox[baprs]-[A-Za-z0-9-]{20,}"),
    re.compile(r"-----BEGIN (?:RSA |OPENSSH |EC |DSA )?PRIVATE KEY-----"),
    re.compile(r"(?i)(access_token|api_key|secret|password)\s*[:=]\s*['\"]?[A-Za-z0-9_./+=-]{16,}"),
]
PRIVATE_CONTEXT_PATTERNS = [
    re.compile(r"Claude-Mem", re.IGNORECASE),
    re.compile(r"\b4206\s+Macleod\b", re.IGNORECASE),
    re.compile(r"\bLeading\s+Outdoor\b", re.IGNORECASE),
    re.compile(r"\blease_7\b", re.IGNORECASE),
    re.compile(r"\bPortage\s+Ave\b", re.IGNORECASE),
    re.compile(r"\bGmail/Notion\b", re.IGNORECASE),
]
HISTORY_EXCLUDES = ["scripts/check_release_safety.py"]
ALLOWED_PLACEHOLDERS = {
    "ANTHROPIC_API_KEY=",
    "ANTHROPIC_API_KEY=...",
    "api_key: str | None = None",
    "resolved_api_key = api_key or os.getenv",
    "if not resolved_api_key:",
}


def main() -> int:
    failures: list[str] = []
    failures.extend(_scan_working_tree())
    failures.extend(_scan_head_history())

    if failures:
        print("Release safety check failed:", file=sys.stderr)
        for failure in failures:
            print(f"- {failure}", file=sys.stderr)
        return 1

    print("Release safety check passed.")
    return 0


def _scan_working_tree() -> list[str]:
    failures: list[str] = []
    for path in _iter_files(ROOT):
        relative = path.relative_to(ROOT)
        if path.name == ".env":
            failures.append(f"{relative}: .env files must not be committed")
            continue

        try:
            text = path.read_text(encoding="utf-8")
        except UnicodeDecodeError:
            continue

        for line_number, line in enumerate(text.splitlines(), start=1):
            if line.strip() in ALLOWED_PLACEHOLDERS:
                continue
            if path.resolve() != Path(__file__).resolve():
                for pattern in PRIVATE_CONTEXT_PATTERNS:
                    if pattern.search(line):
                        failures.append(
                            f"{relative}:{line_number}: possible private release context"
                        )
                        break
            for pattern in SECRET_PATTERNS:
                if pattern.search(line):
                    failures.append(f"{relative}:{line_number}: possible secret")
                    break
    return failures


def _scan_head_history() -> list[str]:
    if not (ROOT / ".git").exists():
        return []
    try:
        revs = subprocess.run(
            ["git", "-C", str(ROOT), "rev-list", "HEAD"],
            text=True,
            capture_output=True,
            check=True,
        ).stdout.splitlines()
    except subprocess.CalledProcessError:
        return []

    failures: list[str] = []
    for rev in revs:
        try:
            files = subprocess.run(
                ["git", "-C", str(ROOT), "ls-tree", "-r", "--name-only", rev],
                text=True,
                capture_output=True,
                check=True,
            ).stdout.splitlines()
        except subprocess.CalledProcessError:
            continue
        for file_name in files:
            if file_name in HISTORY_EXCLUDES:
                continue
            path = Path(file_name)
            if any(part in SKIP_DIRS for part in path.parts):
                continue
            if path.suffix.lower() in SKIP_SUFFIXES:
                continue
            try:
                blob = subprocess.run(
                    ["git", "-C", str(ROOT), "show", f"{rev}:{file_name}"],
                    text=True,
                    capture_output=True,
                    check=True,
                ).stdout
            except (subprocess.CalledProcessError, UnicodeDecodeError):
                continue
            for line_number, line in enumerate(blob.splitlines(), start=1):
                if line.strip() in ALLOWED_PLACEHOLDERS:
                    continue
                for pattern in PRIVATE_CONTEXT_PATTERNS:
                    if pattern.search(line):
                        location = f"{rev[:12]}:{file_name}:{line_number}"
                        failures.append(
                            f"{location}: private release context in history"
                        )
                        break
                for pattern in SECRET_PATTERNS:
                    if pattern.search(line):
                        failures.append(f"{rev[:12]}:{file_name}:{line_number}: secret in history")
                        break
    return failures


def _iter_files(root: Path) -> list[Path]:
    files: list[Path] = []
    for path in root.rglob("*"):
        if not path.is_file():
            continue
        if any(part in SKIP_DIRS for part in path.relative_to(root).parts):
            continue
        if path.suffix.lower() in SKIP_SUFFIXES:
            continue
        files.append(path)
    return files


if __name__ == "__main__":
    raise SystemExit(main())
