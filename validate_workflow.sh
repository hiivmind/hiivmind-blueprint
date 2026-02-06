#!/bin/bash

FILE="hiivmind-blueprint-author/subflows/existing-file-handler.yaml"
ERRORS=()
WARNINGS=()

# 1. Check required fields
echo "Checking required fields..."
for field in "name" "version" "start_node" "nodes" "endings"; do
  if ! yq eval ".$field" "$FILE" | grep -q '^null$\|^$'; then
    echo "  ✓ $field exists"
  else
    ERRORS+=("Missing required field: $field")
  fi
done

# 2. Extract start_node
START_NODE=$(yq eval '.start_node' "$FILE")
echo -e "\nStart node: $START_NODE"

# 3. Get all node names
echo -e "\nExtracted nodes:"
NODES=$(yq eval '.nodes | keys | .[]' "$FILE")
echo "$NODES"
ALL_NODES=($NODES)

# 4. Get all ending names
echo -e "\nExtracted endings:"
ENDINGS=$(yq eval '.endings | keys | .[]' "$FILE")
echo "$ENDINGS"
ALL_ENDINGS=($ENDINGS)

# 5. Validate start_node exists in nodes
if [[ " ${ALL_NODES[@]} " =~ " ${START_NODE} " ]]; then
  echo "✓ Start node '$START_NODE' exists in nodes"
else
  ERRORS+=("Start node '$START_NODE' not found in nodes")
fi

# 6. Check node types are valid
echo -e "\nValidating node types..."
VALID_TYPES=("action" "conditional" "user_prompt" "validation_gate" "reference")
for node in "${ALL_NODES[@]}"; do
  node_type=$(yq eval ".nodes.$node.type" "$FILE")
  if [[ " ${VALID_TYPES[@]} " =~ " ${node_type} " ]]; then
    echo "  ✓ $node: $node_type"
  else
    ERRORS+=("Invalid node type '$node_type' in node '$node'")
  fi
done

# 7. Check referential integrity - all transitions point to valid targets
echo -e "\nChecking referential integrity..."
for node in "${ALL_NODES[@]}"; do
  node_type=$(yq eval ".nodes.$node.type" "$FILE")
  
  # Check on_success and on_failure for action/validation_gate nodes
  if [[ "$node_type" == "action" || "$node_type" == "validation_gate" ]]; then
    on_success=$(yq eval ".nodes.$node.on_success" "$FILE")
    if [[ ! -z "$on_success" && "$on_success" != "null" ]]; then
      if [[ " ${ALL_NODES[@]} " =~ " ${on_success} " ]] || [[ " ${ALL_ENDINGS[@]} " =~ " ${on_success} " ]]; then
        echo "  ✓ $node.on_success -> $on_success"
      else
        ERRORS+=("$node.on_success references non-existent target: $on_success")
      fi
    fi
    
    on_failure=$(yq eval ".nodes.$node.on_failure" "$FILE")
    if [[ ! -z "$on_failure" && "$on_failure" != "null" ]]; then
      if [[ " ${ALL_NODES[@]} " =~ " ${on_failure} " ]] || [[ " ${ALL_ENDINGS[@]} " =~ " ${on_failure} " ]]; then
        echo "  ✓ $node.on_failure -> $on_failure"
      else
        ERRORS+=("$node.on_failure references non-existent target: $on_failure")
      fi
    fi
  fi
  
  # Check branches for conditional nodes
  if [[ "$node_type" == "conditional" ]]; then
    on_true=$(yq eval ".nodes.$node.branches.on_true" "$FILE")
    if [[ ! -z "$on_true" && "$on_true" != "null" ]]; then
      if [[ " ${ALL_NODES[@]} " =~ " ${on_true} " ]] || [[ " ${ALL_ENDINGS[@]} " =~ " ${on_true} " ]]; then
        echo "  ✓ $node.branches.on_true -> $on_true"
      else
        ERRORS+=("$node.branches.on_true references non-existent target: $on_true")
      fi
    fi
    
    on_false=$(yq eval ".nodes.$node.branches.on_false" "$FILE")
    if [[ ! -z "$on_false" && "$on_false" != "null" ]]; then
      if [[ " ${ALL_NODES[@]} " =~ " ${on_false} " ]] || [[ " ${ALL_ENDINGS[@]} " =~ " ${on_false} " ]]; then
        echo "  ✓ $node.branches.on_false -> $on_false"
      else
        ERRORS+=("$node.branches.on_false references non-existent target: $on_false")
      fi
    fi
  fi
  
  # Check on_response for user_prompt nodes
  if [[ "$node_type" == "user_prompt" ]]; then
    responses=$(yq eval ".nodes.$node.on_response | keys | .[]" "$FILE" 2>/dev/null)
    if [[ ! -z "$responses" ]]; then
      while IFS= read -r response; do
        next_node=$(yq eval ".nodes.$node.on_response.$response.next_node" "$FILE")
        if [[ ! -z "$next_node" && "$next_node" != "null" ]]; then
          if [[ " ${ALL_NODES[@]} " =~ " ${next_node} " ]] || [[ " ${ALL_ENDINGS[@]} " =~ " ${next_node} " ]]; then
            echo "  ✓ $node.on_response.$response -> $next_node"
          else
            ERRORS+=("$node.on_response.$response references non-existent target: $next_node")
          fi
        fi
      done <<< "$responses"
    fi
  fi
done

# 8. Check for orphan nodes (BFS from start_node)
echo -e "\nChecking for orphan nodes (reachability from start)..."
declare -A visited
to_visit=("$START_NODE")
while [[ ${#to_visit[@]} -gt 0 ]]; do
  node="${to_visit[0]}"
  to_visit=("${to_visit[@]:1}")
  
  if [[ -z "${visited[$node]}" ]]; then
    visited[$node]=1
    node_type=$(yq eval ".nodes.$node.type" "$FILE")
    
    case "$node_type" in
      action|validation_gate)
        on_success=$(yq eval ".nodes.$node.on_success" "$FILE")
        on_failure=$(yq eval ".nodes.$node.on_failure" "$FILE")
        [[ ! -z "$on_success" && "$on_success" != "null" ]] && to_visit+=("$on_success")
        [[ ! -z "$on_failure" && "$on_failure" != "null" ]] && to_visit+=("$on_failure")
        ;;
      conditional)
        on_true=$(yq eval ".nodes.$node.branches.on_true" "$FILE")
        on_false=$(yq eval ".nodes.$node.branches.on_false" "$FILE")
        [[ ! -z "$on_true" && "$on_true" != "null" ]] && to_visit+=("$on_true")
        [[ ! -z "$on_false" && "$on_false" != "null" ]] && to_visit+=("$on_false")
        ;;
      user_prompt)
        responses=$(yq eval ".nodes.$node.on_response | keys | .[]" "$FILE" 2>/dev/null)
        while IFS= read -r response; do
          next_node=$(yq eval ".nodes.$node.on_response.$response.next_node" "$FILE")
          [[ ! -z "$next_node" && "$next_node" != "null" ]] && to_visit+=("$next_node")
        done <<< "$responses"
        ;;
    esac
  fi
done

for node in "${ALL_NODES[@]}"; do
  if [[ -z "${visited[$node]}" ]]; then
    WARNINGS+=("Orphan node '$node' - not reachable from start_node")
  else
    echo "  ✓ $node is reachable"
  fi
done

# 9. Check for dead ends (nodes without transitions to endings)
echo -e "\nChecking for dead ends (nodes that don't reach endings)..."
declare -A can_reach_ending
for node in "${ALL_NODES[@]}"; do
  node_type=$(yq eval ".nodes.$node.type" "$FILE")
  
  case "$node_type" in
    action|validation_gate)
      on_success=$(yq eval ".nodes.$node.on_success" "$FILE")
      on_failure=$(yq eval ".nodes.$node.on_failure" "$FILE")
      if [[ " ${ALL_ENDINGS[@]} " =~ " ${on_success} " ]] || [[ " ${ALL_ENDINGS[@]} " =~ " ${on_failure} " ]]; then
        can_reach_ending[$node]=1
      fi
      ;;
    conditional)
      on_true=$(yq eval ".nodes.$node.branches.on_true" "$FILE")
      on_false=$(yq eval ".nodes.$node.branches.on_false" "$FILE")
      if [[ " ${ALL_ENDINGS[@]} " =~ " ${on_true} " ]] || [[ " ${ALL_ENDINGS[@]} " =~ " ${on_false} " ]]; then
        can_reach_ending[$node]=1
      fi
      ;;
    user_prompt)
      responses=$(yq eval ".nodes.$node.on_response | keys | .[]" "$FILE" 2>/dev/null)
      while IFS= read -r response; do
        next_node=$(yq eval ".nodes.$node.on_response.$response.next_node" "$FILE")
        if [[ " ${ALL_ENDINGS[@]} " =~ " ${next_node} " ]]; then
          can_reach_ending[$node]=1
          break
        fi
      done <<< "$responses"
      ;;
  esac
  
  if [[ -z "${can_reach_ending[$node]}" ]]; then
    WARNINGS+=("Node '$node' has no direct path to endings (may be indirect)")
  else
    echo "  ✓ $node can reach endings"
  fi
done

# 10. Check user_prompt nodes have valid options and headers
echo -e "\nValidating user_prompt nodes..."
for node in "${ALL_NODES[@]}"; do
  node_type=$(yq eval ".nodes.$node.type" "$FILE")
  if [[ "$node_type" == "user_prompt" ]]; then
    header=$(yq eval ".nodes.$node.prompt.header" "$FILE")
    header_len=${#header}
    if [[ $header_len -le 12 ]]; then
      echo "  ✓ $node header length: $header_len chars (max 12)"
    else
      ERRORS+=("$node header exceeds 12 chars: '$header' ($header_len chars)")
    fi
    
    option_count=$(yq eval ".nodes.$node.prompt.options | length" "$FILE")
    if [[ $option_count -ge 2 && $option_count -le 4 ]]; then
      echo "  ✓ $node has $option_count options (valid: 2-4)"
    else
      ERRORS+=("$node has $option_count options (must be 2-4)")
    fi
  fi
done

# Summary
echo -e "\n========== VALIDATION REPORT =========="
echo "File: $FILE"

if [[ ${#ERRORS[@]} -eq 0 && ${#WARNINGS[@]} -eq 0 ]]; then
  echo "Status: PASS"
else
  if [[ ${#ERRORS[@]} -gt 0 ]]; then
    echo "Status: FAIL"
  else
    echo "Status: PASS (with warnings)"
  fi
fi

if [[ ${#ERRORS[@]} -gt 0 ]]; then
  echo -e "\nERRORS:"
  for error in "${ERRORS[@]}"; do
    echo "  • $error"
  done
fi

if [[ ${#WARNINGS[@]} -gt 0 ]]; then
  echo -e "\nWARNINGS:"
  for warning in "${WARNINGS[@]}"; do
    echo "  • $warning"
  done
fi

echo "=========================================="
