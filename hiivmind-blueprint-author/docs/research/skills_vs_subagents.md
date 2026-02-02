# Research: Claude Code Skills with `fork = true` vs Sub-agents

## Summary

Based on research from official Claude Code documentation, community articles, and technical deep-dives, here's what I found about the effectiveness of skills with `context: fork` versus running sub-agents.

---

## Key Concepts

### Three Approaches Compared

| Approach | What It Is | Context | Best For |
|----------|-----------|---------|----------|
| **Skill (default)** | Instructions loaded into main conversation | Shared | Quick knowledge, simple workflows |
| **Skill with `context: fork`** | Skill runs in isolated sub-agent context | Isolated | Complex workflows generating extensive output |
| **Sub-agent (Task tool)** | Independent worker with own context | Isolated | Parallel tasks, specialized workers, research |

---

## Official Documentation Findings

From [code.claude.com/docs](https://code.claude.com/docs/en/features-overview):

> "Skills can run in your current conversation or in an isolated context via subagents."

> "Use a subagent when you need context isolation or when your context window is getting full. The subagent might read dozens of files or run extensive searches, but your main conversation only receives a summary."

> "A skill can run in isolated context using `context: fork`."

### Skills vs Subagents (Official Comparison)

| Aspect | Skill | Subagent |
|--------|-------|----------|
| **What it is** | Reusable instructions, knowledge, or workflows | Isolated worker with its own context |
| **Key benefit** | Share content across contexts | Context isolation - work happens separately, only summary returns |
| **Best for** | Reference material, invocable workflows | Tasks that read many files, parallel work, specialized workers |

---

## Context Fork Details

From [ClaudeLog](https://claudelog.com/faqs/what-is-context-fork-in-claude-code/):

> "Context fork runs skills in an isolated sub-agent context with separate conversation history, preventing skill execution from cluttering your main conversation thread."

### Implementation
```yaml
---
name: deep-analysis
description: Comprehensive codebase analysis
context: fork
agent: Explore  # Optional: specify agent type
---
```

### When Context Fork Helps
- Skills generating extensive output
- Skills requiring multiple processing steps
- Independent execution without polluting main conversation
- When you want isolation but still want skill-style invocation (`/skill-name`)

---

## Effectiveness Comparison

### Speed
- **Skills (default)**: Fastest - Claude just reads instructions, no agent spawn overhead
- **Skills with `context: fork`**: Medium - spawns a sub-agent context
- **Sub-agents**: Medium - similar spawn overhead

### Context Efficiency
- **Skills (default)**: Consumes main context, can clutter conversation
- **Skills with `context: fork`**: Isolated, returns summary only
- **Sub-agents**: Isolated, returns summary only

### Use Case Fit

| Scenario | Best Choice |
|----------|------------|
| Quick reference docs, simple workflows | Skill (default) |
| Complex analysis that generates lots of intermediate output | Skill with `context: fork` |
| Parallel execution of multiple tasks | Sub-agents |
| Specialized worker with custom tools/prompts | Sub-agents |
| Reusable workflow invoked via `/command` | Skill (potentially with fork) |

---

## Key Insight: They Can Combine

From official docs:
> "A subagent can preload specific skills (`skills:` field). A skill can run in isolated context using `context: fork`."

This means:
1. **Skill with `context: fork`** is essentially a skill that spawns as a sub-agent when invoked
2. **Sub-agents** can load skills into their isolated context
3. The choice is about **invocation style** and **configurability**, not fundamentally different mechanisms

---

## Community Observations

From the dev.to article "Skills vs Subagents - When to Use What?":

> "Start with a skill unless you specifically need subagent features. Skills are simpler, faster, and easier to maintain."

From LinkedIn analysis (Christopher Royse, 55+ skills built):
> "After building 55+ specialized Skills for my neuromorphic computing project, I've realized something profound: Claude Skills might fundamentally replace how we use subagents."

---

## Recommendations for Authoring System

### When to use `context: fork` in skills:
1. Skill generates extensive intermediate output
2. Skill performs multi-step analysis
3. User doesn't need to see all the work, just results
4. Conversation context preservation is important

### When to use Sub-agents instead:
1. Need parallel execution (multiple agents simultaneously)
2. Need programmatic control over agent spawning
3. Need custom tool restrictions per agent
4. Need to pass dynamic prompts based on runtime context

### When to use default skills (no fork):
1. Quick reference material
2. Simple knowledge injection
3. Workflows where seeing the process matters
4. When speed is critical (no spawn overhead)

---

## Sources

1. [Claude Code Official Docs - Extend Claude Code](https://code.claude.com/docs/en/features-overview)
2. [ClaudeLog - What is Context Fork](https://claudelog.com/faqs/what-is-context-fork-in-claude-code/)
3. [Claude Agent Skills: A First Principles Deep Dive](https://leehanchung.github.io/blogs/2025/10/26/claude-skills-deep-dive/)
4. [DEV.to - Claude Code Skills vs Subagents](https://dev.to/nunc/claude-code-skills-vs-subagents-when-to-use-what-4d12)
5. [Young Leaders in Tech - Understanding Claude Code](https://www.youngleaders.tech/p/claude-skills-commands-subagents-plugins)
6. GitHub Issue #17283 - Skill tool should honor `context: fork` and `agent:` frontmatter fields
