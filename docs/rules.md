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

The rule is skipped when no comparison sheet is provided.

## R7_general_lease_clause_coverage

Checks whether the `lease-general` profile extracted core review clauses.

- Inputs: `permitted_use`, `assignment_sublease_consent`, `maintenance_responsibility`, `insurance_requirements`, `default_cure_period_days`, `notice_addresses`, `additional_rent_terms`
- Missing-input severity: `COULD_NOT_VERIFY`

This rule does not decide whether a clause is acceptable. It tells the reviewer when a core term was not visible enough to check.

## R8_renewal_notice_window

Checks whether extracted renewal options include an extracted advance-notice deadline.

- Inputs: `renewal_options`, `renewal_notice_deadline_days`
- Failure severity: `WARN`

## R9_additional_rent_audit_visibility

Flags additional rent, CAM, tax, or operating-expense language when Redline did not extract tenant audit, cap, reconciliation, or review rights.

- Inputs: `additional_rent_terms`, `cam_audit_rights`
- Failure severity: `WARN`

## R10_assignment_consent_standard

Flags assignment/sublease language that appears to let the landlord withhold consent broadly.

- Inputs: `assignment_sublease_consent`
- Failure severity: `WARN`

## R11_termination_rights_asymmetry

Flags termination language when extracted text appears to mention landlord-side termination rights without matching tenant-side rights.

- Inputs: `termination_rights`
- Failure severity: `WARN`
