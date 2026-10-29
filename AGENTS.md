## System design

- For each system design decision, examine SOLID. Use composition, not inheritance.
- Design the code and its tests for standard use, and for the failures that production inputs, dependencies, or code paths can cause. Do not design for failures that only test code can cause.

## Questions

- When you must ask the operator a question, use the question tool. Ask one question, then wait for the answer before you ask the next question. Give concrete answer options, with the recommended option first. This rule replaces the question format of each Skill that asks questions in batches.

## Knowledge

- Before you examine or change the repository, read `GLOSSARY.md` for the project terms and `MEMORY.md` for the applicable entries. Before you change a part of the project, read the ADRs in `docs/adr/` that are related to that part. Obey these ADRs, because each ADR records a decision that the code does not show.

## Workflow

- Branches: Before you create a branch, or open or merge a pull request, obey Git Flow. Open pull requests into `main` only from `release/<semver>` or `hotfix/<name>`. Send all other changes, for example `feature/<name>` and `bugfix/<name>`, through a pull request into `develop`. Change `main` and `develop` only through pull requests with merge commits, because other projects install Skills from `main`.
- Merging: When all required checks pass, merge a pull request into `develop` yourself. For this merge commit, start the message with the line `<type>[(<scope>)]: merge <branch> into develop (#<n>)`. When you write this message, obey each Setting of the Commit policy, `docs/agents/commit-policy.md`, that controls the message. Leave pull requests into `main` for the operator to merge. GitHub deletes the remote branch of a merged pull request, but your local branch stays. After you merge a pull request from a `feature/<name>` or `bugfix/<name>` branch into `develop`, do these steps:
  1. Run `git switch develop`.
  2. Run `git pull`.
  3. Run `git fetch --prune`.
  4. CAUTION: Delete a local branch only with `git branch -d`, not `git branch -D`. `git branch -D` deletes commits that no other branch contains.
  5. Delete the local branch of that pull request with `git branch -d <branch>`.
- Checks: The required check is the `typos` job of `.github/workflows/spelling.yml`. Before you add a check, ask the operator, who picks checks from the CI of popular Neovim plugins.
- Back-merges: After the operator merges a pull request into `main`, `release.yml` opens the back-merge pull request from `main` into `develop`. If the `back-merge` job stops because Git cannot merge `main` into `develop`, do not change that pull request. If you change that pull request, you push commits to `main`. Run `git fetch`. Then do these steps:
  1. Make the branch `bugfix/back-merge-v<semver>` from `origin/develop`. The title of the back-merge pull request gives `<semver>`.
  2. On that branch, run `git merge origin/main` and correct the files that Git cannot merge.
  3. Open a pull request from that branch into `develop`.
  4. Close the back-merge pull request, because the new pull request replaces it.

## Agent skills

### Triage labels

The default labels are needs-triage, needs-info, ready-for-agent, ready-for-human, and wontfix. Before you add or change a triage label, read `docs/agents/triage-labels.md`.

### Issue tracker

Issues are tracked in GitHub Issues (`a1exk-dev/codestyle.nvim`) via the `gh` CLI. See `docs/agents/issue-tracker.md`.

### Domain docs

Before you write or edit `AGENTS.md`, `GLOSSARY.md`, `MEMORY.md`, or an ADR, and when you complete a task, obey `docs/agents/domain.md`.
