# Plan: Fix Standalone Plugin Execution References

## Problem Statement

**Current issue:** engine.md references local paths like `hiivmind-blueprint-lib/execution/traversal.yaml` which:
- Work in dev environment (blueprint-lib is sibling directory)
- **Break in production** - standalone plugins on end-user machines don't have blueprint-lib locally

**Solution:** Thin loaders reference execution YAML via raw GitHub URLs, versioned to match `workflow.yaml`'s `definitions.source`.

---

## Design Decisions

| Decision | Choice |
|----------|--------|
| Version source | Match `workflow.yaml` definitions.source version |
| URL format | Raw GitHub URLs (no shorthand) |
| engine.md | Stop copying, keep as dev-only reference |

---

## Files to Modify

### 1. Templates

**`templates/skill-with-executor.md.template`**
- Replace all `${CLAUDE_PLUGIN_ROOT}/.hiivmind/blueprint/engine.md` references
- Add execution YAML table with raw GitHub URLs
- Use `{{lib_version}}` placeholder to match definitions.source

**`templates/thin-loader.md.template`**
- Same changes as above

**`templates/gateway-command.md.template`**
- Update execution references to remote URLs

### 2. Skills

**`skills/hiivmind-blueprint-generate/SKILL.md`**
- Remove engine.md copying (lines ~163-172)
- Pass `lib_version` from workflow definitions to templates
- Update output documentation

**`skills/hiivmind-blueprint-upgrade/SKILL.md`**
- Remove engine.md upgrade logic
- Add migration: detect old engine.md reference → update to remote URLs
- Preserve plugin-specific context by moving to SKILL.md

**`skills/hiivmind-blueprint-convert/SKILL.md`**
- Ensure `definitions.source` version is captured for template use

### 3. Documentation

**`lib/blueprint/patterns/plugin-structure.md`**
- Remove `.hiivmind/blueprint/engine.md` from directory structure
- Document remote execution reference pattern
- Add example showing version alignment

**`lib/workflow/engine.md`**
- Add banner: "DEV ONLY - Not for standalone deployment"
- Keep as navigation reference for local development

**`CLAUDE.md`**
- Update "Target Plugin Structure" section to remove engine.md

---

## Template Example

### Before
```markdown
## Execution

See: `${CLAUDE_PLUGIN_ROOT}/.hiivmind/blueprint/engine.md`
```

### After
```markdown
## Execution Reference

Execution semantics from [hiivmind-blueprint-lib](https://github.com/hiivmind/hiivmind-blueprint-lib) (version matches workflow definitions):

| Semantic | Source |
|----------|--------|
| Core loop | [traversal.yaml](https://raw.githubusercontent.com/hiivmind/hiivmind-blueprint-lib/{{lib_version}}/execution/traversal.yaml) |
| State | [state.yaml](https://raw.githubusercontent.com/hiivmind/hiivmind-blueprint-lib/{{lib_version}}/execution/state.yaml) |
| Consequences | [consequence-dispatch.yaml](https://raw.githubusercontent.com/hiivmind/hiivmind-blueprint-lib/{{lib_version}}/execution/consequence-dispatch.yaml) |
| Preconditions | [precondition-dispatch.yaml](https://raw.githubusercontent.com/hiivmind/hiivmind-blueprint-lib/{{lib_version}}/execution/precondition-dispatch.yaml) |
| Logging | [logging.yaml](https://raw.githubusercontent.com/hiivmind/hiivmind-blueprint-lib/{{lib_version}}/execution/logging.yaml) |
```

---

## Migration Path

### For existing plugins with `.hiivmind/blueprint/engine.md`:

1. Upgrade skill detects `engine.md` in `.hiivmind/blueprint/`
2. Reads workflow.yaml to get `definitions.source` version
3. Updates all SKILL.md files:
   - Replaces local engine.md refs with remote URLs
   - Injects version from definitions.source
4. Removes `.hiivmind/blueprint/engine.md`
5. If engine.md had plugin-specific sections, moves them to a `CONTEXT.md` or top of SKILL.md

---

## Verification

1. Generate new plugin → verify no `.hiivmind/blueprint/engine.md` created
2. Check SKILL.md contains raw GitHub URLs with correct version
3. Verify URLs resolve (test fetch)
4. Clone plugin to fresh directory, verify no broken local refs
5. Run existing taubench-retail through upgrade skill, verify migration

---

## Implementation Order

1. Update templates with remote URL pattern
2. Update generate skill (remove copying, pass version)
3. Update upgrade skill (add migration logic)
4. Update convert skill (capture version for templates)
5. Update documentation (plugin-structure.md, CLAUDE.md)
6. Test on taubench-retail
