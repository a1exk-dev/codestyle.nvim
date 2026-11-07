# How do popular Neovim plugins tag and release, and do they ship 0.x releases before 1.0?

Research for issue [#91](https://github.com/a1exk-dev/codestyle.nvim/issues/91) (map: [#83](https://github.com/a1exk-dev/codestyle.nvim/issues/83)). It feeds [#89](https://github.com/a1exk-dev/codestyle.nvim/issues/89), which decides.
Question: how do popular Neovim plugins make tags, GitHub releases and changelogs (release-please, semantic-release or by hand)? Do they ship 0.x before 1.0, and for how long? How do lazy.nvim's `version` and `vim.pack`'s `version` pick a tag? How do plugin families version a core and its extensions?

Date of research: 2026-11-07. Sources: GitHub API data (tags, releases, workflows) read on that date, plus the source of lazy.nvim `306a055` (v11.17.5), Neovim `v0.12.6`, release-please `ea20bc2` (v17.11.2), release-please-action `0b6b3fc` (v5.0.0) and semantic-release `04c1923`. Full hashes are in "Sources". Line numbers are for these versions. A tag date is the committer date of the tagged commit. Terms follow `GLOSSARY.md`: the **Core** is codestyle.nvim, a **Language Plugin** is one `codestyle-<id>.nvim` repo. ADR-0009 makes Core 1.0 wait for all sixteen Language Plugins. This note gives facts and no design.

## Answer

- **Three ways to release are common. The tool decides the first version.**
  - *release-please* (a bot release PR, merged by a human): folke's plugins (lazy.nvim, snacks.nvim, noice.nvim, which-key.nvim, trouble.nvim) through one shared workflow, conform.nvim, oil.nvim, gitsigns.nvim, mason.nvim, rocks.nvim, nvim-cmp (since 2026-01), neotest-golang and mason-nvim-dap [FG1 L192–227; LZ1; CF; OI; GS1; GS2; MA1; RK; CMP1; NG; MND].
  - *semantic-release* (a release on every push to the default branch that has a `feat`/`fix` commit, no PR): neotest, nvim-nio, nvim-dap-ui [NT1 L64–83; NT2; DUI].
  - *Hand-made tags*: nvim-lspconfig, telescope.nvim and blink.cmp push a tag, and a workflow reacts to it (luarocks upload, or binaries and a GitHub release) [LSP1 L215–221; LSP2; TS2; BL1 L3–6, L187–196]. nvim-dap and mini.nvim tag and write releases fully by hand [MI2 L289–319]. nvim-treesitter has tags and no GitHub releases.
- **Conventional Commits are a hard input for both tools.** release-please "assumes you are using Conventional Commit messages": `fix:` → patch, `feat:` → minor, `!` or `BREAKING CHANGE` → major [RP1 L12, L45–53]. It works with squash merges and with merge commits, but its "override release notes" feature needs squash merges [RP1 L25–27, L55–57, L136–138]. semantic-release uses the Angular convention by default, and `BREAKING CHANGE:` must be in the footer [SR1 L50–64]. folke checks every PR title with `amannn/action-semantic-pull-request` (scope required, lower-case subject) [FG2 L11–15]. A `Release-As: x.y.z` footer forces the next release-please version [RP1 L106–115].
- **0.x before 1.0 depends mostly on the tool, not on the plugin's maturity.**
  - release-please makes **1.0.0** as the first release when the repo has no release yet, unless `initial-version` or the manifest says otherwise [RP3 L756–761]. semantic-release's `FIRST_RELEASE` is `"1.0.0"` [SR2 L3]. That is why all five folke plugins, conform, oil, rocks.nvim, mason, neotest, nvim-nio, blink.compat and mason-nvim-dap have **no 0.x tag**: their first tag is `v1.0.0` (table below).
  - Plugins with hand-made tags, or with tags from before their tool, started at 0.x. Some left 0.x and some never did. They left after 2 months (neotest-golang), 5.5 months (blink.cmp), 14 months (nvim-dap-ui), 2 years 8 months (nvim-lspconfig) and 3 years 8 months (gitsigns). After 4–5 years these are still on 0.x: telescope (`v0.2.2`), nvim-dap (`0.10.0`), mini.nvim (`v0.18.0`), nvim-treesitter (`v0.10.0`) and nvim-cmp (`v0.0.2`).
  - Plugins that leave 0.x through a tool make many majors later: lazy.nvim is at v11 after 3 years, conform at v9, neotest at v5 and noice at v4.
- **release-please handles 0.x with two settings** [RP2 L173–179]: `bump-minor-pre-major` ("BREAKING CHANGE only bumps semver minor if version < 1.0.0") and `bump-patch-for-minor-pre-major` ("feat commits bump semver patch instead of minor"). Both are off by default. gitsigns turned on `bump-minor-pre-major` while it was on 0.x [GS1 L5]. Leaving 0.x needs `release-as: "1.0.0"` or a `Release-As:` footer [RP2 L165–171; RP1 L106]. Pre-release versions (`1.0.0-beta.1`) need the `prerelease` versioning strategy and `prerelease: true` [RP2 L181–182, L202–210; RP4 L47]. The `simple` release type that all these plugins use writes `CHANGELOG.md` and `version.txt` [RP5 L22–53]. Lines marked `x-release-please-version` / `-major` / `-minor` / `-patch` in `extra-files` get the new version [RP4 L174–188]. lazy.nvim, snacks.nvim and mason.nvim use them to keep a Lua version constant [LZ2 L245; SN1 L15; MA2 L3–6].
- **Changelogs and release notes follow the tool.**
  - release-please: a generated `CHANGELOG.md`, plus a GitHub release whose body is the same entry. Seen in lazy.nvim, snacks, noice, which-key, trouble, conform, oil, gitsigns, mason, rocks [survey table].
  - semantic-release with only `commit-analyzer`, `release-notes-generator` and `github`: a GitHub release body and **no** `CHANGELOG.md` (neotest, nvim-dap-ui) [NT2; DUI].
  - Hand-made: telescope and nvim-lspconfig have no `CHANGELOG.md`. Their maintainers publish GitHub releases with GitHub's generated "What's Changed" list, sometimes with a written summary first. nvim-dap writes its notes by hand and has no `CHANGELOG.md`. mini.nvim keeps a hand-written `CHANGELOG.md` and copies the version's section into the GitHub release [MI2 L304, L314]. blink.cmp commits `chore: bump version to X` with a `CHANGELOG.md` in conventional-changelog format, then its tag workflow makes the release [BL1 L187–196].
  - Release-please users often move a floating tag on each release: `stable` (folke, conform, oil, mason) or `release` (gitsigns) [FG1 L218–227; CF L119–123; MA1 L28–33; GS2 L35–41]. lazy.nvim and `vim.pack` ignore these tags as versions, because they are not semver (below).
- **Many plugins never tag.** These have no tag at all: neotest-python, neotest-jest, nvim-dap-python, nvim-dap-virtual-text, telescope-fzf-native, telescope-ui-select, cmp-nvim-lsp, cmp-buffer and blink.lib. nvim-lint has only `nvim-05`, and lualine has only `compat-nvim-0.5` / `compat-nvim-0.6`. These are pins for old Neovim versions, not releases. conform keeps `nvim-0.8` / `nvim-0.9` branches for the same purpose [CF README L33]. telescope had `nvim-0.5.0`-style tags and a `0.1.x` branch.
- **lazy.nvim `version`** [LZ3; LZ4; LZ2 L9–16; LZD1]:
  - Order: `commit` beats `tag`. Then `version`, but only when it is not `false`. If the spec sets neither `version` nor `branch`, `defaults.version` is used. If no tag matches, the HEAD of the branch is used, which is the remote default branch unless `branch` is set [LZ4 L118–154].
  - **The default `defaults.version` is `nil`, which means the latest commit.** The config comment says: "It's recommended to leave version=false for now, since a lot the plugin that support versioning, have outdated releases" [LZ2 L13–16]. The LazyVim starter sets `version = false` with the same comment [LVS L28–31].
  - **`'*'` is the range `>=0.0.0` with no upper bound, so it matches 0.x tags** [LZ3 L132–135]. Example: telescope's README recommends `version = '*'`, and all its tags are 0.x [TS1 L70–83].
  - **Pre-releases are excluded unless the range itself names a pre-release.** `matches` rejects a version whose `prerelease` differs from the range's `from.prerelease` [LZ3 L124–126]. The docs say "`*`: latest stable version (this excludes pre-release versions)" [LZD1 L17].
  - Tags parse with `^v?(%d+)%.?(%d*)%.?(%d*)…`, so `v0.7` is read as 0.7.0, `0.1.8` (no `v`) works, and `stable` or `nvim-0.6` are ignored [LZ3 L86]. Checked by running lazy.nvim's `semver.lua` (scratch test): with tags `v0.1.0 0.2.5 v1.0.0-rc.1 v1.0.0 v1.4.2 v2.0.0-beta.1 stable`, `*` and `1.*` pick `v1.4.2`, and `^0.2` and `0.2` pick `0.2.5`.
  - `^0.2.3` → `<0.3.0`, `^0.0.3` → `<0.0.4`, `1.*` / `1.x` / `1` → `<2.0.0` [LZ3 L151–189].
  - The parser's modifier set is `[%^=>~]`. So the `<1.2.3` and `<=1.2.3` examples in the docs [LZD1 L23–24] do not parse: `Semver.range('<1.2.3')` returns `nil` (scratch test) [LZ3 L151].
  - **No tags, or no tag in range: lazy.nvim silently falls back to the branch HEAD**, with no error [LZ4 L141–153]. Tags come with the clone, and every fetch runs `git fetch --tags --force` [LZ5 L287–288].
- **`vim.pack` (Neovim 0.12) `version`** [NP1; NP2]:
  - `nil` (default) → the remote's default branch. A string → a branch, tag or commit; anything else is an error that lists the tags and branches. A `vim.version.range()` → "the greatest/last semver tag inside the version constraint" [NP2 L374–378, L607–654; NP1 L411–417].
  - It expects tags "following semver convention `v<major>.<minor>.<patch>` (with or without `v` prefix)" [NP1 L221–223]. Tags are parsed with `vim.version.parse(x, { strict = true })` [NP2 L261–263, L592–603], so `v0.7` and `v0.8.5.1` are ignored (scratch test). The lockfile revision wins over `version` on install [NP2 L717–718; NP1 L226–235].
  - **`vim.version.range('*')` matches 0.x tags**: it is `from = 0.0.0` with no upper bound [NV1 L291–294].
  - **Unlike lazy.nvim, it also matches pre-releases.** `VersionRange:has` has no pre-release filter [NV1 L257–272], although the doc comment says "suffixed versions (1.2.3-rc1) are not matched" [NV1 L22–23]. End-to-end test on Neovim 0.12.6, with a local repo tagged `v0.1.0 v0.9.0 v1.0.0 v1.4.2 v2.0.0-beta.1`: `range('*')` **and `range('1.*')`** installed `v2.0.0-beta.1`, because `2.0.0-beta.1 < 2.0.0`. `range('^0.9')` installed `v0.9.0`, and `range('0.1')` installed `v0.1.0`.
  - **No tag in range is an error**, not a fallback: "No versions fit constraint. Relax it or switch to branch." [NP2 L646–653]. This was reproduced with an untagged repo and `range('*')`. With no `version`, the same tagged repo installed `main` HEAD.
- **Families mostly version the core and the extensions independently, with no declared compatibility range.**
  - *neotest*: core on semantic-release (v5.20.0), nvim-nio on semantic-release (v1.10.1). The first-party adapters neotest-python and neotest-jest have **no tags**. The third-party neotest-golang uses release-please (0.1.0 → 2.10.0). The luarocks upload lists `nvim-nio` with no version bound [NT1 L85–102].
  - *nvim-dap*: core with hand-made 0.x tags. nvim-dap-ui on semantic-release (v4.0.0). nvim-dap-python and nvim-dap-virtual-text are untagged. mason-nvim-dap uses release-please (v2.5.2). nvim-dap-python's rockspec depends on `'nvim-dap'` with no version [DPY L19–22].
  - *telescope*: core with hand-made 0.x tags. The first-party extensions telescope-fzf-native and telescope-ui-select are untagged. The tree has no version module.
  - *nvim-cmp*: core with `v0.0.2`. The sources (cmp-nvim-lsp, cmp-buffer) are untagged.
  - *blink*: blink.cmp has tags; blink.lib (a v2 dependency) is untagged; blink.compat has its own tags (v2.5.0). blink.cmp's prebuilt Rust binary is chosen by `git describe --tags --exact-match`. Off a tag, it fails and tells the user to set `version = '1.*'` [BL2 L22–51; BL3 L73–91]. The README tells v1 users to set `branch = 'v1'` or `version = "1.*"` because v2 is breaking [BL4 L2].
  - *mini.nvim* is the one **lockstep** family. All code lives in `mini.nvim`. A `sync` branch and `make dual_sync`/`dual_push` push patches to the standalone mirrors (`mini.ai` and others). On release, `dual_release.sh` puts the same `v0.xx.0` tag on every mirror, and a `stable` branch is moved to the tag [MI2 L82–100, L311–319]. `mini.ai`'s tags run `v0.6.0`…`v0.18.0`, the same as mini.nvim's from the module's start. The README offers `main` (recommended) or `stable`, and `version = '*'` or `false` for lazy.nvim [MI1 L31–34, L50, L79–85].
  - *Explicit compatibility declaration, the one found*: mason-lspconfig's README says `mason.nvim >= 2.0.0` and `nvim-lspconfig >= 2.0.0` [MLC1 L54–56]. Its `:checkhealth` does `require("mason.version")` and errors unless `MAJOR_VERSION == 2` [MLC2 L12–17]. mason.nvim keeps that module current through release-please `x-release-please-major` markers [MA2 L3–6; MA1 L22–24].
  - LazyVim pins per plugin (`version = not vim.g.lazyvim_blink_main and "*"` for blink) and leaves the global default at `false` [LV L17; LVS L30].

## Release survey

`0.x tags` counts tags starting with `0.` or `v0.`. "First tag" is the lowest semver tag. Data from `gh api repos/<r>/tags` and `/releases` on 2026-11-07.

| Repo | Created | Release tool | First tag (date) | 1.0.0 (date) | Latest | 0.x tags | GitHub releases | CHANGELOG.md |
|---|---|---|---|---|---|---|---|---|
| folke/lazy.nvim | 2022-11-20 | release-please (folke/github) | v1.0.0 (2022-11-29) | 2022-11-29 | v11.17.5 | 0 | 205, bot | generated |
| folke/snacks.nvim | 2024-11-02 | release-please (folke/github) | v1.0.0 (2024-11-06) | 2024-11-06 | v2.31.0 | 0 | 35, bot | generated |
| folke/noice.nvim | 2022-09-21 | release-please (folke/github) | v1.0.0 (2022-11-13) | 2022-11-13 | v4.10.0 | 0 | 104 | generated |
| folke/which-key.nvim | 2021-04-28 | release-please (folke/github) | v1.0.0 (2023-01-04) | 2023-01-04 | v3.17.0 | 0 | 43 | generated |
| folke/trouble.nvim | 2021-04-21 | release-please (folke/github) | v1.0.0 (2023-01-04) | 2023-01-04 | v3.7.1 | 0 | 34 | generated |
| stevearc/conform.nvim | 2023-08-25 | release-please | v1.0.0 (2023-08-26) | 2023-08-26 | v9.1.0 | 0 | 46, bot | generated |
| stevearc/oil.nvim | 2022-12-15 | release-please | v1.0.0 (2023-06-27) | 2023-06-27 | v2.16.0 | 0 | 24 | generated |
| lumen-oss/rocks.nvim | 2023-07-05 | release-please | v1.0.0 (2023-11-20) | 2023-11-20 | v2.49.1 | 0 | 110 | generated |
| mason-org/mason.nvim | 2022-07-06 | release-please (v3 action) | v1.0.0 (2023-04-26) | 2023-04-26 | v2.3.1 (+ `v2.0.0-rc.1/2`, marked pre-release) | 0 | 30 | generated |
| lewis6991/gitsigns.nvim | 2020-10-18 | hand tags, then release-please from 2024-04-17 | v0.1 (2021-05-27) | 2025-02-07 | v2.1.0 | 11 | 15 | generated |
| hrsh7th/nvim-cmp | 2021-06-29 | hand tags; release-please since 2026-01-02, its PR "release 0.1.0" (#2211) still open | v0.0.1 (2022-08-14) | — | v0.0.2 | 2 | 2, hand | none |
| nvim-neotest/neotest | 2022-01-02 | semantic-release | v1.0.0 (2022-06-11) | 2022-06-11 | v5.20.0 | 0 | 183, bot | none |
| rcarriga/nvim-dap-ui | 2021-03-18 | semantic-release (from `v0.0.0`, 2021-04-10) | v0.0.0 (2021-04-10) | 2022-06-18 | v4.0.0 | 76 | 124, bot | none |
| neovim/nvim-lspconfig | 2019-11-13 | hand tags → luarocks workflow | v0.1.0 (2021-12-23) | 2024-09-10 | v2.12.0 | 10 | 24, hand, generated "What's Changed" | none |
| nvim-telescope/telescope.nvim | 2020-07-15 | hand tags → luarocks workflow | 0.1.0 (2022-07-12) | — | v0.2.2 (2026-02-16) | 13 | 12, hand | none |
| saghen/blink.cmp | 2024-07-31 | hand tags → build + `action-gh-release` | v0.1.0 (2024-10-05) | 2025-03-25 | v1.10.2 | 38 | 56, bot | conventional-changelog format, committed by hand |
| mfussenegger/nvim-dap | 2020-04-14 | by hand, no workflows | 0.1.0 (2022-07-21) | — | 0.10.0 (2025-03-17) | 10 | 10, hand-written | none |
| nvim-mini/mini.nvim | 2021-06-18 | by hand (MAINTAINING.md) | v0.1.0 (2021-10-31) | — | v0.18.0 (2026-06-21) | 18 | 18, hand, copied from CHANGELOG | hand-written |
| nvim-treesitter/nvim-treesitter | 2020-04-18 | hand tags | v0.7.2 (2022-10-16) | — | v0.10.0 (2025-05-24); `main` has diverged from it by 513 commits | 13 | 0 | none |
| mfussenegger/nvim-lint | 2021-02-14 | — | only `nvim-05` | — | — | 0 | 0 | none |
| nvim-lualine/lualine.nvim | 2020-12-30 | — | only `compat-nvim-0.5`, `compat-nvim-0.6` | — | — | 0 | 0 | none |

All the semver-tagged repos above publish no pre-release tags except mason.nvim (`v2.0.0-rc.1`, `v2.0.0-rc.2`, GitHub `prerelease: true`).

## How a version spec picks a tag

| Spec | lazy.nvim | `vim.pack` |
|---|---|---|
| nothing | `defaults.version` (default `nil`) → default-branch HEAD | default branch |
| `false` | default-branch HEAD (overrides `defaults.version`) | validation error: `version` must be a string or `vim.VersionRange` [NP2 L346–348, L393]; omit it instead |
| `'*'` | greatest semver tag ≥ 0.0.0, **0.x included**, pre-releases **excluded** | `vim.version.range('*')`: greatest strict-semver tag, **0.x and pre-releases included** |
| `'1.*'` | `[1.0.0, 2.0.0)` without pre-releases | `[1.0.0, 2.0.0)`, and **`2.0.0-beta.1` is inside it** |
| `'^0.2'` | `[0.2.0, 0.3.0)` | same |
| no tag matches | silent fallback to branch HEAD | error, plugin not checked out |
| non-semver tags (`stable`, `nvim-0.6`) | ignored for ranges; usable as `tag = 'stable'` | ignored for ranges; usable as `version = 'stable'` (string) |

## Sources

GitHub API data (tags, releases, workflow listings, branches, PR #2211 of nvim-cmp) was read with `gh api` and `gh release view` on 2026-11-07. The repo files below are at the given commit.

folke:

- [FG1] https://github.com/folke/github `d1cb00f0473c256299c7b35b6e199559366e56bc` `.github/workflows/ci.yml`: inputs L13–17, `release` job L192–227 (`googleapis/release-please-action@v4`, `release-type=simple` when no config, `stable` tag).
- [FG2] same repo, `.github/workflows/pr.yml` L11–15 (+ types list).
- [LZ1] https://github.com/folke/lazy.nvim `306a05526ada86a7b30af95c5cc81ffba93fef97`: `.github/workflows/ci.yml` (calls FG1), `.github/release-please-config.json` L1–9, `.github/.release-please-manifest.json` (`11.17.5`).
- [LZ2] same, `lua/lazy/core/config.lua`: `defaults.version` L13–16, `M.version` with `x-release-please-version` L245.
- [LZ3] same, `lua/lazy/manage/semver.lua`: parse L86, `Range:matches` L118–129, `range('*')` L132–135, modifiers L151–189.
- [LZ4] same, `lua/lazy/manage/git.lua`: `get_versions` L51–64, `get_target` L118–154.
- [LZ5] same, `lua/lazy/manage/task/git.lua` fetch L276–288.
- [LZD1] same repo, branch `docs` `cef6b397011701d900f9ba96cecc2eda1f8bc260`, `docs/spec/versioning.md` L1–24; `docs/spec/index.md` L73–84.
- [SN1] https://github.com/folke/snacks.nvim `882c996cf28183f4d63640de0b4c02ec886d01f2` `lua/snacks/init.lua` L15; `.github/release-please-config.json`.
- [LVS] https://github.com/LazyVim/starter `803bc181d7c0d6d5eeba9274d9be49b287294d99` `lua/config/lazy.lua` L24–32.
- [LV] https://github.com/LazyVim/LazyVim `301a3f71007c4aa5da5dab82f1a7a08389091224` `lua/lazyvim/plugins/extras/coding/blink.lua` L17, L31.

Neovim (https://github.com/neovim/neovim, tag `v0.12.6` = `022946c802832f938398dfae34b3f277ca9509d4`):

- [NP1] `runtime/doc/pack.txt`: L221–235 (semver tags, lockfile), L411–417 (`version`).
- [NP2] `runtime/lua/vim/pack.lua`: L14–15, L261–263 (`parse_semver` strict), L329–331 (`git tag --list`), L374–378 (`version` doc), L592–603 (`get_last_semver_tag`), L607–654 (`resolve_version`), L717–718 (lockfile wins).
- [NV1] `runtime/lua/vim/version.lua`: L17–54 (range table, "suffixed versions … are not matched" L22–23), `VersionRange:has` L257–272, `M.range` L291–368.
- Scratch tests on local `NVIM v0.12.6`: `vim.version.range():has()` on sample tags, and `vim.pack.add` with `file://` repos (tagged and untagged) under throwaway `XDG_*` dirs. Results are quoted above.

release tools:

- [RP1] https://github.com/googleapis/release-please `ea20bc261acd75149f0be90890bb9c90e681eea7` `README.md`: L12, L25–27, L45–57, L106–115, L136–138.
- [RP2] same, `docs/manifest-releaser.md` L159–210.
- [RP3] same, `src/strategies/base.ts` L756–761 (`initialReleaseVersion` → `1.0.0`).
- [RP4] same, `docs/customizing.md` L47 (prerelease strategy), L174–188 (`x-release-please-*` markers).
- [RP5] same, `src/strategies/simple.ts` L22–53.
- [RPA] https://github.com/googleapis/release-please-action `0b6b3fc0186a2f7118bfd88fab9ea481e1839504` `README.md` L74–78 (`release-type`, `target-branch`, `config-file`, `manifest-file`).
- [SR1] https://github.com/semantic-release/semantic-release `04c1923646eb801cf6f0f90455cf00b78b94fdb7` `README.md` L50–64.
- [SR2] same, `lib/definitions/constants.js` L3 (`FIRST_RELEASE = "1.0.0"`).

Plugins:

- [NT1] https://github.com/nvim-neotest/neotest `27bf921498043f7ecd821d6db68d05de244bbd02` `.github/workflows/workflow.yaml` L64–102.
- [NT2] same, `.releaserc.json` L1–12.
- [DUI] https://github.com/rcarriga/nvim-dap-ui `cc9dd33aade7f20bae414d0cba163bc60d4d4b43` `.releaserc.json` (first added `234fe3e`, 2021-04-11); release `v1.0.0` body ("BREAKING CHANGES").
- [LSP1] https://github.com/neovim/nvim-lspconfig `993d048db0d83d8e8ba3f9cb376456321acdcce3` `README.md` L215–221.
- [LSP2] same, `.github/workflows/release.yml` L1–21.
- [TS1] https://github.com/nvim-telescope/telescope.nvim `40aedd8a68c78a656a10a8d62d80c54af59420fb` `README.md` L70–83.
- [TS2] same, `.github/workflows/release.yml` L1–31.
- [CF] https://github.com/stevearc/conform.nvim `016802de402556da54c36bd7359b441266b01cdd` `.github/workflows/tests.yml` L102–123; `README.md` L33.
- [OI] https://github.com/stevearc/oil.nvim `d3733d933833a0e59b813ecec99341527adf0c28` `.github/workflows/tests.yml` L102–123.
- [GS1] https://github.com/lewis6991/gitsigns.nvim `ef707fb93301a9b856f36eae4c8f56f5b988a794` `release-please-config.json` L1–13.
- [GS2] same, `.github/workflows/release-please.yml` L27–58 (added `2215c64`, 2024-04-17).
- [MA1] https://github.com/mason-org/mason.nvim `2a6940af80375532e5e9e7c1f2fc6319a1b7a69d` `.github/workflows/release.yml` L16–33.
- [MA2] same, `lua/mason/version.lua` L1–8.
- [MLC1] https://github.com/mason-org/mason-lspconfig.nvim `55eceab8975036ac43a4176cbfe0d4bf1ddae93f` `README.md` L50–56.
- [MLC2] same, `lua/mason-lspconfig/health.lua` L1–20.
- [RK] https://github.com/lumen-oss/rocks.nvim `8a2fbfd4fb9afce100b06da07203e1cd48313eb4` `.github/workflows/release-please.yml` L19–22.
- [CMP1] https://github.com/hrsh7th/nvim-cmp `fe29aba4117227a6df637bc41e4b4fb4e98864a0` `.github/workflows/release-please.yaml` L1–21 (added `85bbfad`, 2026-01-02).
- [BL1] https://github.com/saghen/blink.cmp `7b31e1b6497be70f620bbad83a789929248697ac` `.github/workflows/release.yaml` L3–6, L187–196.
- [BL2] same repo, branch `v1` `e0d51adba95174760e2e1454fe39543d96194118`, `lua/blink/cmp/fuzzy/download/git.lua` L22–51.
- [BL3] same, `lua/blink/cmp/fuzzy/download/init.lua` L73–91, L110–122.
- [BL4] main `README.md` L2.
- [MI1] https://github.com/nvim-mini/mini.nvim `9b132c10d34675315327a7d58cc6684cb4e8faf2` `README.md` L31–34, L50, L64–85, L223–225.
- [MI2] same, `MAINTAINING.md` L82–100 (dual distribution), L289–319 (stable release).
- [DPY] https://github.com/mfussenegger/nvim-dap-python `1808458eba2b18f178f990e01376941a42c7f93b` `nvim-dap-python-scm-1.rockspec` L19–22.
- [NG] https://github.com/fredrikaverpil/neotest-golang `65b2be63c3de00e6f15c05388ebdc8d603dbd727` `.github/workflows/release.yml` L25–45.
- [MND] https://github.com/jay-babu/mason-nvim-dap.nvim `9a10e096703966335bd5c46c8c875d5b0690dade` `.github/workflows/ci.yml` L30–41.
