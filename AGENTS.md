## System design

- For each system design decision, examine SOLID. Use composition, not inheritance.
- Design the code and its tests for standard use, and for the failures that production inputs, dependencies, or code paths can cause. Do not design for failures that only test code can cause.

## Questions

- When you must ask the operator a question, use the question tool. Ask one question, then wait for the answer before you ask the next question. Give concrete answer options, with the recommended option first. This rule replaces the question format of each Skill that asks questions in batches.

## Knowledge

- Before you examine or change the repository, read `GLOSSARY.md` for the project terms and `MEMORY.md` for the applicable entries. Before you change a part of the project, read the ADRs in `docs/adr/` that are related to that part. Obey these ADRs, because each ADR records a decision that the code does not show.

## Workflow

- Changelog: In each pull request into `develop` with a change that users can see, add its item under `## Unreleased` with the common-changelog Skill. On each `release/*` or `hotfix/*` branch, release the changelog as its version before you open the pull request into `main` (ADR-0019).
- Merge messages: Start the message of each merge commit into `develop` with the line `<type>[(<scope>)]: merge <branch> into develop (#<n>)`. When you write this message, obey each Setting of the Commit policy, `docs/agents/commit-policy.md`, that controls the message.
- Checks: Branch protection on `main` and `develop` requires five checks: the tests on Neovim 0.11.7 and stable, StyLua, and lua-language-server in `.github/workflows/ci.yml`, and `typos` in `.github/workflows/spelling.yml` (ADR-0017). Before you add or remove a required check, ask the operator, who picks checks from the CI of popular Neovim plugins.

## Agent skills

### Triage labels

The default labels are needs-triage, needs-info, ready-for-agent, ready-for-human, and wontfix. Before you add or change a triage label, read `docs/agents/triage-labels.md`.

### Issue tracker

Issues are tracked in GitHub Issues (`a1exk-dev/codestyle.nvim`) via the `gh` CLI. See `docs/agents/issue-tracker.md`.

### Domain docs

Before you write or edit `AGENTS.md`, `GLOSSARY.md`, `MEMORY.md`, or an ADR, and when you complete a task, obey `docs/agents/domain.md`.
