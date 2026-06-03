from __future__ import annotations

from decimal import Decimal

from redline.money_words import parse_money_words


def test_parse_money_words() -> None:
    assert parse_money_words("Four Hundred Thousand Dollars") == Decimal("400000")
    assert parse_money_words("One Million Two Hundred Fifty Thousand") == Decimal("1250000")
    assert parse_money_words("Eight Hundred Thousand Canadian Dollars") == Decimal("800000")
