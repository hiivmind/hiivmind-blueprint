# Workflow Diagram: hiivmind-blueprint-author-gateway

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
        check_yq{yq?}:::conditional -->|true| detect_plugin_name
        check_yq -->|false| error_missing_yq
    end

    subgraph Plugin Detection
        detect_plugin_name[Detect Name]:::action --> confirm_plugin_name
        confirm_plugin_name{name found?}:::conditional
        confirm_plugin_name -->|true| set_plugin_name
        confirm_plugin_name -->|false| prompt_plugin_name
        set_plugin_name[Set Name]:::action --> discover_skills
        prompt_plugin_name([Enter Name]):::userPrompt --> discover_skills
    end

    subgraph Skill Discovery
        discover_skills[Find Skills]:::action --> check_has_skills
        check_has_skills{skills found?}:::conditional
        check_has_skills -->|true| show_skills_summary
        check_has_skills -->|false| error_no_skills
        show_skills_summary[Show Summary]:::action --> confirm_generation
    end

    confirm_generation([Generate Gateway?]):::userPrompt
    confirm_generation -->|yes| generate_gateway_md
    confirm_generation -->|no| success_cancelled

    subgraph File Generation
        generate_gateway_md[Gen gateway.md]:::action --> generate_workflow_yaml
        generate_workflow_yaml[Gen workflow.yaml]:::action --> generate_intent_mapping
        generate_intent_mapping[Gen intent-mapping]:::action --> write_files
        write_files[Write All Files]:::action --> success_complete
    end

    success_complete((✓ Complete)):::success
    success_cancelled((✓ Cancelled)):::success
    error_missing_jq((✗ Missing jq)):::error
    error_missing_yq((✗ Missing yq)):::error
    error_discovery_failed((✗ Discovery)):::error
    error_no_skills((✗ No Skills)):::error
    error_generation_failed((✗ Gen Failed)):::error
    error_write_failed((✗ Write Failed)):::error

    discover_skills -.->|error| error_discovery_failed
    generate_gateway_md -.->|error| error_generation_failed
    generate_workflow_yaml -.->|error| error_generation_failed
    generate_intent_mapping -.->|error| error_generation_failed
    write_files -.->|error| error_write_failed
```

## Summary

| Metric | Value |
|--------|-------|
| **Nodes** | 15 |
| **Conditionals** | 4 |
| **User Prompts** | 2 |
| **Endings** | 8 |
| **Start Node** | check_prerequisites |
