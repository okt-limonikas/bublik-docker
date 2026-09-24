# Contributing to Bublik Docker

Thanks for contributing! This repository packages Bublik — the backend
([`bublik`](https://github.com/ts-factory/bublik)), the UI
([`bublik-ui`](https://github.com/ts-factory/bublik-ui)), the docs
([`bublik-release`](https://github.com/ts-factory/bublik-release)) and
[`test-environment`](https://github.com/ts-factory/test-environment) — into
Docker images and Compose stacks. Those four live here as git submodules.

Every change must satisfy three things before it can be merged:

1. [Every commit is signed](#signing-your-commits) and signed off.
2. [Every commit follows Conventional Commits](#commit-messages).
3. [You checked it locally](#checking-your-change) — there is no CI on pull
   requests.

For setting up and running the stack, see [README.md](./README.md) and the
[Docker setup guide](https://ts-factory.github.io/bublik-release/docker/setup).

---

## Where does my change go?

Code inside the submodule directories belongs to the submodule's own
repository, not this one. Commit it there, following that project's
contributing guide (for example,
[bublik-ui's](https://github.com/ts-factory/bublik-ui/blob/main/CONTRIBUTING.md)),
and get it merged first.

This repository owns everything around the submodules:

- `Dockerfile`, `nginx/` — the runner, log-server and nginx images
- `docker-compose*.yml`, `entrypoint-*.sh` — how the services start
- `docker-settings.py.template`, `.env.example` — deployment settings
  (the Django settings used in Docker come from the template, not from
  `bublik/bublik/settings.py`)
- `Taskfile.yml`, `scripts/`, `bootstrap/` — developer and operator tooling
- `e2e/`, `tests/` — the end-to-end campaign and the helpers' tests
- `.github/workflows/` — the release pipeline

### Submodule pointers

A commit that moves a submodule pointer should say why. Bump a submodule in
the same commit as the Docker-side change that needs it — e.g.
`feat(chat): deploy AI assistant with configurable file storage` moves
`bublik`, `bublik-ui` and `bublik-release` alongside the Compose and settings
changes. Pure version bumps are done by maintainers in `chore(release)`
commits; don't include unrelated pointer moves in your PR.

`git status` often shows submodules as modified while you work. Before
committing, check that you are not staging a pointer by accident:

```bash
git diff --cached --submodule
```

---

## Signing your commits

**All commits must have verified signatures.** GitHub shows a green **Verified**
badge next to such commits; unsigned commits are not accepted.

Follow GitHub's guide to set this up once:
<https://docs.github.com/en/authentication/managing-commit-signature-verification>

Either GPG or SSH signing works. Once your key is configured and added to your
GitHub account, turn signing on for this repository:

```bash
git config commit.gpgsign true
```

In addition to the cryptographic signature, every commit must carry a
[Developer Certificate of Origin](https://developercertificate.org/) sign-off
trailer. `git commit -s` adds it for you:

```bash
git commit -s -S -m "fix(celery): pin worker prefetch multiplier to 1"
```

- `-S` produces the signature that gives you the **Verified** badge.
- `-s` appends `Signed-off-by: Your Name <your@email>` to the message.

Check your work before pushing — every commit should print `G` (good signature)
and show a `Signed-off-by:` trailer:

```bash
git log --pretty='%h %G? %s' -n 10
git log -1 --format='%(trailers:key=Signed-off-by)'
```

If you forgot either on the last commit:

```bash
git commit --amend -s -S --no-edit
```

To fix a whole branch at once, rebase it onto `main` with signing and sign-off
applied to every commit:

```bash
git rebase --exec 'git commit --amend -s -S --no-edit' main
```

---

## Commit messages

We use [Conventional Commits](https://www.conventionalcommits.org/). Release
notes are written from the commit history, so a malformed message means a
malformed release note.

> **Note:** there is no commitlint, no git hook, and no CI job checking commit
> messages. This is a convention enforced by reviewers — please get it right
> before opening a PR.

### Format

```
<type>(<scope>): [<sub-scope>] <summary>
<BLANK LINE>
<body wrapped at 72 columns>
<BLANK LINE>
<footers>
```

`(<scope>)` and `[<sub-scope>]` are optional. The body is optional for trivial
changes. Footers are optional but expected whenever an issue exists.

### Types

| Type       | Use for                                                        |
| ---------- | -------------------------------------------------------------- |
| `feat`     | A new capability of the stack or its tooling                   |
| `fix`      | A bug fix                                                      |
| `refactor` | Restructuring with no behavior change                          |
| `perf`     | Making something measurably faster or smaller                  |
| `test`     | Adding or fixing tests                                         |
| `docs`     | Documentation only                                             |
| `build`    | Dockerfiles, image contents, build arguments                   |
| `ci`       | GitHub Actions workflows                                       |
| `chore`    | Dependency and version pins, housekeeping, releases            |
| `revert`   | Reverting a previous commit                                    |

### Scopes

The scope names the part of the stack you touched. It is optional — omit it for
genuinely cross-cutting changes — but it makes the history much easier to scan.
Prefer the scopes already established in the history:

| Area                 | Scopes                                                                  |
| -------------------- | ----------------------------------------------------------------------- |
| Services and images  | `nginx`, `celery`, `db`, `proxy`, `te`, `analytics`, `chat`, `mcp`       |
| Setup and deployment | `deploy`, `settings`, `bootstrap`, `projects`, `import`, `version`      |
| Tooling              | `build`, `dev`, `tasks`, `test`, `publish`, `deps`, `release`, `docs`   |

If your change does not fit any of them, name the service or file you edited
rather than inventing a new word.

- **Multiple scopes** are joined with a comma and no space:

  ```
  fix(nginx,deploy): honour URL prefix in health checks
  ```

- **Sub-scopes** go in square brackets right after the colon, to name a
  component or sub-area within the scope:

  ```
  fix: [nginx] preserve original `X-Forwarded-Proto` for proxied requests
  ```

### Summary line

- **Imperative mood** — "add", "fix", "remove", not "added" or "adds".
- **Lowercase** after the colon.
- **No trailing period.**
- Backticks are fine for identifiers: ``fix: pin `setuptools` version to `81.0.0` ``.
- **Keep it at 72 characters or fewer.** 100 is a hard limit — if you cannot
  describe the change in 72 characters, the detail belongs in the body.

```
✅ fix(celery): pin worker prefetch multiplier to 1
✅ feat: add auto-confirm option to restore db without confirmation
❌ Fixed the build.
❌ feat: stuff
```

### Body

Separate the body from the summary with a blank line and **wrap it at 72
columns**.

Write **why before what**: start with the context or root cause, then describe
what the change does about it. The diff already shows what changed; the body
exists to explain what the diff cannot — especially for Docker and Compose
changes, where the reason for a pin or a flag is rarely obvious.

```
fix(version): preserve deploy info through the Docker build

The build context has no git: .dockerignore strips .git, and the
submodules' .git files point into the superproject, so the images
reported empty version info.

Collect the version on the host with scripts/git_version_env.sh and
pass it to the build as build arguments.
```

A `Changes:` bullet list is an accepted alternative when a change has several
independent parts. Small, self-explanatory changes can skip the body entirely.

### Footers

Footers go last, after a blank line, one per line.

**Linking issues.** Issues live in
[`ts-factory/bublik-docker`](https://github.com/ts-factory/bublik-docker/issues),
so a bare `#123` resolves there.

| Footer           | Meaning                                                                    |
| ---------------- | -------------------------------------------------------------------------- |
| `Fixes #123`     | This commit **closes** the issue. GitHub closes it automatically on merge. |
| `Issue: #123`    | This commit **relates to** the issue but does not close it.                |
| `Related: <url>` | A cross-repository reference — e.g. the matching `bublik` or `bublik-ui` PR. |

Changes here often go together with a PR in a submodule; link it with a full
URL:

```
Related: https://github.com/ts-factory/bublik/pull/316
```

**Sign-off** always goes last:

```
Signed-off-by: Your Name <your@email>
```

**Breaking changes** — anything that requires operators to edit `.env`,
settings or volumes when upgrading — are marked with a `!` before the colon, a
`BREAKING CHANGE:` footer, or both:

```
feat(db)!: extract postgres to a separate compose file

BREAKING CHANGE: deployments using the bundled database must now pass
-f docker-compose.db.yml to docker compose.
```

---

## Checking your change

Pull requests do not run CI — the only workflow,
[`release.yml`](./.github/workflows/release.yml), builds and publishes images
when a `v*` tag is pushed. A broken Dockerfile or Compose file is only caught at
release time, so check your change locally before you push.

You need [Docker](https://docs.docker.com/get-docker/) with Compose v2 and
[Task](https://taskfile.dev/installation/). Run `task` to list what is
available.

| What you changed                        | Check it with                                                     |
| --------------------------------------- | ----------------------------------------------------------------- |
| Anything                                | `docker compose config -q` (plus `-f docker-compose.db.yml` / `-f docker-compose.dev.yml` if you touched those) |
| `Dockerfile`, `nginx/`, build arguments | `task docker:build-images`                                        |
| Services, entrypoints, settings, `.env` | `task docker:up` and check the UI, API and logs come up           |
| `scripts/e2e.py`, `scripts/e2e_ready.sh` | `python3 -m unittest tests/test_e2e.py`                          |
| `e2e/plan.yaml`                         | `bublik-e2e plan --plan e2e/plan.yaml`                            |
| Anything that affects the running app   | the E2E loop: `task e2e:up`, `task e2e:seed`, `task e2e:test`     |

See the [E2E workflow](./README.md#e2e-workflow) section of the README for the
details of the E2E stack. In the PR description, say which of these you ran.

---

## Pull requests

### Branches

Branch off `main`. The preferred naming pattern is:

```
<your-github-username>/<issue-number>-<short-slug>
```

for example `okt-limonikas/12-external-db`. If there is no issue, drop the
number: `okt-limonikas/add-contributing`.

When a change spans this repository and a submodule, use the same branch name
in both so the pair is easy to find.

### Keep history linear

**This repository has no merge commits.** Bring your branch up to date by
rebasing, never by merging `main` into it:

```bash
git fetch upstream
git rebase upstream/main
```

A rebase rewrites commits, so re-sign them if your rebase dropped the
signatures (see [Signing your commits](#signing-your-commits)).

### One logical change per commit

Split unrelated work into separate commits, each with its own message and its
own issue link. Squash fixup commits into the commit they belong to before
requesting review:

```bash
git rebase -i upstream/main
```

### Before you open the PR

- [ ] Every commit is signed (`%G?` is `G`) and signed off.
- [ ] Every commit message follows the format above.
- [ ] Issues are linked with `Fixes #N` or `Issue: #N`; submodule PRs with
      `Related: <url>`.
- [ ] Submodule pointers move only where the change needs them, and the
      submodule commits are already merged upstream.
- [ ] New settings or variables are documented in `.env.example` or
      `docker-settings.py.template`.
- [ ] You ran the [checks](#checking-your-change) that cover your change.

Open the PR against `main`.
