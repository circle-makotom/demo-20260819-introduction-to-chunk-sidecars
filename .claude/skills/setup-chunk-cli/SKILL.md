---
name: setup-chunk-cli
description: Use when the user says "set up Chunk CLI", "install the chunk CLI", "install the sidecar CLI", or otherwise wants a fresh machine to be able to run the `chunk` CLI for CircleCI's Chunk Sidecar. Installs Homebrew at its default Linux prefix (`/home/linuxbrew/.linuxbrew`) if missing, installs `CircleCI-Public/circleci/chunk`, and authenticates CircleCI via `chunk auth login` browser OAuth, which persists the token to chunk's user config file (`${XDG_CONFIG_HOME:-$HOME/.config}/chunk/config.json`). Targets a bare Arch / WSL2 / Docker container where the user has root via `su` but no `sudo`. Does not modify any rc files; brew and chunk are invoked at their absolute paths or via per-Bash-call `shellenv` eval.
version: 3.0.0
allowed-tools:
  - Bash(su -c *)
  - Bash(chown:*)
  - Bash(find:*)
  - Bash(getent group wheel)
  - Bash(brew --version)
  - Bash(brew --prefix)
  - Bash(brew install:*)
  - Bash(brew shellenv)
  - Bash(/home/linuxbrew/.linuxbrew/bin/brew --version)
  - Bash(/home/linuxbrew/.linuxbrew/bin/brew --prefix)
  - Bash(/home/linuxbrew/.linuxbrew/bin/brew shellenv)
  - Bash(chunk --version)
  - Bash(chunk auth status)
  - Bash(/home/linuxbrew/.linuxbrew/bin/chunk --version)
  - Bash(/home/linuxbrew/.linuxbrew/bin/chunk auth status)
  - Bash(/home/linuxbrew/.linuxbrew/bin/chunk auth --help)
  - Bash(/home/linuxbrew/.linuxbrew/bin/chunk auth login --help)
  - Bash(/home/linuxbrew/.linuxbrew/bin/chunk auth login --no-browser --insecure-storage)
  - Bash(chmod:*)
  - Bash(command -v *)
  - Bash(curl:*)
  - Bash(eval *)
  - Bash(mkdir -p:*)
  - Bash(test -x *)
  - Bash(test -d *)
  - Bash(test -f *)
  - Bash(ls:*)
  - Bash(id)
  - Bash(unset:*)
  - Read
  - Write
  - Edit
---

# Set up the Chunk CLI

This skill installs and configures the **`chunk` CLI** so the machine can run it. The CLI is what you later use to drive Chunk Sidecars - but creating/using sidecars is **not** part of this skill. The deliverable here is a working, authenticated `chunk` binary, nothing more.

End state: `/home/linuxbrew/.linuxbrew/bin/chunk --version` runs successfully as the normal user, `chunk auth status` shows `Source: Config file (user config)` and `Valid` for CircleCI, and Homebrew is installed at `/home/linuxbrew/.linuxbrew`.

CircleCI auth survives a fresh shell because the token is persisted to `${XDG_CONFIG_HOME:-$HOME/.config}/chunk/config.json` - chunk's documented user config file (schema sourced from the chunk source code - see Step 4). Brew is **not** put on PATH persistently - no rc edits are made.

## Environment assumptions (read this first - they drive every step)

This skill was last exercised end-to-end on a **bare Arch Linux Docker container under WSL2**, as a non-root user (uid 1000) who:

- has **no `sudo`** (it is not installed), but
- can become root with **`su -c '...'`** without a password.

These two facts change the procedure materially versus a normal sudo-equipped Linux box, because:

1. `pacman` needs root -> run it through `su -c`.
2. The official Homebrew installer **refuses to create its prefix** for a non-root user with no sudo, and **also refuses to run as root** - *except* inside a container. The container exemption is the whole reason the `su` route in Step 3 works.

Before doing anything, establish the lay of the land:

```
id                                    # confirm uid / whether already root
command -v git curl                   # what's already present
test -x /home/linuxbrew/.linuxbrew/bin/brew && echo brew-present || echo brew-absent
test -x /home/linuxbrew/.linuxbrew/bin/chunk && echo chunk-present || echo chunk-absent
test -f /.dockerenv && echo container || echo not-container
```

If `brew` and `chunk` are already present and `chunk auth status` is already `Valid`, there is nothing to do - every step below is idempotent, skip the satisfied ones.

## Step 1: Choose the auth route (do this early)

Ask up front so the long installs can run while the user decides. Use AskUserQuestion. Keep it to one sentence plus one short caveat line - see [[feedback-secret-prompt-brevity]].

- "Browser OAuth (recommended)" - no secret is pasted; you run `chunk auth login --no-browser --insecure-storage` and hand the user the printed URL (see Step 5).
- "Skip auth for now" (install chunk but leave CircleCI unconfigured; they can run `chunk auth set circleci` later in a real TTY), and
- "Use existing config/auth" (collect nothing; rely on whatever `chunk auth status` already resolves - env var, keychain, or an existing config file. Verify at Step 5: if it reports `Not set` or invalid, surface what was actually found - e.g. a config carrying only `orgID` and no `circleCIToken` - and ask again instead of proceeding).

If `chunk auth status` already shows a `Valid` token, `chunk auth login` overwrites it - say so and let the user decide.

Nothing needs to be held in memory; no secret passes through the transcript.

## Step 2: Install git via pacman (through `su`)

The Homebrew installer requires `git` (and a working `curl`, usually already present).

```
su -c 'pacman -Syu --noconfirm git'
```

Then confirm:

```
command -v git
```

## Step 3: Homebrew at the default Linux prefix

Check first - if `test -x /home/linuxbrew/.linuxbrew/bin/brew` succeeds AND `/home/linuxbrew/.linuxbrew/bin/brew --prefix` returns `/home/linuxbrew/.linuxbrew`, skip to Step 4. If brew exists at a different prefix, stop and ask - do not silently use another prefix.

Use the absolute path for the check, not `command -v brew`: the Bash tool starts a fresh shell each call, so a previous `eval "$(brew shellenv)"` is gone. See "Using brew and chunk from later Bash calls" below.

### Why the plain one-liner fails here, and what to do instead

Running the official installer as the normal user fails immediately:

```
NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
# => Insufficient permissions to install Homebrew to "/home/linuxbrew/.linuxbrew" (the default prefix).
```

The installer needs `sudo` to create and chown `/home/linuxbrew/.linuxbrew`; with no sudo it aborts. It will **not** silently fall back.

The installer also has a `check_run_command_as_root` guard that aborts with *"Don't run this as root!"* - **but it returns early (allowing root) when `/.dockerenv`, `/run/.containerenv`, or a known CI/container cgroup is present**. On a Docker container that guard is satisfied, so the supported move is to run the installer as root via `su`:

```
su -c 'NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"'
```

> If `test -f /.dockerenv` was false (not a container), this root route will abort. In that case stop and ask the user how to proceed (install `sudo`, pre-create and chown the prefix, etc.) - do not improvise an unsupported prefix.

This installs brew **owned by `root:root`**, which a non-root user cannot use for `brew install`. Make the prefix writable by the `wheel` group rather than world-writable - give group ownership to `wheel`, grant the group `rwx`, drop world-write, and set the **setgid** bit on directories so files brew creates later inherit the `wheel` group:

```
su -c 'chown -R :wheel /home/linuxbrew'                          # group -> wheel
su -c 'chmod -R g+rwX,o-w /home/linuxbrew'                       # group rwx, no world-write
su -c "find /home/linuxbrew -type d -exec chmod g+s {} +"        # setgid on dirs (group inheritance)
```

(The setgid bit `g+s` is what makes new files inherit `wheel` - sometimes loosely called the "sticky bit", but the true sticky bit `+t` is unrelated.)

**The normal user must be a `wheel` member, and that membership must be *active in the current session*.** Check both - `getent group wheel` should list the user, but `id` reflects the *running* session and on this machine showed only the primary group even though `/etc/group` had the user in `wheel`. While wheel is not active in-session, prefix writes (`brew trust`, `brew install`) must run as root via `su -c`, and the three ownership/permission commands above must then be re-applied so everything is back under group `wheel` with `g+rwX` and setgid. (On a fresh real-terminal login wheel is already active and the `su` route is unnecessary - it is specifically the harness's inherited session that lacks it.) If the user is not in `wheel` at all, add them first: `su -c 'usermod -aG wheel <user>'`.

### Verify

```
/home/linuxbrew/.linuxbrew/bin/brew --version
/home/linuxbrew/.linuxbrew/bin/brew --prefix      # expect /home/linuxbrew/.linuxbrew
```

A `shallow or no git repository` warning on `--version` is benign. While wheel is inactive in-session, `touch /home/linuxbrew/.linuxbrew/.wtest` as the normal user returns `Permission denied` - expected, not a fault, and the reason `brew` writes go through `su`. `chunk` itself only needs *execute* (others keep `r-x`), so running the installed binary needs no privilege; only `brew` writes do. If brew landed somewhere unexpected, surface the actual location and stop.

### Using brew and chunk from later Bash calls

Each Bash call is a fresh shell, so `eval "$(brew shellenv)"` does **not** carry over. Every call needing `brew`/`chunk` must either invoke the absolute path under `/home/linuxbrew/.linuxbrew/bin/`, or chain shellenv into the same command, e.g. `eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)" && brew <args>`. **Never** make shellenv persistent; never touch `~/.bashrc` or any rc file.

## Step 4: Install the chunk formula

Check first:

```
test -x /home/linuxbrew/.linuxbrew/bin/chunk && /home/linuxbrew/.linuxbrew/bin/chunk --version
```

If that succeeds, skip to Step 5. Otherwise install - shellenv eval, `brew trust`, and `brew install` in the **same** Bash call (this pulls the tap, trusts it, and installs in one go; it can take a couple of minutes, so running it as a background Bash task is reasonable). Because these write to the prefix and wheel is typically inactive in the session, run them as root via `su -c` (see Step 3). Redirect brew's output to a log file (`> <scratchpad>/chunk-install.log 2>&1`); do not pipe it through `head`/`tail`, which produced `Error: Broken pipe` and a silent no-op install:

```
su -c 'eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)" && brew trust circleci-public/circleci && brew install CircleCI-Public/circleci/chunk'
```

Root-installed files must be brought back under group `wheel` - re-apply the Step 3 permissions:

```
su -c 'chown -R :wheel /home/linuxbrew'
su -c 'chmod -R g+rwX,o-w /home/linuxbrew'
su -c "find /home/linuxbrew -type d -exec chmod g+s {} +"
```

**The `brew trust` step is required - do not drop it.** Current Homebrew (`4.3.0` and later) gates third-party taps. Without trusting the tap first, `brew install CircleCI-Public/circleci/chunk` does **not** error out: it prints a `Warning: Skipping circleci-public/circleci because it is not trusted` notice, installs nothing, and `chunk` stays absent - a silent no-op that looks fine until the verify step reports `chunk` missing. `circleci-public/circleci` is the official CircleCI tap this skill installs from, so trusting it is intrinsic to the task, not a separate trust decision to deliberate. (Note the tap name is lowercase for `brew trust`, even though the install target is `CircleCI-Public/circleci/chunk`.)

Verify:

```
test -x /home/linuxbrew/.linuxbrew/bin/chunk && /home/linuxbrew/.linuxbrew/bin/chunk --version
```

If brew reports a formula "must be built from source" and the build fails for a missing compiler, ensure `gcc` is installed (Step 2: `su -c 'pacman -Syu --noconfirm gcc'`) and re-run. Do **not** `brew install gcc` - pacman is the prescribed dependency source. If `chunk` is still absent from the expected absolute path, surface the install output and stop.

## Step 5: Authenticate to CircleCI via browser OAuth

> The source paths cited in this step (e.g. `internal/config/config.go`) are relative to the chunk CLI repo root. That source tree is **not guaranteed to be present locally**; if you need to verify one, clone it first: `git clone https://github.com/CircleCi-Public/chunk-cli.git`.

Skip if the user chose "Skip auth" in Step 1. Otherwise run `/home/linuxbrew/.linuxbrew/bin/chunk auth status` first; a `Valid` line means a token is already stored and logging in replaces it - ask before doing so.

`--insecure-storage` (hidden global, `internal/cmd/root.go:63`) is required here: a bare container has no Secret Service, so the default keychain save fails and the command exits 1 with `save token: The name org.freedesktop.secrets ...`. With the flag, the token goes to the user config file instead.

```
/home/linuxbrew/.linuxbrew/bin/chunk auth login --no-browser --insecure-storage
```

Run it as a background Bash task and Read the task output file for the URL: it blocks on the callback for up to 5 minutes. Hand the URL over verbatim and promptly - each attempt mints a new challenge and callback port, so an earlier URL is dead. A `--network host` container shares 127.0.0.1 with the host, so the redirect reaches the waiting CLI.

Success is `✓ CircleCI token saved to user config (<path>/chunk/config.json)` and exit 0. The token sits in that 0600 file in plaintext - say so in the report; the alternative is a Secret Service (e.g. `gnome-keyring`) via pacman and a login without the flag.

Token resolution order, for reading `auth status` (`internal/config/config.go:212-228`): `CIRCLE_TOKEN`, then `CIRCLECI_TOKEN`, then keychain, then `${XDG_CONFIG_HOME:-$HOME/.config}/chunk/config.json` field `circleCIToken`.

### Step 5b: verify

Single Bash call (the `unset` only persists within the same shell, and `chunk` is not on PATH):

```
unset CIRCLECI_TOKEN CIRCLE_TOKEN && /home/linuxbrew/.linuxbrew/bin/chunk auth status
```

Expected: `Source: Config file (user config)` and `Valid`. Unsetting the env vars forces the config-file path - if they were set, the source line would read `Environment variable (...)` (also working, but it would not prove the file write).

### Things not to do

- Do not write `CIRCLECI_TOKEN` exports to `~/.bashrc` or any rc file.
- Do not run `chunk auth login` without `--insecure-storage` on a container with no Secret Service.
- Do not run `chunk auth set circleci` non-interactively hoping it works.
- Do not write the system keychain manually - it is libsecret-backed, not a flat file.

## Done

Report concisely:

- Brew version (first line of `/home/linuxbrew/.linuxbrew/bin/brew --version`) and resolved prefix.
- Chunk version (`/home/linuxbrew/.linuxbrew/bin/chunk --version`).
- That `chunk auth status` reports `Source: Config file (user config)` and `Valid`.
- That the token is persisted at `${XDG_CONFIG_HOME:-$HOME/.config}/chunk/config.json` (0600) and survives fresh shells.
- That the prefix was made user-usable by giving group `wheel` `rwx` + setgid (not world-write), if that step ran, and that `brew` writes ran as root via `su` with those permissions re-applied afterwards, because wheel is inactive in-session.

The CLI is now ready. Do **not** go on to create a sidecar, sync a repo, or scaffold `test-suites.yml` - that is the [[chunk-sidecar]] skill's job and the user has not asked for it. Stop here.
