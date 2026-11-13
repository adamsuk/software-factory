# Adversarial issue-text fixtures (#380)

Recorded hostile issue text, replayed by `scripts/test-untrusted-issue.sh` and
`scripts/test-watcher-fence.sh`. Plain data: nothing here is ever executed. Each
file ends with a `HOSTILE_PAYLOAD_*` line that must stay inside the fence.

- `fence-closers.md`: fixed and random-looking fence closers and openers.
- `instruction-lines.md`: lines that read as instructions to an agent.
- `zero-width.md`: zero-width, word-joiner, bidi, BOM and soft-hyphen characters.
