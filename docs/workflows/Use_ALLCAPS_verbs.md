# Plan: Fix USER_PROMPT Node Not Calling AskUserQuestion Tool

## Problem

When executing the decision-maker workflow, the USER_PROMPT node displays text instead of calling the AskUserQuestion tool.

## Root Cause

1. **execution.md uses vague verbs** - "present to user" instead of "CALL AskUserQuestion tool"
2. **thin-loader template doesn't reference execution.md** for USER_PROMPT handling
3. **No verb conventions** - ambiguous what "present" means vs explicit tool calls

## Fix Strategy

**Don't duplicate logic** - the framework files ARE the source of truth. Fix them, then reference them.

### Step 1: Tighten execution.md verbs

Add explicit ALL_CAPS verb conventions throughout. Key verbs:
- `CALL [ToolName]` - Invoke a Claude Code tool
- `DISPLAY` - Output text to user
- `READ` - Read a file (implies Read tool)
- `SET` - Mutate state
- `RETURN` - Return from function
- `STORE` - Save to state location

**User Prompt Node section (lines 179-266)** needs these changes:

Current vague code:
```
response = present_prompt(rendered)
```

Should be:
```
IF interface == "claude_code":
    response = CALL AskUserQuestion with rendered
ELSE:
    DISPLAY rendered
    response = WAIT for user message
```

And `build_ask_user_question` should explicitly show:
```
CALL AskUserQuestion tool with:
    questions: [{
        question: interpolate(node.prompt.question),
        header: node.prompt.header,
        multiSelect: false,
        options: [...]
    }]
```

### Step 2: Update thin-loader template

Replace the vague USER_PROMPT section (lines 99-107) with a reference to execution.md:

```
USER_PROMPT NODE:
- Execute per ${CLAUDE_PLUGIN_ROOT}/lib/workflow/execution.md (User Prompt Node)
- Uses state.interface (detected in Phase 1) to select presentation:
  - claude_code: CALL AskUserQuestion tool
  - claude_ai: DISPLAY markdown table
- WAIT for response, match handler, apply consequence, route to next_node
- CONTINUE
```

### Step 3: Update decision-maker SKILL.md

Same pattern - reference the framework, don't duplicate:

```
USER_PROMPT NODE:
- Execute per ${CLAUDE_PLUGIN_ROOT}/lib/workflow/execution.md (User Prompt Node)
- Uses state.interface to select presentation method
- WAIT for response, match handler, apply consequence, route
- CONTINUE
```

## Files to Modify

| File | Change |
|------|--------|
| `lib/workflow/execution.md` | Tighten ALL_CAPS verbs throughout, especially User Prompt Node section |
| `templates/thin-loader.md.template` | Reference execution.md for USER_PROMPT, don't duplicate logic |
| `hiivmind-nexus-demo/skills/decision-maker/SKILL.md` | Reference execution.md for USER_PROMPT |

## Verification

1. Run `/decision-maker` in Claude Code
2. Verify AskUserQuestion tool is CALLED (not text displayed)
3. Verify tool call has proper structure (questions array with header, options)
