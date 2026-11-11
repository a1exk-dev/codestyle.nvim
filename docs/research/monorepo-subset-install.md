# Can one Git repo give users a chosen subset of languages and separate versions?

Research for issue [#97](https://github.com/a1exk-dev/codestyle.nvim/issues/97) (map: [#95](https://github.com/a1exk-dev/codestyle.nvim/issues/95)). It feeds the ticket that #97 blocks ([#98](https://github.com/a1exk-dev/codestyle.nvim/issues/98)), which compares A (one repo per Language Plugin), B (one monorepo of the Core and all languages, possibly with a subfolder per language) and C (the Core repo plus one bundle repo).

Question: if all Language Plugins live in one Git repo, can a user install only some languages, can each language have its own version, and what does the user's install spec look like? Checked for lazy.nvim, Neovim 0.12 `vim.pack`, rocks.nvim with rocks-git.nvim, LuaRocks rockspecs per subfolder, and split mirror repos (mini.nvim style).

Date of research: 2026-11-11. Sources (read as source code, not secondary write-ups): lazy.nvim `main` at [`306a055`](https://github.com/folke/lazy.nvim/tree/306a05526ada86a7b30af95c5cc81ffba93fef97); Neovim v0.12.6 `runtime/lua/vim/pack.lua`, `runtime/lua/vim/version.lua` and `runtime/doc/pack.txt` (the installed v0.12.6 runtime, same files as the [v0.12.6 tag](https://github.com/neovim/neovim/tree/v0.12.6/runtime)); rocks.nvim [`8a2fbfd`](https://github.com/lumen-oss/rocks.nvim/tree/8a2fbfd4fb9afce100b06da07203e1cd48313eb4); rocks-git.nvim [`a647412`](https://github.com/lumen-oss/rocks-git.nvim/tree/a647412d2e212a03c551d665005f5a1e0c575d1d); LuaRocks [`docs/rockspec_format.md`](https://github.com/luarocks/luarocks/blob/85bfe36c812465b2f377877939d884a4db829a25/docs/rockspec_format.md); luarocks-tag-release [`action.yml`](https://github.com/lumen-oss/luarocks-tag-release/blob/5ce6a6711fe10d55a8f65353626b141b8b261593/action.yml); mini.nvim [`f9ac12d`](https://github.com/nvim-mini/mini.nvim/tree/f9ac12d7cbd2563cfc2cce9a8152fc8df2ad0d6f) `scripts/dual_*.sh`, `Makefile`, `readmes/mini-ai.md`. Tag behaviour was also run headless on Neovim 0.12.6 (scripts below). Terms follow `GLOSSARY.md`. This note gives facts and no design.

## Answer

- **With the Git-based managers (lazy.nvim, `vim.pack`, rocks-git.nvim), one repo gives neither a subset nor separate versions.** Each manager clones the repo and puts only the clone's root directory on the runtimepath. None of them has a field for a subfolder. A clone is checked out at one commit, so every language in it has the same version.
- **A second copy of the same repo does not help.** lazy.nvim merges two specs with the same URL into one plugin. `vim.pack` accepts the same `src` under two names and makes two full clones, but then every language is on the runtimepath twice, and the Core reports duplicate language ids (ADR-0007).
- **Tags with a prefix, such as `php-v1.2.0`, are invisible to version ranges.** `vim.pack` parses tags with `vim.version.parse(tag, { strict = true })`, which returns `nil` for them. lazy.nvim's own parser also needs the tag to start with `v` or a digit. rocks-git.nvim drops them too. Only an exact tag works (`tag = 'php-v1.2.0'` in lazy.nvim, `version = 'php-v1.2.0'` in `vim.pack`), and it moves every language in the clone to that commit.
- **One lazy.nvim-only trick exists:** suffix tags such as `v1.2.0-php` with `version = '^1.0.0-php'`. lazy.nvim matches a range only against tags with the same pre-release text. In `vim.pack`, the same tags are ordinary pre-releases, so `vim.version.range('1.*')` matches every language's tags. It still gives one version per clone, and it breaks ADR-0019 (plain `vX.Y.Z` tags, no pre-releases).
- **Only two routes give both a subset and separate versions from one source repo:**
  1. **One rockspec per language on luarocks.org.** A rockspec's `source.tag` can name `php-v1.2.0`, and its `build.modules` can install only the files of one subfolder. rocks.nvim puts the installed Lua tree on the runtimepath, so the Core finds the spec. This serves rocks.nvim users only: lazy.nvim and `vim.pack` do not install plugins from luarocks.org (see [`luarocks-publishing.md`](https://github.com/a1exk-dev/codestyle.nvim/blob/research/luarocks-publishing/docs/research/luarocks-publishing.md)).
  2. **Split mirror repos**, one per language, made from the monorepo by a script or a bot. Users install the mirrors as ordinary plugins (option A for the user). mini.nvim does this with maintainer-run shell scripts, not a bot, and gives every mirror the same release tag.

## Per manager

| Manager | Subset of languages from one repo? | Own version per language? | Install spec |
|---|---|---|---|
| lazy.nvim | No. Only the clone root goes on the runtimepath. A local `dir` spec can point into a subfolder of a clone, but lazy.nvim does not install or update `dir` plugins. | No. Same URL = one plugin. Exact prefixed tag only; suffix tags + pre-release ranges work in lazy.nvim alone. | `{ 'a1exk-dev/codestyle.nvim' }` (all languages, one version) |
| `vim.pack` | No. `:packadd` adds the clone root. | No. Prefixed tags are not semver to `vim.version.range`; two clones duplicate every language. | `vim.pack.add({ 'https://github.com/a1exk-dev/codestyle.nvim' })` |
| rocks-git.nvim | No. | No. It takes the latest tag whose parts are all numbers; `rev = 'php-v1.2.0'` pins exactly. | `[plugins] "codestyle.nvim" = { git = "a1exk-dev/codestyle.nvim" }` |
| rocks.nvim (luarocks.org) | Yes, one rock per language, each built from one subfolder. | Yes, each rock has its own version. | `:Rocks install codestyle-php.nvim` → `[plugins] "codestyle-php.nvim" = "1.2.0"` |
| Split mirrors (any manager) | Yes, one mirror repo per language. | Yes, if the script tags each mirror on its own. | Same as option A: `{ 'a1exk-dev/codestyle-php.nvim' }` |

## Evidence

### lazy.nvim

- **No subfolder field.** The spec fields for source are `[1]`, `dir`, `url`, `name` and `dev` ([`doc/lazy.nvim.txt` L250–262](https://github.com/folke/lazy.nvim/blob/306a05526ada86a7b30af95c5cc81ffba93fef97/doc/lazy.nvim.txt#L250-L262)); for versions, `branch`, `tag`, `commit`, `version`, `pin` and `submodules` ([L355–375](https://github.com/folke/lazy.nvim/blob/306a05526ada86a7b30af95c5cc81ffba93fef97/doc/lazy.nvim.txt#L355-L375)). `main` only names the Lua module for `config()` (L314). `submodules` only controls whether Git submodules are fetched.
- **Only the plugin directory goes on the runtimepath.** `add_to_rtp` inserts `plugin.dir` and `plugin.dir .. "/after"` ([`lua/lazy/core/loader.lua` L461–493](https://github.com/folke/lazy.nvim/blob/306a05526ada86a7b30af95c5cc81ffba93fef97/lua/lazy/core/loader.lua#L461-L493)). `plugin.dir` is the user's `dir`, or `root .. "/" .. name` for a cloned plugin ([`lua/lazy/core/meta.lua` L213–239](https://github.com/folke/lazy.nvim/blob/306a05526ada86a7b30af95c5cc81ffba93fef97/lua/lazy/core/meta.lua#L213-L239)). A `dir` plugin is a "local plugin" (L255) and is not cloned.
- **One URL is one plugin.** `M:add` looks up an existing plugin by name, then by URL, then by `dir`, and a spec with a new `name` but the same URL renames that plugin instead of adding a second one ([`meta.lua` L70–117](https://github.com/folke/lazy.nvim/blob/306a05526ada86a7b30af95c5cc81ffba93fef97/lua/lazy/core/meta.lua#L70-L117)). So `{ url = X, name = 'php', version = '^1' }` and `{ url = X, name = 'css', version = '^2' }` cannot coexist.
- **Tags must start with `v` or a digit.** `Semver.version` matches `^v?(%d+)%.?(%d*)%.?(%d*)%-?([^+]*)+?(.*)$` ([`lua/lazy/manage/semver.lua` L86](https://github.com/folke/lazy.nvim/blob/306a05526ada86a7b30af95c5cc81ffba93fef97/lua/lazy/manage/semver.lua#L86)), and `get_versions` skips every tag it cannot parse ([`lua/lazy/manage/git.lua` L51–64](https://github.com/folke/lazy.nvim/blob/306a05526ada86a7b30af95c5cc81ffba93fef97/lua/lazy/manage/git.lua#L51-L64)).
- **A range matches only tags with the same pre-release text.** `Range:matches` returns false when `version.prerelease ~= self.from.prerelease` ([`semver.lua` L117–127](https://github.com/folke/lazy.nvim/blob/306a05526ada86a7b30af95c5cc81ffba93fef97/lua/lazy/manage/semver.lua#L117-L127)). Run headless against lazy.nvim's module with tags `v1.4.0`, `php-v1.2.0`, `php/v1.2.0`, `v1.2.0-php`, `v1.3.0-css`, `v2.0.0-php`:

  | `version` | Tags that match |
  |---|---|
  | `*`, `^1`, `1.*` | `v1.4.0` |
  | `^1.0.0-php` | `v1.2.0-php` |
  | `^1.0.0-css` | `v1.3.0-css` |

  No range ever matches `php-v1.2.0` or `php/v1.2.0`.
- **No sparse checkout.** The clone uses `--filter=blob:none` when `git.filter` is set ([`lua/lazy/manage/task/git.lua` L139–141](https://github.com/folke/lazy.nvim/blob/306a05526ada86a7b30af95c5cc81ffba93fef97/lua/lazy/manage/task/git.lua#L139-L141)); there is no `sparse-checkout` call in the source.

### Neovim `vim.pack` (0.12.6)

- **A spec is `src`, `name`, `version` and `data`, nothing else.** `name` defaults to the last path part of `src` ([`pack.lua` L386–394](https://github.com/neovim/neovim/blob/v0.12.6/runtime/lua/vim/pack.lua#L386-L394)). The plugin lives in `<plug_dir>/<name>` and is loaded with `:packadd <name>` ([L419](https://github.com/neovim/neovim/blob/v0.12.6/runtime/lua/vim/pack.lua#L419), [L806](https://github.com/neovim/neovim/blob/v0.12.6/runtime/lua/vim/pack.lua#L806)), which adds that directory, not a subfolder, to the runtimepath.
- **Same `src`, two names: two clones.** The conflict check runs only between specs with the same name ([L441–455](https://github.com/neovim/neovim/blob/v0.12.6/runtime/lua/vim/pack.lua#L441-L455)). So `{ src = X, name = 'cs-php', version = … }` and `{ src = X, name = 'cs-css', version = … }` are allowed, but each clone has every language, and the Core finds each language id twice.
- **Ranges use strict semver.** `parse_semver` is `vim.version.parse(x, { strict = true })` ([L261–263](https://github.com/neovim/neovim/blob/v0.12.6/runtime/lua/vim/pack.lua#L261-L263)). `get_last_semver_tag` skips tags that do not parse ([L592–603](https://github.com/neovim/neovim/blob/v0.12.6/runtime/lua/vim/pack.lua#L592-L603)). A string `version` is used as a branch, tag or commit as it is ([L628–640](https://github.com/neovim/neovim/blob/v0.12.6/runtime/lua/vim/pack.lua#L628-L640)). The docs say target plugins "should be Git repositories with versions as named tags following semver convention `v<major>.<minor>.<patch>` (with or without `v` prefix)" ([L14–15](https://github.com/neovim/neovim/blob/v0.12.6/runtime/lua/vim/pack.lua#L14-L15)).
- **Strict parsing anchors at the start.** `vim.version` matches `^v?(%d+)%.?(%d*)%.?(%d*)` ([`version.lua` L197](https://github.com/neovim/neovim/blob/v0.12.6/runtime/lua/vim/version.lua#L197)). Run headless on Neovim 0.12.6:

  | Tag | `parse(strict)` | `parse` (loose) | In `range('^1')`? |
  |---|---|---|---|
  | `v1.2.0`, `1.2.0` | `1.2.0` | `1.2.0` | yes |
  | `php-v1.2.0`, `php/v1.2.0`, `php-1.2.0` | `nil` | `1.2.0` | skipped by `vim.pack` |
  | `v1.2.0-php` | `1.2.0-php` (pre-release) | `1.2.0-php` | yes, as are all other languages' suffix tags |
  | `v1.2.0+php` | `nil` | `1.2.0+php` | skipped |

  `vim.version.range('php-^1')` does not filter by prefix either: it returns `1.0.0 - 2.0.0`. The loose parse strips the prefix, so a prefixed tag would match any language's range if `vim.pack` used it, but it does not.
- **No sparse checkout.** `git_clone` runs `clone --quiet --no-checkout --filter=blob:none` ([L280–292](https://github.com/neovim/neovim/blob/v0.12.6/runtime/lua/vim/pack.lua#L280-L292)).

### rocks.nvim and rocks-git.nvim

- **rocks-git.nvim** has the spec fields `opt`, `rev`, `branch`, `build` and `ignore_tags`, and no subfolder field ([`lua/rocks-git/parser.lua` L22–27](https://github.com/lumen-oss/rocks-git.nvim/blob/a647412d2e212a03c551d665005f5a1e0c575d1d/lua/rocks-git/parser.lua#L22-L27)). It has no ranges: it installs the latest remote tag whose parts, after removing `v`, are all numbers ([`parser.lua` L135–178](https://github.com/lumen-oss/rocks-git.nvim/blob/a647412d2e212a03c551d665005f5a1e0c575d1d/lua/rocks-git/parser.lua#L135-L178)), so `php-v1.2.0` is never picked. `rev = "php-v1.2.0"` pins that tag exactly.
- **rocks.nvim puts every rock's Lua tree on the runtimepath.** It appends `<rocks_path>/rocks_rtp` to `runtimepath` and links `rocks_rtp/lua` to `<rocks_path>/share/lua/5.1` ([`lua/rocks/adapter.lua` L27–28, L83–90, L187–193](https://github.com/lumen-oss/rocks.nvim/blob/8a2fbfd4fb9afce100b06da07203e1cd48313eb4/lua/rocks/adapter.lua#L27-L28)). A rock that installs the module `codestyle.languages.php` therefore puts `lua/codestyle/languages/php.lua` where `nvim_get_runtime_file` finds it (ADR-0007).

### LuaRocks rockspecs per subfolder

- **Nothing ties a rock to a whole repo.** A rockspec names its source with `source.url` (`git+https://…`) and `source.tag`, which can be any tag, such as `php-v1.2.0` ([`rockspec_format.md` L37–55](https://github.com/luarocks/luarocks/blob/85bfe36c812465b2f377877939d884a4db829a25/docs/rockspec_format.md#L37-L55)). The `builtin` build installs only the modules listed in `build.modules`, with paths "relative to `source.dir`" ([L79–90](https://github.com/luarocks/luarocks/blob/85bfe36c812465b2f377877939d884a4db829a25/docs/rockspec_format.md#L79-L90)). So `codestyle-php.nvim-1.2.0-1.rockspec` can map `codestyle.languages.php` to `languages/php/lua/codestyle/languages/php.lua` and install nothing else. LuaRocks still downloads the whole repo at that tag.
- **Publishing with luarocks-tag-release** takes `name` and `version` inputs, and `version` "uses the git tag by default" ([`action.yml` L9–20](https://github.com/lumen-oss/luarocks-tag-release/blob/5ce6a6711fe10d55a8f65353626b141b8b261593/action.yml#L9-L20)). With prefixed tags, each language's workflow must pass `name` and strip the prefix into `version` itself. A `template` input (L43) takes a custom rockspec, where `build.modules` would name the subfolder.

### Split mirror repos (mini.nvim)

- **How mini.nvim makes them.** `make dual_sync` runs `scripts/dual_sync.sh` on `main`. For each module it runs `git format-patch sync..HEAD -- lua/mini/<m>.lua doc/mini-<m>.txt readmes/mini-<m>.md LICENSE <extra paths>`, rewrites the README path in the patch with `sed`, clones the mirror `nvim-mini/mini.<m>` if needed, and applies the patch with `git am`. `make dual_push` pushes each changed mirror's `main` and moves the monorepo's `sync` branch to `HEAD` ([`scripts/dual_sync.sh`](https://github.com/nvim-mini/mini.nvim/blob/f9ac12d7cbd2563cfc2cce9a8152fc8df2ad0d6f/scripts/dual_sync.sh), [`scripts/dual_push.sh`](https://github.com/nvim-mini/mini.nvim/blob/f9ac12d7cbd2563cfc2cce9a8152fc8df2ad0d6f/scripts/dual_push.sh), [`Makefile` L48–60](https://github.com/nvim-mini/mini.nvim/blob/f9ac12d7cbd2563cfc2cce9a8152fc8df2ad0d6f/Makefile#L48-L60)). The commits keep their messages and authors, but get new hashes in each mirror.
- **Releases share one tag.** `scripts/dual_release.sh <tag> <message>` points each mirror's `stable` branch at `main`, then creates and pushes the same annotated tag in all mirrors ([`scripts/dual_release.sh`](https://github.com/nvim-mini/mini.nvim/blob/f9ac12d7cbd2563cfc2cce9a8152fc8df2ad0d6f/scripts/dual_release.sh)). So mini.nvim gives a subset, not separate versions. Separate versions would need the script to tag only the changed mirrors with their own numbers.
- **What users write.** Each module's README offers the monorepo ("recommended") or the mirror, e.g. `vim.pack.add({ 'https://github.com/nvim-mini/mini.ai' })` and lazy.nvim `{ 'nvim-mini/mini.ai', version = false }` ([`readmes/mini-ai.md` L57–132](https://github.com/nvim-mini/mini.nvim/blob/f9ac12d7cbd2563cfc2cce9a8152fc8df2ad0d6f/readmes/mini-ai.md#L57-L132)).
- **Cost, as the scripts show it.** One list of modules and their paths, kept by hand in two scripts (46 modules each); one script run per sync and per release; a `sync` branch in the monorepo as the marker; and a public repo per module that must exist before the first sync. The scripts run on the maintainer's machine with his Git credentials. A GitHub Actions bot doing the same would need a token that can push to every mirror, because the workflow's `GITHUB_TOKEN` is scoped to the repository that runs the workflow ([GitHub Docs, "Automatic token authentication"](https://docs.github.com/en/actions/security-for-github-actions/security-guides/automatic-token-authentication)). Each mirror still needs its own `main`, tags, releases and README if it is to follow ADR-0019, and contributions arrive in the monorepo only.

## Conflicts with ADRs

- Prefixed (`php-v1.2.0`) or suffixed (`v1.2.0-php`) tags contradict ADR-0019, which makes every release a plain `vX.Y.Z` tag and rules out pre-release tags because `vim.pack` ranges match them.
- ADR-0019's "`main` holds only releases, so README specs have no `version`" works for a monorepo only with one shared version: a release of any language moves `main` for every user.

## Scripts

`vim.version` check, run with `nvim --clean -l`:

```lua
local r = vim.version.range('^1')
for _, t in ipairs({ 'v1.2.0', '1.2.0', 'php-v1.2.0', 'php/v1.2.0', 'php-1.2.0', 'v1.2.0-php', 'v1.2.0+php' }) do
  local s = vim.version.parse(t, { strict = true })
  print(t, tostring(s), tostring(vim.version.parse(t)), s and r:has(s))
end
print(vim.version.range('php-^1'))
```

lazy.nvim check, run with `nvim --clean -l lazysemver.lua <path to lazy.nvim clone>`:

```lua
package.path = arg[1] .. '/lua/?.lua;' .. package.path
local S = require('lazy.manage.semver')
local tags = { 'v1.4.0', 'php-v1.2.0', 'php/v1.2.0', 'v1.2.0-php', 'v1.3.0-css', 'v2.0.0-php' }
for _, spec in ipairs({ '*', '^1', '1.*', '^1.0.0-php', '^1.0.0-css' }) do
  local r, hits = S.range(spec), {}
  for _, t in ipairs(tags) do
    local v = S.version(t)
    if v and r:matches(v) then hits[#hits + 1] = t end
  end
  print(spec, table.concat(hits, ', '))
end
```
