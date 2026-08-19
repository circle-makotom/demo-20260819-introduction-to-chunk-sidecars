---
name: offload-tasks-to-sidecars
description: 'Offload and distribute work to Chunk Sidecars (ephemeral CircleCI Linux workers), run it detached in the background, and pull the results back - so the orchestrating agent spends near-zero tokens while the work runs. Use this whenever offloading is requested, at any size: "offload this", "run this on sidecars", "distribute across sidecars", "fan this out", "run it in the background on a fleet", "scrape/validate across an org", batch or parallel jobs. If a request seems pointless to offload, flag the concern and let the user decide - do not decline on your own. Delegates `chunk` CLI install/auth to setup-chunk-cli. Requires the `chunk` CLI and a CircleCI org-id.'
version: 0.1.0
allowed-tools:
  - Bash(chunk --version)
  - Bash(chunk auth status)
  - Bash(chunk sidecar:*)
  - Bash(chunk config:*)
  - Bash(curl:*)
  - Bash(base64:*)
  - Bash(cat .chunk/config.json)
  - Bash(sed:*)
  - Read
  - Write
  - Edit
  - Grep
  - Glob
  - AskUserQuestion
  - TodoWrite
---

# Offload and distribute tasks to a Chunk Sidecar fleet

A Chunk Sidecar is an ephemeral Linux worker provisioned through CircleCI. The `chunk` CLI creates them, runs work on them, and lets you pull results back. Treat sidecars as a fleet of background workers: the agent orchestrates (launch -> leave -> collect), the sidecars do the compute.

**Why this saves tokens.** Tokens are spent only while the agent is active. So the rule is: never make the agent sit and watch. Launch the work _detached_ on the sidecars, end the turn, get woken once when it finishes, then pull the results back - which may be a set of files, not a one-line summary. The agent pays for the launch and the collect; the long wait and all the verbose output stay off its context. This is near-zero cost _per unit of remote work_, not literally zero.

**Wake-on-done is the required mechanism** (Step 5). Polling is fine as a complement - e.g. when you want mid-run progress - as long as it runs in a background shell (off the agent's context), not the foreground.

**Scope.** Use this whenever offloading is asked for, regardless of how big or small the task looks - judging that is not the agent's call. The only hard exclusions are in Step 1 (destructive external writes; non-Linux work). If a request looks pointless to offload, raise it and let the user decide; do not unilaterally decline.

**Everything runs on sidecars - never locally.** The offloaded work, and every trial of it, executes on sidecars only. Do not run the payload, a reduced version, a single-item smoke test, or a "just to check it works" trial on the local machine - not even once. The local machine only orchestrates: `chunk` calls, base64 encoding, and reading pulled results. Running the work locally defeats the purpose and puts the user's machine at risk (IP address bans from hitting external services, resource exhaustion, unintended side effects). When fan-out is needed, the small test that validates one chunk is itself run on a sidecar - that is what the user expects.

## Step 0: Preflight

1. `chunk --version` and `chunk auth status`. If `chunk` is missing or CircleCI is "Not set", hand off to the **setup-chunk-cli** skill; if that skill is not available here, ask the human how to install/authenticate. Never read credential environment variables (`echo $CIRCLE_TOKEN`, `env`, `printenv`).
2. **Org-id.** Every `chunk sidecar` command needs one. **Before asking, check whether one is already persisted** in either config file, in this order: the project's `.chunk/config.json` (`cat .chunk/config.json`), then the user-level `~/.chunk/config.json` (`cat ~/.chunk/config.json`). Either may carry the `orgID` field, and the home file often holds it when the project one is absent or has no `orgID`.
   - **If an `orgID` is already stored, ask the user (via AskUserQuestion) whether to reuse it** - show the stored id (and which file it came from) in the prompt - or supply a different one. Never silently reuse it and never silently overwrite it. (AskUserQuestion needs >=2 options, e.g. "Reuse `<id>`" and "Use a different org-id".)
   - **Otherwise** (none stored, or the user wants a different one) obtain it by **asking the user, ideally via an AskUserQuestion dialogue** - never by listing or enumerating their orgs - and persist it with `chunk config set orgID <id>`.

   Sidecars run in _your own_ org even when the work targets another org's resources.

## Step 1: Shape the work into units

1. **Exclude destructive external writes.** Anything that mutates state outside the sidecar - `git push`, `gh release create`, `npm/cargo/yarn publish`, `docker push`, `kubectl apply`, `terraform apply`, deploy/notify webhooks - is out of scope. The gate is what the commands do, not the unit's name; when unsure, ask.
2. **Exclude non-Linux work** (macOS/Windows) - sidecars are Linux.
3. **Split into chunks; per chunk define a command, output file(s), and a done-marker.** Each chunk's script must, on finishing, write its output file(s) and then a done-marker last, e.g. `echo $? > /tmp/cout/<chunk>.exit`. The marker is what Step 5 waits on; the output files are what Step 6 pulls.

## Step 2: Snapshots (optional - cut setup cost)

If a fresh sidecar needs expensive warm-up (toolchains, deps, compiles), build a snapshot once and launch chunks from it to save that time and compute on every run: `chunk sidecar setup --dir .` -> warm it -> `chunk sidecar snapshot create --name <name>` -> later `chunk sidecar create --image <snapshot-id>`. A per-task snapshot is fine when the warm-up is heavy.

## Step 3: Create and manage the sidecars

Create one sidecar per chunk and keep its UUID:

```
chunk sidecar create --org-id <orgID> [--image <snapshot-id>] --name <proj>-<chunk>
# prints: Created sidecar <name> (<uuid>)   -> capture <uuid>
```

Running several at once:

- Target **every** subsequent call with `--sidecar-id <uuid>`; do not rely on a single "current" sidecar once you have many.
- `chunk sidecar list --org-id <orgID>` enumerates them (`name <uuid>` per line) if you lose track.
- Drive independent chunks concurrently - one background task per chunk, or `xargs -P N`.

### Reusing a sidecar from earlier - wake it first

You can keep working on a sidecar from earlier in this session, or from another session: `chunk sidecar list --org-id <orgID>` shows every sidecar in the org, not just this session's, so find the one you want and address it by `--sidecar-id <uuid>`. (The "current" sidecar is session-local, so another session's sidecar will not show up as `current` - go by UUID.)

Sidecars are Firecracker VMs that sleep when idle, so a reused one is probably asleep. The **first** `chunk sidecar exec`/`ssh` against it wakes the VM, but that first call is slow and can hit the ~30 s exec timeout (`context deadline exceeded`) while it boots. Before launching real work, fire a cheap warm-up call and retry until it answers:

```
# wake: retry a trivial exec until the VM answers (the first call may time out mid-boot)
until chunk sidecar exec --sidecar-id <uuid> --command bash --args -lc \
      --args "echo awake" 2>/dev/null | grep -q awake; do
  sleep 5
done
```

Detection is by stdout content (`grep -q awake`), not the exec exit code - same reason as Step 5. Because the boot can be slow, run this warm-up loop in a background task (like the wait-on-done pattern) so it stays off the agent's context; only deliver and launch the work (Step 4) once the VM answers.

### Keeping a fleet awake - sidecars poke each other

**Why this exists:** a long-running job launched detached (Step 4) risks stalling if its VM goes dormant mid-run. Wake-ups are driven by incoming `exec`/`ssh` calls (see above), so internal activity alone may not keep a VM awake. As a precaution for long runs, guarantee continuous external stimuli by having the sidecars keep **each other** awake: each runs a detached loop that execs a trivial command against a peer every ~10 s. Verified on a 2-sidecar pair (Ubuntu 24.04): 6 minutes, 30/30 pokes per side, zero timeouts.

1. **Install + auth the chunk CLI on each sidecar** via a variation of setup-chunk-cli: sidecars ship git/gcc/curl and passwordless sudo, so the official Homebrew installer runs as the normal user (no `su` dance), then `brew trust circleci-public/circleci && brew install CircleCI-Public/circleci/chunk`, then write the token to `~/.config/chunk/config.json` (0700 dir / 0600 file).
2. **Use a dedicated temporary PAT for the wake ring - never the orchestrator's own token.** Ask the user for a throwaway `CCIPAT_...` minted for this purpose (AskUserQuestion), and remind them to revoke it when the fleet is torn down: it sits as a flat file on every sidecar.
3. On-sidecar `chunk sidecar exec` takes only `--sidecar-id`/`--command`/`--args` - there is **no `--org-id` flag** and no org config is needed on the sidecar.
4. Pair the fleet in a ring (each pokes the next; 2 sidecars poke each other) with this loop, delivered base64-style and launched detached like any other job:

```bash
#!/bin/bash
# $1 = peer sidecar uuid; poke it every 10 s
PEER=$1
exec >> /tmp/cout/poke.log 2>&1
while true; do
  ts=$(date -u +%FT%TZ)
  out=$(/home/linuxbrew/.linuxbrew/bin/chunk sidecar exec --sidecar-id "$PEER" --command bash --args -lc --args "echo pong" 2>&1)
  echo "$ts $out"
  sleep 10
done
```

5. **Kill the loops when the run is over** (`pkill -f poke.sh` on each member, or delete the sidecars) - a poke ring never idles, so it bills until stopped.

## Step 4: Deliver the work and launch it DETACHED

**Getting the script/data onto the sidecar.** You cannot push _arbitrary_ files into a sidecar (for a git repo with a GitHub remote, `chunk sidecar sync` is the exception - see below). Inline the script base64-encoded and decode it there:

```
B64=$(base64 -w0 < job.sh)
chunk sidecar exec --sidecar-id <uuid> --command bash --args -lc --args "
  mkdir -p /tmp/cout
  echo '$B64' | base64 -d > /tmp/cout/job.sh
"
```

`chunk sidecar exec --command bash --args -lc --args "<shell>"` is the reliable way to run a shell on the sidecar. (`chunk sidecar ssh -- '<cmd>'` does not run a shell - it tries to exec the string as a program - so use the `exec --command bash` form.)

**Multiple files / directories - tar them through the same channel.** The base64-inline trick generalises: pack many files (or whole trees, binaries included) into one tar stream, base64 it, and unpack on the sidecar. `tar` preserves paths, modes, and nesting, so this delivers a directory layout the single-file `base64 -d >` form cannot.

```
B64=$(tar czf - job.sh lib/ data/*.json | base64 -w0)
chunk sidecar exec --sidecar-id <uuid> --command bash --args -lc --args "
  mkdir -p /tmp/cout
  echo '$B64' | base64 -d | tar xzf - -C /tmp/cout
"
```

`tar xzf - -C /tmp/cout` unpacks the archive under `/tmp/cout`, recreating the original relative paths (`/tmp/cout/job.sh`, `/tmp/cout/lib/...`). The same form pulls a multi-file _result_ set back in Step 6 - `tar` on the sidecar, base64 to stay text-safe over the exec channel, decode locally.

**If the working dir is a git repo with a GitHub remote - `chunk sidecar sync` delivers it natively.** No base64 needed; chunk sends the repo to the sidecar.

```
ssh-keygen -t ed25519 -f ~/.ssh/chunk_ai      # one-time; chunk has no keygen, it just expects this key (or pass --identity-file)
chunk sidecar sync --sidecar-id <uuid> [--workdir <dest>]
```

- Sync needs an SSH key **before anything else**: chunk looks for `~/.ssh/chunk_ai` and, if absent, errors `SSH key not found` (checked ahead of the remote); generate it with the `ssh-keygen` line above, or pass `--identity-file`.
- The `origin` remote **must be a GitHub URL**; anything else is rejected with `not a GitHub remote URL: <url>` (the gate is the URL itself, not repo reachability).
- Default mode transfers a locally-built git **bundle** (`Sending full bundle`); `--checkout` uses git checkout/patch instead and needs the branch pushed to GitHub.
- `--sidecar-id` defaults to the active sidecar; `--workdir` defaults to `/home/user/<repo>`.
- Warm the sidecar before syncing - a not-yet-ready sidecar can fail the key-registration step with a transient `404`.

**Launch detached.** `chunk sidecar exec` holds the connection open only briefly and has a ~30 s client timeout; a job run in the foreground would be cut off. To detach, **background the work and redirect its std fds away from the connection**:

```
chunk sidecar exec --sidecar-id <uuid> --command bash --args -lc --args "
  cd /tmp/cout
  bash job.sh </dev/null >/dev/null 2>&1 &
"
```

The fd redirection is the part that matters: without it, the backgrounded job keeps the connection open and the exec blocks until the 30 s timeout (the work still runs, but the launch hangs). `setsid`/`nohup` are optional extras, not required. For isolation or a specific image, `sudo docker run -d -v /tmp/cout:/out <image> sh /out/job.sh` is an alternative that also returns immediately (plain `docker` fails with a socket-permission error; the SSH user has passwordless `sudo`, not docker-group membership, so prefix `sudo`).

Either way the job writes its result file(s) and then its done-marker, and the launch call returns immediately while the work continues.

## Step 5: Wake on done - never poll in the foreground

`chunk sidecar exec` does **not** propagate the remote command's exit code (it returns 0 even for `test -f missing` or `exit 7`). So **detect completion from captured stdout, never from the exec exit code.**

Start one background task (`Bash` with `run_in_background: true`) that waits - server-side, off the agent's context - until the marker has content, then exits. A backgrounded `Bash` task exiting re-invokes the agent: that is the wake-up.

```
# run_in_background: true
until out=$(chunk sidecar exec --sidecar-id <uuid> --command bash --args -lc \
            --args "test -f /tmp/cout/job.exit && cat /tmp/cout/job.exit" 2>/dev/null); \
      [ -n "$out" ]; do
  sleep 15
done
echo "done: exit=$out"   # task exits -> agent woken once
```

The agent spends no tokens during the wait and is woken once. For several chunks, run one such wait-task per chunk (or one that loops over all UUIDs). A `context deadline exceeded` from any `chunk sidecar exec` is a client-side timeout, not a remote failure - the remote work continues; confirm via the marker.

## Step 6: Collect the results

Pull each result file with the same exec form:

```
chunk sidecar exec --sidecar-id <uuid> --command bash --args -lc --args "cat /tmp/cout/job.out"
```

Results may be many files - loop `cat` per file, or `tar` them through the exec channel (base64-encode binary to stay text-safe). Verify sizes before trusting a pull; re-pull anything empty or truncated. Read each `.exit` marker for pass/fail.

## Step 7: Tidy up (optional, and only with the user's approval)

Sidecars are reusable - keep them if more rounds are coming. Deleting them just stops them billing. **Always ask the user before deleting any sidecar; never delete automatically.**

The primary way is the `chunk sidecar delete` subcommand:

```
chunk sidecar delete --sidecar-id <uuid>     # prints: Deleted sidecar <uuid>
```

If the subcommand is unavailable, the CircleCI API does it directly:

```
TOKEN=$(sed -n 's/.*"circleCIToken":[[:space:]]*"\([^"]*\)".*/\1/p' ~/.config/chunk/config.json)
curl -sS -X DELETE -H "Circle-Token: $TOKEN" \
  "https://circleci.com/api/v2/sidecar/instances/<uuid>"     # 200 {"message":"ok"}
```

## Gotchas

- **`chunk sidecar exec` swallows the remote exit code** - always detect via captured stdout, not the exec exit code.
- **Detach by redirecting the backgrounded job's fds** (`</dev/null >/dev/null 2>&1 &`); without that the launch blocks to the 30 s exec timeout.
- **Plain `docker` needs `sudo`** on the sidecar.
- **You cannot push files in** - base64-inline on launch, pull on collect.
- **`chunk sidecar ssh -- '<cmd>'` is not shell-wrapped** - use `exec --command bash`.
- **Environment resets wipe brew + chunk** - reinstall via setup-chunk-cli; never resolve dependencies ad hoc.

## Out of scope

- Running the offloaded work, or any test/trial of it, on the local machine - all execution happens on sidecars.
- Installing/authenticating the `chunk` CLI -> setup-chunk-cli, or ask the human.
- Destructive external-write work; non-Linux work.
- Editing files on the sidecar over SSH - they are wiped on the next sync.
