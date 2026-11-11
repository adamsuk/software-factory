# Station 01 backlog metrics

Station 01 (Backlog) asks for one hand check of three metrics that can be read
from issue label events. This note names those metrics and gives one read-only
command for each. Each command is a GitHub API `GET` through `gh api --method GET`.
The backlog for this check is this repo (upstream:
[adamsuk/software-factory](https://github.com/adamsuk/software-factory)). In the
commands, `<owner>/<repo>` is the repo whose backlog you are measuring.

The three metrics are:

1. **Triage lead time:** issue opened until it is labelled `factory:ready` or `factory:blocked`.
2. **The share of `factory:ready` issues** whose body has one target-repo line and checkable acceptance criteria.
3. **Bounce-backs:** an issue moved from `factory:building` back to `factory:triage`.

Label events are `labeled` entries. On an event, `label.name` is the label and
`created_at` is the timestamp. One issue's events are
`GET /repos/<owner>/<repo>/issues/<number>/timeline`. Every issue in
the repo is `GET /repos/<owner>/<repo>/issues/events`, and each event
there includes `issue.number` and `issue.body`.

`--paginate --slurp` fetches every page and prints one JSON array of those pages.
Pipe that into `jq`. `add` joins the pages into one list of events, and
`.[] | .[]` walks pages, then events. `gh` rejects `--slurp` together with its
own `--jq` flag, so the filter always runs in `jq`.

Who sets each `factory:*` label is in [AGENTS.md section 9](../../AGENTS.md#9-status-labels-43).
What a triaged issue contains is in the [intake brief](../../agents/roles/intake.md).
Weekly measurement stays on #14.
Station 08 stays on #50.

## Worked example: #52

Issue #52
has a `labeled` event on its timeline for label `factory:done` at timestamp
`2026-10-26T11:32:05Z`. That label and timestamp were read from the timeline on
2026-10-26.

```sh
gh api --method GET --paginate --slurp \
  "/repos/<owner>/<repo>/issues/52/timeline?per_page=100" \
  | jq '.[] | .[] | select(.event == "labeled" and .label.name == "factory:done") | {event, label: .label.name, at: .created_at}'
```

The hand check recorded:

```json
{"event":"labeled","label":"factory:done","at":"2026-10-26T11:32:05Z"}
```

The command prints one object per `factory:done` event. The object above is the
one recorded on 2026-10-26. Triage lead time ends at `factory:ready` or
`factory:blocked`. This `factory:done` event is the worked example of reading a
label event.

## Triage lead time

Triage lead time is the time from the issue being opened until it is labelled
`factory:ready` or `factory:blocked`. Opened is the issue's `created_at`. The
end is the earliest `labeled` event on its timeline whose label is
`factory:ready` or `factory:blocked`.

Set `n` to the issue number. The command GETs the issue and its timeline, writes
the responses under `/tmp`, and prints `opened`, `label`, `at`, and
`lead_time_seconds`. A null `label` means neither label is on the timeline yet.

```sh
n=52 &&
gh api --method GET "/repos/<owner>/<repo>/issues/${n}" > "/tmp/sf-issue-${n}.json" &&
gh api --method GET --paginate --slurp "/repos/<owner>/<repo>/issues/${n}/timeline?per_page=100" > "/tmp/sf-timeline-${n}.json" &&
jq -n --slurpfile issue "/tmp/sf-issue-${n}.json" --slurpfile pages "/tmp/sf-timeline-${n}.json" '
  $issue[0].created_at as $opened
  | [ $pages[0] | add | .[]
      | select(.event == "labeled" and (.label.name == "factory:ready" or .label.name == "factory:blocked"))
    ]
  | sort_by(.created_at)
  | (first // null) as $hit
  | if $hit == null then
      {opened: $opened, label: null, at: null, lead_time_seconds: null}
    else
      {
        opened: $opened,
        label: $hit.label.name,
        at: $hit.created_at,
        lead_time_seconds: (($hit.created_at | fromdateiso8601) - ($opened | fromdateiso8601))
      }
    end
'
```

## Share of factory:ready issues

The share of `factory:ready` issues whose body has one target-repo line and
checkable acceptance criteria.

The population is every issue with at least one `labeled` event for
`factory:ready`. For each issue the command keeps the earliest of those events
and reads that event's `issue.body`.

A target-repo line is a line whose first non-space text is `Target repo:`.
One target-repo line means `target_line_count` is 1. A checklist item is a
markdown task line: optional indent, then `-`, `*`, or a number plus `.`, then
`[ ]`, `[x]`, or `[X]`. Checkable means each of those items can be verified by
a test, a command, or a look at the diff, which is the checklist the intake
brief asks for.

`ready` is the denominator. `structural_passes` counts issues that already have
one target-repo line and at least one checklist item. Read each `checklist`,
and keep an issue only when every item is checkable. The share is that kept
count divided by `ready`. When `ready` is 0, there is no share to take.

```sh
gh api --method GET --paginate --slurp \
  "/repos/<owner>/<repo>/issues/events?per_page=100" \
  | jq '
    add
    | [ .[]
        | select(.event == "labeled" and .label.name == "factory:ready" and .issue.number != null)
        | {number: .issue.number, at: .created_at, body: (.issue.body // "")}
      ]
    | group_by(.number)
    | map(sort_by(.at) | first)
    | map(
        .body |= gsub("\r"; "")
        | . as $row
        | ($row.body | split("\n")) as $lines
        | ($lines | map(select(test("^[[:space:]]*Target repo:")))) as $targets
        | ($lines | map(select(test("^[[:space:]]*([-*]|[0-9]+\\.)[[:space:]]+\\[[ xX]\\]")))) as $checks
        | {
            number: $row.number,
            at: $row.at,
            target_lines: $targets,
            target_line_count: ($targets | length),
            checklist: $checks,
            checklist_count: ($checks | length)
          }
      )
    | {
        ready: length,
        structural_passes: (map(select(.target_line_count == 1 and .checklist_count > 0)) | length),
        issues: .
      }
  '
```

## Bounce-backs

A bounce-back is an issue moved from `factory:building` back to `factory:triage`.

The command reads every `labeled` event whose label starts with `factory:`,
orders each issue's events by `created_at`, and keeps a pair when the event is
`factory:triage` and the previous `factory:*` event on that issue is
`factory:building`. `bounce_backs` is how many such pairs there are. `events`
lists each one with `building_at` and `triage_at`.

```sh
gh api --method GET --paginate --slurp \
  "/repos/<owner>/<repo>/issues/events?per_page=100" \
  | jq '
    add
    | [ .[]
        | select(.event == "labeled" and ((.label.name // "") | startswith("factory:")) and .issue.number != null)
        | {number: .issue.number, label: .label.name, at: .created_at}
      ]
    | group_by(.number)
    | map(
        (sort_by(.at)) as $ev
        | [ range(1; $ev | length)
            | . as $i
            | select($ev[$i].label == "factory:triage" and $ev[$i - 1].label == "factory:building")
            | {issue: $ev[0].number, building_at: $ev[$i - 1].at, triage_at: $ev[$i].at}
          ]
      )
    | (add // [])
    | {bounce_backs: length, events: .}
  '
```
