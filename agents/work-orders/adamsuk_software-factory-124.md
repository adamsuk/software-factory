---
repo: adamsuk/software-factory
issue: 124
issue_repo: adamsuk/software-factory
title: "Retrofit: agentic provider abstractions from PR #122"
branch: factory/124-provider-abstractions
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

Retrofit the agentic provider abstraction work from PR #122 into the factory flow properly.

## Acceptance criteria

- [ ] Provider-agnostic station runner in `scripts/station-run.sh`
- [ ] Adapters in `adapters/{opencode,grok,claudecode}/run.sh` and `adapters/README.md`
- [ ] Orchestration in `scripts/foreman-orchestrate.sh`
- [ ] Prompt linting in `scripts/lint-prompts.sh`
- [ ] Documentation in `stations/README.md`
- [ ] All CodeRabbit actionable feedback addressed
- [ ] CI passes
- [ ] Clean merge after review

## Likely files

- scripts/station-run.sh
- scripts/foreman-orchestrate.sh
- scripts/lint-prompts.sh
- adapters/*
- stations/*

## Out of scope

- None

## Issue text (untrusted)

> Retrofit: agentic provider abstractions from PR #122
