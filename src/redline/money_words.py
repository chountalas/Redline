from __future__ import annotations

import re
from decimal import Decimal

_UNITS = {
    "zero": 0,
    "one": 1,
    "two": 2,
    "three": 3,
    "four": 4,
    "five": 5,
    "six": 6,
    "seven": 7,
    "eight": 8,
    "nine": 9,
    "ten": 10,
    "eleven": 11,
    "twelve": 12,
    "thirteen": 13,
    "fourteen": 14,
    "fifteen": 15,
    "sixteen": 16,
    "seventeen": 17,
    "eighteen": 18,
    "nineteen": 19,
}

_TENS = {
    "twenty": 20,
    "thirty": 30,
    "forty": 40,
    "fifty": 50,
    "sixty": 60,
    "seventy": 70,
    "eighty": 80,
    "ninety": 90,
}

_SCALES = {
    "hundred": 100,
    "thousand": 1_000,
    "million": 1_000_000,
    "billion": 1_000_000_000,
}

_DROP_WORDS = {
    "and",
    "dollar",
    "dollars",
    "cad",
    "cdn",
    "canadian",
    "currency",
    "only",
}


def parse_money_words(words: str) -> Decimal | None:
    """Parse common English money words into a whole-dollar Decimal."""

    normalized = re.sub(r"[^a-zA-Z -]", " ", words).lower().replace("-", " ")
    tokens = [token for token in normalized.split() if token not in _DROP_WORDS]
    if not tokens:
        return None

    total = 0
    current = 0
    consumed = False

    for token in tokens:
        if token in _UNITS:
            current += _UNITS[token]
            consumed = True
        elif token in _TENS:
            current += _TENS[token]
            consumed = True
        elif token == "hundred":
            current = max(current, 1) * 100
            consumed = True
        elif token in {"thousand", "million", "billion"}:
            total += max(current, 1) * _SCALES[token]
            current = 0
            consumed = True
        else:
            return None

    if not consumed:
        return None
    return Decimal(total + current)
