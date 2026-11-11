# How do Neovim plugin families with many language modules lay out their repos?

Research for issue [#96](https://github.com/a1exk-dev/codestyle.nvim/issues/96) (map: [#95](https://github.com/a1exk-dev/codestyle.nvim/issues/95)). It feeds [#98](https://github.com/a1exk-dev/codestyle.nvim/issues/98), which decides.
Question: how do Neovim plugin families with many language or extension modules lay out their repos, and why? For each family: one repo or many, how third-party extensions fit, how CI tests the parts, what maintainers say made them choose or switch, and how they keep many repos in step.

Date of research: 2026-11-11. Sources: shallow clones of each repo's default branch on that date (commit hashes in "Sources"), plus two GitHub issue pages. Line numbers are for these commits. The GitHub REST API was not used. Terms follow `GLOSSARY.md`: the **Core** is codestyle.nvim, a **Language Plugin** supplies one language. Candidates A/B/C are those of #95. This note gives facts and no design.

## Answer

- **Families that ship many per-language modules written by the maintainers keep them in one repo.** nvim-treesitter (322 query folders), nvim-lspconfig (426 configs), conform.nvim (265 formatters), nvim-lint (191 linters), LazyVim (49 language extras, 12 extra groups) and mini.nvim (46 modules) each have one development repo. No family in the sample keeps its own first-party language modules in one repo per language. This is layout B.
- **Families whose extensions are mostly third-party define a contract in the core repo and leave every extension in its own repo.** neotest (adapters), nvim-dap (adapter configs and extensions), telescope (extensions), nvim-cmp (sources). The core lists known extensions in its README or wiki, and does not test them. The few first-party extensions of these families (neotest-python, neotest-plenary, telescope-fzf-native) are also separate repos. This is layout A, but for an open ecosystem, not for a fixed first-party set.
- **Layout C (core repo + one bundle repo of first-party extras) exists, as a split for code the core no longer wants to own**: none-ls.nvim moved builtins out to `none-ls-extras.nvim` [NL1; NL2]. mason.nvim keeps its 608 package definitions in a separate `mason-registry` repo, which also lets users add their own registries [MA1 L121–125, L238–242].
- **Switches seen go from "everything in core" to "core + separate repos", never the other way**: none-ls (extras repo, 2024), telescope (no new builtin pickers, "package it up as its own Telescope extension"), nvim-treesitter (`main` is a full rewrite; textobjects and context are separate repos). blink.cmp went the other way relative to nvim-cmp at its start: it ships the core sources built in and names that as a difference from nvim-cmp.
- **mini.nvim is the one family with a monorepo plus per-module repos.** All development, issues and PRs are in `mini.nvim`. Each module's standalone repo is a read-only mirror, produced by hand with `git format-patch` + `git am` scripts, and tagged by script on release [MI1; MI2; MI3]. The mirrors have no CI and no `.github` folder.
- **CI in monorepos tests every module in one job.** Per-module test files exist (mini.nvim `tests/test_<module>.lua`, nvim-treesitter `tests/indent/<lang>_spec.lua`, nvim-lint `spec/<linter>_spec.lua`, LazyVim one spec that loops over every extra), but the workflow runs all of them on every PR. mini.nvim skips tests when no code path changed. Core-plus-extension families do not test the extensions in core CI. The one cross-repo check found is nvim-treesitter's `downstream.yml`, which lints the queries of its sibling repos when the parser list changes.
- **Multi-repo families keep repos in step with shared workflows and template files, not with shared code.** folke's 21 repos (LazyVim, lazy.nvim, snacks.nvim and others) call reusable workflows from `folke/github`, and an hourly job in each repo copies template files from `folke/github` and opens a PR [FG1; FG2; FG3]. mini.nvim syncs by patch scripts. Everything else found is a README or wiki list.

## Family by family

### mini.nvim — monorepo plus standalone mirror repos

- **Layout.** One repo, 46 modules (`lua/mini/<module>.lua`, `doc/mini-<module>.txt`, `readmes/mini-<module>.md`, `tests/test_<module>.lua`). "Every module is also distributed as a standalone Git repository" [MI1 L88]. "Each module can be used separately without any startup and usage overhead" [MI1 L7].
- **How mirrors are produced** [MI2 L82–100; MI3]:
  - "All development takes place in 'mini.nvim' while being synced to standalone ones. This is done by having special `sync` branch which points to the latest commit which was synced to standalone repositories."
  - `make dual_sync` runs, for each module, `git format-patch sync..HEAD --output <patch> -- lua/mini/<m>.lua doc/mini-<m>.txt readmes/mini-<m>.md LICENSE <extra paths>` [MI3 L26–31]. It rewrites `readmes/mini-<m>.md` to `README.md` in the patch with `sed` [MI3 L47–52], clones the mirror if needed and applies the patch with `git am` [MI3 L54–68]. Extra paths per module are listed by hand, for example the colour schemes of `base16` and `hues` [MI3 L74, L92].
  - "If some commit touches files from several modules, it results into commits for every affected standalone repository" [MI2 L96]. `make dual_push` pushes the mirrors and moves `sync` [MI2 L97–100].
  - The maintainer runs this by hand after CI passes on `main` [MI2 L86–89, L113–116].
  - Release: `dual_release.sh` moves `stable` to `main` in every mirror and puts the same annotated tag on each [MI4 L36–52].
- **Third parties.** Not applicable: the modules are closed. Each mirror README says "All contributions (issues, pull requests, discussions, etc.) are done inside of 'mini.nvim'" [MI5 L18]. The mirror `mini.ai` has only `doc/`, `lua/`, `LICENSE` and `README.md`.
- **CI.** One workflow, `quality-control.yml`. It skips `sync` and `stable` branches. A path filter runs tests only when `colors/`, `lua/`, `tests/`, `scripts/minimal_init.lua` or workflows change. The matrix is Neovim 0.10, 0.11, 0.12 and nightly on Linux, plus Windows on 0.12, and runs `make test`, which runs all modules [MI6 L3–60; MI7]. `make test_<module>` runs one module locally [MI7]. Commit scope is mandatory and is the module name, or `ALL` [MI8 L44].
- **Stated reason.** No written rationale for the mirrors was found in the repo beyond "can be used separately".

### nvim-treesitter — all languages in one repo, parsers upstream

- **Layout.** One repo: `lua/nvim-treesitter/parsers.lua` lists each parser (URL, `revision`, `tier`), and `runtime/queries/<lang>/*.scm` holds 322 languages' queries [TS1 L32–76]. The parser code itself lives in each grammar's own upstream repo, pinned by revision.
- **Third parties.** A new language is a PR to this repo with a parser that meets listed criteria: maintained, on GitHub, covered by CI with upstream workflows, with reference queries [TS1 L17–30]. Each language has a tier: stable (follows semver releases), unstable (follows HEAD), unmaintained, unsupported [TS2 L6].
- **CI.** One `Tests` workflow on PRs to `main` builds parsers and checks queries [TS3]. Indent tests are per language in `tests/indent/<lang>_spec.lua`. A weekly bot opens a PR per tier that bumps parser revisions; tier 2 PRs auto-merge [TS4 L1–60].
- **Sibling repos.** `nvim-treesitter-textobjects` and `nvim-treesitter-context` are separate repos in the same org. `downstream.yml` runs on PRs that change `parsers.lua`, sparse-clones the `queries` folder of both, and runs `ts_query_ls check` on them [TS5 L1–60].
- **Switch.** The `main` branch "is a full, incompatible, rewrite"; `master` "is locked but will remain available for backward compatibility with Nvim 0.11" [TS6 L13].

### conform.nvim and nvim-lint — every tool definition in one repo

- **Layout.** conform: one file per formatter in `lua/conform/formatters/` (265). nvim-lint: one file per linter in `lua/lint/linters/` (191). Each file is a small table (command, args, parser).
- **Third parties.** Users register their own in config. nvim-lint: "You can register custom linters by adding them to the `linters` table, but please consider contributing a linter if it is missing" [NLI L330–332]. Its rules: no project-root logic, no complex pre-processing, no generative AI, "Tests are optional for linter additions"; PRs go to Codeberg, "Github is only a mirror" [NLI L334–349].
- **CI.** conform: luacheck, typecheck, StyLua and one test job; per-formatter tests are almost absent (`tests/formatters/` holds only `prettierd_spec.lua`); a workflow requests review from the maintainer on each PR [CF1; CF2]. nvim-lint: `luarocks test` on nightly and 0.9.5; 65 spec files, mostly one per linter parser [NLI2].

### nvim-lspconfig — 426 configs in one repo

- One `lsp/<name>.lua` per server. "These configs are **best-effort and supported by the community (you)**" [LC1 L23]. New configs need evidence of popularity (100 stars or similar) "to avoid spam/quasi-marketing/vanity projects" [LC2 L20–31]. One `vusted ./test` job tests the framework, not each config [LC3].

### neotest and adapters — core contract, every adapter in its own repo

- **Layout.** The core defines the adapter interface (`lua/neotest/adapters/interface.lua`) and helpers under `neotest.lib`; the README has a "Writing Adapters" guide [NT1 L274–287]. The README table lists 47 test runners; 3 adapter links are in the `nvim-neotest` org (neotest-python twice, neotest-plenary), the rest are third-party repos [NT1 L86–134]. The user lists adapters in `setup({ adapters = … })` [NT1 L141–145].
- **CI.** The core workflow installs plenary, nvim-treesitter and nvim-nio, runs the core unit tests and semantic-release; no adapter is tested [NT2 L43–83]. The first-party `neotest-python` repo has no `.github` folder, so no CI.
- **Keeping in step.** Only the README table and the interface file.

### nvim-dap — core client only, adapters and extensions elsewhere

- Per-language debug adapter configs are not in the repo: "See the Debug-Adapter Installation wiki"; "The Wiki is community maintained" [ND1 L30–34, L85–86]. "All known extensions are listed in the Wiki" [ND1 L105–107]. Non-goals: adapter installation ("It's not the business of an editor plugin to re-invent a package manager") and an "nvim-dapconfig" bundle of configs [ND1 L111–115]. Extensions such as nvim-dap-ui (rcarriga) and nvim-dap-python are separate repos. CI runs on Woodpecker with specs for the core only (`spec/`).

### telescope.nvim and extensions — closed core, open extensions

- Extensions are found on the runtimepath as `lua/telescope/_extensions/<name>.lua` ("The underscore is significant") and loaded by `load_extension` [TE1 L285–300; TE2 L521–531]. This is the same discovery mechanism as ADR-0007.
- "At this time, we are content with the number and functionality of the pickers we offer built in with Telescope and so we are currently not accepting new pickers … we encourage packaging it up as its own Telescope extension" [TE3 L6–12]. Community extensions are listed in the wiki [TE2 L516–517]. The first-party `telescope-fzf-native.nvim` (C, `build = 'make'`) is a separate repo in the `nvim-telescope` org [TE2 L61, L80].

### nvim-cmp sources and blink.cmp — external sources versus built-in sources

- nvim-cmp: "Completion sources are installed from external repositories and 'sourced'" [CM1 L4]. More sources are found through the wiki and the `nvim-cmp` GitHub topic [CM1 L147–149]. Even basic sources (cmp-buffer, cmp-nvim-lsp, cmp-path) are separate repos.
- blink.cmp: "The `lsp`, `path`, `snippets`, `buffer`, and `omni` sources are built-in. You may add additional community sources" [BL1 L9]. It lists this as a difference: "Core sources (buffer, snippets, path, lsp) are built-in versus nvim-cmp's exclusively external sources" [BL2 L38]. nvim-cmp sources run through the separate `blink.compat` repo [BL2 L14].

### LazyVim extras — all extras in one repo

- 49 language extras in `lua/lazyvim/plugins/extras/lang/`, among other extra groups. Contributors must know the language's ecosystem, and "Every language extra requires a `recommended` section" [LV1 L18–31]. Extra requests go to a Discussions category, not issues [FG3 L12–26].
- CI: one spec, `tests/extras/extra_spec.lua`, loops over every extra file and checks that its spec is valid and that its Mason packages and parsers exist [LV2 L16–60]. A PR labeler adds `extras` / `extras-lang` labels by path [LV3].

### none-ls.nvim → none-ls-extras.nvim — a split out of the core

- Issue #58 (2024-01-11, maintainer mochaaP), "Deprecating builtins with unmaintained upstream or native LSP replacement". Criteria: "Unmaintained (> 1y) or deprecated by upstream", "Fully overlapped feature", "Native LSP available". Reasons: "The removals are mostly due to the overhead on executing binaries" and "I mind the quality of this project." Some removed builtins went to `none-ls-extras.nvim` [NL1].
- `none-ls-extras.nvim` is "Extra sources for none-ls.nvim", installed as a dependency of none-ls; its sources load by `require("none-ls.<method>.<tool>")` [NL2 L1–49]. Its README also lists single-tool third-party repos (`none-ls-php.nvim`, `none-ls-shellcheck.nvim` and others) and a `none-ls-sources` GitHub topic [NL2 L51–62]. Its only workflow is a LuaRocks upload.

### mason.nvim → mason-registry — data repo apart from the core

- "Mason's core package registry is located at mason-org/mason-registry"; it is downloaded at runtime, and `registries` accepts several entries [MA1 L121–125, L238–242]. The registry has one `packages/<name>/package.yaml` per package (608), Renovate, and a `package-tests.yaml` workflow that tests changed packages on PRs [MR1]. Version 2.0 added "Official support for custom registries" [MA2 L97].

### Keeping many repos in step: folke/github

- `folke/github` holds reusable workflows (`ci.yml`, `pr.yml`, `labeler.yml`, `update.yml`) and `templates/` (`.editorconfig`, `stylua.toml`, `selene.toml`, `LICENSE`, `tests/minit.lua`, …) [FG1].
- Each repo's `update.yml` runs every hour and calls the reusable `update.yml`, whose action checks out `folke/github`, runs `lua/github/build.lua` against the repo, and opens a `chore(update): update repository` PR with `peter-evans/create-pull-request` [FG4; FG2 L1–26]. `build.lua` has per-repo overrides (for example LazyVim's issue-form text) [FG3 L1–50]. `scripts/repos.sh` lists the 21 repos covered [FG5].
- The reusable `ci.yml` enables tests, docs and build jobs only when the repo has `scripts/test`, `scripts/docs` or `scripts/build` [FG6 L26–39].

## Summary table

| Family | First-party modules | Repos | Third-party fit | CI of the parts |
|---|---|---|---|---|
| mini.nvim | 46 modules | 1 dev repo + 46 read-only mirrors | none (closed set) | all modules in one job; mirrors no CI |
| nvim-treesitter | 322 languages' queries | 1 (+ upstream parser repos) | PR to the one repo, tier per language | one workflow; downstream query check of 2 sibling repos |
| conform.nvim | 265 formatters | 1 | user config or PR | one job; almost no per-formatter tests |
| nvim-lint | 191 linters | 1 (Codeberg; GitHub mirror) | user config or PR | `luarocks test`, optional per-linter spec |
| nvim-lspconfig | 426 configs | 1 | PR with popularity evidence | framework tests only |
| LazyVim | 49 language extras | 1 | PR; requests in Discussions | one spec loops over all extras |
| neotest | 2 adapters (python, plenary) | 1 per adapter | own repo, README table | core only; neotest-python has no CI |
| nvim-dap | none in core | 1 per extension | own repo, wiki list | core only |
| telescope | fzf-native | 1 per extension | own repo, wiki list | core only |
| nvim-cmp | buffer, lsp, path, … | 1 per source | own repo, wiki + topic | core only |
| blink.cmp | 5 built-in sources | 1 (+ blink.compat) | own repo, docs list | one repo |
| none-ls | builtins + extras | core + 1 extras bundle | own repo, topic | extras: LuaRocks upload only |
| mason | 608 package specs | core + 1 registry repo | custom registries | registry: tests changed packages |

## Sources

Repos are cloned at the commit given; paths are relative to the repo root.

- [MI1] nvim-mini/mini.nvim `f9ac12d7cbd2563cfc2cce9a8152fc8df2ad0d6f` `README.md`
- [MI2] same, `MAINTAINING.md`
- [MI3] same, `scripts/dual_sync.sh`
- [MI4] same, `scripts/dual_release.sh`
- [MI5] nvim-mini/mini.ai `98a5d73937930a2bb08129020601ab8d5016d706` `README.md`
- [MI6] mini.nvim, `.github/workflows/quality-control.yml`
- [MI7] mini.nvim, `Makefile`
- [MI8] mini.nvim, `CONTRIBUTING.md`
- [TS1] nvim-treesitter/nvim-treesitter `19bdfc04f40ed2ccb3340591d125f759b0406875` `CONTRIBUTING.md`
- [TS2] same, `SUPPORTED_LANGUAGES.md`
- [TS3] same, `.github/workflows/test-queries.yml`
- [TS4] same, `.github/workflows/update-parsers.yml`
- [TS5] same, `.github/workflows/downstream.yml`
- [TS6] same, `README.md`
- [CF1] stevearc/conform.nvim `016802de402556da54c36bd7359b441266b01cdd` `.github/workflows/tests.yml`
- [CF2] same, `.github/workflows/automation_request_review.yml`
- [NLI] mfussenegger/nvim-lint `52107ce2076a27a285af781248e2c59bad817cd0` `README.md`
- [NLI2] same, `.github/workflows/tests.yml`
- [LC1] neovim/nvim-lspconfig `443d92c6bea761ab54cdde46fb197a2b4d614bdd` `README.md`
- [LC2] same, `CONTRIBUTING.md`
- [LC3] same, `.github/workflows/test.yml`
- [NT1] nvim-neotest/neotest `27bf921498043f7ecd821d6db68d05de244bbd02` `README.md`
- [NT2] same, `.github/workflows/workflow.yaml`
- nvim-neotest/neotest-python `1b56ca4ba51c6014f986d6548ee629bdc95589d1` (tree: no `.github`)
- [ND1] mfussenegger/nvim-dap `cfa2d58f4537aca6ca83e2de1a0d9f1491121264` `README.md`, `.woodpecker.yaml`
- [TE1] nvim-telescope/telescope.nvim `1e1bab730218eaf97fce743be3f56e51075928ac` `developers.md`
- [TE2] same, `README.md`
- [TE3] same, `CONTRIBUTING.md`
- [CM1] hrsh7th/nvim-cmp `fe29aba4117227a6df637bc41e4b4fb4e98864a0` `README.md`
- [BL1] Saghen/blink.cmp `7b31e1b6497be70f620bbad83a789929248697ac` `doc/configuration/sources.md`
- [BL2] same, `doc/index.md`
- [LV1] LazyVim/LazyVim `5c26fac21fd3896024a23f2dbc62b722f9a731db` `CONTRIBUTING.md`
- [LV2] same, `tests/extras/extra_spec.lua`
- [LV3] same, `.github/labeler.yml`, `.github/workflows/{ci,update,pr,labeler}.yml`
- [NL1] nvimtools/none-ls.nvim issue #58, <https://github.com/nvimtools/none-ls.nvim/issues/58> (read 2026-11-11; later converted to Discussion #81)
- [NL2] nvimtools/none-ls-extras.nvim `9a8b8a9aeb43382e5aaf49b00b7cfb5d42d32118` `README.md`
- [MA1] mason-org/mason.nvim `2a6940af80375532e5e9e7c1f2fc6319a1b7a69d` `README.md`
- [MA2] same, `CHANGELOG.md`
- [MR1] mason-org/mason-registry `78bb34ab3c23fbedc7a24ec5f7bcc342b23fb266` `packages/`, `.github/workflows/package-tests.yaml`
- [FG1] folke/github `d1cb00f0473c256299c7b35b6e199559366e56bc` tree (`templates/`, `.github/workflows/`)
- [FG2] same, `update/action.yml`
- [FG3] same, `lua/github/build.lua`
- [FG4] same, `.github/workflows/update.yml`
- [FG5] same, `scripts/repos.sh`
- [FG6] same, `.github/workflows/ci.yml`
