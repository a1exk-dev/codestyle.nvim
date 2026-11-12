# Language Plugins keep their own repos and get shared files through the template

Each first-party Language Plugin stays in its own `codestyle-<id>.nvim` repo, as ADR-0009 and ADR-0013 say. Shared files reach the plugins on one path: the Core pushes its shared docs and agent setup to the template repo, and the template pushes them, with its own boilerplate, to every plugin, in pull requests that merge themselves when their checks pass. This replaces ADR-0013's weekly copy of `docs/core/` and its hand-applied template diffs ("Which repo layout do the Core and the first-party Language Plugins use?", #98). The operator wants users to install only the languages they use, each language to keep its own version and 1.0 (ADR-0019), and an agent in one plugin to read only that plugin and to have no way to edit the Core or another language.

## What is synced

- **Core → template:** the files on a list kept in the Core: `GLOSSARY.md` and the Core ADRs into `docs/core/`, the skills (`skills-lock.json`), and `docs/agents/` policies. ADRs about the Menu and the Core's own tests (ADR-0004, ADR-0012, ADR-0016, ADR-0017) are not on the list.
- **Template → plugins:** everything above, plus the boilerplate that is the same in every plugin: `test/run.lua`, the CI workflow files, `CONTRIBUTING.md` and the shared `AGENTS.md`. CI files are synced copies, not reusable workflows, so a CI change passes each plugin's own checks before it lands there.
- **Never synced:** a plugin's spec and lazy modules, `test/corpus/`, `test/cases/`, `test/expected_failures.lua`, `test/deps.lua`, its own `docs/adr/` and `GLOSSARY.md`, and `docs/agents/plugin.md`, which holds the plugin's own agent notes and which the shared `AGENTS.md` names.

## Consequences

- One GitHub App, installed on the Core, the template and every plugin repo, opens the sync pull requests. Pull requests opened with the default `GITHUB_TOKEN` do not run checks, and a change to `.github/workflows/` needs the Workflows permission. Each repo turns on auto-merge.
- A boilerplate change is made and tested in the template first: its CI runs `init.lua` on a throwaway copy (ADR-0013) before the change goes out.
- A required check in each plugin fails a pull request that edits a synced file by hand. A sync pull request that turns red is the only sync step that needs the operator.
- A contract `api` bump still needs one pull request per plugin for its own code, from the migration note in the Core's release notes. Only its boilerplate arrives by sync.
- A personal account has no rulesets across repos, so a script sets branch protection with the required checks (ADR-0013) on every repo.
- Third-party plugins start from the template and get no sync pull requests. They follow the template by hand, with its `api-<N>` tags.

## Considered Options

- **One repo for the Core and all sixteen languages**, alone or with read-only mirror repos per language (as mini.nvim does). One pull request would cover a change to the Core and several languages. Rejected: without mirrors users get every language and one shared version; with mirrors the project needs a mirror bot and its own per-language tag script. In both, only instructions keep an agent inside one language.
- **The Core and one repo for all sixteen languages.** Rejected: users still get every language with one version.
- **A weekly pull into each plugin, merged by hand** (ADR-0013). Rejected: copies are up to a week old and the operator merges up to sixteen pull requests.
- **The Core, or an extra hub repo, as the source of every shared file.** Rejected: boilerplate would go out before it ran in a plugin's shape.
