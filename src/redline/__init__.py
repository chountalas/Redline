from __future__ import annotations

from importlib.metadata import PackageNotFoundError, version

from redline.models import (
    CheckReport,
    DealSheet,
    Evidence,
    ExtractedValue,
    Finding,
    LeaseFacts,
    Money,
    ScheduleLine,
    Severity,
)

try:
    __version__ = version("redline-lease")
except PackageNotFoundError:  # pragma: no cover
    __version__ = "0.0.0"

__all__ = [
    "CheckReport",
    "DealSheet",
    "Evidence",
    "ExtractedValue",
    "Finding",
    "LeaseFacts",
    "Money",
    "ScheduleLine",
    "Severity",
]
