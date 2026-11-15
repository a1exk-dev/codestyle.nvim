# codestyle.nvim

The Core of the codestyle Neovim plugins. The skills, the process policies (commits, branches and versions, changelog, issues), and the decisions that cover more than one repo live in [codestyle-home](https://github.com/a1exk-dev/codestyle-home). Follow its `AGENTS.md` for process. Agent issues are tracked in `a1exk-dev/codestyle-home`.

This repo keeps a copy of the `git-commit`, `semver` and `common-changelog` skills in `.agents/skills/` and of their policies in `docs/agents/`, so that a session in this repo alone follows the same process ([home ADR-0006](https://github.com/a1exk-dev/codestyle-home/blob/main/docs/adr/0006-each-repo-keeps-a-copy-of-the-process-skills-and-policies.md)). The home is their source: change them there, not here.

## Knowledge

- Before you examine or change this repo, read `GLOSSARY.md` for the project terms. Before you change a part of the Core, read the ADRs in `docs/adr/` that are related to that part. Obey these ADRs, because each ADR records a decision that the code does not show. An ADR that moved to the home keeps a stub here that links to it.

## System design

- For each system design decision, examine SOLID. Use composition, not inheritance.
- Design the code and its tests for standard use, and for the failures that production inputs, dependencies, or code paths can cause. Do not design for failures that only test code can cause.

## Checks

- Branch protection on `main` and `develop` requires five checks: the tests on Neovim 0.11.7 and stable, StyLua, and lua-language-server in `.github/workflows/ci.yml`, and `typos` in `.github/workflows/spelling.yml` (ADR-0017). Before you add or remove a required check, ask the operator, who picks checks from the CI of popular Neovim plugins.
