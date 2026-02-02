# Plan: Remove Bundle Pattern from hiivmind-blueprint Architecture

## Problem Statement

The `bundle.yaml` pattern was designed for "offline/airgapped fallback" - a scenario that doesn't exist for LLM agentic workflows (Claude Code requires API connectivity). This creates:

1. **Unnecessary duplication** - Same type definitions exist in 3 places
2. **Sync burden** - Any type update requires synchronizing all copies
3. **False rationale** - "Offline fallback" is impossible when Claude Code needs the API

## Design Decisions

- **Release format**: Raw GitHub files (no special artifacts, use raw.githubusercontent.com)
- **Caching**: None - always fetch fresh (simplest approach)

---

## Changes Overview

### hiivmind-blueprint (this repo)

| Action | Path |
|--------|------|
| DELETE | `lib/types/bundle.yaml` |
| DELETE | `lib/types/README.md` |
| DELETE | `lib/types/` directory entirely |
| UPDATE | `lib/blueprint/patterns/type-resolution.md` |
| UPDATE | `lib/workflow/type-loader.md` |
| UPDATE | `lib/workflow/logging-config-loader.md` |
| DELETE | `lib/schema/types-lock-schema.json` (lock files no longer needed) |
| UPDATE | `lib/blueprint/patterns/plugin-structure.md` |
| UPDATE | `CLAUDE.md` |

### hiivmind-blueprint-lib (separate repo)

| Action | Path |
|--------|------|
| DELETE | `bundle.yaml` |
| UPDATE | `README.md` |

---

## Phase 1: Delete Bundle Files

### hiivmind-blueprint
```
rm lib/types/bundle.yaml
rm lib/types/README.md
rmdir lib/types/
```

### hiivmind-blueprint-lib
```
rm bundle.yaml
```

---

## Phase 2: Simplify Type Resolution Protocol

### New Resolution Flow (Direct Raw URL)

```
definitions:
  source: hiivmind/hiivmind-blueprint-lib@v2.0.0

Resolution:
1. Parse owner/repo@version
2. Construct raw URL: https://raw.githubusercontent.com/{owner}/{repo}/{version}/
3. Fetch consequences/index.yaml and preconditions/index.yaml
4. For each referenced type, fetch individual file on-demand
```

### Update type-loader.md

Remove:
- Cache key computation
- Cache check/write logic
- Fallback strategies (embedded, warn, error)
- Lock file generation

Simplify to:
- Direct URL construction
- Fetch index
- Fetch individual types as needed
- No persistence

### Update type-resolution.md

Remove:
- "Hybrid Model" section
- Cache structure documentation
- Fallback options
- Lock file format

Replace with:
- Direct raw GitHub URL resolution
- No caching, no fallback

---

## Phase 3: Remove Lock File Infrastructure

### Delete types-lock-schema.json

Lock files are no longer needed since:
- No caching means no need to track resolved versions
- Always fetch fresh means always get latest for pinned version

### Update plugin-structure.md

Remove:
- `.hiivmind/blueprint/types.lock` from plugin structure
- Lock file generation documentation
- Cache directory structure (`~/.claude/cache/hiivmind/blueprint/`)

---

## Phase 4: Update CLAUDE.md

Remove/update these sections:
- "External Type Definitions" - simplify to raw URL approach
- "Hybrid Model" - remove entirely
- "Version Pinning" - keep but simplify
- "Global Cache" - remove entirely
- "Lock File Format" - remove entirely
- "Type Inventory" - keep, just reference lib directly

---

## Phase 5: Update logging-config-loader.md

Remove embedded fallback references in the 4-tier hierarchy. Update to:
```
1. Runtime flags (--log-level=debug)     ← Highest priority
2. Workflow initial_state.logging        ← Skill-specific
3. Plugin .hiivmind/blueprint/logging.yaml ← Plugin-wide
4. Remote defaults from lib              ← Framework defaults (always fetched)
```

---

## Verification

1. Grep for "offline", "fallback", "embedded", "cache", "lock" across both repos
2. Ensure all references updated or removed
3. Verify raw.githubusercontent.com URLs work for current lib structure
4. Update any examples that reference bundle.yaml

---

## Files Summary

### hiivmind-blueprint deletions
- `lib/types/bundle.yaml`
- `lib/types/README.md`
- `lib/types/` (directory)
- `lib/schema/types-lock-schema.json`

### hiivmind-blueprint updates
- `lib/blueprint/patterns/type-resolution.md`
- `lib/blueprint/patterns/plugin-structure.md`
- `lib/workflow/type-loader.md`
- `lib/workflow/logging-config-loader.md`
- `CLAUDE.md`

### hiivmind-blueprint-lib deletions
- `bundle.yaml`

### hiivmind-blueprint-lib updates
- `README.md`
