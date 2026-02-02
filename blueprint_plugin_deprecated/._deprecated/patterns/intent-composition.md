# Composable Intent Detection Pattern

Integrate reusable 3VL intent detection into gateway workflows, eliminating N-conditional routing cascades.

---

## The Problem: O(N) Routing Cascade

Traditional gateway routing uses a conditional node per action:

```yaml
route_to_init:
  type: conditional
  condition: { type: state_equals, field: computed.matched_action, value: "delegate_init" }
  branches: { on_true: delegate_init, on_false: route_to_build }

route_to_build:
  type: conditional
  # ... continues for each action
```

**Issues:** Adding actions requires adding nodes. Verbose, hard to maintain.

---

## The Solution: O(1) Dynamic Routing

Use `dynamic_route` consequence with interpolated `on_success`:

```yaml
execute_dynamic_route:
  type: action
  actions:
    - type: dynamic_route
      action: "${computed.matched_action}"
  on_success: "${computed.dynamic_target}"  # Interpolated at runtime
  on_failure: show_main_menu
```

The `dynamic_route` consequence sets `computed.dynamic_target` from the action, then `on_success` interpolates it.

---

## Integration Options

### Option 1: Remote Workflow Reference (Recommended)

```yaml
detect_intent:
  type: reference
  workflow: hiivmind/hiivmind-blueprint-lib@v2.0.0:intent-detection
  context:
    arguments: "${arguments}"
    intent_flags: "${intent_flags}"
    intent_rules: "${intent_rules}"
    fallback_action: "show_main_menu"
  next_node: execute_dynamic_route
```

### Option 2: Local File Reference

```yaml
detect_intent:
  type: reference
  doc: "lib/workflows/intent-detection.yaml"
  context: { ... }
  next_node: execute_dynamic_route
```

---

## Adding a New Action

With dynamic routing, add only:

1. **Flag** in `intent-mapping.yaml`:
   ```yaml
   has_new_feature:
     keywords: ["new feature", "add feature"]
   ```

2. **Rule** in `intent-mapping.yaml`:
   ```yaml
   - name: "new_feature"
     conditions: { has_new_feature: T }
     action: "delegate_new_feature"
   ```

3. **Delegate node** in `workflow.yaml`:
   ```yaml
   delegate_new_feature:
     type: action
     actions:
       - type: invoke_skill
         skill: "my-plugin-new-feature"
     on_success: success
     on_failure: error_skill_failed
   ```

No conditional cascade updates needed.

---

## Comparison

| Aspect | Cascade | Dynamic |
|--------|---------|---------|
| Routing nodes | O(N) | O(1) |
| Add new action | 3 changes + conditional | 3 changes only |
| Testing | Cover all branches | Single path |

---

## Related Documentation

- **Intent Detection Guide:** `docs/intent-detection-guide.md`
- **Workflow Loader:** `lib/workflow/workflow-loader.md`
- **Gateway Template:** `templates/gateway-command.md.template`
