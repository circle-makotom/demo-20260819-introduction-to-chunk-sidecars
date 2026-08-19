---
name: plan-test-atom-distribution
description: Use when the user wants to see how a CircleCI smarter-testing suite's test atoms would spread across parallel nodes, or to judge whether that split can be balanced at all. Takes the atom list from `circleci testsuite <suite> --list-tests-only` run on a Chunk Sidecar via offload-tasks-to-sidecars, so the local machine needs no project toolchain; the bin count from `parallelism` in `.circleci/config.yml`; and stored per-test timings from the CircleCI API, then computes a greedy longest-processing-time split with a small Python 3 script. Read-only: it never triggers a run and never edits the repo.
version: 0.1.0
---

# Plan the distribution of test atoms across parallel nodes

Produces, for one suite, the per-bin atom lists and per-bin predicted seconds - one plan per job whose stored timings can serve as input - plus how far each result sits from a perfectly even split.

This is a planning aid computed from public CLI and API surfaces. It does not claim to reproduce how CircleCI assigns atoms to nodes at run time; a real run may differ.

**_WARNING: FOLLOW THE INSTRUCTIONS IN THE WRITTEN SEQUENCE._**

## Prerequisites

**Resolve these prerequisites before moving forward.**

- A **fresh temporary CircleCI token, solicited from the user** for the sidecar's CLI. Never send the local machine's credential to a sidecar. **Ask for this as early as possible.**
- Python 3 here, standard library only - no third-party packages.
- A Chunk Sidecar, driven through the **offload-tasks-to-sidecars** skill, which owns the `chunk` CLI's install and auth, which credential a sidecar may hold, waking a reused VM, and teardown. **Prerequisites and dependencies of the external skill should be addressed before moving forward with this skill; follow the instructions in the external skill precisely.**
- The project checkout here, including `.circleci/config.yml` and the suite definition (`.circleci/test-suites.yml`): Steps 1 and 3 read them, and Step 2 syncs the checkout to the sidecar. For `chunk sidecar sync`, `origin` must be a GitHub URL and `~/.ssh/chunk_ai` must exist.

## Step 1: suite name and bin count

The suite name is the `name:` field of the suite definition - read it rather than guessing, and note a project may define several suites.

The bin count is the `parallelism` of the job that runs the suite. A matrix over that job multiplies jobs, not bins: each matrix instance uses the same `parallelism`.

## Step 2: the atom list - the CLI's own selection, produced on a sidecar

Two constraints at once. The list comes from `--list-tests-only`, not a filesystem glob; and that command runs on a Chunk Sidecar, never here.

`--list-tests-only` is documented as "List selected test atoms on stdout", so it yields the atoms the suite would run for the tree it sees. A `find`-style discovery list is a different, larger set whenever selection narrows anything, and distributing that answers a question nobody asked.

**Sidecar mechanics belong to offload-tasks-to-sidecars.** Creating the sidecar, the `chunk` CLI's own install and auth, which credential a sidecar may hold, waking a reused VM, and tearing it down are defined there and are not restated here.

**Image, and the tooling that lands on it here.** Launch from a warmed snapshot when one has been created _within this session_ already (`chunk sidecar create --image <snapshot-id>`); otherwise kit a fresh sidecar out from the beginning, and on finishing snapshot the warm state and record it with `chunk config set validation.sidecarImage <snapshot-id>` - validate-via-sidecars Step 4 takes that image as its bootstrap source, so leaving one behind is part of completing this skill. **Never attempt to reuse snapshots coming from another session.** Either way, confirm all of this is on the sidecar before running anything below - Step 4 uses the same CLI and the same auth:

- the project's own test toolchain, since `--list-tests-only` runs the suite's `discover` as a subprocess;
- the `@next` `circleci` CLI, installed from scratch - ignore whatever `circleci` the image already ships;
- the `testsuite` extension: `circleci extension install testsuite`;
- that CLI's auth, as the next paragraph requires.

**Auth on the sidecar: ask the user for a fresh temporary token for each session.** Stop and solicit one - `AskUserQuestion`, a token minted for this run alone - before authenticating the CLI there. Never forward the credential this machine holds. Store it on stdin, never with `circleci auth login` (a browser OAuth flow that mints its own token):

```
chunk sidecar exec --sidecar-id <uuid> --command bash --args -lc --args 'circleci setting set token - <<"TOKEN"
<the temporary token>
TOKEN'
```

`setting set` accepts an invalid token silently, so confirm with `circleci auth me`.

**Deliver the tree with `chunk sidecar sync` alone.** Run it from the checkout; it sends the committed history and then applies the working-tree changes on top, untracked files included, so the sidecar ends up on the same HEAD with the same `git status --porcelain` and byte-identical content for both modified files and an untracked `.circleci/state-main.json`. Nothing further has to be shipped by hand:

```
chunk sidecar sync --sidecar-id <uuid>
```

**Name the project explicitly: the sidecar cannot autodetect it.** `chunk sidecar sync` leaves the checkout with no git remotes, so the plugin's project autodetection fails there. Pass the project id on the command line, `--project-id <project-uuid>`, or put it in the environment as `CIRCLE_PROJECT_ID`; the sidecar's own `circleci testsuite --help` lists which of the two that build accepts. Derive the project ID from the project slug, which Step 1 already has, with one API call on the sidecar:

```
chunk sidecar exec --sidecar-id <uuid> --command bash --args -lc --args 'circleci api api/v2/project/<vcs>/<org>/<repo> --jq ".id"'
```

That response also carries `organization_id`, `name`, and `vcs_info.default_branch`, so it doubles as a check that the slug is the project you meant.

**Run it detached, with a done-marker.** Discovery can outlast the ~30 s exec window, and `chunk sidecar exec` does not propagate the remote exit code, so write the list, then the marker last, in one exec whose file descriptors are redirected away from the connection. Single-quote the payload so `$?` reaches the sidecar unexpanded:

```
chunk sidecar exec --sidecar-id <uuid> --command bash --args -lc --args '
  mkdir -p /tmp/cout
  cd /home/user/<repo>
  { circleci testsuite "<suite name>" --list-tests-only --project-id <project-uuid> > /tmp/cout/selected.txt 2> /tmp/cout/selected.err; echo $? > /tmp/cout/selected.exit; } </dev/null >/dev/null 2>&1 &
'
```

Wait with that skill's background wake-on-done task, then pull the marker and the list:

```
chunk sidecar exec --sidecar-id <uuid> --command bash --args -lc --args "cat /tmp/cout/selected.exit"
chunk sidecar exec --sidecar-id <uuid> --command bash --args -lc --args "cat /tmp/cout/selected.txt" > selected.txt
```

A non-zero marker means discovery failed: read `selected.err` and stop, because a truncated list would be planned as though it were complete.

An empty `selected.txt` with marker `0` is a legitimate answer: nothing was selected, so there is nothing to distribute. Do not treat it as a failure and do not go hunting for a bigger list. Two things govern how much gets selected:

- A change touching a path in the suite's `full-test-run-paths` forces a full run.
- The untracked `.circleci/state-main.json` records a hash per `full-test-run-paths` entry and affects what counts as changed. Never delete or edit it, here or on the sidecar, without asking the user.

## Step 3: read the suite's `discover` command to learn what the atoms are

**_WARNING: NEVER RUN THIS BEFORE COMPLETING PREVIOUS STEPS._ IT DEPENDS ON THE DELIVERABLE FROM STEP 2.**

Atoms are named by whatever `discover` enumerates, and that determines which field of the timing payload they must be looked up in:

| `discover` enumerates | Atoms look like                | `--match-key` |
| --------------------- | ------------------------------ | ------------- |
| file paths            | `spec/models/author_spec.rb`   | `file`        |
| class names           | `com.example.demo.Fast001Test` | `classname`   |
| individual test names | a single test's own name       | `name`        |

A `find`-based discovery command enumerates paths; a build-tool task that lists test classes enumerates class names. Decide once, here, from the command as written in the suite definition _and the atoms in `selected.txt`_. Do not compute a plan per candidate key to see which looks right.

## Step 4: find timings on the sidecar, headless

The walk runs on the sidecar Step 2 used, through the CLI authenticated there; only the payloads and a manifest come back here.

Jobs that store no test results return `items: []` with exit 0, so an empty payload is not an error and will not announce itself. The script below therefore walks runs newest first, probes every job for records keyed by the Step 3 field, keeps **every** qualifying job of the first run that has one - a `resource_class` matrix yields one timing set per resource class, and each kept job gets its own plan - and exits 3 when the window holds nothing usable. It reads the API rather than `circleci testresult list`, whose JSON exposes `classname, name, result, run_time, message` but omits `file`. Set `limit` well above the number of runs you expect to need; it is the third argument.

```bash
#!/bin/bash
# timings.sh <project-slug> <match-key> [limit] [outdir]
# Walks runs newest first. For the newest run holding usable test records, writes
# one payload per job plus a manifest and exits 0; exits 3 if no run qualifies.
set -u
SLUG="$1"; KEY="$2"; LIMIT="${3:-50}"; OUT="${4:-/tmp/cout}"
mkdir -p "$OUT"
: > "$OUT/manifest.tsv"

for run in $(circleci run list --limit "$LIMIT" --project "$SLUG" --json --jq ".[] | .id"); do
  hit=0
  for wf in $(circleci api "api/v2/pipeline/$run/workflow" --jq ".items[].id"); do
    while read -r num name; do
      [ -z "${num:-}" ] && continue
      read -r records keyed <<< "$(circleci api "api/v2/project/$SLUG/$num/tests" --jq "\"\(.items|length) \([.items[] | .$KEY] | map(select(. != null)) | length)\"")"
      [ "${records:-0}" -gt 0 ] || continue
      [ "${keyed:-0}" -gt 0 ] || continue
      safe="${name//[^A-Za-z0-9._-]/-}"
      circleci api "api/v2/project/$SLUG/$num/tests" --jq ".items" > "$OUT/tests-$safe.json"
      printf "%s\t%s\t%s\t%s\n" "$run" "$num" "$name" "tests-$safe.json" >> "$OUT/manifest.tsv"
      hit=1
    done <<< "$(circleci api "api/v2/workflow/$wf/job" --jq ".items[] | select(.job_number != null) | \"\(.job_number) \(.name)\"")"
  done
  [ "$hit" -eq 1 ] && { echo "$run" > "$OUT/run.id"; exit 0; }
done
echo "no run in the last $LIMIT has a job whose records are keyed by $KEY" >&2
exit 3
```

Write it on the sidecar with a quoted heredoc, then launch it detached with the marker written last:

```
chunk sidecar exec --sidecar-id <uuid> --command bash --args -lc --args '
  mkdir -p /tmp/cout
  cat > /tmp/cout/timings.sh <<"SH"
<the script above, verbatim>
SH
  { bash /tmp/cout/timings.sh <vcs>/<org>/<repo> <match-key> 50; echo $? > /tmp/cout/timings.exit; } </dev/null >/dev/null 2>/tmp/cout/timings.err &
'
```

Wait with the wake-on-done task, then read the marker: `0` means the payloads and the manifest are on the sidecar; `3` means the walk found nothing usable, so read `timings.err`, say so and stop rather than planning from an empty payload; any other value is a failure, also reported in `timings.err`.

Pull the manifest, then one payload per manifest row:

```
chunk sidecar exec --sidecar-id <uuid> --command bash --args -lc --args "cat /tmp/cout/timings.exit"
chunk sidecar exec --sidecar-id <uuid> --command bash --args -lc --args "cat /tmp/cout/manifest.tsv" > manifest.tsv
chunk sidecar exec --sidecar-id <uuid> --command bash --args -lc --args "cat /tmp/cout/tests-<job-name>.json" > tests-<job-name>.json
```

Each manifest row is `run-id`, `job-number`, `job-name`, `payload-file`, tab separated. Check every pulled file is non-empty before planning from it: a truncated pull reads like a payload with no records.

Records are per test case, so several rows can share one `file` or `classname`; an atom's time is their sum.

Two payload traps worth checking before trusting the numbers: a field can be absent from every record, `file` being absent wherever the runner reports only class names; and records can carry `run_time` while being `result: skipped`, in which case the times are not measurements of work done in that job.

## Step 5: the weight for atoms with no timing data

An atom present in `selected.txt` but absent from a payload - new spec, renamed file, or a job that never ran it - has no measured weight.

Default: the mean of the timed atoms' times, as the expected cost of an unmeasured atom.

Override it with `--default-seconds <seconds>` when the user names a different weight. The script reports `timed`, `untimed` and `default_seconds`, so the report can state how many atoms leaned on the fallback and at what weight.

If _no_ atom matches, the script fails rather than planning: it prints the key it used and how many atoms it tried, and exits 2.

## Step 6: compute the split

Method: sum each atom's `run_time`, sort descending, and place each atom into the currently lightest bin - the standard greedy longest-processing-time heuristic. Ties go to the lowest-numbered bin.

Save as `plan_atoms.py`:

```python
#!/usr/bin/env python3
"""Split selected test atoms across parallel bins, longest processing time first.

Reads a CircleCI test-results payload (the `items` array) and a newline-separated
list of selected test atoms, then reports the per-bin assignment and predicted
seconds.

Atoms are looked up in the payload field that speaks the same vocabulary as the
suite's `discover` command: `file` for paths, `classname` for class names,
`name` for individual test names. Pass that field as --match-key.
"""

import argparse
import json
import math
import statistics
import sys

MATCH_KEYS = ("file", "classname", "name")


def sum_run_time_by_key(records, match_key):
    """Total run_time per distinct value of match_key across the payload."""
    totals = {}
    for record in records:
        key = record.get(match_key)
        if not key:
            continue
        totals[key] = totals.get(key, 0.0) + record["run_time"]
    return totals


def distribute(weights, bins):
    """Longest processing time: heaviest atom first, into the lightest bin.

    Ties go to the lowest-numbered bin. Returns a list of (atoms, seconds) pairs,
    or an empty list when there is nothing to distribute.
    """
    if not weights or bins < 1:
        return []
    ordered = sorted(weights, key=lambda pair: -pair[1])
    packed = [([], 0.0) for _ in range(bins)]
    for atom, seconds in ordered:
        lightest = min(range(bins), key=lambda i: packed[i][1])
        atoms, total = packed[lightest]
        packed[lightest] = (atoms + [atom], total + seconds)
    return packed


def to_millis(seconds):
    """Round to milliseconds, halves away from zero."""
    return math.floor(seconds * 1000 + 0.5) / 1000


def build_plan(records, selected, bins, match_key, default_seconds=None):
    timed = sum_run_time_by_key(records, match_key)
    fallback = default_seconds
    if fallback is None:
        measured = [timed[atom] for atom in selected if atom in timed]
        fallback = statistics.fmean(measured) if measured else 0.0

    weights = [(atom, timed.get(atom, fallback)) for atom in selected]
    total = sum(seconds for _, seconds in weights)

    return {
        "match_key": match_key,
        "selected": len(selected),
        "timed": sum(1 for atom in selected if atom in timed),
        "untimed": sum(1 for atom in selected if atom not in timed),
        "default_seconds": fallback,
        "total_seconds": to_millis(total),
        "ideal_seconds": to_millis(total / bins) if bins > 0 else None,
        "bins": [
            {
                "bin": index + 1,
                "atoms": len(atoms),
                "seconds": to_millis(seconds),
                "items": atoms,
            }
            for index, (atoms, seconds) in enumerate(distribute(weights, bins))
        ],
    }


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--tests", required=True, help="JSON file holding the API `items` array")
    parser.add_argument("--selected", required=True, help="File of selected atoms, one per line")
    parser.add_argument("--bins", required=True, type=int, help="Number of bins (job parallelism)")
    parser.add_argument(
        "--match-key",
        required=True,
        choices=MATCH_KEYS,
        help="Payload field the atoms are named after, per the suite's discover command",
    )
    parser.add_argument(
        "--default-seconds",
        type=float,
        default=None,
        help="Weight for atoms with no timing data (default: mean of the timed atoms)",
    )
    args = parser.parse_args(argv)

    with open(args.tests, encoding="utf-8") as handle:
        records = json.load(handle)
    with open(args.selected, encoding="utf-8") as handle:
        selected = [line.strip() for line in handle if line.strip()]

    plan = build_plan(records, selected, args.bins, args.match_key, args.default_seconds)

    if plan["selected"] and not plan["timed"]:
        print(
            f"error: none of the {plan['selected']} selected atoms were found in the "
            f"'{args.match_key}' field of {args.tests}. The atoms and that field speak "
            f"different vocabularies - check the suite's discover command and pass the "
            f"matching --match-key.",
            file=sys.stderr,
        )
        return 2

    json.dump(plan, sys.stdout, indent=2)
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
```

Run it once per kept job, with the key decided in Step 3:

```
python3 plan_atoms.py --tests tests-<job-name>.json --selected selected.txt --bins <parallelism> --match-key <field> > plan-<job-name>.json
```

Add `--default-seconds <seconds>` only when overriding the fallback of Step 5.

## Step 7: report

For each job's plan, give per bin: atom count, predicted seconds, and the atoms. Then compare the heaviest bin - the makespan - with `ideal_seconds`, and name any atom whose own time exceeds that ideal share, because no split can finish faster than its slowest single atom. Where several jobs were planned, put their makespans side by side; the same suite on different hardware can differ by a factor of two.

Always report `match_key`, and which run, revision and job each payload came from. Report `untimed` when non-zero, naming the fallback weight used.

## Known limitations

- The plan is static. Anything the platform does at run time - queueing, rebalancing, reruns - is outside what this computes.
- Timings are historical: they come from a past job, so an atom whose cost has since changed is mispredicted.
- Matching is exact string equality within the chosen field; no normalisation is applied, so a differently spelled prefix on otherwise identical atoms takes the fallback weight.
- Repeated lines in `selected.txt` are counted twice; the script does not deduplicate.
- If every weight ends up zero - for instance `--default-seconds 0` with no timed atoms - the whole suite lands in bin 1.
