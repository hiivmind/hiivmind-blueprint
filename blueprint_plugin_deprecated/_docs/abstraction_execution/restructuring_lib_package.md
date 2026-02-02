# Migration: intent-detection.yaml to hiivmind-blueprint-lib

## Goal

Migrate the intent-detection.yaml workflow from hiivmind-blueprint to hiivmind-blueprint-lib, along with:
1. Renaming the package to `hiivmind-blueprint-lib`
2. Restructuring directories to remove redundant `definitions/` level
3. Adding workflows support
4. Updating all references

---

## Current State

### hiivmind-blueprint-lib structure:
```
hiivmind-blueprint-lib/
├── package.yaml
├── bundle.yaml
├── consequences/definitions/core/...     # Has 'definitions' level
├── consequences/definitions/extensions/...
├── preconditions/definitions/core/...
├── preconditions/definitions/extensions/...
├── nodes/definitions/core/...
└── schema/
```

### Source workflow:
- `/home/nathanielramm/git/hiivmind/hiivmind-blueprint/lib/workflows/intent-detection.yaml`
- 172 lines, uses: `parse_intent_flags`, `match_3vl_rules`, `set_state`, `evaluate_expression`

### References to update (18 files in hiivmind-blueprint):
- CLAUDE.md, lib/types/README.md, lib/workflow/workflow-loader.md
- lib/blueprint/patterns/intent-composition.md, logging-configuration.md
- lib/workflow/engine.md, type-loader.md, logging-config-loader.md
- lib/types/bundle.yaml, skills/hiivmind-blueprint-validate/SKILL.md
- lib/intent_detection/execution.md, templates/gateway-command.md.template
- docs/abstraction_execution/*.md

---

## Design Decisions

| Question | Decision |
|----------|----------|
| Package name | `hiivmind-blueprint-lib` |
| Directory structure | Remove `definitions/` level |
| Workflows location | `workflows/core/intent-detection.yaml` |
| Nesting under types/ | No, keep flat |

---

## Implementation Plan

### Phase 1: Restructure hiivmind-blueprint-lib (in /home/nathanielramm/git/hiivmind/hiivmind-blueprint-lib)

**1.1 Rename repository directory** (manual or via git):
```
hiivmind-blueprint-lib/ → hiivmind-blueprint-lib/
```

**1.2 Remove `definitions/` level from all paths:**

| Old Path | New Path |
|----------|----------|
| `consequences/definitions/core/` | `consequences/core/` |
| `consequences/definitions/extensions/` | `consequences/extensions/` |
| `consequences/definitions/index.yaml` | `consequences/index.yaml` |
| `preconditions/definitions/core/` | `preconditions/core/` |
| `preconditions/definitions/extensions/` | `preconditions/extensions/` |
| `preconditions/definitions/index.yaml` | `preconditions/index.yaml` |
| `nodes/definitions/core/` | `nodes/core/` |
| `nodes/definitions/index.yaml` | `nodes/index.yaml` |

**1.3 Create workflows directory and add intent-detection:**
```
workflows/
├── index.yaml
└── core/
    └── intent-detection.yaml
```

**1.4 Update package.yaml:**
- Change `name` to `hiivmind-blueprint-lib`
- Update all path references to remove `definitions/`
- Add workflows section

**1.5 Update bundle.yaml:**
- Update schema_version if needed
- Add `workflows` section with intent-detection content
- Update stats to include workflow count

### Phase 2: Update hiivmind-blueprint references

**2.1 Update bundle.yaml in hiivmind-blueprint:**
- `/home/nathanielramm/git/hiivmind/hiivmind-blueprint/lib/types/bundle.yaml`
- Change source references from `hiivmind-blueprint-lib` to `hiivmind-blueprint-lib`

**2.2 Update workflow loader references:**
- `lib/workflow/workflow-loader.md` - Update package name in examples
- `lib/workflow/type-loader.md` - Update package name in examples
- `lib/workflow/logging-config-loader.md` - Update package name
- `lib/workflow/engine.md` - Update package name in examples

**2.3 Update pattern documentation:**
- `lib/blueprint/patterns/intent-composition.md` - Update references
- `lib/blueprint/patterns/logging-configuration.md` - Update references
- `lib/blueprint/patterns/plugin-structure.md` - Update references
- `lib/blueprint/patterns/type-resolution.md` - Update references

**2.4 Update other documentation:**
- `CLAUDE.md` - Update architecture section with new package name
- `lib/types/README.md` - Update package references
- `docs/abstraction_execution/intent_detection_workflow.md`
- `docs/abstraction_execution/distributed_composable_workflows.md`

**2.5 Update templates:**
- `templates/gateway-command.md.template` - Update package references

**2.6 Update lib/intent_detection:**
- `lib/intent_detection/execution.md` - Update references

**2.7 Clean up local workflows:**
- Remove or mark as deprecated: `/home/nathanielramm/git/hiivmind/hiivmind-blueprint/lib/workflows/intent-detection.yaml`
- Update to reference the distributed version instead

---

## Files to Modify

### In hiivmind-blueprint-lib(-lib):

| File | Change |
|------|--------|
| `package.yaml` | Rename, update paths |
| `bundle.yaml` | Add workflows, update paths |
| `consequences/definitions/` → `consequences/` | Move contents up |
| `preconditions/definitions/` → `preconditions/` | Move contents up |
| `nodes/definitions/` → `nodes/` | Move contents up |
| `workflows/` | **CREATE** new directory |
| `workflows/index.yaml` | **CREATE** |
| `workflows/core/intent-detection.yaml` | **CREATE** |
| `README.md` | Update structure docs |
| `CHANGELOG.md` | Add migration notes |

### In hiivmind-blueprint:

| File | Change |
|------|--------|
| `CLAUDE.md` | Update package name, structure |
| `lib/types/bundle.yaml` | Update source reference |
| `lib/types/README.md` | Update package references |
| `lib/workflow/engine.md` | Update examples |
| `lib/workflow/type-loader.md` | Update examples |
| `lib/workflow/workflow-loader.md` | Update examples |
| `lib/workflow/logging-config-loader.md` | Update references |
| `lib/blueprint/patterns/intent-composition.md` | Update references |
| `lib/blueprint/patterns/logging-configuration.md` | Update references |
| `lib/blueprint/patterns/type-resolution.md` | Update references |
| `lib/blueprint/patterns/plugin-structure.md` | Update references |
| `lib/intent_detection/execution.md` | Update references |
| `templates/gateway-command.md.template` | Update references |
| `docs/abstraction_execution/intent_detection_workflow.md` | Update references |
| `docs/abstraction_execution/distributed_composable_workflows.md` | Update references |
| `lib/workflows/intent-detection.yaml` | Remove or deprecate |

---

## New File: workflows/index.yaml

```yaml
# Workflow Definitions Index
# hiivmind-blueprint-lib
#
# Reusable workflow definitions for Blueprint-enabled plugins.

schema_version: "1.0"
category: "workflows"

stats:
  total_workflows: 1
  core_workflows: 1

core:
  - name: intent-detection
    file: core/intent-detection.yaml
    version: "1.0.0"
    description: "Reusable 3VL intent detection for dynamic routing"
    depends_on:
      consequences:
        - parse_intent_flags
        - match_3vl_rules
        - set_state
      preconditions:
        - evaluate_expression
```

---

## Verification

1. **In hiivmind-blueprint-lib:**
   - Verify all files moved correctly (no orphaned `definitions/` dirs)
   - Verify bundle.yaml aggregates all types correctly
   - Verify workflows/core/intent-detection.yaml is valid YAML

2. **In hiivmind-blueprint:**
   - Search for old package name: `grep -r "hiivmind-blueprint-lib[^-]" .`
   - Verify no broken references remain
   - Run any validation skills if available

3. **Integration test:**
   - Reference the new workflow: `hiivmind/hiivmind-blueprint-lib@v1.x.x:intent-detection`
   - Verify loading protocol works with new structure

---

## Migration Commands (for reference)

```bash
# In hiivmind-blueprint-lib directory:

# 1. Restructure consequences
mv consequences/definitions/core consequences/core
mv consequences/definitions/extensions consequences/extensions
mv consequences/definitions/index.yaml consequences/index.yaml
rmdir consequences/definitions

# 2. Restructure preconditions
mv preconditions/definitions/core preconditions/core
mv preconditions/definitions/extensions preconditions/extensions
mv preconditions/definitions/index.yaml preconditions/index.yaml
rmdir preconditions/definitions

# 3. Restructure nodes
mv nodes/definitions/core nodes/core
mv nodes/definitions/index.yaml nodes/index.yaml
rmdir nodes/definitions

# 4. Create workflows
mkdir -p workflows/core
# Then create index.yaml and intent-detection.yaml

# 5. Rename directory (at parent level)
cd ..
mv hiivmind-blueprint-lib hiivmind-blueprint-lib
```

---

## Rollout Strategy

1. Complete all changes in hiivmind-blueprint-lib first
2. Commit and tag as v2.0.0 (breaking change due to package rename)
3. Update hiivmind-blueprint to reference new package
4. Commit hiivmind-blueprint changes
5. Update any other consumers of the types package
