Plan: Promote Logging to Core Consequence

 Goal

 Move logging from an extension to a core consequence, making it a first-class citizen in all hiivmind-blueprint skills. This includes validation for config/usage alignment and full integration into the skill
 conversion pipeline.

 ---
 Current State

 Core consequences: 20 types in lib/workflow/consequences/core/
 - workflow.md (16), intent-detection.md (4), shared.md (patterns)

 Extension consequences: 10 types in lib/workflow/consequences/extensions/
 - file-system.md (4), git.md (4), web.md (2)

 Logging (currently extension): 10 types in extensions/logging.md
 - init_log, log_node, log_event, log_warning, log_error
 - log_session_snapshot, finalize_log, write_log, apply_log_retention, output_ci_summary

 ---
 Implementation Phases

 Phase 1: Move Logging to Core

 1.1 Create core logging file

 Copy lib/workflow/consequences/extensions/logging.md to:
 - New: lib/workflow/consequences/core/logging.md

 Update header to reflect core status and update Related Documentation links.

 1.2 Update taxonomy in README.md

 File: lib/workflow/consequences/README.md

 Changes:
 - Update counts: Core 20 → 30, Extensions 10 → 10 (unchanged - file-system/git/web)
 - Add core/logging.md to directory structure
 - Add 10 logging consequences to Core Quick Reference table
 - Add logging to Domain Files table: core/logging.md | Workflow Logging | 10

 1.3 Create deprecation stub

 Replace lib/workflow/consequences/extensions/logging.md with a redirect stub:
 # DEPRECATED: Logging Moved to Core

 Logging consequences are now core. See: [../core/logging.md](../core/logging.md)

 1.4 Update JSON Schema

 File: lib/schema/workflow-schema.json

 Change all logging consequence tags from [EXT:logging] to [CORE].

 ---
 Phase 2: Add Logging Validation Rules

 2.1 Add to validation-queries.md

 File: lib/workflow/validation-queries.md

 Add new section ## Logging Validation Queries with these checks:
 ┌─────┬───────────────────────────────────┬─────────────────────────────────────────────────┐
 │  #  │               Query               │                     Purpose                     │
 ├─────┼───────────────────────────────────┼─────────────────────────────────────────────────┤
 │ L1  │ Check init_log exists             │ Find workflows with logging config but no init  │
 ├─────┼───────────────────────────────────┼─────────────────────────────────────────────────┤
 │ L2  │ Check finalize_log exists         │ init without finalize is incomplete             │
 ├─────┼───────────────────────────────────┼─────────────────────────────────────────────────┤
 │ L3  │ Check order: init before finalize │ Detect out-of-order consequences                │
 ├─────┼───────────────────────────────────┼─────────────────────────────────────────────────┤
 │ L4  │ Check write_log has finalize      │ Can't write unfinalized log                     │
 ├─────┼───────────────────────────────────┼─────────────────────────────────────────────────┤
 │ L5  │ Check level consistency           │ Config=error but uses log_event (requires info) │
 ├─────┼───────────────────────────────────┼─────────────────────────────────────────────────┤
 │ L6  │ Check retention has write         │ apply_log_retention without write_log           │
 ├─────┼───────────────────────────────────┼─────────────────────────────────────────────────┤
 │ L7  │ List all logging consequences     │ Audit helper                                    │
 └─────┴───────────────────────────────────┴─────────────────────────────────────────────────┘
 2.2 Add logging to known consequences

 Update KNOWN_CONSEQUENCES array in validation-queries.md:
 # Add after existing core consequences:
 "init_log" "log_node" "log_event" "log_warning" "log_error"
 "log_session_snapshot" "finalize_log" "write_log"
 "apply_log_retention" "output_ci_summary"

 ---
 Phase 3: Integrate into Blueprint Skills

 3.1 Update hiivmind-blueprint-analyze

 File: skills/hiivmind-blueprint-analyze/SKILL.md

 Add detection for logging patterns in prose:
 - Scan for: "log execution", "audit trail", "CI summary", "retain logs"
 - Output: analysis.logging_patterns.intent_present: true/false
 - Add logging_recommendation: "enable"|"optional"|"skip" to conversion recommendations

 3.2 Update hiivmind-blueprint-convert

 File: skills/hiivmind-blueprint-convert/SKILL.md

 Add Phase 2.4: Configure Logging:
 - If logging_patterns.intent_present: auto-add default logging config
 - Otherwise: ask user via AskUserQuestion (Yes/Manual/No)
 - Generate initial_state.logging section with sensible defaults
 - When logging.auto.node_tracking enabled: inject log_node consequences

 3.3 Update hiivmind-blueprint-generate

 File: skills/hiivmind-blueprint-generate/SKILL.md

 Add logging files to required libs:
 - lib/workflow/consequences/core/logging.md
 - lib/workflow/logging-schema.md (if logging enabled)
 - lib/blueprint/patterns/logging-configuration.md (if logging enabled)

 3.4 Update hiivmind-blueprint-validate

 File: skills/hiivmind-blueprint-validate/SKILL.md

 Add Phase 3.9: Logging Validation with these checks:
 ┌─────┬────────────────────────────────────────────┬──────────┐
 │  #  │                   Check                    │ Severity │
 ├─────┼────────────────────────────────────────────┼──────────┤
 │ 45  │ Config enabled but no init_log             │ Warning  │
 ├─────┼────────────────────────────────────────────┼──────────┤
 │ 46  │ init_log without finalize_log              │ Error    │
 ├─────┼────────────────────────────────────────────┼──────────┤
 │ 47  │ write_log without finalize_log             │ Error    │
 ├─────┼────────────────────────────────────────────┼──────────┤
 │ 48  │ Level mismatch (config vs usage)           │ Warning  │
 ├─────┼────────────────────────────────────────────┼──────────┤
 │ 49  │ Retention without write_log                │ Warning  │
 ├─────┼────────────────────────────────────────────┼──────────┤
 │ 50  │ Deprecated extensions/logging.md reference │ Warning  │
 └─────┴────────────────────────────────────────────┴──────────┘
 3.5 Update hiivmind-blueprint-upgrade

 File: skills/hiivmind-blueprint-upgrade/SKILL.md

 Add logging migration:
 - Detect references to extensions/logging.md → update to core/logging.md
 - If logging consequences exist but no config → add default config
 - Version bump for logging schema changes

 ---
 Phase 4: Template Updates

 4.1 Update workflow template

 File: templates/workflow.yaml.template

 Add optional logging section after initial_state:
 initial_state:
   # ... existing ...
   {{#if_logging}}
   logging:
     enabled: true
     level: "info"
     auto:
       init: true
       node_tracking: true
       finalize: true
       write: true
     output:
       format: "yaml"
       location: ".logs/"
     retention:
       strategy: "count"
       count: 10
   {{/if_logging}}

 4.2 Create logging config template

 File: templates/logging-config.yaml.template

 Standalone template for adding logging to existing workflows.

 ---
 Phase 5: Documentation Updates

 5.1 Update cross-references

 Files to update with new path core/logging.md:
 - lib/workflow/logging-schema.md
 - lib/blueprint/patterns/logging-configuration.md
 - lib/blueprint/patterns/session-tracking.md
 - lib/workflow/preconditions.md

 5.2 Update CLAUDE.md

 Update Cross-Cutting Concerns table:
 - Change consequence count: 30 → 40
 - Add row: Logging configuration | analyze, convert, generate, validate | Config/usage alignment

 ---
 Files Summary
 ┌────────┬────────────────────────────────────────────────────────┐
 │ Action │                          File                          │
 ├────────┼────────────────────────────────────────────────────────┤
 │ CREATE │ lib/workflow/consequences/core/logging.md              │
 ├────────┼────────────────────────────────────────────────────────┤
 │ CREATE │ templates/logging-config.yaml.template                 │
 ├────────┼────────────────────────────────────────────────────────┤
 │ MODIFY │ lib/workflow/consequences/README.md                    │
 ├────────┼────────────────────────────────────────────────────────┤
 │ MODIFY │ lib/workflow/consequences/extensions/logging.md (stub) │
 ├────────┼────────────────────────────────────────────────────────┤
 │ MODIFY │ lib/workflow/validation-queries.md                     │
 ├────────┼────────────────────────────────────────────────────────┤
 │ MODIFY │ lib/schema/workflow-schema.json                        │
 ├────────┼────────────────────────────────────────────────────────┤
 │ MODIFY │ skills/hiivmind-blueprint-analyze/SKILL.md             │
 ├────────┼────────────────────────────────────────────────────────┤
 │ MODIFY │ skills/hiivmind-blueprint-convert/SKILL.md             │
 ├────────┼────────────────────────────────────────────────────────┤
 │ MODIFY │ skills/hiivmind-blueprint-generate/SKILL.md            │
 ├────────┼────────────────────────────────────────────────────────┤
 │ MODIFY │ skills/hiivmind-blueprint-validate/SKILL.md            │
 ├────────┼────────────────────────────────────────────────────────┤
 │ MODIFY │ skills/hiivmind-blueprint-upgrade/SKILL.md             │
 ├────────┼────────────────────────────────────────────────────────┤
 │ MODIFY │ templates/workflow.yaml.template                       │
 ├────────┼────────────────────────────────────────────────────────┤
 │ MODIFY │ lib/workflow/logging-schema.md                         │
 ├────────┼────────────────────────────────────────────────────────┤
 │ MODIFY │ lib/blueprint/patterns/logging-configuration.md        │
 ├────────┼────────────────────────────────────────────────────────┤
 │ MODIFY │ lib/blueprint/patterns/session-tracking.md             │
 ├────────┼────────────────────────────────────────────────────────┤
 │ MODIFY │ CLAUDE.md                                              │
 └────────┴────────────────────────────────────────────────────────┘
 ---
 Verification

 1. Structural: Run ls lib/workflow/consequences/core/ - should show logging.md
 2. Taxonomy: Check README counts: Core=30, Extensions=10
 3. Validation: Run validate skill on a workflow with logging - new checks should fire
 4. Convert: Run convert on a prose skill - should offer logging configuration
 5. Generate: Check generated workflow includes logging libs if enabled
 6. Backward compat: Old path reference should trigger deprecation warning

 ---
 Validation Query Examples

 # Check init_log without finalize_log
 yq '
   ([.nodes | to_entries | .[] | .value.actions[]? | select(.type == "init_log")] | length > 0) and
   ([.nodes | to_entries | .[] | .value.actions[]? | select(.type == "finalize_log")] | length == 0)
 ' workflow.yaml

 # Check config enabled but no init_log
 yq '
   (.initial_state.logging.enabled == true) and
   ([.nodes | to_entries | .[] | .value.actions[]? | select(.type == "init_log")] | length == 0)
 ' workflow.yaml

 # Check level mismatch (error/warn config but uses log_event)
 yq '
   (.initial_state.logging.level == "error" or .initial_state.logging.level == "warn") and
   ([.nodes | to_entries | .[] | .value.actions[]? | select(.type == "log_event")] | length > 0)
 ' workflow.yaml
