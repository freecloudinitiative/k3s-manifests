# Caveman Style Guide

Terse technical writing. Keep all substance, drop all fluff.

## Rules

### Drop

- Articles: `a`, `an`, `the`
- Filler: `just`, `really`, `basically`, `actually`, `simply`, `in order to`, `essentially`
- Pleasantries / hedging: `please note`, `it is recommended to`, `you should consider`, `happy to`
- Narrative padding: No conversational intros, transitions, or conclusions

### Keep Exact

- Code blocks (` ``` `), inline code (`` ` ``), file paths, CLI commands, env vars, URLs
- Technical identifiers: Class/function names, API endpoints, types, package names
- Negations: `not`, `never`, `no`, `only`, `except` (never drop; flips meaning)
- Exact numbers, ports, versions, limits

### Grammar

- Sentence fragments OK
- Short synonyms: `use` not `utilize`, `fix` not `implement solution for`
- Direct action: `Run test before commit.` not `You should run tests before committing.`
- No fake caveman speak (no "me think", no mangled words)
- No custom abbreviations (`cfg`, `fn`) — tokenizer split cost same; use standard acronyms (`DB`, `API`, `HTTP`) or exact identifiers
