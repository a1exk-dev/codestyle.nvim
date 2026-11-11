# How do shared standards reach many plugin repos while Core and language context stay separate?

Research for issue [#99](https://github.com/a1exk-dev/codestyle.nvim/issues/99) (map: [#95](https://github.com/a1exk-dev/codestyle.nvim/issues/95)). It feeds [#98](https://github.com/a1exk-dev/codestyle.nvim/issues/98), which decides.
Question: how do process standards, the agent setup and the Core's domain docs reach many Language Plugin repos automatically, and how does the one-repo alternative keep each context apart? For each mechanism: what runs without a human, what still needs a human merge, how drift shows up, and the cost per extra repo.

Date of research: 2026-11-11. Sources: shallow clones of each repo's default branch on that date (commit hashes in "Sources"), the `github/docs` source for GitHub's documentation, and three web pages. Terms follow `GLOSSARY.md`: the **Core** is codestyle.nvim, a **Language Plugin** supplies one language. Layouts A (repo per Language Plugin), B (monorepo) and C (Core + one bundle repo) are those of #95. This note builds on [`plugin-family-layouts.md`](https://github.com/a1exk-dev/codestyle.nvim/blob/research/plugin-family-layouts/docs/research/plugin-family-layouts.md) (#96), which already describes folke's `folke/github` hub; it does not repeat that description. This note gives facts and no design.

## Answer

- **Process standards: reusable workflows are the only mechanism that removes per-repo copies of CI logic and that a personal account can use.** A plugin repo keeps a short caller file per workflow; the logic lives in one public repo [GH1; GH2]. With `@main` a change reaches every repo with no PR and no merge; with a tag or SHA, Dependabot opens one bump PR per repo [GH2; GH6]. Org-level rulesets and "required workflows" would enforce checks across repos, but rulesets across repos need an organization on the Enterprise plan, and required workflows exist only on GitHub Enterprise Cloud and Server [GH3; GH4]. `a1exk-dev` is a personal account (`gh api users/a1exk-dev` → `"type": "User"`). So branch protection with the five required checks (ADR-0017) must be set on each repo, by hand or by a script that calls the REST API, as folke does hourly [FG4].
- **`.github`-repo defaults do not carry the agent setup or CI.** The default-file repo serves only community health files (CONTRIBUTING, issue/PR templates, SECURITY, SUPPORT, …), and only for repos that have no file of that type [GH5]. Workflow templates in `.github` are an organization feature and copy a workflow once, with no later sync [GH7].
- **Agent setup and other plain files need a copy-and-PR bot; every option ends in a human merge.** Two shapes exist: pull (each repo runs a scheduled job that copies files from a hub and opens a PR: folke's hourly `update.yml` [FG1–FG3]) and push (the hub runs one job on change and opens a PR in each target repo: `repo-file-sync-action` [RF1]). Skills have their own tool: `npx skills check` exits 1 when a skill has an update or local changes, and `npx skills update -y` updates without a prompt [SK1; SK2]. Dependabot and Renovate only bump a ref or digest written in a file (a `uses:` ref, or a SHA matched by a regex manager); they never copy file contents [GH6; RN1–RN3].
- **A PR opened with the default `GITHUB_TOKEN` does not run CI normally.** Its `pull_request` runs start in an "approval-required" state until someone with write access approves them [GH8]; `peter-evans/create-pull-request` documents the older behaviour (no runs at all) and the fixes: a GitHub App token or a PAT [CP1]. A sync PR that changes `.github/workflows/` also needs a token with the Workflows permission [CP1 L307–308]. "Allow GitHub Actions to create and approve pull requests" is off by default per repo [GH9]. So a fully unattended sync PR needs an App or PAT secret in each repo (pull) or in the hub (push), and the Actions setting turned on in each repo.
- **Core domain docs: a copy is the form that agents read without extra steps.** Claude Code loads `CLAUDE.md`/`AGENTS.md` and their `@path` imports; an import of a file outside the working directory needs a one-time approval per project, and a file that is only named in prose is read only if the agent decides to open it [CC1]. A copy in `docs/core/` (ADR-0013 today) plus a pointer in `docs/agents/domain.md` is reachable offline and at a known commit. A link to the Core on GitHub is fetched only when an agent chooses to, and shows `main` at fetch time. A Git submodule pins a Core commit (Renovate can bump it [RN4]) but brings the whole Core tree, which agents in the plugin repo would then also read.
- **One repo: per-context folders work for the domain-modeling skill but not yet for this repo's other skills or for `docs/agents/domain.md`.** The skill reads `GLOSSARY-MAP.md` to find each context's `GLOSSARY.md` and `docs/adr/` [DM1; DM2]. Of the other installed skills, only `wait-what` mentions the map; `tdd`, `pr` and `improve-codebase-architecture` read the root `GLOSSARY.md` [DM3]. `docs/agents/domain.md` says "This is a single-context repo". Agents do load the nearest `AGENTS.md`/`CLAUDE.md` of the folder they work in, and Claude Code loads path-scoped rules only for matching files [AM1; CC1]. Nothing found keeps a change inside one context by force; the tools found are instructions plus CI path filters and commit scopes (mini.nvim makes the module scope mandatory, per #96).

## 1. Process standards (CI checks, StyLua/`typos` config, release workflow)

### Reusable workflows called across repos

- **How.** A job calls `{owner}/{repo}/.github/workflows/{filename}@{ref}`; `{ref}` "can be a SHA, a release tag, or a branch name", and "Using the commit SHA is the safest option" [GH2]. A public repo can call only workflows in public repos [GH1 L41–47]. Limits: 10 nesting levels and 50 unique reusable workflows per caller file; `env` of the caller does not reach the called workflow; runner billing goes to the caller [GH1 L58–66, L98].
- **folke's use.** Each repo's `ci.yml` is a 9-line caller of `folke/github/.github/workflows/ci.yml@main` with `plugin` and `repo` inputs [FG5]. The reusable `ci.yml` turns jobs on only when the caller repo has `scripts/test`, `scripts/docs` or `scripts/build` [FG6 L25–39], so one file serves repos of different shapes.
- **Config files are not covered.** A reusable workflow runs in the caller's checkout; `stylua.toml`, `.typos.toml`, `.luarc.json`, `.editorconfig` must still be files in each repo (folke copies them as templates [FG1]).
- **Without a human:** with `@main`, every change in the hub applies on the next run in all repos. **Human merge:** none with `@main`; one Dependabot PR per repo with a tag or SHA (Dependabot keeps "reusable workflows used inside workflows … up to date" [GH6]; folke's template `dependabot.yml` does this weekly for `github-actions` [FG7]). **Drift:** none in the logic with `@main`, but a broken hub change breaks every repo's CI at once; with pins, drift is the open bump PRs. **Cost per extra repo:** one caller file per workflow, plus the config files.

### Org-level `.github` defaults

- Default community health files live in a public repo named `.github`, for "any repository owned by the account that does not contain its own file of that type"; this works for organizations and personal accounts [GH5 L21–37, L58–60]. Supported types: ACCESSIBILITY, CODE_OF_CONDUCT, CONTRIBUTING, discussion forms, FUNDING, issue/PR templates, SECURITY, VULNERABILITY_REPORT, SUPPORT [GH5 L62–78]. A default `ISSUE_TEMPLATE` folder is ignored when the repo has its own [GH5 L35]. A license cannot be a default [GH5 L80].
- The default files "won't appear in the file browser or Git history of the individual repositories, and are not included in their clones" [GH5 L37]. So an agent working in a clone does not see them.
- Workflow templates in `.github/workflow-templates/` are documented for organizations and are offered once when a workflow is created [GH7]; nothing keeps the copy in step afterwards.
- **Without a human:** everything, for the file types above. **Human merge:** none. **Drift:** none (one file). **Cost per extra repo:** zero. **Not covered:** workflows, `AGENTS.md`, `docs/agents/`, skills, config files.

### Rulesets and required workflows

- "A ruleset is a named list of rules that applies to a repository or to multiple repositories in an organization for customers on {Team} and {Enterprise} plans"; rulesets across repositories are for "organizations on the {Enterprise} plan" [GH3 L17–23].
- "Require workflows to pass before merging" is configured "at the organization or enterprise level" [GH3b], and its feature flag is set only for `ghec` and `ghes` [GH4]. It is not available to a personal account on github.com.
- folke instead runs an hourly workflow in the hub that calls the REST API for every repo to set merge settings, branch protection and labels, with a PAT in `secrets.CLEANUP_TOKEN` [FG8; FG9 L94–130].
- **For the Core's account:** each plugin repo needs its own branch protection on `main` and `develop` with the five required checks (ADR-0017). **Cost per extra repo:** one REST call per branch (script) or a settings page by hand.

## 2. Agent setup (`AGENTS.md`, `CLAUDE.md`, `docs/agents/`, skills)

### Pull model: scheduled job in each repo (folke)

- Each repo's `update.yml` runs `cron: "0 * * * *"` and calls `folke/github/.github/workflows/update.yml@main` [FG2]. The composite action checks out the repo and the hub, runs `lua/github/build.lua` (renders `templates/` with per-repo values, skips files in a `keep` list when they exist), and opens one PR titled `chore(update): update repository` with `peter-evans/create-pull-request@v6` [FG3; FG10 L74–121]. `create-pull-request` updates the same branch on each run, so one PR stays open per repo.
- **Without a human:** detection and the PR, every hour. **Human merge:** each PR, in each repo. **Drift:** an open `chore(update)` PR; a file a repo edited by hand is overwritten on the next run unless it is in `keep`. **Cost per extra repo:** the caller `update.yml`, Actions permission to create PRs [GH9], and a token that makes CI run on the PR [GH8; CP1].

### Push model: one job in the hub (`repo-file-sync-action`)

- The hub's `.github/sync.yml` maps `owner/repo@branch` (or a group of repos) to files or folders, with `dest`, `exclude`, `replace: false`, `deleteOrphaned` and Nunjucks templates [RF1 L130–300]. It runs on push to the hub, creates "a pull request in the target repo so you have the last say on what gets merged", labels it `sync`, can assign users, and has `SKIP_PR` to push straight to the branch [RF1 L14–23, L107–128]. The `@branch` key lets the PR target `develop`.
- It needs `GH_PAT` with full `repo` scope or a GitHub App installation token; "`GITHUB_TOKEN` will **not** work" [RF1 L54–65].
- **Without a human:** PRs in every target repo on each hub change. **Human merge:** each PR (or none with `SKIP_PR`, which bypasses review and is blocked by branch protection that requires PRs). **Drift:** a hand edit in a target repo persists until the next hub change touches that file. **Cost per extra repo:** one line in `sync.yml` and the App installed on the repo; no workflow in the target repo.

### Skills via `skills-lock.json`

- This repo's `skills-lock.json` (version 1) lists each skill's `source` (`mattpocock/skills` or `a1exk-dev/agent-context`), `skillPath`, `computedHash`, and for `common-changelog` a `ref: develop`. The installed files are in `.agents/skills/`, with `.claude/skills/` entries as symlinks to them.
- `npx skills check` reports updates and "skills whose installed files differ from the content hash … (`has local changes`). It exits with code 1 when any skill has an update or local changes, so it can gate CI" [SK2 L176–186]. `npx skills update -y` runs without the scope prompt [SK2 L188–215]. Restore (`skills install` with no source) uses `--frozen-lockfile` by default in CI and fails when files do not match the lock [SK2 L382–420]. A source can be pinned with `owner/repo@v1.2.3` [SK2 L21–22]. A version 1 lock is upgraded to version 2 on read [SK1 L108].
- **Without a human:** a scheduled job can run `skills update -y` and open a PR with `create-pull-request`; a CI job can run `skills check` to flag drift. **Human merge:** the update PR. **Drift:** `skills check` fails, or `install --frozen-lockfile` fails. **Cost per extra repo:** the same lock file and one or two workflow jobs (or one caller of a shared reusable workflow).
- `a1exk-dev/agent-context` (public) already holds the operator's skills, `AGENTS.md`, `CLAUDE.md`, `GLOSSARY.md`, `MEMORY.md` and `docs/agents/*.md` policies (tree of `develop`, 2026-11-11). It is a candidate hub for the plain files too.

### Files that mix shared and local text (`AGENTS.md`)

- A whole-file copy overwrites each plugin's own lines. `agconf` (a small third-party CLI) splits `AGENTS.md` into a managed block between `<!-- agconf:global:start -->`/`end` and a local block that sync keeps, records the synced version in `.agconf/lockfile.json`, and checks on PRs, through a reusable workflow in the hub, that managed files were not edited [AC1]. folke solves the same need with per-repo values in `build.lua` (`M.props`) [FG10 L10–46].
- Claude Code also offers `@path` imports, so a shared file and a local file can be two files: `CLAUDE.md` imports a synced `docs/agents/shared.md` next to the plugin's own text [CC1].

### Dependabot / Renovate for non-package files

- Dependabot `github-actions` updates `uses:` refs of actions and reusable workflows [GH6]. Renovate's `github-actions` manager does the same and can keep a digest with a version comment [RN1]. A Renovate regex custom manager with the `git-refs` datasource can keep any SHA written in any file at the head of a branch [RN2; RN3]. Renovate's `git-submodules` manager bumps submodule commits [RN4].
- None of them copy file contents. They can bump a pin (for example a `docs/core/SOURCE` line with a Core SHA), and a workflow on that PR would still have to fetch the files.

### Template repo diffs (ADR-0013 `api-<N>` tags)

- ADR-0013 has each plugin apply `git diff api-<N-1> api-<N>` of the template by hand. Nothing runs without a human; drift shows only when a plugin's tests fail against a new Core (the weekly canary of ADR-0013). Cost per repo: one manual patch per `api` bump. The bots above could open these diffs as PRs, but contract changes touch plugin code, which no found bot rewrites.

## 3. Core domain (Core ADRs, `GLOSSARY.md`) as read-only reference

- **How agents find files.** Claude Code loads the `CLAUDE.md`/`AGENTS.md` files above the working directory at launch and a subdirectory's file when it reads a file there; `@path` imports load with the importing file, up to four hops [CC1 L64, L104–106, L148]. An import that resolves outside the working directory triggers an approval dialog once per project; if declined, it stays off [CC1 L136]. A `CLAUDE.md` that only names a file in words is read only "if it decides to open the file" [CC1 L439]. This repo's `docs/agents/domain.md` is the file every skill reads before it explores; today it names `GLOSSARY.md` and `docs/adr/`.
- **Copy in `docs/core/` (ADR-0013).** Offline, in every clone and worktree, at the commit the weekly PR recorded. Without a human: the weekly job. Human merge: each PR when the Core's ADRs or glossary changed. Drift: an open PR, or a copy older than the Core's `main`. Cost per repo: one workflow (or one caller) and the sync token. Agents need a line in the plugin's `docs/agents/domain.md` that names `docs/core/GLOSSARY.md` and `docs/core/adr/` as read-only, because no skill looks there by default.
- **Link to the Core on GitHub.** No copy, no PR, no drift in the files. But an agent reads it only by fetching a URL, which needs network and a decision to fetch, and it shows `main` at fetch time, which may be ahead of the Core release the plugin's `test/deps.lua` pins (ADR-0013).
- **Submodule or a fetch at test time.** A submodule pins a Core commit and Renovate can bump it [RN4]; the plugin's tests already clone the Core into a gitignored `.tests/` at a release tag (ADR-0013), so `.tests/codestyle.nvim/docs/adr/` exists after a test run but is gitignored, absent in a fresh clone, and the whole Core tree comes with it.

## 4. The one-repo alternative: several contexts in one repo

- **The skill's layout.** "If a `GLOSSARY-MAP.md` exists at the root, the repo has multiple contexts": root `docs/adr/` holds system-wide decisions, and each context folder has its own `GLOSSARY.md` and `docs/adr/` [DM1 L24–38]. The map lists each context, its path and a one-line purpose; the skill infers single or multi context from the files that exist [DM2 L32–58].
- **Who reads the map.** In this repo's installed skills, `GLOSSARY-MAP` appears only in `domain-modeling` and `wait-what` [DM3]. `tdd`, `pr` and `improve-codebase-architecture` tell the agent to read `GLOSSARY.md` and `docs/adr/` with no mention of the map. `docs/agents/domain.md` states "This is a single-context repo" and shows one root glossary. These skills come from `mattpocock/skills` and `a1exk-dev/agent-context` through the lock, so a local edit would show as drift in `skills check`; the repo-owned hook point is `docs/agents/domain.md`.
- **Per-folder instructions.** AGENTS.md: "Place another AGENTS.md inside each package. Agents automatically read the nearest file in the directory tree, so the closest one takes precedence"; "The closest AGENTS.md to the edited file wins" [AM1]. Claude Code loads a subdirectory's `CLAUDE.md`/`AGENTS.md` when it touches a file there, loads `.claude/rules/*.md` with a `paths:` list only for matching files, and `claudeMdExcludes` skips other folders' files [CC1 L148–150, L194–215, L336–349]. So `languages/php/AGENTS.md` could say "read `languages/php/GLOSSARY.md` and `languages/php/docs/adr/`, and the Core's root ones as read-only".
- **Keeping a change in one context.** These files are instructions, "context, not enforced configuration" [CC1]. The mechanical aids found are: commit scope = module (mini.nvim, mandatory; #96), CI path filters per folder (mini.nvim, nvim-treesitter; #96), and the `domain.md` rule to flag ADR conflicts. Nothing found blocks an agent from editing another context's files.
- **Without a human / merge / drift / cost.** No sync job and no sync PRs; process standards and agent setup exist once. Drift between contexts cannot happen for shared files; it can happen between a context's glossary and the map. Cost per extra context: one folder with `GLOSSARY.md`, `docs/adr/`, an optional `AGENTS.md`, and one line in `GLOSSARY-MAP.md`.

## Summary table

| Mechanism | Covers | Runs without a human | Human merge | Drift shows as | Cost per extra repo |
|---|---|---|---|---|---|
| Reusable workflow `@main` | CI and release logic | all runs | none | nothing (one source); a bad hub change fails all repos | 1 caller file per workflow |
| Reusable workflow `@tag`/SHA + Dependabot | same | bump PR | 1 PR per repo per bump | open Dependabot PR | caller files + `dependabot.yml` |
| `.github` repo defaults | community health files only | all | none | nothing | zero |
| Org rulesets / required workflows | required checks | all | none | nothing | not available to a personal account |
| Branch protection script (folke `repos.yml`) | settings, protection, labels | hourly API calls | none | overwritten each hour | none in the repo; PAT in the hub |
| Pull sync (folke `update.yml`) | any file, templated | hourly PR | 1 PR per repo per change | open `chore(update)` PR | caller file, Actions PR setting, CI token |
| Push sync (`repo-file-sync-action`) | any file, templated | PR on hub push | 1 PR per repo per change | open `sync` PR | 1 line in hub `sync.yml`, App install |
| `skills check` / `skills update -y` | skills | check in CI; update job + PR | update PR | `skills check` exit 1 | lock file + 1–2 jobs |
| Renovate regex / submodule | a pinned SHA | bump PR | 1 PR per repo per bump | open Renovate PR | `renovate.json` |
| `api-<N>` template diff | contract changes | nothing | manual patch | canary failure | 1 manual patch per bump |
| Monorepo + `GLOSSARY-MAP.md` | everything | n/a | none | map vs folders | 1 folder per context |

## Sources

Repos are cloned at the commit given; paths are relative to the repo root.

- [GH1] github/docs `b1faf75dbd3e7627ecdfaab5241b91953e308ddb` `content/actions/reference/workflows-and-actions/reusing-workflow-configurations.md` (<https://docs.github.com/en/actions/reference/workflows-and-actions/reusing-workflow-configurations>)
- [GH2] same, `data/reusables/actions/reusable-workflow-calling-syntax.md`, included in `content/actions/how-tos/reuse-automations/reuse-workflows.md`
- [GH3] same, `content/repositories/configuring-branches-and-merges-in-your-repository/managing-rulesets/about-rulesets.md`
- [GH3b] same, `content/repositories/configuring-branches-and-merges-in-your-repository/managing-rulesets/available-rules-for-rulesets.md` L279–293 and `data/reusables/repositories/rulest-workflows-intro-paragraph.md`
- [GH4] same, `data/features/repo-rules-required-workflows.yml` (`versions: ghec: '*', ghes: '>=3.12'`)
- [GH5] same, `content/communities/setting-up-your-project-for-healthy-contributions/creating-a-default-community-health-file.md`
- [GH6] same, `content/code-security/how-tos/secure-your-supply-chain/secure-your-dependencies/auto-update-actions.md` L24
- [GH7] same, `content/actions/how-tos/reuse-automations/create-workflow-templates.md` and reference [GH1] L122–139
- [GH8] same, `data/reusables/actions/actions-do-not-trigger-workflows.md` and `data/features/actions-github-token-pull-request-approval.yml` (`fpt`, `ghec`)
- [GH9] same, `content/repositories/managing-your-repositorys-settings-and-features/enabling-features-for-your-repository/managing-github-actions-settings-for-a-repository.md` L117; default off per `content/admin/enforcing-policies/enforcing-policies-for-your-enterprise/enforcing-policies-for-github-actions-in-your-enterprise.md` L276
- [FG1] folke/github `d1cb00f0473c256299c7b35b6e199559366e56bc` tree (`templates/`)
- [FG2] same, `templates/.github/workflows/update.yml`
- [FG3] same, `update/action.yml`, `.github/workflows/update.yml`
- [FG4] same, `.github/workflows/repos.yml`
- [FG5] same, `templates/.github/workflows/ci.yml`
- [FG6] same, `.github/workflows/ci.yml`
- [FG7] same, `templates/.github/dependabot.yml`
- [FG8] same, `.github/workflows/repos.yml`
- [FG9] same, `scripts/update.js`
- [FG10] same, `lua/github/build.lua`
- [RF1] BetaHuhn/repo-file-sync-action `8b92be3375cf1d1b0cd579af488a9255572e4619` `README.md`
- [CP1] peter-evans/create-pull-request `3ffccacd46053766916f087ce41d627c0b8cf2d1` `docs/concepts-guidelines.md` L139–161, L295–308
- [SK1] vercel-labs/skills `e781cb4d07433dfe1d19e924ed45cc61738c55ec` `README.md`
- [SK2] same, `docs/commands.md`
- [RN1] renovatebot/renovate `96edca7b402949385adc81db35df49eb387e345a` `lib/modules/manager/github-actions/readme.md`
- [RN2] same, `lib/modules/datasource/git-refs/readme.md`
- [RN3] same, `lib/modules/manager/custom/regex/readme.md`
- [RN4] same, `lib/modules/manager/git-submodules/readme.md`
- [AC1] agconf documentation, <https://julian-pani.github.io/agconf/> (read 2026-11-11; repo <https://github.com/julian-pani/agconf>, not cloned)
- [AM1] AGENTS.md site, <https://agents.md/> (read 2026-11-11), sections "Large monorepo?" and FAQ
- [CC1] Claude Code docs, "How Claude remembers your project", <https://code.claude.com/docs/en/memory> (read 2026-11-11; line numbers are of the fetched Markdown)
- [DM1] this repo, `.agents/skills/domain-modeling/SKILL.md` (`develop`, 2026-11-11)
- [DM2] this repo, `.agents/skills/domain-modeling/GLOSSARY-FORMAT.md`
- [DM3] this repo, `grep -rn GLOSSARY-MAP .agents/skills .claude/skills`, and `.claude/skills/{tdd,pr,improve-codebase-architecture}/SKILL.md`
- This repo: `skills-lock.json`, `docs/agents/domain.md`, `docs/adr/0013-plugins-start-from-a-template-repo-with-vendored-corpus-tests.md`, `.github/workflows/release.yml` (opens back-merge PRs with `github.token`, so those PRs are subject to [GH8])
- `a1exk-dev/agent-context` tree of `develop`, `gh api repos/a1exk-dev/agent-context/git/trees/develop?recursive=1` (2026-11-11)
