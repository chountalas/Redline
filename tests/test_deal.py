from __future__ import annotations

from decimal import Decimal

from redline.deal import load_deal_sheet


def test_load_deal_sheet_money_string(tmp_path) -> None:
    path = tmp_path / "deal.yaml"
    path.write_text(
        """
total_rent: "CAD 400000"
num_display_faces: 2
base_term_years: 5
renewal_options: [5, "5"]
escalation_pct: "2"
""".strip(),
        encoding="utf-8",
    )

    deal = load_deal_sheet(path)

    assert deal.total_rent is not None
    assert deal.total_rent.amount == Decimal("400000")
    assert deal.total_rent.currency == "CAD"
    assert deal.renewal_options == [Decimal("5"), Decimal("5")]
