# Implementation Plan: Configurable User-Prompt Execution Modes

## Summary

Add configurable execution modes to `user-prompt` nodes, allowing workflows to explicitly choose between:
- **Interactive mode**: Use AskUserQuestion tool (current behavior)
- **Tabular mode**: Present options as markdown table, parse user text response

Configuration is workflow-wide via `initial_state.prompts` block, following the established logging configuration pattern.

## Requirements

Based on user preferences:
1. **Presentation**: Markdown table with columns: Option ID, Label, Description
2. **Free text handling**: Match user input to option IDs first (prefix matching), route to 'other' handler if no match
3. **Configuration level**: Workflow-wide default in `initial_state.prompts`
4. **Mode selection**: Explicitly configured (no auto-detection/fallback)

## Key Design Decisions

### 1. Configuration Structure

Add `prompts` block to `initial_state` (parallel to `logging` config):

```yaml
# workflow.yaml
initial_state:
  phase: "start"
  flags: {}
  computed: {}
  prompts:                        # NEW: Prompt configuration
    mode: "interactive"           # "interactive" | "tabular"
    tabular:                      # Tabular mode settings
      match_strategy: "prefix"    # "exact" | "prefix" | "fuzzy"
      other_handler: "prompt"     # "prompt" | "route" | "fail"
```

**Defaults (backward compatible):**
- If `prompts` block omitted → default to `mode: "interactive"`
- If `mode: "tabular"` but `tabular` block omitted → use framework defaults

### 2. Mode Behavior

| Mode | Tool Required | Behavior | Error Handling |
|------|---------------|----------|----------------|
| `interactive` | AskUserQuestion | Call tool, get structured response | Fail if tool unavailable |
| `tabular` | None | Render markdown table, parse text | N/A |

**No fallback**: If `mode: "interactive"` but AskUserQuestion unavailable → fail with clear error message.

### 3. Tabular Mode Settings

**Match Strategy** (how to match user text to option IDs):
- `exact`: User must type exact option ID (case-insensitive)
- `prefix`: Match if user input starts with option ID (recommended)
- `fuzzy`: Use similarity scoring (Levenshtein distance, 70% threshold)

**Other Handler** (what to do when no match):
- `prompt`: Re-display table, ask user to choose again
- `route`: Route to special `other` handler (requires `on_response.other`)
- `fail`: End workflow with error

### 4. Execution Flow

#### Interactive Mode (Current Behavior)
```
Build options → Call AskUserQuestion → Get response → Route to handler
```

#### Tabular Mode (New)
```
Build options → Render markdown table → Display to user →
Wait for next turn → Parse user text → Match to option ID → Route to handler
```

**Tabular mode is conversational**: The workflow pauses, displays the table, and resumes when user responds in the next conversation turn.

## Critical Files to Modify

### Phase 1: Type Definitions (hiivmind-blueprint-lib)

**Primary changes:**

1. **`nodes/core/user-prompt.yaml`** - Core execution logic
   - Add mode detection at start of execution
   - Wrap existing code in `execute_interactive_mode()`
   - Add new `execute_tabular_mode()` function
   - Add `render_options_table()` helper
   - Add `match_user_input_to_option()` helper
   - Add tabular mode example
   - Lines affected: 137-200 (execution section)

2. **`execution/state.yaml`** - State structure updates
   - Document `awaiting_input` field for conversational continuation
   - Document `prompts` configuration resolution
   - Add to runtime fields section

3. **`execution/traversal.yaml`** - Execution flow updates
   - Handle `awaiting_input` state (multi-turn conversation)
   - Resume workflow after user text input in tabular mode
   - Skip to conversation handling if node returns `{ awaiting_input: true }`

### Phase 2: Schema Definitions (hiivmind-blueprint-lib)

4. **`schema/workflow.json`** - Add prompts config
   - Add `prompts` to `initial_state` properties
   - Define `$defs/promptsConfig` with mode enum
   - Define `$defs/tabularConfig` with settings

5. **`schema/prompts-config.json`** (NEW) - Standalone schema
   - Standalone schema for prompts configuration validation
   - Mirrors logging-config.json pattern
   - Used by validate skill

### Phase 3: Documentation (hiivmind-blueprint)

6. **`lib/workflow/prompts-config-loader.md`** (NEW) - Configuration reference
   - How prompts configuration is resolved
   - Mode selection algorithm
   - Tabular mode behavior (table rendering, input matching, non-match handling)
   - Examples for each mode and strategy

7. **`lib/workflow/engine.md`** - Engine reference update
   - Add "Prompts Configuration (Summary)" section
   - Reference prompts-config-loader.md
   - Document awaiting_input state

8. **`lib/blueprint/patterns/node-mapping.md`** - Pattern guidance
   - Add section on user_prompt mode configuration
   - Guide on when to use each mode based on prose analysis

9. **`references/prompts-config-examples.md`** (NEW) - Examples
   - Default interactive mode (no config)
   - Tabular mode with different strategies
   - Fuzzy matching example
   - Route to "other" handler example

10. **`CLAUDE.md`** - Project overview updates
    - Add prompts configuration to "Cross-Cutting Concerns" table
    - Add schema validation example for prompts config
    - Update "Available Schemas" table

### Phase 4: Validation & Testing

11. **Validation updates** (hiivmind-blueprint)
    - Update `skills/hiivmind-blueprint-validate/SKILL.md` to check prompts config
    - Validate against prompts-config.json schema
    - Check `other_handler: "route"` requires `on_response.other`
    - Validate match_strategy enum values

12. **Test scenarios** (hiivmind-blueprint-lib)
    - Unit tests for each match strategy
    - Unit tests for each other_handler
    - Integration test: gateway workflow with tabular mode
    - Integration test: dynamic options in tabular mode

## Implementation Sequence

### Step 1: Schema & Documentation (No Breaking Changes)
✓ No code execution changes yet
- Create `schema/prompts-config.json`
- Update `schema/workflow.json`
- Create `lib/workflow/prompts-config-loader.md`
- Create `references/prompts-config-examples.md`
- Update `CLAUDE.md`

### Step 2: Core Execution Logic
✓ Implements the mode switching
- Update `nodes/core/user-prompt.yaml`:
  - Add mode detection logic
  - Implement `execute_tabular_mode()`
  - Add helpers: `render_options_table()`, `match_user_input_to_option()`
  - Add tabular mode example

### Step 3: State & Flow Management
✓ Multi-turn conversation support
- Update `execution/state.yaml` (document `awaiting_input`)
- Update `execution/traversal.yaml` (handle `awaiting_input` state)

### Step 4: Pattern Guidance
✓ Blueprint toolchain support
- Update `lib/blueprint/patterns/node-mapping.md`
- Update `lib/workflow/engine.md`

### Step 5: Validation & Testing
✓ Ensure correctness
- Update validate skill
- Create test scenarios
- Test with example workflows

## Verification Plan

### Manual Testing

1. **Default behavior (backward compatibility)**
   ```bash
   # Run existing workflow with user-prompt nodes
   # Verify: Uses AskUserQuestion, works as before
   ```

2. **Tabular mode with prefix matching**
   ```yaml
   initial_state:
     prompts:
       mode: "tabular"
       tabular:
         match_strategy: "prefix"
   ```
   - Verify: Renders markdown table
   - Verify: User types "mark" → matches "markdown"
   - Verify: User types "xyz" → re-prompts

3. **Exact match strategy**
   ```yaml
   initial_state:
     prompts:
       mode: "tabular"
       tabular:
         match_strategy: "exact"
   ```
   - Verify: User types "mark" → no match, re-prompts
   - Verify: User types "markdown" → matches

4. **Route to other handler**
   ```yaml
   initial_state:
     prompts:
       mode: "tabular"
       tabular:
         other_handler: "route"

   nodes:
     test_prompt:
       on_response:
         option1:
           next_node: handle_option1
         other:
           next_node: handle_custom
   ```
   - Verify: User types "custom text" → routes to handle_custom
   - Verify: `user_responses.test_prompt.text` contains "custom text"

5. **Schema validation**
   ```bash
   # Validate workflow with prompts config
   check-jsonschema --base-uri "file://.../hiivmind-blueprint-lib/schema/" \
     --schemafile workflow.json \
     test-workflow.yaml
   ```

### Automated Testing

Unit tests to create in `hiivmind-blueprint-lib/tests/`:
- `test_user_prompt_default_mode.yaml` - No config → interactive
- `test_user_prompt_tabular_mode.yaml` - Tabular mode renders table
- `test_match_strategy_exact.yaml` - Exact matching
- `test_match_strategy_prefix.yaml` - Prefix matching
- `test_match_strategy_fuzzy.yaml` - Fuzzy matching with typos
- `test_other_handler_prompt.yaml` - Re-prompt on no match
- `test_other_handler_route.yaml` - Route to other
- `test_other_handler_fail.yaml` - Error on no match

## Backward Compatibility

✅ **Fully backward compatible**

- Default `mode: "interactive"` maintains existing behavior
- Existing workflows continue to work unchanged
- Configuration is optional
- No breaking changes to node structure

## Migration Path

For workflows that want tabular mode:

**Before:**
```yaml
initial_state:
  phase: "start"
```

**After:**
```yaml
initial_state:
  phase: "start"
  prompts:
    mode: "tabular"
    tabular:
      match_strategy: "prefix"
      other_handler: "prompt"
```

## Example Output (Tabular Mode)

When a user-prompt node executes in tabular mode:

```markdown
## Which format do you prefer?

| Option ID | Label | Description |
|-----------|-------|-------------|
| markdown | Markdown | Portable, human-readable |
| json | JSON | Machine-parseable |
| yaml | YAML | Structured, readable |

**Please type the Option ID of your choice.**
```

User response handling:
- User types "markdown" → matched (exact)
- User types "mark" → matched (prefix)
- User types "markdwon" → matched (fuzzy, 88% similarity)
- User types "xyz" → no match → re-prompt (if other_handler: "prompt")

## Risks & Mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| Multi-turn state management complexity | High | Use existing `awaiting_input` pattern from deprecated docs |
| Fuzzy matching false positives | Medium | Set 70% threshold, allow exact/prefix as alternatives |
| Breaking changes to existing workflows | High | Default to "interactive" for backward compatibility |
| Schema validation failures | Low | Comprehensive JSON Schema with clear error messages |

## Success Criteria

✅ User-prompt nodes support both interactive and tabular modes
✅ Mode configured explicitly in `initial_state.prompts`
✅ Tabular mode renders markdown table with Option ID, Label, Description
✅ Prefix matching works correctly (case-insensitive)
✅ Exact and fuzzy matching strategies implemented
✅ Non-matches handled per `other_handler` setting
✅ Backward compatible (existing workflows unchanged)
✅ Full schema validation support
✅ Comprehensive documentation and examples
