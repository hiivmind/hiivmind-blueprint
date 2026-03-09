> **Used by:** `SKILL.md` Phase 2, Step 2.1
> **Supplements:** `${CLAUDE_PLUGIN_ROOT}/lib/patterns/skill-analysis.md`

# Keyword Extraction Algorithm

Complete regex catalog and extraction pipeline for deriving trigger keywords from SKILL.md
description fields. Used by `bp-gateway` to build the keyword lists that populate
intent_flags in intent-mapping.yaml.

---

## Extraction Pipeline

The algorithm runs five extraction passes in priority order. Later passes only contribute
keywords not already captured by earlier passes.

```
Pass 1: Quoted Phrases       (highest fidelity)
  |
Pass 2: Trigger Section      (explicit author intent)
  |
Pass 3: Verb-Object Phrases  (action + target pairs)
  |
Pass 4: Standalone Verbs     (individual action words)
  |
Pass 5: Deduplicate + Normalize
```

---

## Pass 1: Quoted Phrase Extraction

Extract phrases explicitly quoted by the skill author in the description. These are the
highest-fidelity keywords because the author intentionally marked them as trigger phrases.

**Regex pattern:**

```
/"([^"]+)"/g
```

**Examples:**

| Description Fragment | Extracted |
|---------------------|-----------|
| `asks to "create intent mapping"` | `create intent mapping` |
| `"generate file", "write output"` | `generate file`, `write output` |
| `"set up 3VL matching"` | `set up 3VL matching` |

**Edge cases:**

- Nested quotes are not supported; the outermost pair is used
- Empty quoted strings (`""`) are discarded
- Single-character quoted strings (`"?"`) are kept (the `?` help trigger)

---

## Pass 2: Trigger Section Parsing

Extract the comma-separated list following the "Triggers on" marker that appears at the end
of most skill descriptions.

**Regex pattern:**

```
/Triggers on\s+(.+?)\.?\s*$/s
```

**Post-processing:**

```pseudocode
function parse_triggers(triggers_text):
  items = split(triggers_text, ",")
  result = []
  for item in items:
    cleaned = item.strip()
    # Strip surrounding quotes if present
    cleaned = strip_outer_quotes(cleaned)
    if len(cleaned) > 0:
      result.append(cleaned)
  return result
```

**Examples:**

| Triggers Text | Extracted |
|--------------|-----------|
| `Triggers on "intent create", "create intent", "intent mapping"` | `intent create`, `create intent`, `intent mapping` |
| `Triggers on discover skills, plugin discover, list skills` | `discover skills`, `plugin discover`, `list skills` |

**Edge cases:**

- If the "Triggers on" section contains a period at the end, strip it before splitting
- If no "Triggers on" marker is found, this pass produces no output (not an error)
- Multi-line descriptions: the trigger section may wrap across lines; use the `s` (dotall) flag

---

## Pass 3: Verb-Object Phrase Extraction

Extract action verb + object pairs to capture meaningful two-word or three-word phrases.

**Regex pattern:**

```
/\b(create|delete|update|find|show|list|analyze|analyse|convert|validate|generate|set up|add|remove|check|verify|scan|discover|build|rebuild|refresh|sync|configure|define|map|route|detect|extract)\s+(\w+(?:\s+\w+)?)/gi
```

**Matching rules:**

- The verb must be a recognized action verb (see verb catalog below)
- Capture 1-2 words after the verb as the object
- The result is the full matched phrase (verb + object)

**Verb catalog:**

| Category | Verbs |
|----------|-------|
| Creation | create, generate, build, initialize, init, setup, set up, add, define |
| Modification | update, edit, change, modify, extend, configure, refresh, sync, rebuild |
| Query | find, search, show, list, discover, scan, check, verify, detect, analyze, analyse |
| Deletion | delete, remove, clear, reset |
| Transformation | convert, transform, map, route, extract, validate |

**Edge cases:**

- "set up" is treated as a single verb (two words) matching the pattern `set\s+up`
- "analyse" (British English) is equivalent to "analyze"
- Stop words after the verb are skipped: "set up **the** environment" extracts "set up environment"

---

## Pass 4: Standalone Verb Extraction

Extract individual action verbs that may not have been captured as part of phrases.

**Regex pattern:**

```
/\b(create|delete|update|find|show|list|analyze|analyse|convert|validate|generate|setup|init|initialize|discover|scan|verify|check|build|rebuild|refresh|sync|configure|define|map|route|detect|extract|add|remove|edit|modify)\b/gi
```

**Deduplication with Pass 3:**

If a verb was already captured as part of a phrase in Pass 3, the standalone verb is still added
to the keyword list (it acts as a broader match). For example, if Pass 3 captured "create intent"
then Pass 4 will also capture "create" as a standalone keyword. Both are kept because:

- "create intent" matches the specific use case
- "create" alone catches variations like "create mapping" or just "create"

---

## Pass 5: Deduplicate and Normalize

After all passes complete, merge the results:

```pseudocode
function deduplicate_keywords(all_keywords):
  seen = set()
  result = []

  for kw in all_keywords:
    # Normalize: lowercase, strip whitespace, collapse internal spaces
    normalized = kw.strip().lower()
    normalized = regex_replace(normalized, /\s+/, " ")

    # Skip empty or single-character (except "?")
    if len(normalized) <= 1 and normalized != "?":
      continue

    # Skip pure stop words
    if normalized in STOP_WORDS:
      continue

    if normalized not in seen:
      seen.add(normalized)
      result.append(normalized)

  return result
```

**Stop words to exclude:**

```
STOP_WORDS = {"the", "a", "an", "is", "are", "was", "were", "be", "been",
              "being", "have", "has", "had", "do", "does", "did", "will",
              "would", "could", "should", "may", "might", "can", "shall",
              "to", "of", "in", "for", "on", "with", "at", "by", "from",
              "or", "and", "not", "no", "but", "if", "then", "else",
              "when", "this", "that", "it", "its"}
```

**Ordering:** Preserve the order from passes 1-4. This means quoted phrases appear first
(highest author intent), followed by trigger section items, then verb-object phrases, then
standalone verbs.

---

## Negative Keyword Detection

Negative keywords are extracted separately and indicate when a keyword should NOT match a
particular skill. They are critical for 3VL disambiguation.

**Sources of negative keywords:**

1. **Explicit negative markers in description:**

   ```
   /\bnot\s+(\w+(?:\s+\w+)?)/gi
   /\bexcluding\s+(\w+(?:\s+\w+)?)/gi
   /\bexcept\s+(\w+(?:\s+\w+)?)/gi
   ```

2. **Overlap-derived negatives** (computed during Phase 3 of the parent skill):

   When two skills share a keyword, each skill's unique keywords become the other's negative
   keywords. For example:

   | Skill A keywords | Skill B keywords | Shared | A negatives | B negatives |
   |-----------------|-----------------|--------|-------------|-------------|
   | create, intent, mapping | create, gateway, command | create | gateway, command | intent, mapping |

3. **Antonym pairs:**

   | Keyword | Antonym (negative) |
   |---------|-------------------|
   | create | delete, remove |
   | add | remove, delete |
   | single | batch, all |
   | batch | single |

---

## Priority Ordering

When the same keyword could be assigned to multiple flags, use this priority:

1. **Exact match in quoted phrase** -- highest priority, assign to the skill that quoted it
2. **Trigger section match** -- explicit author assignment
3. **Verb-object phrase match** -- contextual match with object
4. **Standalone verb match** -- broadest match, lowest priority

If a keyword appears in two skills' quoted phrases (both authors claimed it), it becomes a
**shared keyword** and both skills get it, but both also get the other's unique keywords as
negatives.

---

## Examples

### Example 1: Simple Description

```yaml
description: >
  This skill should be used when the user asks to "validate workflow",
  "check workflow.yaml", or "find workflow errors". Triggers on
  "validate", "check workflow", "lint", "verify".
```

**Pass 1:** `validate workflow`, `check workflow.yaml`, `find workflow errors`
**Pass 2:** `validate`, `check workflow`, `lint`, `verify`
**Pass 3:** `validate workflow`, `check workflow.yaml`, `find workflow`
**Pass 4:** `validate`, `check`, `find`, `verify`
**Deduplicated:** `validate workflow`, `check workflow.yaml`, `find workflow errors`, `validate`, `check workflow`, `lint`, `verify`, `find workflow`, `check`, `find`

### Example 2: Description with Overlap Signals

```yaml
description: >
  This skill should be used when the user asks to "create intent mapping"
  or "generate intent-mapping.yaml". Not for modifying existing intents.
  Triggers on "intent create", "create intent", "intent mapping".
```

**Pass 1:** `create intent mapping`, `generate intent-mapping.yaml`
**Pass 2:** `intent create`, `create intent`, `intent mapping`
**Pass 3:** `create intent`, `generate intent-mapping.yaml`
**Pass 4:** `create`, `generate`
**Negative (explicit):** `modifying existing intents` -> `modify`, `existing`
**Deduplicated:** `create intent mapping`, `generate intent-mapping.yaml`, `intent create`, `create intent`, `intent mapping`, `create`, `generate`

---

## Related Documentation

- **Flag Generation Rules:** `patterns/flag-generation-rules.md`
- **Intent Mapping Template:** `${CLAUDE_PLUGIN_ROOT}/templates/intent-mapping.yaml.template`
- **Skill Analysis Pattern:** `${CLAUDE_PLUGIN_ROOT}/lib/patterns/skill-analysis.md`
