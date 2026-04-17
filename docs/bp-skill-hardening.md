  For hardening the blueprint skills, here's what went wrong and what would
   prevent it:

  Problem 1: Validate skill modified files

  The skill says "read-only" in prose, but nothing enforced it.

  Fix: Add a PreToolUse hook to the plugin that blocks Edit and Write tool
  calls when the validate skill is active. Prose instructions get ignored
  under pressure — hooks don't.

  Problem 2: I never read the actual blueprint-lib

  The validator's pattern files contain a summary of valid types. I treated
   the summary as authoritative and never went to the source. The authoring
   skills have the same gap.

  Fix: Every blueprint skill that touches types should have a mandatory
  first step that reads the actual YAML definitions from
  hiivmind-blueprint-lib/consequences/ and
  hiivmind-blueprint-lib/preconditions/. Not "reference this pattern file"
  — literally Read the lib files. The pattern files should say "THIS IS A
  SUMMARY — the lib is the source of truth" with a hard-gate.

  Problem 3: No guardrail against invented types

  I used instruction instead of pseudocode, message instead of content,
  invented increment as a mutate_state operation. Nothing caught this.

  Fix: The validate skill should load the lib's YAML definitions
  programmatically and check action parameters against the actual parameter
   schemas — not just type names. Field-level validation, not just
  type-level.

  Problem 4: Pattern files drift from lib

  The pattern files list all_of/any_of as valid, but the lib v4.0.0
  replaced them with composite. The summaries are stale.

  Fix: Either generate the pattern files from the lib (so they can't
  drift), or delete them and always read from the lib directly.

  Want me to help implement any of these hardening changes in the blueprint
   plugin?
