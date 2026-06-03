# Rule Reference

Every deterministic rule returns either zero findings, one or more findings, or `COULD_NOT_VERIFY` when required facts are missing. A rule must not silently pass if it lacked the facts needed to run.

## R1_schedule_sums_to_total

Checks whether the sum of `rent_schedule` equals `stated_total_rent`.

- Inputs: `rent_schedule`, `stated_total_rent`
- Failure severity: `ERROR`
- Missing-input severity: `COULD_NOT_VERIFY`

Example: schedule totals CAD 390,000 but the lease states CAD 400,000.

## R2_per_face_total_reconcile

Checks whether `per_face_rent * num_display_faces == stated_total_rent` when the rent basis is per display face.

- Inputs: `rent_basis`, `per_face_rent`, `num_display_faces`, `stated_total_rent`
- Failure severity: `ERROR`
- Missing-input severity: `COULD_NOT_VERIFY`

This catches the common defect where a value intended as total rent is structurally applied per face.

## R3_escalation_consistency

Checks whether scheduled rent follows the extracted escalation percentage, and flags escalating schedules without an escalation clause or flat schedules with a positive escalation clause.

- Inputs: `rent_schedule`, `escalation_pct`, `escalation_clause_present`
- Failure severity: `WARN`
- Missing-input severity: `COULD_NOT_VERIFY`

## R4_numeral_vs_words

Checks whether extracted numeral/word pairs agree, such as `$400,000` and `Four Hundred Thousand Dollars`.

- Inputs: `amount_word_pairs`
- Failure severity: `ERROR`
- Missing-input severity: `COULD_NOT_VERIFY`

## R5_term_date_coherence

Checks whether `commencement_date + base_term_years - one day == stated_expiry_date`. Also emits an `INFO` finding for total exposure when base term and renewal options are present.

- Inputs: `commencement_date`, `base_term_years`, `stated_expiry_date`, optional `renewal_options`
- Failure severity: `ERROR`
- Missing-input severity: `COULD_NOT_VERIFY`

## R6_dealsheet_match

Checks extracted facts against optional negotiated deal terms.

- Inputs: `deal.yaml`, matching extracted facts
- Failure severity: `ERROR`
- Missing-input severity: `COULD_NOT_VERIFY`

The rule is skipped when no deal sheet is provided.
