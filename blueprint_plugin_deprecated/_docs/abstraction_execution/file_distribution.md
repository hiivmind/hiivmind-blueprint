# Blueprint File Distribution & Version Management

## Goal

Design a consistent approach for:
1. Placing engine.md and type definitions in target plugins
2. Aligning with existing `.hiivmind/` patterns (from hiivmind-pulse-gh)
3. Managing versions, pinning, and updates for distributed files

---

## Design Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| File location | `.hiivmind/blueprint/` | Aligns with hiivmind ecosystem pattern |
| Global cache path | `~/.claude/cache/hiivmind/blueprint/` | Consistent branding, not `blueprint-types` |
| Offline fallback | Not needed | Network always required for Claude |

---

## Architecture

### Global Cache (User-Level, Shared)

```
~/.claude/cache/hiivmind/blueprint/
├── types/
│   └── {owner}/{repo}/{version}/
│       ├── bundle.yaml
│       └── metadata.yaml
└── engine/
    └── {version}/
        └── engine.md
```

### Plugin-Level (`.hiivmind/blueprint/`)

```
{target_plugin}/
├── .hiivmind/
│   └── blueprint/
│       ├── engine.md              # Copied from cache/source
│       └── types.lock             # Version pinning
├── skills/
│   └── my-skill/
│       ├── SKILL.md               # References .hiivmind/blueprint/engine.md
│       └── workflow.yaml
└── ...
```

**Note:** No embedded/offline fallback needed - Claude requires network access.

---

## Version Management

### Version Resolution Rules

| Request | Matches | Behavior |
|---------|---------|----------|
| `@v1.2.3` | Exact | Use exact, never re-resolve |
| `@v1.2` | Latest v1.2.x | Re-resolve after 24h |
| `@v1` | Latest v1.x.x | Re-resolve after 24h |

### Update Flow

```
/hiivmind-blueprint upgrade --check
    │
    ▼
Read .hiivmind/blueprint/types.lock
    │
    ▼
Fetch latest from GitHub releases API
    │
    ▼
Report: "Types: v1.3.2 → v1.4.0, Engine: 1.1.0 → 1.2.0"
    │
    ▼
/hiivmind-blueprint upgrade
    │
    ▼
Download to ~/.claude/cache/hiivmind/blueprint/
    │
    ▼
Copy engine.md → .hiivmind/blueprint/
    │
    ▼
Update types.lock
```

---

## Final Structure

### Target Plugin Layout

```
{target_plugin}/
├── .hiivmind/
│   └── blueprint/
│       ├── engine.md              # Workflow execution semantics (copied)
│       └── types.lock             # Pinned versions and SHAs
├── skills/
│   └── my-skill/
│       ├── SKILL.md               # References .hiivmind/blueprint/engine.md
│       └── workflow.yaml
└── ...
```

### Lock File Format

```yaml
# .hiivmind/blueprint/types.lock
schema: "1.0"
generated_at: "2026-01-27T12:00:00Z"
generated_by: "hiivmind-blueprint v1.1.0"

engine:
  version: "1.1.0"
  sha256: "abc123..."
  source: "hiivmind/hiivmind-blueprint@v1.1.0"

types:
  hiivmind/hiivmind-blueprint-lib:
    requested: "@v1"
    resolved: "v1.3.2"
    sha256: "def456..."
    fetched_at: "2026-01-27T05:30:00Z"

  # Additional type sources (extensions)
  mycorp/custom-types:
    requested: "@v2.0.0"
    resolved: "v2.0.0"
    sha256: "ghi789..."
```

---

## Files to Modify

### In hiivmind-blueprint

| File | Change |
|------|--------|
| `templates/skill-with-executor.md.template` | Update engine path to `.hiivmind/blueprint/engine.md` |
| `skills/hiivmind-blueprint-generate/SKILL.md` | Copy engine.md to `.hiivmind/blueprint/`, create types.lock |
| `skills/hiivmind-blueprint-upgrade/SKILL.md` | Update engine.md, refresh types.lock |
| `lib/workflow/type-loader.md` | Update cache path to `~/.claude/cache/hiivmind/blueprint/`, lock file to `.hiivmind/blueprint/types.lock` |
| `lib/blueprint/patterns/type-resolution.md` | Document new structure |

### New Files to Create

| File | Purpose |
|------|---------|
| `lib/blueprint/patterns/plugin-structure.md` | Document `.hiivmind/blueprint/` layout |
| `lib/schema/types-lock-schema.json` | JSON Schema for lock file validation |

---

## Implementation Steps

1. **Update global cache path** in type-loader.md
   - Change `~/.claude/cache/blueprint-types/` → `~/.claude/cache/hiivmind/blueprint/`

2. **Update thin loader template**
   - Change `${CLAUDE_PLUGIN_ROOT}/lib/workflow/engine.md` → `${CLAUDE_PLUGIN_ROOT}/.hiivmind/blueprint/engine.md`

3. **Update generate skill**
   - Create `.hiivmind/blueprint/` directory
   - Copy engine.md to `.hiivmind/blueprint/engine.md`
   - Create `types.lock` with pinned versions

4. **Update upgrade skill**
   - Read current versions from `types.lock`
   - Fetch latest versions
   - Update engine.md and types.lock

5. **Create documentation**
   - Document `.hiivmind/blueprint/` structure in plugin-structure.md
   - Create JSON Schema for types.lock validation

---

## Verification

1. Generate a test workflow to a new plugin
2. Verify `.hiivmind/blueprint/` directory structure created
3. Verify thin loader references `.hiivmind/blueprint/engine.md`
4. Verify types.lock contains correct version info
5. Test upgrade flow detects and updates versions



Implementation Complete

I've implemented the Blueprint File Distribution & Version Management plan. Here's what was done:

Files Modified
┌─────────────────────────────────────────────┬──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
│                    File                     │                                                             Changes                                                              │
├─────────────────────────────────────────────┼──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
│ lib/workflow/type-loader.md                 │ Updated cache path ~/.claude/cache/blueprint-types/ → ~/.claude/cache/hiivmind/blueprint/, updated lock file format and location │
├─────────────────────────────────────────────┼──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
│ lib/workflow/engine.md                      │ Updated cache path reference                                                                                                     │
├─────────────────────────────────────────────┼──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
│ templates/skill-with-executor.md.template   │ Updated all engine references to .hiivmind/blueprint/engine.md, added types.lock reference                                       │
├─────────────────────────────────────────────┼──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
│ skills/hiivmind-blueprint-generate/SKILL.md │ Added Phase 3.1 (create .hiivmind/blueprint/ structure), Phase 3.2 (create types.lock), updated output summary                   │
├─────────────────────────────────────────────┼──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
│ skills/hiivmind-blueprint-upgrade/SKILL.md  │ Added infrastructure upgrade mode, Phase 5 for engine/types updates, version check flow                                          │
├─────────────────────────────────────────────┼──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
│ lib/blueprint/patterns/type-resolution.md   │ Updated cache paths, lock file location, added plugin structure section and update flow                                          │
├─────────────────────────────────────────────┼──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
│ CLAUDE.md                                   │ Added target plugin structure section, lock file format, global cache documentation                                              │
└─────────────────────────────────────────────┴──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
Files Created
┌────────────────────────────────────────────┬───────────────────────────────────────────────────────────────────────────────────┐
│                    File                    │                                      Purpose                                      │
├────────────────────────────────────────────┼───────────────────────────────────────────────────────────────────────────────────┤
│ lib/blueprint/patterns/plugin-structure.md │ Documents the .hiivmind/blueprint/ layout, aligns with hiivmind ecosystem pattern │
├────────────────────────────────────────────┼───────────────────────────────────────────────────────────────────────────────────┤
│ lib/schema/types-lock-schema.json          │ JSON Schema for validating types.lock format                                      │
└────────────────────────────────────────────┴───────────────────────────────────────────────────────────────────────────────────┘
Key Architecture Decisions Implemented

1. File location: .hiivmind/blueprint/ in target plugins (aligns with ecosystem pattern)
2. Global cache path: ~/.claude/cache/hiivmind/blueprint/ (consistent branding)
3. Lock file location: .hiivmind/blueprint/types.lock (not .blueprint-types.lock)
4. Lock file format: Includes both engine and types sections with SHA256 hashes

Target Plugin Structure

{target_plugin}/
├── .hiivmind/
│   └── blueprint/
│       ├── engine.md              # Copied from source
│       └── types.lock             # Version pinning
├── skills/
│   └── my-skill/
│       ├── SKILL.md               # References .hiivmind/blueprint/engine.md
│       └── workflow.yaml

✻ Churned for 13m 20s
