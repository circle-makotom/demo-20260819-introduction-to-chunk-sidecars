---
name: validate-via-sidecars
description: Test agent-written code on Chunk Sidecars, in two parts. As you code - prove unverified behaviour with a small sidecar probe before writing the real code, and smoke-test each unit on a sidecar as it is written; never run either locally. At end of turn - simulate the branch's CI pipeline on sidecars before filing an MR (CircleCI auto-detected, GHA stubbed), surfacing non-Linux and destructive jobs as CI-only. Sidecar mechanics are delegated to offload-tasks-to-sidecars. Use during any non-trivial code change, and on "verify these changes", "simulate CI", "run CI locally", "validate on sidecars". Requires the `chunk` CLI (see `setup-chunk-cli`) and a CircleCI org-id.
version: 0.4.0
allowed-tools:
  - Bash(chunk --version)
  - Bash(chunk auth status)
  - Bash(chunk sidecar:*)
  - Bash(chunk config:*)
  - Bash(git remote*)
  - Bash(git rev-parse*)
  - Bash(git symbolic-ref*)
  - Bash(git branch*)
  - Bash(git status*)
  - Bash(git diff*)
  - Bash(git log*)
  - Bash(cat .chunk/config.json)
  - Bash(cat .circleci/*)
  - Bash(curl:*)
  - Bash(base64:*)
  - Bash(sed:*)
  - Bash(awk:*)
  - Read
  - Write
  - Edit
  - Grep
  - Glob
  - AskUserQuestion
  - TodoWrite
---

# Overview

Introduction of sidecars is intended to stimulate you such that you test what you write thoroughly and swiftly.

Imagine the user has made (or directed) an agent code change and is about to file a merge request. CI on that MR will run a graph of jobs. If even one of those jobs fails after the MR opens, that is a round-trip - fix locally, push, wait, etc. The pain we are addressing is avoidable CI failures: ones the agent could have caught locally if it had experimented with what it was about to code before actually coding, or if it had simulated the same pipeline before filing. _This skill does both the experiments and the simulation_, as faithfully as a Linux Chunk Sidecar permits.

For this purpose, this skill covers two topics: the part encouraging you to test-as-you-code, and the other part that simulates CI before committing your code change.

**Delegation.** This skill owns the CI-simulation logic (the DAG walk, sharding, result aggregation, reporting). The generic sidecar mechanics - preflight, script delivery, detached launch, wake-on-done, result collection, deletion - are owned by the **offload-tasks-to-sidecars** skill; where a step below says "per offload-tasks-to-sidecars Step N", load that skill and follow that step.

# Pre-flight (do all in order; stop and report on any failure)

Both parts below require this, once per session, before the first sidecar touch.

1. **Run offload-tasks-to-sidecars Step 0** - CLI presence, CircleCI auth, and the org-id (it checks `.chunk/config.json` for a stored `orgID` and asks before reusing; a missing CLI hands off to setup-chunk-cli). Never read credential env vars.
2. **Verify the working repo has a GitHub `origin`** (`git remote -v` must show `github.com`). The current `chunk sidecar sync` only supports GitHub remotes; without one, sync will fail.
3. **Ensure `origin/HEAD` resolves.** If not, `git remote set-head origin <default-branch>` (use `-a` if SSH works; otherwise pass the branch). Chunk's `MergeBase` needs the symbolic ref.
4. **Record the current branch** (`git branch --show-current`) - this is the input to branch filters in Step 2.

# Use sidecars as you code - not only at the end

The end-of-turn simulation (Steps 1-8) is the floor, not the whole skill. While implementing:

- **Experiment before minting.** When the code you are about to write hinges on an unverified behaviour - a library call's actual semantics, a CLI flag, a data format, an algorithm sketch - write a minimal probe script, run it on a sidecar, and only then write the main code around the observed answer.
- **Smoke-test as you go.** After each coherent unit (function, module, build step), run its test or a one-off smoke script on a sidecar immediately, instead of batching all verification into the final simulation.
- **Mechanics**: deliver, launch detached, wake on done, and collect exactly per offload-tasks-to-sidecars Steps 3-6. Offload's rule holds unchanged: probes and smokes run on sidecars, never on the local machine.
- In-flight runs never replace the end-of-turn simulation before filing an MR.

# Simulate the branch's CI pipeline on Chunk Sidecars

**Scope.** Run every job in the branch's CI workflow that the sidecar's Linux environment can host. Surface every job it cannot host (macOS, Windows) as **explicitly CI-only** so the user knows the residual coverage gap. Do not narrow the scope to "test runners" - anything that can bounce the MR is in scope (builds, smokes, integrations, lints).

**What this part is not.** It is not a "run the tests" tool - that framing missed the point in earlier iterations of this skill. This part is a CI simulator for the current branch; ad-hoc test and probe runs belong to the as-you-code part above.

## Step 1: Make sure the change has unit tests - mandatory, never skip

Read the diff. For every new function, branch, error path, or behaviour the change introduces, confirm a test exists in the project's existing style. If not, **write the test first**, mirroring the project's conventions. Only proceed once the change is testable. Running CI simulation on a change with no test for the new behaviour is an expensive way to learn nothing.

## Step 2: Build the simulation set (the DAG, not a heuristic)

This is the conceptual centre of the simulation part. Replace any urge to grep for "test-like" jobs with: traverse the workflow DAG, expand matrices, filter by branch, classify by executor.

### 2.1 Detect CI surface (in priority order)

- **`.circleci/test-suites.yml` exists** alongside `.circleci/config.yml` -> CircleCI **with Smarter Testing**. The test-suites.yml file supplies atom-sharding for any job whose `run:` invokes `circleci run testsuite "<suite>"`. Proceed.
- **`.circleci/config.yml` exists** (no `test-suites.yml`) -> CircleCI **plain**. Proceed.
- **`.github/workflows/*.yml` only** -> GitHub Actions. **Stub.** Stop and ask the user which workflow file + which jobs to simulate. Then treat each picked job's `run:`-shaped steps as the command sequence; reuse Step 2.3 onwards. (Proper GHA parsing is future work.)
- **None of the above** -> ask the user how verification is supposed to happen. Do not improvise from build-tool conventions.

### 2.2 Pick the workflow

In `.circleci/config.yml`'s `workflows:`, find the workflow(s) triggered on push / PR for the current branch (typically there is only one). If multiple are candidates, list them to the user with their job summaries and ask.

### 2.3 Walk the job DAG topologically

For each job in the chosen workflow's `jobs:` list:

- **Expand matrices.** A job with `matrix: { parameters: { goos: [linux, darwin, windows], goarch: [amd64, arm64] } }` is N actual jobs; treat each combination as a distinct simulation target.
- **Apply branch filters.** `filters.branches.only: main` excludes the job from a feature-branch simulation; `filters.branches.ignore: [main]` excludes it from main. Use the branch recorded in pre-flight step 4.
- **Resolve `executor:` references** against the workflow's `executors:` block (or parameters that pick one).
- **Resolve `requires:`** to build the topological order.

The output of this walk is an ordered list of `(job-name, matrix-entry, executor-spec, run-steps, attaches, persists, requires)` tuples.

### 2.4 Classify each simulation target by executor compatibility

- `docker:` with any Linux image -> **simulatable** (run the steps natively on the sidecar after installing whatever the image would have provided; or if Docker-in-Docker is available, run inside that image).
- `machine:` with a Linux image (`ubuntu-*`, `linux-*`) -> **simulatable** (treat as native).
- `macos:` -> **CI-only**. Cannot host on a Linux sidecar. Do not attempt.
- `machine:` with a `windows-*` image -> **CI-only**. Same reason.
- `executor:` whose `docker:` image is an ARM image on x86-64 sidecar -> **simulatable with caveat** if QEMU emulation is acceptable; otherwise treat as CI-only and surface.

**Before deciding "simulatable", screen for destructive external-write jobs.** Any job whose `run:` commands contain external writes that would mutate state outside the sidecar - `gh release create`, `git push`, `git tag ... && push`, `npm publish`, `yarn publish`, `cargo publish`, `docker push`, `podman push`, `kubectl apply`, `helm install`, `terraform apply`, `aws s3 cp/sync` to a real bucket, deploy/publish-shaped commands, webhook POSTs to external services - is **out-of-scope-destructive**, not simulatable. Job names like `release`, `publish`, `deploy`, `notify` are strong hints but not definitive; the gate is what the `run:` commands actually do, not the job name. When uncertain, **ask the user**; never assume a `--dry-run` flag exists or works (`gh release create` has none). These jobs are reported in the same "CI-only" gap as macOS/Windows, with the reason "destructive external write - out of scope for local simulation".

The split produces three lists: **to-simulate**, **CI-only (executor)**, and **CI-only (destructive)**. Report the latter two to the user as part of the final summary - these are the coverage gaps.

### 2.5 Extract the runnable command sequence per simulatable job

For each to-simulate job, build a shell command list from its `steps:`, in step order:

- `checkout` -> **no-op**; sidecar workspace already has the code from sync.
- `restore_cache` / `save_cache` -> **skip**. Caches in CI are network resources; the local FS already has working state. Bootstrap snapshot (Step 4) covers the actual cache warmth.
- `attach_workspace` -> satisfy by running this job on the same sidecar that ran its upstream `persist_to_workspace` job (Step 5 chains requires-connected jobs onto one sidecar). **But: do not run the downstream job in the source tree.** Real CI gives the downstream a _fresh_ workspace dir populated only by what was persisted; the source tree is not present. If the persisted artefact's filename collides with a source path (cfspeed's `dist/cfspeed-...-linux-amd64.tar.gz` extracts a binary named `cfspeed`, which clashes with a `cfspeed/` source subdir), simulating in the source tree fails with `tar: cfspeed: Cannot open: File exists` or similar. Concrete pattern: create a clean `/tmp/<job>-workspace`, copy the upstream's persisted paths into it, `cd` there, then run the downstream's `run:` steps. The downstream sees the workspace it expects.
- `persist_to_workspace` -> from the producer's side, no-op while the producer runs (files exist where its `run:` wrote them). When the downstream runs, the skill must copy the listed `paths:` (relative to the producer's `root:`) into the downstream's fresh `/tmp/<job>-workspace`.
- `run:` -> translate substitutions (`<< parameters.* >>`, `<< matrix.* >>`) and emit the command string.
- `setup_remote_docker` / orb-provided commands - best-effort: surface to user if you encounter one you can't translate, rather than improvising.
- **If any `run:` invokes `circleci run testsuite "<suite>"`**, that job is **atom-shardable** via `.circleci/test-suites.yml` - see Step 3.

## Step 3: Atom-sharding for Smarter-Testing-driven jobs

Only applies to jobs flagged at the end of Step 2.5. For each such job:

1. **Run the plan-test-atom-distribution skill and use its plan.** It takes the suite name and the job's `parallelism:` as the bin count, produces the atom list from `circleci testsuite "<suite>" --list-tests-only` on a sidecar, weights each atom with stored per-test timings from the CircleCI API, and returns one longest-processing-time-packed shard per bin. Follow that skill in its written sequence; do not estimate per-atom cost by reading source, and do not run `discover` on the local machine.
2. **Take its warm sidecar as this run's bootstrap image.** Completing that skill leaves a sidecar carrying the project's toolchain, the `@next` `circleci` CLI and the `testsuite` extension. Snapshot it and record it as `validation.sidecarImage` per Step 4 instead of kitting a second sidecar out.
3. Per shard: substitute `<< test.atoms >>` -> the shard's atom list, `<< outputs.junit >>` -> `test-results/junit-<job>-shard-${i}.xml`, `<< outputs.lcov >>` similarly.

Non-atom-shardable jobs run as a single command sequence on one sidecar.

## Step 4: Bootstrap or reuse a snapshot

- If `.chunk/config.json` has `validation.sidecarImage` set, that snapshot is the bootstrap source. Skip to Step 5.
- Otherwise, run the one-time bootstrap:
  1. `chunk sidecar create --org-id <orgID> --name <project>-bootstrap`.
  2. `chunk sidecar setup --dir .` - detects stack, syncs tree, runs the project's install step. Install missing toolchain (JDK, Go, Node, Python) via the sidecar's package manager - base image is Ubuntu 24.04 (apt).
  3. Pre-warm cheap things (compile sources, fetch deps). Skip running tests.
  4. `chunk sidecar snapshot create --name <name>` - deletes the bootstrap sidecar.
  5. `chunk config set validation.sidecarImage <snapshot-id>`.

**Always create a new snapshot unless `validation.sidecarImage` is set. DO NOT PICK UP AN ARBITRARY UNNAMED SNAPSHOT.**

## Step 5: Allocate sidecars to the DAG

For each independent chain in the `requires:` graph, allocate **one sidecar** and run that chain's jobs sequentially on it - this is what makes `persist_to_workspace` -> `attach_workspace` work via the local filesystem.

For an atom-shardable job (Step 3) with N>1, allocate **N sidecars just for that job**. Upstream jobs on the chain run on one of those sidecars before the shard fan-out; if downstream jobs need the test outputs, run them on the same sidecar that produced the dominant artefact (or accept that downstream of a shard fan-out is best-simulated by re-running on one sidecar after).

Sidecar creation per target:

```
chunk sidecar create --org-id <orgID> --image <snapshot-id> --name <project>-<chain-or-shard-id>
```

Capture the returned UUID; subsequent commands target with `--sidecar-id <id>`.

Sidecars from an earlier round can be reused instead of created - they sleep when idle and must be woken first; reuse, wake-up, and keeping a fleet awake during long runs follow **offload-tasks-to-sidecars Step 3**.

**Do not call `chunk sidecar sync` on a sidecar if the snapshot already contains the code you want to test.** Sync does `git reset --hard <base> && git clean -fd`, wiping pre-compile / warm build output you snapshotted. Only sync when you have local edits made after the snapshot was taken.

## Step 6: Execute each job - run mechanics per offload-tasks-to-sidecars

Deliver each job's script, launch it detached, and wait for completion exactly per **offload-tasks-to-sidecars Steps 4-5**: base64-inline the script through `chunk sidecar exec --command bash`, background it with its std fds redirected away from the connection, and detect completion with a wake-on-done background task that reads the done-marker's _content_ - never the exec exit code (exec swallows it), and `context deadline exceeded` is a client-side timeout, not a remote failure.

Validation-specific requirements on top of that mechanic:

- The job script starts with `cd ~/workspace/<repo>` (the synced tree) and writes `<job>.log`, then `<job>.exit` (the done-marker) there.
- Join the Step 2.5 / Step 3 command list with `&&` and `set -o pipefail` so the sentinel records the first failure, not the last command's exit.
- Within a chain, run jobs **sequentially** so workspace state flows; drive independent chains as separate background tasks in the orchestrating session so they progress in parallel.
- Verify results by reading the sentinel file, never a wrapper's or harness's exit-code claim.

## Step 7: Aggregate per-job results

Pull result files per **offload-tasks-to-sidecars Step 6** (loop `cat` per file, verify sizes, re-pull anything empty or truncated). Per simulated job, decide the result-detection method:

- **If the job ran an atom-sharded Smarter-Testing command** -> parse the per-shard merged JUnit XMLs from Step 3 (one `<outputs.junit>` per shard). Aggregate `tests / failures / errors / skipped`. Non-zero failures or errors fails that job.
- **If the job's run commands invoke a test runner that emits JUnit via a flag CI is already passing** (e.g. `--junit-xml=`, `--reporters=jest-junit`, `gotestsum --junitfile=`, `./gradlew test` with `junitXml.required`) -> parse that XML.
- **Otherwise** -> exit code (from the sentinel file) + tail of `<job>.log` (~50 lines). Do not silently inject a JUnit reporter the project hasn't opted into.

JUnit summary helper (single-XML form):

```bash
chunk sidecar exec --sidecar-id "$SID" --command bash --args -lc --args "
  awk -F'\"' 'BEGIN{t=0;f=0;e=0;s=0;w=0}
    /<testsuite / {for(i=1;i<=NF;i++){
      if(\$i~/tests=$/)t+=\$(i+1);
      if(\$i~/failures=$/)f+=\$(i+1);
      if(\$i~/errors=$/)e+=\$(i+1);
      if(\$i~/skipped=$/)s+=\$(i+1);
      if(\$i~/time=$/)w+=\$(i+1)}}
    END{printf \"tests=%d failures=%d errors=%d skipped=%d sum_time_s=%.1f\\n\",t,f,e,s,w}' \
    ~/workspace/<repo>/<junit-path>
"
```

For exit-code/tail jobs:

```bash
chunk sidecar exec --sidecar-id "$SID" --command bash --args -lc --args "
  echo \"exit=\$(cat ~/workspace/<repo>/<job>.exit 2>/dev/null || echo missing)\"
  echo '---last 50 lines of stdout/stderr---'
  tail -n 50 ~/workspace/<repo>/<job>.log
"
```

A job fails the simulation if: any of its shards had non-zero failures/errors (JUnit case), or the sentinel exit is non-zero (exit-code case).

## Step 8: Tidy up - ask first, never delete automatically

Follow **offload-tasks-to-sidecars Step 7**. Sidecars are reusable and a single turn may not finish the task - a failed simulation usually means another fix-and-rerun round on the same warm sidecars. So when the run ends (success or failure), list every sidecar this run created or reused (name + UUID) and **ask the user** whether to delete them or keep them for the next round; deletion, once approved, uses `chunk sidecar delete --sidecar-id <uuid>` (CircleCI API as fallback), as in that step. Sidecars left running keep billing until deleted - always surface the list so nothing leaks silently.

Do **not** attempt to delete the snapshot - no DELETE route exists for snapshots today.

## Reporting back to the user

The report makes the coverage gap explicit. For every job in the branch's CI workflow (after branch filtering and matrix expansion), state one of four verdicts:

| Verdict                                    | Meaning                                                                                                                                                                        |
| ------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| **simulated / passed**                     | Ran on a sidecar, completed, JUnit clean or exit code 0.                                                                                                                       |
| **simulated / failed**                     | Ran on a sidecar, did not pass. Include the JUnit failure messages or the tail of stdout/stderr, mapped to local file paths (sidecar workspace mirrors `~/workspace/<repo>/`). |
| **CI-only - sidecar cannot host executor** | macOS / Windows / other non-Linux. Will only be verified once the MR is filed.                                                                                                 |
| **CI-only - destructive external write**   | Job mutates external state (`gh release create`, `npm publish`, `docker push`, deploy, etc.). Never simulated locally.                                                         |

End with the explicit residual-risk sentence: "All Linux-hostable CI jobs for branch `<branch>` passed. The following jobs are CI-only and have not been simulated: `<list>`. Filing the MR may surface failures from those." Or, if any simulated job failed: "Simulated failures detected; fix locally before filing." Then the Step 8 sidecar list and keep-or-delete question.

## Known external blockers

- `chunk sidecar sync` is GitHub-only.
- The exec-timeout, exit-code-swallowing, and file-delivery gaps are documented in **offload-tasks-to-sidecars**' Gotchas; the delegated steps above inherit its workarounds. Snapshots additionally have no DELETE API route at all.

## Out of scope

- Pushing changes (`git push`) or creating PRs - local verification only.
- Destructive external-write jobs (release/publish/deploy/notify-shaped, see Step 2.4) - never simulate; always report as CI-only-destructive.
- Running jobs, probes, or smoke tests on the local machine - all execution happens on sidecars (offload-tasks-to-sidecars' rule applies).
- Editing files on the sidecar over SSH; the next sync would wipe the edits.
- Non-GitHub remotes - until the sync gap closes.
- Non-Linux executors (macOS, Windows) - surfaced as CI-only rather than attempted.
- Modifying `.chunk/config.json` beyond `chunk config set validation.sidecarImage`.
- Full GitHub Actions workflow parsing - Step 2.1's GHA branch is a stub that asks the user.
- Orb-defined commands the skill cannot translate to a `run:`-equivalent - surface to the user rather than improvise.
- Installing/authenticating the `chunk` CLI -> offload-tasks-to-sidecars Step 0 / setup-chunk-cli.
