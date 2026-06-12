from __future__ import annotations

from pathlib import Path
from typing import Any

import yaml
from pydantic import ValidationError

from redline.errors import DealSheetError
from redline.models import DealSheet


def load_deal_sheet(path: str | Path) -> DealSheet:
    deal_path = Path(path)
    try:
        raw: Any = yaml.safe_load(deal_path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError) as exc:
        raise DealSheetError(f"Could not read comparison sheet: {deal_path}") from exc
    except yaml.YAMLError as exc:
        raise DealSheetError(f"Invalid YAML in comparison sheet: {deal_path}") from exc

    if raw is None:
        raw = {}
    if not isinstance(raw, dict):
        raise DealSheetError("Comparison sheet must be a YAML mapping.")

    try:
        return DealSheet.model_validate(raw)
    except ValidationError as exc:
        raise DealSheetError(f"Invalid comparison sheet: {exc}") from exc
