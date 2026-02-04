# Workflow Diagram: hiivmind-blueprint-author-upgrade

```mermaid
flowchart TD
    classDef success fill:#90EE90,stroke:#228B22
    classDef error fill:#FFB6C1,stroke:#DC143C
    classDef conditional fill:#87CEEB,stroke:#4682B4
    classDef userPrompt fill:#DDA0DD,stroke:#9932CC
    classDef action fill:#F5F5F5,stroke:#696969

    start([Start]) --> check_prerequisites

    subgraph Prerequisites
        check_prerequisites{jq?}:::conditional -->|true| check_yq
        check_prerequisites -->|false| error_missing_jq
        check_yq{yq?}:::conditional -->|true| parse_args
        check_yq -->|false| error_missing_yq
    end

    parse_args[Parse Args]:::action --> discover_skills

    subgraph Discovery
        discover_skills[Find SKILL.md Files]:::action --> classify_skills
        classify_skills[Classify Each]:::action --> show_discovery_summary
        show_discovery_summary[Show Summary]:::action --> check_has_candidates
    end

    check_has_candidates{prose skills?}:::conditional
    check_has_candidates -->|true| confirm_batch_conversion
    check_has_candidates -->|false| success_nothing_to_convert

    subgraph Confirmation
        confirm_batch_conversion{force?}:::conditional
        confirm_batch_conversion -->|true| start_batch_conversion
        confirm_batch_conversion -->|false| prompt_confirm_batch
        prompt_confirm_batch([Convert Skills?]):::userPrompt
        prompt_confirm_batch -->|all| start_batch_conversion
        prompt_confirm_batch -->|select| prompt_skill_selection
        prompt_confirm_batch -->|cancel| success_cancelled
        prompt_skill_selection([Select Skills]):::userPrompt --> start_batch_conversion
    end

    subgraph Batch Loop
        start_batch_conversion[Initialize]:::action --> process_next_skill
        process_next_skill{more skills?}:::conditional
        process_next_skill -->|true| convert_current_skill
        process_next_skill -->|false| show_final_report
        convert_current_skill[Convert Current]:::action --> check_dry_run
        check_dry_run{dry run?}:::conditional
        check_dry_run -->|true| dry_run_skill
        check_dry_run -->|false| invoke_convert_skill
        dry_run_skill[Show Preview]:::action --> increment_and_continue
        invoke_convert_skill[Run Convert]:::action --> record_conversion_success
        record_conversion_success[Record Success]:::action --> increment_and_continue
        record_conversion_failure[Record Failure]:::action --> increment_and_continue
        increment_and_continue[Next Index]:::action --> process_next_skill
        invoke_convert_skill -.->|error| record_conversion_failure
    end

    show_final_report[Final Report]:::action --> success_complete

    success_complete((✓ Complete)):::success
    success_nothing_to_convert((✓ Nothing)):::success
    success_cancelled((✓ Cancelled)):::success
    error_missing_jq((✗ Missing jq)):::error
    error_missing_yq((✗ Missing yq)):::error
    error_discovery_failed((✗ Discovery Failed)):::error

    discover_skills -.->|error| error_discovery_failed
    classify_skills -.->|error| error_discovery_failed
```

## Summary

| Metric | Value |
|--------|-------|
| **Nodes** | 19 |
| **Conditionals** | 6 |
| **User Prompts** | 2 |
| **Endings** | 6 |
| **Start Node** | check_prerequisites |
