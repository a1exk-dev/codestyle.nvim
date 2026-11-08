# Public 0.x releases are cut from Git Flow branches, and installs follow `main`

The Core and every Language Plugin publish tagged 0.x releases that users can install long before Core 1.0, which waits for all sixteen plugins (ADR-0009). A release is a `release/X.Y.Z` or `hotfix/<name>` branch, and `release.yml` tags the merge into `main`, publishes the GitHub release and opens the back-merges. The notes come from `CHANGELOG.md`. Each repo has its own semver, and the contract `api` links them (ADR-0007) ("How are releases tagged, and can users install 0.x before Core 1.0?", #89). Popular plugins that start with release-please or semantic-release begin at 1.0.0 and have no 0.x phase. Only plugins tagged by hand ship 0.x (#91).

## Rules

- `docs/agents/semver-policy.md` holds the Settings, and the semver Skill applies them. On 0.x a breaking change bumps the minor version (`Breaking before 1.0.0: minor`), so no breaking change turns into 1.0.0 by accident. A hotfix gets the next patch version.
- A version is always `X.Y.Z`, never a pre-release. `vim.pack` ranges match pre-releases: on Neovim 0.12.6, `vim.version.range('1.*')` installed a `v2.0.0-beta.1` tag (re-checked for #89). So a beta tag would reach users who pinned the major version.
- Each pull request into `develop` with a change that users can see adds its item under `## Unreleased` with the common-changelog Skill. The author writes the item while the details are fresh. A migration note for an `api` bump (ADR-0013) is one example. The `release/*` or `hotfix/*` branch releases the changelog as its version before its pull request into `main`. `release.yml` copies that entry into the GitHub release, and uses generated notes only when the entry is missing.
- A Language Plugin tags 1.0.0 when it passes its own Behaviour Records, with only its flagged Options failing. This can come before Core 1.0. From then on, its key migrations (ADR-0007) keep stored values loading.
- `main` is the default branch and holds only released commits. So the README install spec has no `version`: lazy.nvim (default `version = nil`), LazyVim (`false`) and `vim.pack` all install the latest release. A short "Pin a version" note shows lazy.nvim `version = '^0.5'` or `'1.*'`, and `vim.pack` `version = vim.version.range('1.*')`. The Language Plugin template README uses the same text.

## Considered Options

- **release-please or semantic-release.** Rejected: both start at 1.0.0. release-please opens its own release pull request into `main` from a branch that Git Flow does not permit, and semantic-release releases on every push.
- **Tags only for Language Plugin CI, with "wait for 1.0" in the README.** Rejected: users of the finished languages would wait for the last of the sixteen plugins.
- **Changelog items drafted only at release time.** Rejected: the release agent would write the migration notes from commits that it did not make.
- **Every Language Plugin tags 1.0.0 together with the Core.** Rejected: users of a finished language would get no stability promise until the last plugin is done.
- **`version = '*'` or a pinned minor version in the README spec.** Rejected: `'*'` installs the same commit as no `version` and adds noise to each dependency line, and a pinned minor version has to be edited in the README at each release.
