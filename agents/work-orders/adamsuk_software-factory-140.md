---
repo: adamsuk/software-factory
issue: 140
issue_repo: adamsuk/software-factory
title: "fix: make the provider choice real"
branch: factory/140-provider-adapters
base: main
test_command: "shellcheck scripts/*.sh adapters/*/run.sh"
setup_command: ""
changelog: true
merge_allowed: false
review_bot: coderabbit
attempt: 1
created: 2026-10-28
---

## Goal

Make `FACTORY_PROVIDER` mean something. Today one provider works, one adapter
passes a flag its CLI rejects, and one is a stub, so a 402 on grok stops the
whole line. Fix the adapters, and fix the two gate failures that hid station 04
from ever running on this machine.

## Acceptance criteria

- [ ] `adapters/opencode/run.sh` runs on opencode v2.2.0 with no unsupported flags
- [ ] `adapters/claudecode/run.sh` implements the adapter interface for
      non-builder roles and reports a missing CLI distinctly
- [ ] `adapters/grok/run.sh` separates a missing CLI from a failed capability probe
- [ ] `scripts/gate-issue.sh` names a missing PyYAML instead of blaming factory.yml
- [ ] The `gh` minimum version is documented with the other prerequisites
- [ ] `scripts/test-adapters.sh` covers the contract for all three providers
- [ ] CI lints `adapters/*/run.sh`, which it never did
- [ ] `adapters/README.md` no longer calls claudecode a placeholder
- [ ] An independent review runs on a provider other than grok

## Likely files

- adapters/opencode/run.sh
- adapters/claudecode/run.sh
- adapters/grok/run.sh
- adapters/README.md
- scripts/gate-issue.sh
- scripts/test-adapters.sh
- .github/workflows/lint.yml
- .github/factory.yml
- README.md

## Out of scope

- Restoring the Grok Build balance
- A cross-provider fallback chain
- Making `scripts/run-work-order.sh` provider-agnostic so `builder` runs
  anywhere. Recorded in `adapters/README.md` under "Role coverage".
- The audit findings themselves (#134 and children)

## Issue text (untrusted)

> Make the provider choice real: fix the opencode and claudecode adapters, and
> the two gate failures
