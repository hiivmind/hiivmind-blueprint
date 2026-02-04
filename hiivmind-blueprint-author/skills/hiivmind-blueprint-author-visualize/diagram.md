# Workflow Diagram: hiivmind-blueprint-author-visualize

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

    parse_args[Parse Args]:::action --> check_workflow_path

    subgraph Load Workflow
        check_workflow_path{path provided?}:::conditional
        check_workflow_path -->|true| validate_workflow_path
        check_workflow_path -->|false| search_for_workflow
        validate_workflow_path{exists?}:::conditional
        validate_workflow_path -->|true| set_workflow_path
        validate_workflow_path -->|false| error_file_not_found
        set_workflow_path[Set Path]:::action --> read_workflow
        search_for_workflow[Search]:::action --> check_search_results
        check_search_results{found?}:::conditional
        check_search_results -->|true| prompt_workflow_selection
        check_search_results -->|false| prompt_for_path
        prompt_workflow_selection([Select Workflow]):::userPrompt
        prompt_workflow_selection -->|selected| read_workflow
        prompt_workflow_selection -->|other| prompt_for_path
        prompt_for_path([Enter Path]):::userPrompt --> validate_workflow_path
    end

    read_workflow[Read workflow.yaml]:::action --> generate_mermaid

    subgraph Output
        generate_mermaid[Generate Mermaid]:::action --> check_output_mode
        check_output_mode{output to file?}:::conditional
        check_output_mode -->|true| write_to_file
        check_output_mode -->|false| display_diagram
        write_to_file[Write File]:::action --> success_complete
        display_diagram[Display]:::action --> success_complete
    end

    success_complete((✓ Complete)):::success
    error_missing_jq((✗ Missing jq)):::error
    error_missing_yq((✗ Missing yq)):::error
    error_file_not_found((✗ Not Found)):::error
    error_invalid_yaml((✗ Invalid YAML)):::error
    error_generation_failed((✗ Gen Failed)):::error
    error_write_failed((✗ Write Failed)):::error

    read_workflow -.->|error| error_invalid_yaml
    generate_mermaid -.->|error| error_generation_failed
    write_to_file -.->|error| error_write_failed
```

## Summary

| Metric | Value |
|--------|-------|
| **Nodes** | 17 |
| **Conditionals** | 5 |
| **User Prompts** | 2 |
| **Endings** | 7 |
| **Start Node** | check_prerequisites |
