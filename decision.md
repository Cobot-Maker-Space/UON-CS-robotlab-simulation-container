# 📘 `build-image.yml` explained, block by block

**What this is:** a walkthrough of `.github/workflows/build-image.yml` — the GitHub Actions
workflow that builds and publishes the ROS 2 container image the Windows deployment depends on.

**Who it is for:** someone who has not written CI before, who needs to understand not just *what*
each block does but *why it is there*, well enough to defend it in a review.

Read Part 1 if "workflow", "runner" and "action" are new words. Skip to Part 3 if they aren't.

---

## Part 0 — The 60-second version

The workflow does six useful things, in order:

1. Works out **what image name and tag** it is about to publish.
2. **Refuses to run** if that does not match what `devcontainer.json` tells students to pull.
3. Builds the image on a GitHub machine — including compiling the whole ROS workspace inside it.
4. Pushes it to GHCR (GitHub's container registry).
5. **Pulls it back and tests it**, to prove the thing it just published actually works.
6. Reminds you that new packages are private and nobody can pull them yet.

Steps 2 and 5 are the ones worth defending. Everything else is plumbing.

---

## Part 1 — The concepts, briefly

| Term | What it means here |
|---|---|
| **GitHub Actions** | GitHub's built-in automation. You commit a YAML file describing a job; GitHub runs it on their machines. |
| **Workflow** | One YAML file under `.github/workflows/`. This repo has exactly one. |
| **Runner** | The temporary virtual machine your job runs on. Ours is `ubuntu-latest`. It is destroyed afterwards — nothing persists between runs except explicit caches. |
| **Job** | A group of steps that run on one runner. We have a single job, `build`. |
| **Step** | One thing in the list. Either a shell command (`run:`) or a prebuilt component (`uses:`). |
| **Action** | A reusable component someone else wrote, referenced with `uses:`. `actions/checkout@v4` means version 4 of GitHub's official checkout action. |
| **GHCR** | GitHub Container Registry, `ghcr.io`. Where the built image is stored so lab PCs can pull it. |
| **Expression** `${{ ... }}` | Evaluated **by GitHub before the shell ever sees it**. This matters — see the warning in Part 3.4. |

One idea that trips everyone up at first: **the runner starts empty every time.** Your repository
is not there until you check it out. Nothing you build survives unless you push it somewhere.

---

## Part 2 — Why this workflow exists at all

Before it, the image was built by hand on somebody's laptop and pushed manually. That produced a
specific, expensive failure, recorded in the file's own header:

> The production package ended up with a single tag (`2026-08-07`) while `devcontainer.json` pinned
> `:latest` — a tag that never existed, so every student got `manifest unknown`.

Two independent things had to agree — the tag that exists in the registry, and the tag students are
told to pull — and nothing checked that they did. Discovering the mismatch took a room full of
students failing at once.

**So the workflow is not really about automation. It is about making that mismatch impossible.**
That is the argument to lead with if anyone asks why this exists. Automation is a side benefit;
the guard in Part 3.6 is the point.

---

## Part 3 — The file, block by block

### 3.1 `name:`

```yaml
name: Build dev container image
```

The label shown in the Actions tab. Purely cosmetic, but it is what you click, so it should say
what it does.

### 3.2 `on:` — what makes it run

```yaml
on:
  workflow_dispatch:
    inputs:
      tag:
        description: "Image tag to publish (e.g. humble-sim-2026-09). Must match the pin in devcontainer.json."
        required: true
        default: humble-sim-2026-09
      push_latest:
        description: "Also move the ':latest' tag on the testing package."
        type: boolean
        required: false
        default: true
  push:
    tags:
      - "humble-sim-*"
```

Two triggers, and **notably not a third**:

| Trigger | Fires when |
|---|---|
| `workflow_dispatch` | You click **Run workflow** in the Actions tab and fill in the form. `inputs:` defines that form. |
| `push: tags:` | Someone pushes a git tag whose name starts with `humble-sim-`. |
| ~~`push: branches:`~~ | **Absent on purpose.** Pushing a branch publishes nothing. |

**Why no branch trigger?** This job takes 20-40 minutes and publishes something the whole lab
pulls. Publishing on every commit to a branch would mean an unfinished edit could silently become
what students download. Publishing must be a deliberate act.

**A gotcha worth knowing:** `workflow_dispatch` only shows a **Run workflow** button if the
workflow file exists on the repository's **default branch**. That is why this file was added to
`main` even though the deployment work happens elsewhere. Before it was there, the Actions API
reported zero workflows and zero runs for this repo — the button simply did not exist.

When you dispatch, GitHub runs the workflow file **from the branch you select**, not from `main`.
`main` only makes the button appear.

### 3.3 `env:` — values used across the job

```yaml
env:
  REGISTRY: ghcr.io
  # The owner is 'Cobot-Maker-Space' but GHCR rejects any uppercase in a repository name, so the
  # full image name is lowercased in the 'meta' step rather than built here.
  IMAGE_BASENAME: windows-robot-simulation
```

Two constants. The comment explains a real trap: our GitHub org is `Cobot-Maker-Space` with
capitals, but **container registries reject uppercase in image names**. The owner therefore cannot
be hardcoded here — it gets lowercased at runtime in 3.5.

### 3.4 `jobs:` — the runner and its permissions

```yaml
jobs:
  build:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      packages: write
```

`runs-on: ubuntu-latest` picks a fresh Ubuntu VM.

`permissions:` is the security-relevant part and is worth defending. Every run gets an automatic
credential called `GITHUB_TOKEN`, created when the job starts and destroyed when it ends. This
block narrows what that token may do:

- `contents: read` — may read the repository. It cannot commit, push, or delete anything.
- `packages: write` — may publish container images. That is the whole reason the job exists.

Anything not listed is denied. So even if a build script were compromised, that token could not
rewrite the repository, touch other repos, or open pull requests. **This is least privilege, stated
explicitly rather than inherited.**

> ⚠️ **Security note on `${{ }}`.** Expressions are substituted by GitHub into the script *as text*
> before bash runs. That means untrusted text (a branch name, a PR title) can become executable
> shell. Our inputs come only from someone with write access clicking a form or pushing a tag, so
> the exposure is low — but this is why you should never interpolate untrusted values into `run:`
> blocks. It is the most common Actions vulnerability.

### 3.5 The steps

#### Step 1 — Check out repository

```yaml
- name: Check out repository
  uses: actions/checkout@v4
```

The runner starts with an empty disk. This clones the repo onto it. Without it, every later step
would fail with "file not found". `@v4` pins the major version so a future release cannot change
behaviour underneath you.

#### Step 2 — Free up disk space

```yaml
- name: Free up disk space
  run: |
    sudo rm -rf /usr/share/dotnet /usr/local/lib/android /opt/ghc \
                /usr/local/share/boost "$AGENT_TOOLSDIRECTORY"
    df -h /
```

**What:** deletes preinstalled toolchains we never use — .NET, the Android SDK, Haskell, Boost.

**Why:** GitHub runners ship with a lot of preinstalled software and a limited disk (~14 GB free of
~84 GB). Our image is a 2.3 GB base plus a fully compiled ROS workspace. Without this the build
dies partway through with a confusing "no space left on device", after 20 minutes of work.

`df -h /` prints free space to the log, so if it ever fails again you can see how close it was.

#### Step 3 — Resolve image name and tag

```yaml
- name: Resolve image name and tag
  id: meta
  run: |
    if [ "${{ github.event_name }}" = "workflow_dispatch" ]; then
      TAG="${{ inputs.tag }}"
    else
      TAG="${GITHUB_REF_NAME}"
    fi
    OWNER=$(echo "${{ github.repository_owner }}" | tr '[:upper:]' '[:lower:]')
    IMAGE="${REGISTRY}/${OWNER}/${IMAGE_BASENAME}"
    echo "tag=${TAG}"   >> "$GITHUB_OUTPUT"
    echo "image=${IMAGE}" >> "$GITHUB_OUTPUT"
    echo "image_name=${OWNER}/${IMAGE_BASENAME}" >> "$GITHUB_OUTPUT"
    echo "Publishing ${IMAGE}:${TAG}"
```

This assembles the full image name once, so later steps cannot disagree about it.

**The `if`** handles the two triggers differently:
- Manual run → the tag is whatever you typed in the form.
- Tag push → the tag is the git tag name itself (`GITHUB_REF_NAME`). Push `humble-sim-2026-09` and
  the image gets tagged `humble-sim-2026-09`. One name, no chance to mistype it twice.

**The `tr`** lowercases the owner, solving the uppercase problem from 3.3.

**`>> "$GITHUB_OUTPUT"`** is how a step publishes values to later steps. It is a real file; writing
`key=value` lines to it makes them readable as `steps.meta.outputs.key`. `id: meta` is what gives
this step the name `meta` in that reference. Shell variables do **not** survive between steps —
each step is a separate shell — so this file is the mechanism.

#### Step 4 — Verify devcontainer.json pins the tag being built ⭐

```yaml
- name: Verify devcontainer.json pins the tag being built
  run: |
    PINNED=$(grep -oP '^\s*"image"\s*:\s*"\K[^"]+' src/.devcontainer/devcontainer.json)
    EXPECTED="${{ steps.meta.outputs.image }}:${{ steps.meta.outputs.tag }}"
    echo "devcontainer.json pins: ${PINNED}"
    echo "this build publishes:   ${EXPECTED}"
    if [ "${PINNED}" != "${EXPECTED}" ]; then
      echo "::error::devcontainer.json pins '${PINNED}' but this run publishes '${EXPECTED}'."
      echo "::error::Update the 'image' field in src/.devcontainer/devcontainer.json to match, or build the tag it already pins."
      exit 1
    fi
```

**This is the most important block in the file.** Everything else is standard; this is the part
that exists because of a specific outage.

It reads the image name students will actually pull straight out of `devcontainer.json`, compares
it to what this run is about to publish, and **aborts before publishing** if they differ.

- `grep -oP` uses Perl regex; `\K` means "forget everything matched so far", so only the value
  inside the quotes is printed.
- `::error::` is a **workflow command** — GitHub recognises that prefix and renders the line as a
  red annotation on the run summary, not just a log line.
- `exit 1` fails the step, which fails the job. Nothing is pushed.

**Why it matters:** without this, the two halves can drift, and the symptom appears at the worst
possible moment — a whole class getting `manifest unknown` simultaneously. The check costs
milliseconds and makes the original outage structurally impossible.

There is a useful side effect: selecting the wrong branch fails here, safely. `main` has no
`.devcontainer` directory, so `grep` finds no file, the step fails, and nothing is published.

> **Note:** GitHub runs `run:` blocks with `bash -e`, so a failing command aborts the step even
> without an explicit check. That is why the missing-file case stops here rather than continuing
> with an empty `PINNED`.

#### Step 5 — Set up Docker Buildx

```yaml
- uses: docker/setup-buildx-action@v3
```

Enables BuildKit, Docker's modern builder. We need it for the layer caching in step 7; the legacy
builder cannot do it.

#### Step 6 — Log in to GHCR

```yaml
- uses: docker/login-action@v3
  with:
    registry: ${{ env.REGISTRY }}
    username: ${{ github.actor }}
    password: ${{ secrets.GITHUB_TOKEN }}
```

Authenticates so the push can succeed. Note there is **no secret to manage**: `GITHUB_TOKEN` is
generated automatically for the run and expires with it, and `github.actor` is whoever triggered
it. Nobody has to create a personal access token, store it, or rotate it — and there is no
long-lived credential to leak. This is a genuine advantage of building in CI rather than on a
laptop, and worth saying out loud in a review.

#### Step 7 — Build and push

```yaml
- uses: docker/build-push-action@v6
  with:
    context: .
    file: src/.devcontainer/Dockerfile
    platforms: linux/amd64
    push: true
    tags: |
      ${{ steps.meta.outputs.image }}:${{ steps.meta.outputs.tag }}
      ${{ (github.event_name == 'push' || inputs.push_latest) && format('{0}:latest', steps.meta.outputs.image) || '' }}
    cache-from: type=gha
    cache-to: type=gha,mode=max
```

The step that does the actual work, and where the 20-40 minutes goes.

**`context: .` is not the obvious choice and gets asked about.** The build context is the set of
files sent to the builder, and it is the **repository root**, not the `.devcontainer` folder the
Dockerfile lives in. That is because the Dockerfile does `COPY src/ ...` to bake in a
pre-compiled workspace, and Docker can only copy from inside the context. `.dockerignore` at the
root then trims what gets sent — without it the whole `.git` history would be uploaded on every
build.

**`platforms: linux/amd64`** — lab PCs are Intel/AMD. The file's comment records why arm64 is not
here: the ROS apt packages and the workspace build would both have to work there, and build time
roughly doubles. That is a decision with a stated cost, not an oversight.

**The `tags` expression** is GitHub's version of a ternary, and it reads badly until you have seen
it once:

```
${{ CONDITION && VALUE_IF_TRUE || VALUE_IF_FALSE }}
```

So: on a tag push, or when you ticked `push_latest`, also tag the image `:latest`. Otherwise
produce an empty string, which the action ignores.

**`cache-from` / `cache-to: type=gha`** store Docker layers in GitHub's cache between runs. Without
this every run recompiles the entire ROS workspace from scratch. `mode=max` caches intermediate
layers too, not just the final one — more storage, much faster rebuilds when you have only changed
something near the end of the Dockerfile.

#### Step 8 — Smoke test the published image ⭐

```yaml
- name: Smoke test the published image
  run: |
    IMAGE="${{ steps.meta.outputs.image }}:${{ steps.meta.outputs.tag }}"
    docker pull "$IMAGE"

    docker run --rm "$IMAGE" test -f /home/ros2_ws/install/setup.bash \
      || { echo "::error::No prebuilt workspace in the image - students would face a full colcon build."; exit 1; }

    docker run --rm "$IMAGE" bash -lc \
      'source /home/ros2_ws/install/setup.bash && ros2 pkg list | grep -c turtlebot3'

    docker run --rm "$IMAGE" bash -lc \
      'source /opt/ros/humble/setup.bash && ros2 pkg prefix gazebo_ros'

    docker run --rm "$IMAGE" bash -lc 'command -v rossim-rebuild'
```

The second block worth defending. It **pulls the image back from the registry** — not the local
copy — and checks four things that would otherwise only be discovered by a student:

| Check | The disaster it catches |
|---|---|
| `install/setup.bash` exists | The prebuild silently failed. The image would still be *valid*, just useless — every student would sit through a 20-minute `colcon build`. **This is the headline feature; only an explicit assertion catches its absence.** |
| TurtleBot3 packages resolve | The workspace built but our customised packages are not actually there. |
| `gazebo_ros` resolves | Gazebo is baked into the image rather than apt-installed at container start, which would make a working network a hard requirement for starting a container. |
| `rossim-rebuild` on PATH | The student-facing rebuild helper made it into the image and is executable. |

The general principle: **an image that builds is not the same as an image that works.** These four
commands are the difference between finding out in CI and finding out in a classroom.

#### Step 9 — Remind about package visibility

```yaml
- name: Remind about package visibility
  run: |
    echo "### Published ..." >> "$GITHUB_STEP_SUMMARY"
    ...
```

`$GITHUB_STEP_SUMMARY` is a file whose Markdown contents are rendered on the run's summary page.

This prints a reminder that **new GHCR packages are private by default**, along with a
copy-pasteable check for anonymous pull. A private package means every lab PC needs `docker login`
before it can pull anything — a failure that looks like a networking problem and is not.

This is institutional knowledge turned into something the tool tells you, instead of something the
one person who knows has to remember.

---

## Part 4 — How to run it

**Manually (normal case):**

1. Actions tab → **Build dev container image** → **Run workflow**.
2. **Use workflow from:** pick the deployment branch — *not* `main`.
3. **tag:** type it explicitly, e.g. `humble-sim-2026-09`. It must equal the tag in that branch's
   `devcontainer.json`, or step 4 stops the run.
4. Run, then watch step 4 first — it fails in seconds if something is out of sync.

**By tag push (alternative, needs nothing on `main`):**

```bash
git tag humble-sim-2026-09 <branch>
git push origin humble-sim-2026-09
```

To re-run after a fix you must delete and re-push the tag, which is why the manual route is usually
nicer:

```bash
git push origin :refs/tags/humble-sim-2026-09
git tag -d humble-sim-2026-09
```

**Afterwards:** set the package visibility to Public the first time, then verify anonymous pull:

```bash
R=cobot-maker-space/windows-robot-simulation
T=$(curl -s "https://ghcr.io/token?scope=repository:$R:pull&service=ghcr.io" | jq -r .token)
curl -s -H "Authorization: Bearer $T" "https://ghcr.io/v2/$R/tags/list"
```

Expect a tag list. `denied` means it is still private.

---

## Part 5 — Reading a failure

| Step that failed | Almost certainly |
|---|---|
| Verify devcontainer.json pins... | The tag you typed ≠ the pin in that branch, **or** you selected a branch with no `.devcontainer` (e.g. `main`). The log prints both values — compare them. |
| Free up disk space / Build | Out of disk. Check the `df -h` output. The image grew, or the cleanup list needs extending. |
| Build and push, `denied` | Permissions. Check `packages: write` is still in the `permissions:` block. |
| Build, a `RUN apt-get` line | An upstream package changed or a mirror was down. Re-run first before assuming it is your change. |
| Build, the `colcon build` line | A genuine compile error in `src/`. This is your code, not CI. |
| Smoke test, first check | The build "succeeded" but produced no compiled workspace. **Do not publish over this** — investigate the colcon step. |
| Smoke test, `rossim-rebuild` | The helper was renamed or moved without updating the Dockerfile's `COPY`. |

---

## Part 6 — Decisions you may be asked to defend

**"Why not build on a laptop and push? It worked before."**
It produced the `manifest unknown` outage. CI gives three things a laptop cannot: the tag-vs-pin
guard, smoke tests against the *published* artefact, and no long-lived registry credential to leak.
It is also reproducible by anyone, not just the person whose laptop it was.

**"Why does publishing need a manual click?"**
Because the artefact is pulled by a whole cohort, and the build takes 20-40 minutes. Automatic
publishing on every push would let an unfinished commit become what students download. Deliberate
action is the safety property, not an inconvenience.

**"Why bake a compiled workspace into the image instead of building on the student's machine?"**
Building took 10-25 minutes and used to happen on every container create, in class. Doing it once
on a GitHub runner replaces 60 builds with one. The cost is a larger image, pulled ahead of time
when nobody is waiting.

**"Why a dated tag rather than `:latest`?"**
So a mid-term push cannot change what a running class is using. `:latest` is a moving target; a
dated tag is a promise.

**"Are the smoke tests not overkill?"**
The first one catches an image that builds successfully and is completely useless. That failure is
invisible to `docker build` and visible to every student simultaneously. Four `docker run`
commands is a very cheap insurance premium.

---

## Part 7 — What this workflow does *not* do

Worth knowing, and worth saying before someone else points it out:

- **It does not set package visibility.** First publish is private; a human must change it. The
  workflow can only remind you.
- **It does not update `devcontainer.json`.** It only checks the pin. Moving to a new tag is a
  deliberate commit.
- **It does not deploy to any machine.** Publishing an image and rolling it out are separate;
  rollout is `Install-RobotLab.ps1` plus a workspace reset.
- **It does not test the Windows side.** No PowerShell, no Docker Desktop, no VS Code involved.
  Everything about the launcher is still tested by hand on a real machine.
- **It does not build arm64.** Deliberate — see 3.5, step 7.

---

## Glossary

| Term | Meaning |
|---|---|
| **Runner** | The throwaway VM a job runs on. Starts empty, is destroyed after. |
| **`uses:`** | Run a prebuilt action written by someone else. |
| **`run:`** | Run shell commands. Uses `bash -e` on Linux, so any failing command aborts the step. |
| **`GITHUB_TOKEN`** | An automatic, short-lived credential scoped by the `permissions:` block. |
| **`$GITHUB_OUTPUT`** | A file a step writes `key=value` into so later steps can read `steps.<id>.outputs.<key>`. |
| **`$GITHUB_STEP_SUMMARY`** | A file whose Markdown is rendered on the run summary page. |
| **`::error::`** | A workflow command; makes GitHub display the line as a red annotation. |
| **Build context** | The files sent to the Docker builder. Here the repo root, trimmed by `.dockerignore`. |
| **Buildx / BuildKit** | Docker's modern builder. Needed for the layer caching used here. |
| **Layer cache (`type=gha`)** | Docker layers stored in GitHub's cache between runs, so unchanged steps are not rebuilt. |
| **GHCR** | GitHub Container Registry, `ghcr.io`. New packages are private by default. |
| **`manifest unknown`** | Registry-speak for "that tag does not exist". The error this workflow exists to prevent. |
