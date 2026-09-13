# Specification Quality Checklist: Sidebar Detail View

**Purpose**: Validate specification completeness and quality before proceeding to planning
**Created**: 2026-09-08
**Feature**: [spec.md](../spec.md)

## Content Quality

- [x] No implementation details (languages, frameworks, APIs)
- [x] Focused on user value and business needs
- [x] Written for non-technical stakeholders
- [x] All mandatory sections completed

## Requirement Completeness

- [x] No [NEEDS CLARIFICATION] markers remain
- [x] Requirements are testable and unambiguous
- [x] Success criteria are measurable
- [x] Success criteria are technology-agnostic (no implementation details)
- [x] All acceptance scenarios are defined
- [x] Edge cases are identified
- [x] Scope is clearly bounded
- [x] Dependencies and assumptions identified

## Feature Readiness

- [x] All functional requirements have clear acceptance criteria
- [x] User scenarios cover primary flows
- [x] Feature meets measurable outcomes defined in Success Criteria
- [x] No implementation details leak into specification

## Notes

- Items marked incomplete require spec updates before `/speckit.clarify` or `/speckit.plan`

Feature 008 removed the former terminal-neutrality requirement.
The dated records below describe the earlier policy, not a current support obligation.
Ghostel-only support now governs this feature.

### Validation record 2026-09-08

Iteration 1 findings, all resolved in the current spec:

- The `V` key binding and the persistent setting read like implementation
  detail, but the user named both in the feature request. FR-010 through FR-012
  state them as requirements without naming any symbol, function, or file.
  Kept.
- SC-007 names the batch quality gate. This is a governance requirement from
  the project constitution, principle II, so it stays as a success criterion.
- The description source was the one open question. The `refs/` survey in
  [research.md](../research.md) answered it, and the answer is recorded under
  Clarifications and Assumptions. No `[NEEDS CLARIFICATION]` marker was needed.
- Terminal-backend neutrality, constitution principle IV, was initially
  unaddressed. FR-018 now states the rule and names the missing title as a
  title-availability limit rather than a view difference.
- Out of Scope was added to bound the feature against model-generated titles,
  transcript reading, a separate description field, and extra metadata rows.

### Clarify record 2026-09-08

Four questions asked and answered. Re-validation after integration: 16 of 16
items still pass, no regressions, no newly passing items. The checklist was
already fully checked, so the value of this pass was fixing defects the
checklist alone did not catch:

- A contradiction is now gone. FR-014 said the view survives a restart through
  manager persistence, while Story 3 said a toggle never writes the saved
  preference. Those could not both hold. The customize setting is now the only
  stored value, and FR-014 states that the manager state file stores no view.
  This tightened "Requirements are testable and unambiguous", which had passed
  on a requirement that was in fact self-contradictory.
- The spec drawing disagreed with the original sketch on where the title line
  starts. FR-007 now fixes the column, so the visual acceptance test has one
  answer.
- FR-004 now says "no fallback content", closing a gap that mattered because
  only one terminal backend reports a title today.
- Out of Scope now excludes the pin-order editor, which shows Session titles
  through its own separate setting.
- One thing had two names. "Layout" and "view" both meant the compact or detail
  rendering. The spec now says "view" throughout, and reserves "window layout"
  for the Emacs window arrangement. "Flat" and "grouped" are now called
  arrangements, so they no longer collide with the new term.
- A research claim was too broad. The spec said every surveyed project derives
  a secondary label from a terminal title or transcript. research.md records
  two projects that label nothing, and plannotator's label comes from CLI
  arguments. Both documents now state the per-project split.
