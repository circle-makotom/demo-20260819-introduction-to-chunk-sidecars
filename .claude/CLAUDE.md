# Preface

THIS SESSION IS A LIVE DEMONSTRATION FOR CHUNK SIDECARS AND SMARTER TESTING, AND YOU SHOULD BE ABLE TO RESOLVE EVERYTHING WITHOUT STOPPING AND ASKING, BECAUSE ALL THE REQUIRED INPUT IS ALREADY GIVEN IN A DETERMINISTIC WAY. IF THERE IS ANY UNCERTAINTY, REREAD ALL THE ASSETS YOU HAVE. NEITHER ASKING A QUESTION NOR MAKING YOUR OWN UNAUTHORIZED DECISION IS ACCEPTABLE.

# Working rule

- Always work in a new worktree; create a new one at the beginning. Make sure that the worktree is not conflicting with pre-existing ones.
- The timeout settings for `chunk sidecar exec` is strictly set to 30 sec, and hence some tasks would time out. To let the command survive those abrupt signals, consider to run commands in the background and poll the status. For anything run inside a container, prefer launching it detached with `docker run -d` and polling `docker inspect` (see "Working around the 30 s timeout with detached containers" below).
- When the session is to make a code change: at the ending of the session, create 1 fresh snapshot-based sidecar running spin up the app in the background bound to all interfaces on the default port (`bin/rails server -b 0.0.0.0`, port 3000), such that I can test the app by myself.
  - To get the app's external endpoint, run `chunk sidecar add-ssh-key --sidecar-id <id> --public-key-file <any-public-key>` (registering a throwaway key is just an unavoidable side effect) to print the sidecar URL https://8000-<sandbox-id>.e2b.app, then swap the 8000 for the app's port and hand me `https://3000-<sandbox-id>.e2b.app` as the endpoint to work with.
  - If you use the running app for your own E2E test. You don't have to restart the app. **Never attempt to restart the app to refresh!**
- Keep all sidecars as-is at the end of the session.
- When needed use this as CircleCI Org ID: 11023efd-8d20-40c0-b255-df8c99397450
- Use the contents of ~/tmp-circleci-token as a temporary CircleCI API token that should be transferred to sidecars.
- There can be other sessions running - if you see sidecars that are not yours still running, leave them.
- Show how long the tests took, and how many sidecars you spun up to expedite the entire process.
- Never forget to follow all the rules predefined in CLAUDE.md.

## Toolchain on sidecars: prefer Docker over installing on the host

The sidecar base image ships the Docker CLI and a live daemon (reachable via `sudo`; the `user` account is not in the `docker` group). CI runs every job inside the `ruby` image, so run that same image on the sidecar rather than apt-installing a toolchain:

- `sudo docker run --rm -v "$REPO":/work -w /work -e BUNDLE_PATH=vendor/bundle ruby bash -lc '<cmd>'` reproduces CI's exact executor. Bind mounts of the synced repo work for read and write, so `vendor/bundle`, `test-reports/rspec` and `coverage/lcov.info` land back in `$REPO` on the sidecar.
- Install gems exactly as CI does: `bundle install` with `BUNDLE_PATH=vendor/bundle`, then run everything through `bundle exec`. The gem tree is what CI passes between jobs via the workspace, so install once and reuse it across execs.
- `image: ruby` is unpinned, i.e. `ruby:latest`, while the repo pins ruby-3.4.8 and the Dockerfile builds `ruby:3.4.8-slim`. Match CI (`ruby`) when simulating CI; match the Dockerfile when reproducing a production build.
- A fresh sidecar's daemon starts with zero images, so the `ruby` pull recurs on each new sidecar unless the image is already baked into the snapshot you create from.

## Working around the 30 s timeout with detached containers

`docker run -d` returns a container ID immediately (well under the 30 s exec limit) and keeps the work running detached. For container workloads this is cleaner than the `nohup … & disown` + sentinel-file pattern:

- Launch: `CID=$(sudo docker run -d ... node:current-slim bash -lc '<long job>')`, writing `$CID` somewhere you can read back (shell state does not persist between `chunk sidecar exec` calls).
- Poll with short execs: `sudo docker inspect -f '{{.State.Status}} {{.State.ExitCode}}' "$CID"` until the status is `exited`, then read the exit code and `sudo docker logs "$CID"`.
- Do not use `docker wait` to block for completion in a single exec - it blocks until the container exits and so trips the 30 s timeout. Poll `docker inspect` instead.

Verified in this environment: a detached container sleeping 40 s stayed pollable across the 30 s boundary and its exit code (7) was recoverable via `docker inspect`.
