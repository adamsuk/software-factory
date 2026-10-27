---
repo: adamsuk/software-factory
issue: 124
issue_repo: adamsuk/software-factory
title: "Retrofit: agentic provider abstractions from PR #122"
branch: factory/124-provider-abstractions-fresh
base: main
test_command: "shellcheck scripts/*.sh"
setup_command: ""
changelog: true
merge_allowed: true
review_bot: none
attempt: 1
created: 2026-10-27
---

## Goal

Retrofit agentic provider abstractions properly through the factory flow.

## Acceptance criteria

- [ ] Provider-agnostic station runner (scripts/station-run.sh)
- [ ] Adapters for opencode, grok, claudecode
- [ ] Orchestration script (scripts/foreman-orchestrate.sh)
- [ ] Prompt lint (scripts/lint-prompts.sh)
- [ ] Documentation (adapters/README.md, stations/README.md)
- [ ] All CodeRabbit feedback addressed
- [ ] CI passes
- [ ] Clean merge

## Likely files

- scripts/station-run.sh
- scripts/foreman-orchestrate.sh
- scripts/lint-prompts.sh
- adapters/*
- stations/*

## Out of scope

- None

## Issue text (untrusted)

> Fresh start for issue 124
