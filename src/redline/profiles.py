from __future__ import annotations

from typing import Literal

from redline.errors import ExtractionError
from redline.models import ProfileMeta

ProfileID = Literal["lease-general", "lease-math"]
DEFAULT_PROFILE: ProfileID = "lease-general"
PROFILE_CHOICES: tuple[ProfileID, ...] = ("lease-general", "lease-math")


def normalize_profile(profile: str | None) -> ProfileID:
    raw = (profile or DEFAULT_PROFILE).strip().lower()
    if raw in PROFILE_CHOICES:
        return raw
    raise ExtractionError("Profile must be one of: lease-general, lease-math.")


def profile_meta(profile: ProfileID) -> ProfileMeta:
    if profile == "lease-math":
        return ProfileMeta(
            id="lease-math",
            name="Lease math",
            version="1",
            description="Commercial lease rent, term, date, and comparison-term checks.",
        )
    return ProfileMeta(
        id="lease-general",
        name="General lease",
        version="1",
        description=(
            "Commercial lease financial, date, comparison-term, and general clause "
            "coverage checks."
        ),
    )
