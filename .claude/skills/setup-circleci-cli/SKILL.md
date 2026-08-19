---
name: setup-circleci-cli
description: Use when the user says "set up the CircleCI CLI", "install the circleci CLI", or otherwise wants a fresh machine to be able to run the `circleci` CLI (CircleCI's official command-line tool, `@next` channel). Installs Homebrew at its default Linux prefix (`/home/linuxbrew/.linuxbrew`) if missing, then installs `CircleCI-Public/circleci/circleci@next`. Targets a bare Arch / WSL2 / Docker container where the user has root via `su` but no `sudo`. Does not modify any rc files; brew and circleci are invoked at their absolute paths or via per-Bash-call `shellenv` eval.
version: 0.1.0
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
  - Bash(circleci version)
  - Bash(circleci auth login:*)
  - Bash(circleci auth me)
  - Bash(circleci setting list)
  - Bash(/home/linuxbrew/.linuxbrew/bin/circleci version)
  - Bash(/home/linuxbrew/.linuxbrew/bin/circleci auth login:*)
  - Bash(/home/linuxbrew/.linuxbrew/bin/circleci auth me)
  - Bash(/home/linuxbrew/.linuxbrew/bin/circleci setting list)
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

# Set up the CircleCI CLI

This skill installs and configures the **`circleci` CLI** (CircleCI's official command-line tool, `@next` channel) so the machine can run it. The deliverable is a working, authenticated `circleci` binary, nothing more.

End state: `/home/linuxbrew/.linuxbrew/bin/circleci version` runs successfully as the normal user, CircleCI auth is configured and valid, and Homebrew is installed at `/home/linuxbrew/.linuxbrew`.

Brew is **not** put on PATH persistently - no rc edits are made.

## Environment assumptions (read this first - they drive every step)

This skill targets a **bare Arch Linux Docker container under WSL2**, as a non-root user (uid 1000) who:

- has **no `sudo`** (it is not installed), but
- can become root with **`su -c '...'`** without a password.

These two facts change the procedure materially versus a normal sudo-equipped Linux box, because:

1. `pacman` needs root -> run it through `su -c`.
2. The official Homebrew installer **refuses to create its prefix** for a non-root user with no sudo, and **also refuses to run as root** - *except* inside a container. The container exemption is the whole reason the `su` route in Step 2 works.

Before doing anything, establish the lay of the land:

```
id                                    # confirm uid / whether already root
command -v git gcc curl               # what's already present
test -x /home/linuxbrew/.linuxbrew/bin/brew && echo brew-present || echo brew-absent
test -x /home/linuxbrew/.linuxbrew/bin/circleci && echo circleci-present || echo circleci-absent
test -f /.dockerenv && echo container || echo not-container
```

If `brew` and `circleci` are already present and auth is already valid, there is nothing to do - every step below is idempotent, skip the satisfied ones.

## Step 1: Install git via pacman (through `su`)

The Homebrew installer requires **`git`** (and a working `curl`, usually already present). On a bare container `git` is typically absent. `pacman` needs root and there is no `sudo`, so go through `su`. **Always `pacman -Syu`, never `pacman -S` or `-Sy`** - a partial upgrade links new packages against old libraries and breaks them:

```
su -c 'pacman -Syu --noconfirm git'
```

Then confirm:

```
command -v git
```

(No compiler is needed: `circleci@next` installs as a Homebrew **cask** - a prebuilt binary download, not a source build - so `gcc` is not required for this skill.)

## Step 2: Homebrew at the default Linux prefix

Check first - if `test -x /home/linuxbrew/.linuxbrew/bin/brew` succeeds AND `/home/linuxbrew/.linuxbrew/bin/brew --prefix` returns `/home/linuxbrew/.linuxbrew`, skip to Step 3. If brew exists at a different prefix, stop and ask - do not silently use another prefix.

Use the absolute path for the check, not `command -v brew`: the Bash tool starts a fresh shell each call, so a previous `eval "$(brew shellenv)"` is gone. See "Using brew and circleci from later Bash calls" below.

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

A `shallow or no git repository` warning on `--version` is benign. While wheel is inactive in-session, `touch /home/linuxbrew/.linuxbrew/.wtest` as the normal user returns `Permission denied` - expected, not a fault, and the reason `brew` writes go through `su`. `circleci` itself only needs *execute* (others keep `r-x`), so running the installed binary needs no privilege; only `brew` writes do. If brew landed somewhere unexpected, surface the actual location and stop.

### Using brew and circleci from later Bash calls

Each Bash call is a fresh shell, so `eval "$(brew shellenv)"` does **not** carry over. Every call needing `brew`/`circleci` must either invoke the absolute path under `/home/linuxbrew/.linuxbrew/bin/`, or chain shellenv into the same command, e.g. `eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)" && brew <args>`. **Never** make shellenv persistent; never touch `~/.bashrc` or any rc file.

## Step 3: Install the circleci cask

`circleci@next` is a Homebrew **cask** (a prebuilt binary), not a formula - so `brew install` downloads and links a binary rather than compiling anything.

Check first:

```
test -x /home/linuxbrew/.linuxbrew/bin/circleci && /home/linuxbrew/.linuxbrew/bin/circleci version
```

If that succeeds, skip to Step 4. Otherwise install - shellenv eval, `brew trust`, and `brew install` in the **same** Bash call (this pulls the tap, trusts it, and installs in one go; it takes about a minute, so running it as a background Bash task is reasonable). Because these write to the prefix and wheel is typically inactive in the session, run them as root via `su -c` (see Step 2):

```
su -c 'eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)" && brew trust circleci-public/circleci && brew install CircleCI-Public/circleci/circleci@next'
```

Root-installed files must be brought back under group `wheel` - re-apply the Step 2 permissions:

```
su -c 'chown -R :wheel /home/linuxbrew'
su -c 'chmod -R g+rwX,o-w /home/linuxbrew'
su -c "find /home/linuxbrew -type d -exec chmod g+s {} +"
```

**The `brew trust` step is required - do not drop it.** Current Homebrew (`4.3.0` and later) gates third-party taps. Without trusting the tap first, `brew install CircleCI-Public/circleci/circleci@next` does **not** error out: it prints a `Warning: Skipping circleci-public/circleci because it is not trusted` notice, installs nothing, and `circleci` stays absent - a silent no-op that looks fine until the verify step reports `circleci` missing. `circleci-public/circleci` is the official CircleCI tap this skill installs from, so trusting it is intrinsic to the task, not a separate trust decision to deliberate. (Note the tap name is lowercase for `brew trust`, even though the install target is `CircleCI-Public/circleci/circleci@next`.)

The cask prints a caveat that its `circleci` binary conflicts with the stable `circleci` formula from homebrew-core; Homebrew cannot declare the conflict automatically. On a fresh machine the core formula is not installed, so this is informational. If it *is* present, unlink it first to avoid a clashing symlink: `brew unlink circleci`.

Verify:

```
test -x /home/linuxbrew/.linuxbrew/bin/circleci && /home/linuxbrew/.linuxbrew/bin/circleci version
```

If `circleci` is still absent from the expected absolute path, surface the install output and stop.

## Step 4: Authenticate to CircleCI via OAuth (browser, no TTY)

The `@next` CLI authenticates with a browser-based OAuth flow: `circleci auth login`. No TTY is needed, but a human must approve in a browser, and the browser's redirect must be able to reach the CLI's loopback server.

By default the token is saved to the system keyring; on a bare container with no keyring daemon, pass `--insecure-storage` to persist it to `~/.config/circleci/config.yml` (0600) instead.

### Step 4a: check for existing auth first

Before starting any login flow, check whether the CLI is already authenticated:

```
circleci auth me          # exits 0 and prints the account (name + login) when already authenticated
```

If it prints an account and exits 0, auth is already valid - **skip the rest of Step 4 and go straight to Done**; do not start a login flow and do not flag auth as an outstanding blocker. Only proceed to Step 4b when this check shows no valid auth (non-zero exit or no account).

### Step 4b: start the flow

Starting the login flow is authorized by this skill itself - **proceed with it directly; do not pause to ask the user for a separate go-ahead before running `circleci auth login`.** A human still has to approve in the browser (4c), but initiating the flow and handing over the URL needs no extra acknowledgement.

`auth login` blocks until approval, so run it as a background Bash task and read the URL from its output. `--no-browser` makes it print the authorize URL instead of trying to launch a browser that isn't present:

```
circleci auth login --no-browser --insecure-storage
```

It prints:

```
Open this URL in your browser to continue:

  https://circleci.com/oauth/authorize?request_uri=...
```

Hand that URL to the user - this step needs a human with a browser and a CircleCI account; you cannot complete it alone.

### Step 4c: approve in the browser

The user opens the URL, logs in, and approves. `auth login` runs a temporary loopback HTTP server on `127.0.0.1:<random port>/callback`; after approval CircleCI redirects the browser there, the CLI validates the `state`, exchanges the code via `POST /oauth/token`, saves the token and host, and exits 0.

**This completes automatically only if the browser's redirect to `127.0.0.1:<port>` can reach the CLI's loopback server.** That holds when the CLI and the browser share the same loopback - e.g. a desktop, or a container started with `--network host` (which shares the host's network namespace, so the host's browser hitting `127.0.0.1` reaches the container). A default-bridge container does not share loopback with the host and will not receive the redirect - use the fallback below.

*Fallback (isolated host):* the browser's redirect shows a connection error. Copy the full `http://127.0.0.1:<port>/callback?code=...&state=...` from the address bar and replay it on the CLI host: `curl "<that URL>"`. It is one shot per run - a malformed or wrong-`state` request makes the CLI exit; re-run `auth login` to retry.

### Step 4d: verify

```
circleci auth me          # shows the logged-in account (name + login)
```

Expect the user's name and login. `circleci setting list` shows the stored token (masked) and host.

## Done

Report concisely:

- Brew version (first line of `/home/linuxbrew/.linuxbrew/bin/brew --version`) and resolved prefix.
- Circleci version (`/home/linuxbrew/.linuxbrew/bin/circleci version`).
- That `circleci auth me` reports the logged-in account, and the token is persisted at `~/.config/circleci/config.yml` (0600).
- That the prefix was made user-usable by giving group `wheel` `rwx` + setgid (not world-write), if that step ran, and that `brew` writes ran as root via `su` with those permissions re-applied afterwards, because wheel is inactive in-session.
