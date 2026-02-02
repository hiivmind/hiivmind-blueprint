# Workflow Execution Engine

This document provides execution semantics for the retail agent workflows. The authoritative execution semantics are defined in YAML files within `hiivmind-blueprint-lib`.

---

## Authoritative Sources

The execution logic references structured YAML from the blueprint library:

| Content | Authoritative Source |
|---------|---------------------|
| Core execution loop | `hiivmind-blueprint-lib/execution/traversal.yaml` |
| State structure and interpolation | `hiivmind-blueprint-lib/execution/state.yaml` |
| Consequence dispatch | `hiivmind-blueprint-lib/execution/consequence-dispatch.yaml` |
| Precondition evaluation | `hiivmind-blueprint-lib/execution/precondition-dispatch.yaml` |
| Node type execution | `hiivmind-blueprint-lib/nodes/core/*.yaml` |

---

## tau-bench Retail Agent Context

This plugin implements a customer service agent for an online retail store. The workflow engine executes skills that:

1. **Authenticate users** by email or name+zip
2. **Look up information** about users, orders, and products
3. **Execute actions** with mandatory confirmation:
   - Cancel pending orders
   - Modify pending orders (address, payment, items)
   - Return delivered order items
   - Exchange delivered order items

### Policy Constraints (Encoded as Preconditions)

| Rule | Implementation |
|------|----------------|
| Must authenticate first | `state_not_null: user_id` precondition |
| Order must be pending for cancel/modify | `evaluate_expression: status == 'pending'` |
| Order must be delivered for return/exchange | `evaluate_expression: status == 'delivered'` |
| Must confirm before action | `user_prompt` node with yes/no branches |
| Item modification is one-time | `evaluate_expression: status != 'pending (items modified)'` |

---

## Execution Model

### Phase 1: Initialization

1. Load workflow.yaml
2. Load type definitions from `hiivmind-blueprint-lib`
3. Validate schema and graph connectivity
4. Check entry preconditions
5. Initialize state from `initial_state`

### Phase 2: Execution Loop

```
LOOP:
    node = workflow.nodes[current_node]
    IF current_node IN endings: GOTO Phase 3

    # Check preconditions
    IF node.preconditions:
        FOR each precondition:
            IF NOT evaluate(precondition):
                current_node = node.on_failure OR error
                CONTINUE LOOP

    # Execute node by type
    outcome = dispatch_node(node, state)

    # Apply consequences
    FOR each consequence in outcome.consequences:
        apply_consequence(consequence, state)

    # Route to next node
    current_node = outcome.next_node
UNTIL ending
```

### Phase 3: Completion

1. Display ending message to user
2. Return final state

---

## Node Types

| Type | Purpose | Key Fields |
|------|---------|------------|
| `action` | Execute tool call | `tool`, `arguments`, `consequences` |
| `conditional` | Branch on condition | `condition`, `branches.on_true/on_false` |
| `user_prompt` | Get user input | `prompt`, `options`, `branches` |
| `validation_gate` | Verify state | `preconditions`, `on_failure` |
| `reference` | Include sub-workflow | `workflow`, `context` |

---

## State Structure

```yaml
state:
  # User context
  user_id: null
  user: null

  # Order context
  order_id: null
  order: null

  # Action parameters
  reason: null
  payment_method_id: null
  item_ids: []
  new_item_ids: []

  # Address fields (for modify)
  address1: null
  address2: null
  city: null
  state: null
  country: null
  zip: null

  # Results
  result: null

  # Routing
  flags:
    authenticated: false
    confirmed: false
```

---

## Variable Interpolation

```yaml
# State field reference
user_id: "${user_id}"

# Nested computed value
status: "${order.status}"

# User response
reason: "${user_responses.cancellation_reason}"

# Conditional expression
condition: "${order.status} == 'pending'"
```

---

## tau-bench Tool Mapping

| tau-bench Tool | Workflow Usage |
|----------------|----------------|
| FindUserIdByEmail | `tool: FindUserIdByEmail` in action node |
| FindUserIdByNameZip | `tool: FindUserIdByNameZip` in action node |
| GetUserDetails | `tool: GetUserDetails` in action node |
| GetOrderDetails | `tool: GetOrderDetails` in action node |
| GetProductDetails | `tool: GetProductDetails` in action node |
| ListAllProductTypes | `tool: ListAllProductTypes` in action node |
| CancelPendingOrder | `tool: CancelPendingOrder` in action node |
| ModifyPendingOrderAddress | `tool: ModifyPendingOrderAddress` in action node |
| ModifyPendingOrderPayment | `tool: ModifyPendingOrderPayment` in action node |
| ModifyPendingOrderItems | `tool: ModifyPendingOrderItems` in action node |
| ReturnDeliveredOrderItems | `tool: ReturnDeliveredOrderItems` in action node |
| ExchangeDeliveredOrderItems | `tool: ExchangeDeliveredOrderItems` in action node |
| Think | `tool: Think` for chain-of-thought |
| Calculate | `tool: Calculate` for arithmetic |
| TransferToHumanAgents | `tool: TransferToHumanAgents` for escalation |

---

## Confirmation Pattern

All destructive actions require explicit confirmation:

```yaml
confirm_action:
  type: user_prompt
  prompt: |
    Please confirm the following action:
    - Order: ${order_id}
    - Action: ${action_description}
    - Details: ${action_details}

    Do you confirm? (yes/no)
  branches:
    "yes": execute_action
    "no": action_cancelled
```

This pattern is reusable via the `lib/workflows/confirm-action.yaml` sub-workflow.
