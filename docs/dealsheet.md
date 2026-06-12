# Comparison Sheet

`deal.yaml` is optional for lease profiles. It lets Redline compare a draft lease against negotiated intent, which is the only way to catch an internally consistent lease that uses the wrong business terms.

Every field may be omitted.

```yaml
total_rent:
  amount: "400000"
  currency: CAD
per_face_rent:
  amount: "200000"
  currency: CAD
num_display_faces: 2
base_term_years: 5
renewal_options: [5, 5, 5]
escalation_pct: 2
```

Money may also be written as a string:

```yaml
total_rent: "CAD 400000"
```

Redline treats `escalation_pct: 2` as two percent, not `0.02`.
