# Who installs Neovim plugins from LuaRocks, and what does publishing cost?

Research for issue [#86](https://github.com/a1exk-dev/codestyle.nvim/issues/86) (map: [#83](https://github.com/a1exk-dev/codestyle.nvim/issues/83)). It feeds the grilling ticket that #86 blocks ([#88](https://github.com/a1exk-dev/codestyle.nvim/issues/88)), which decides whether the Core and the Language Plugins publish to LuaRocks.

Question: which users and plugin managers install Neovim plugins from LuaRocks, how many popular plugins publish there, what publishing takes per repo and per release, how a dependency on another Neovim plugin (snacks.nvim) is expressed, and what users lose when a plugin is not on LuaRocks.

Date of research: 2026-11-07. Sources: lazy.nvim `v11.17.5` (`doc/lazy.nvim.txt`, `lua/lazy/pkg/rockspec.lua` on `main`); rocks.nvim `v2.49.1` README and its issue #539; rocks-git.nvim README; `nvim-neorocks/luarocks-tag-release` README (`v9`); NURR (`lumen-oss/nurr`) README and `plugins.json`; luarocks.org pages (module pages, the `neovim` manifest and label, the `neorocks` user, the September 2026 incident report); Neovim v0.12.6 `runtime/doc/pack.txt`; the release workflows of telescope.nvim and rustaceanvim. Counts are as luarocks.org showed them on that date. Terms follow `GLOSSARY.md`. This note gives facts and no design.

## Answer

- **Only rocks.nvim installs Neovim plugins from luarocks.org.** lazy.nvim and Neovim's own `vim.pack` install from Git. lazy.nvim uses LuaRocks only to build a plugin that it has already cloned, and only when that plugin's repo has a rockspec that needs it. rocks.nvim has about 1.1k GitHub stars, against 21.7k for lazy.nvim. Its README asks new users to wait for a breaking v3 rewrite.
- **Most Neovim plugins on luarocks.org are uploaded by a third party, not by their authors.** The NURR bot (luarocks user `neorocks`) uploads 693 modules: plugins from a curated `plugins.json` of 347 entries, and Tree-sitter parsers. These include snacks.nvim, lazy.nvim, conform.nvim, mini.nvim and lualine.nvim. Only a few authors publish their own plugins, for example telescope.nvim (155k downloads), rustaceanvim, neorg and nvim-treesitter.
- **Per repo, publishing costs one workflow file and one secret.** You need a luarocks.org account, an API key stored as a GitHub Actions secret, and a tag-triggered workflow that runs `luarocks-tag-release` (or `gh-actions-lux`). The action generates the rockspec, so the repo needs none. **Per release, it costs nothing extra:** pushing a SemVer tag uploads the rock (a leading `v` is stripped).
- **A dependency on another plugin is a LuaRocks dependency by rock name**, for example `snacks.nvim` in the action's `dependencies` input. It works only if that plugin exists on LuaRocks. snacks.nvim is there (uploaded by NURR, `2.31.0`, matching its latest GitHub release). lazy.nvim does not read luarocks.org for this. It reads a `*-scm-1.rockspec` that is committed in the plugin's repo, or the recommended `lazy.lua`.
- **Without LuaRocks, rocks.nvim users must use rocks-git.nvim, and they must list the dependencies themselves.** The plugin also gets no SemVer resolution in `:Rocks install` and no name completion. lazy.nvim, `vim.pack`, packer-style and manual users lose nothing. NURR can also add a plugin without its author ([NURR README](https://github.com/lumen-oss/nurr)).

## Who installs from LuaRocks, and how

### rocks.nvim

- rocks.nvim is "a Neovim plugin manager that works directly with LuaRocks". Users run `:Rocks install foo.nvim [version] [opt=true]`, and rocks.nvim records the plugin in `rocks.toml` ([rocks.nvim README](https://github.com/lumen-oss/rocks.nvim)).
- Packages come from luarocks.org. Prebuilt binary rocks, mostly Tree-sitter parsers, come from `rocks-binaries` and `rocks-binaries-dev`, so users do not compile them ([rocks.nvim README L54–55, L131](https://github.com/lumen-oss/rocks.nvim)).
- Its reason for using LuaRocks is to move the job of declaring dependencies and build steps from users to plugin authors. Dependencies "are automatically resolved and installed" from the plugin's rockspec ([rocks.nvim README](https://github.com/lumen-oss/rocks.nvim)).
- Plugins load at startup unless `opt = true` is set. Its docs ask plugin authors to handle their own lazy initialization ([rocks.nvim README](https://github.com/lumen-oss/rocks.nvim)).
- Status: version `v2.49.1` came out on 2026-10-15, and the repo has 1,075 stars. The README warns: "rocks.nvim will be undergoing a major rewrite soon … we recommend you wait for rocks.nvim v3.0.0". The rewrite moves from `luarocks` to `lux`, because "many users have issues installing or bootstrapping luarocks (mostly on non-Linux systems)" ([issue #539](https://github.com/lumen-oss/rocks.nvim/issues/539), open).
- rocks-git.nvim adds plugins from Git (`[plugins] neorg = { git = "nvim-neorg/neorg" }`). It is "a simple, minimal bridge for plugins that cannot be installed with luarocks". For Lua plugins it recommends uploading them to luarocks, "as this enables proper SemVer versioning". Its `rocks.toml` fields are `name`, `git`, `opt`, `rev`, `branch` and `build`. It has no field for dependencies, and its README does not mention dependency resolution ([rocks-git.nvim README](https://github.com/lumen-oss/rocks-git.nvim)).

### lazy.nvim (Git first, LuaRocks only as a build tool)

- lazy.nvim installs plugins from Git. The short form `"owner/repo"` expands through `git.url_format`, which defaults to `https://github.com/%s.git` ([`doc/lazy.nvim.txt`](https://github.com/folke/lazy.nvim/blob/main/doc/lazy.nvim.txt)).
- It reads dependency metadata from three package sources, in order: `config.pkg.sources = { "lazy", "rockspec", "packspec" }`. "Using a `lazy.lua` file is the recommended way to define your plugin dependencies and configuration." The first source that finds a package wins ([`doc/lazy.nvim.txt`](https://github.com/folke/lazy.nvim/blob/main/doc/lazy.nvim.txt), Packages).
- The `rockspec` source looks only in the cloned plugin directory, for a file ending in `scm-1.rockspec`, `git-1.rockspec` or `dev-1.rockspec`. It never queries luarocks.org for the plugin itself ([`lua/lazy/pkg/rockspec.lua` `find_rockspec`](https://github.com/folke/lazy.nvim/blob/main/lua/lazy/pkg/rockspec.lua)).
- When a rockspec dependency names a known Neovim plugin rock, lazy.nvim turns it into a Git plugin spec. Its own map does this for `plenary.nvim`, and the community specs do it for others. lazy.nvim runs `luarocks make` (`build = "rockspec"`) only when the plugin has no `/lua` directory, has a complex build, or has dependencies that are not plugins. A pure-Lua plugin whose only dependencies are Neovim plugins is never built with LuaRocks ([`rockspec.lua` `M.get`](https://github.com/folke/lazy.nvim/blob/main/lua/lazy/pkg/rockspec.lua); [`doc/lazy.nvim.txt`](https://github.com/folke/lazy.nvim/blob/main/doc/lazy.nvim.txt): "A rockspec will only be used if …").
- Pure Lua libraries without a plugin repo are fetched as rocks. The defaults are `rocks.enabled = true`, `rocks.root = stdpath("data") .. "/lazy-rocks"`, `rocks.server = "https://lumen-oss.github.io/rocks-binaries/"`, and `hererocks = nil`, which uses hererocks when `luarocks` is missing ([`doc/lazy.nvim.txt`](https://github.com/folke/lazy.nvim/blob/main/doc/lazy.nvim.txt), Configuration).

### Neovim `vim.pack` (0.12)

- `vim.pack` "uses Git to manage plugins and requires present `git` executable". Each plugin is a `{ src = 'https://github.com/user/plugin', version = … }` entry, and target plugins "should be Git repositories with versions as named tags following semver". It has no LuaRocks support ([Neovim v0.12.6 `runtime/doc/pack.txt` L221–261](https://github.com/neovim/neovim/blob/v0.12.6/runtime/doc/pack.txt)).

### How much Neovim is on luarocks.org

| luarocks.org view | Count | Source |
|---|---|---|
| Modules uploaded by `neorocks` (NURR) | 693, with 10.1M downloads in total | [luarocks.org/modules/neorocks](https://luarocks.org/modules/neorocks) |
| NURR `plugins.json` entries | 347 plugins; Tree-sitter parsers are listed in a separate file | [nurr `plugins.json`](https://github.com/lumen-oss/nurr/blob/main/plugins.json) |
| Modules labelled `neovim` | 64 in the root manifest, 67 in all manifests | [labels/neovim](https://luarocks.org/labels/neovim) |
| `neovim` manifest ("Luarocks modules containing packaged Neovim plugins") | 42 | [m/neovim](https://luarocks.org/m/neovim) |

Examples:

| Plugin | On LuaRocks? | Who uploads | Notes |
|---|---|---|---|
| snacks.nvim | Yes, `2.31.0-1` plus `scm` | `neorocks` (NURR) | 8,923 downloads. Its only rockspec dependency is `lua >= 5.1`. folke's repo has no LuaRocks workflow ([module page](https://luarocks.org/modules/neorocks/snacks.nvim); repo workflows: `ci.yml`, `labeler.yml`, `pr.yml`, `stale.yml`, `update.yml`). |
| lazy.nvim, conform.nvim, mini.nvim, lualine.nvim, flash.nvim, which-key.nvim | Yes | `neorocks` (NURR) | Their authors do not publish them ([luarocks search](https://luarocks.org/search); NURR `plugins.json`). |
| telescope.nvim | Yes | its author (`Conni2461`) | 155k downloads. `.github/workflows/release.yml` runs `luarocks-tag-release@v7` on each tag, with `dependencies: plenary.nvim` ([workflow](https://github.com/nvim-telescope/telescope.nvim/blob/master/.github/workflows/release.yml)). |
| rustaceanvim | Yes | its author (`mrcjkb`) | `.github/workflows/luarocks.yml` runs `lx --nvim upload` with `gh-actions-lux` and signs the upload with GPG ([workflow](https://github.com/mrcjkb/rustaceanvim/blob/master/.github/workflows/luarocks.yml)). |
| neorg, nvim-treesitter, nvim-lspconfig | Yes | their own orgs (`neorg`, `neovim`) | [luarocks.org/modules/neorg/neorg](https://luarocks.org/modules/neorg/neorg), [neovim/nvim-treesitter](https://luarocks.org/modules/neovim/nvim-treesitter). |
| codestyle.nvim | No module of that name | — | A search for `codestyle` finds only an unrelated user ([luarocks search](https://luarocks.org/search?q=codestyle)). |

## What publishing takes

### Once per repo

- **A luarocks.org account and an API key.** You create the key at `luarocks.org/settings/api-keys` and store it as a GitHub Actions secret. The `v9` README calls it `LUX_API_KEY`, and older users such as telescope.nvim on `@v7` call it `LUAROCKS_API_KEY` ([luarocks-tag-release README "Prerequisites"](https://github.com/nvim-neorocks/luarocks-tag-release)). One account can own all 17 rocks, but each repo needs the secret, because a GitHub template copies files and not secrets.
- **One workflow file.** This is the minimal workflow from the README:

  ```yaml
  on:
    push:
      tags: ["*"]     # uploads to luarocks.org
    pull_request:     # tests a local install without uploading
  jobs:
    luarocks-release:
      runs-on: ubuntu-latest
      steps:
        - uses: actions/checkout@v3
        - uses: nvim-neorocks/luarocks-tag-release@v9
          env:
            LUX_API_KEY: ${{ secrets.LUX_API_KEY }}
  ```

  The action README itself now says: "We recommend switching to [gh-actions-lux]". That is the route rustaceanvim takes (`lx --nvim upload`) ([luarocks-tag-release README L29–31](https://github.com/nvim-neorocks/luarocks-tag-release)).
- **No rockspec in the repo.** "No need to add a rockspec to your repository for each release (or at all)." The action generates a `lux.toml` from the repository metadata and the inputs. An optional `extra.rockspec` (`template` input) can change it, but it must not set `version` or `source` ([README "Features", `template`](https://github.com/nvim-neorocks/luarocks-tag-release)).
- **Defaults that matter here:**
  - The rock name defaults to the repository name, so `codestyle.nvim` and `codestyle-<id>.nvim`.
  - `labels` defaults to the repo's GitHub topics.
  - `copy_directories` defaults to `{{ neovim.plugin.dirs }}`, the standard runtimepath directories such as `plugin`, `doc` and `ftplugin`, so `lua/` and `doc/` ship without any setup.
  - The Lua constraint defaults to `>= 5.1`.
  - It "only works on public repositories".

  ([README "Inputs", "Limitations"](https://github.com/nvim-neorocks/luarocks-tag-release))
- **Optional:** GPG signing of the upload (a private-key input). On pull requests, the action builds and installs the rock locally without uploading it, and this works as an extra CI check ([README](https://github.com/nvim-neorocks/luarocks-tag-release)).

### Per release

- Nothing by hand. "Publishes packages to LuaRocks when a git tag is pushed". Lux "derives the version from the git tag (a leading `v` is stripped). If there is no SemVer tag, a `dev` version is published." `specrev` is managed automatically ([README "Versioning"](https://github.com/nvim-neorocks/luarocks-tag-release)). So a `v1.2.0` tag from the release workflow becomes rock version `1.2.0-1`.
- A scheduled job with `version: scm` (or `dev`) can also publish the development head, which is what NURR's `scm-N` rocks are ([README `version`](https://github.com/nvim-neorocks/luarocks-tag-release)).

### Operational risk

- On 2026-09-25 luarocks.org received a report of remote code execution through an uploaded bytecode "rockspec". The flaw was exploited between 2026-07-09 and 2026-08-20. "All API keys have been revoked", sessions were ended, password hashes are treated as exposed, and 2FA secrets were removed. The operators found no evidence that existing packages were modified, and they ask maintainers to review recent versions on the Security Audit page ([luarocks.org incident report](https://luarocks.org/security-incident-september-2026)). Each publishing repo carries a credential that may need rotating like this.

## How a dependency on snacks.nvim is expressed

- In the action, you list the dependency by rock name: `dependencies: | snacks.nvim`. "Any dependencies specified here must be available on LuaRocks." lux needs an explicit version requirement, and "bare names (e.g. `plenary.nvim`) are resolved by lux to the latest version at publish time" ([README `dependencies`](https://github.com/nvim-neorocks/luarocks-tag-release)). telescope.nvim declares `plenary.nvim` this way.
- snacks.nvim exists on luarocks.org only because NURR uploads it. NURR runs every 4 hours from `plugins.json`, where snacks.nvim has `"dependencies": []` ([NURR README](https://github.com/lumen-oss/nurr); [module page](https://luarocks.org/modules/neorocks/snacks.nvim)). A rock that depends on `snacks.nvim` therefore depends on NURR continuing to upload it. No NURR entry depends on snacks.nvim today.
- A Language Plugin would list `codestyle.nvim` (with a version range) as its rock dependency in the same way. rocks.nvim then installs the Core and snacks.nvim with it.
- Tree-sitter parsers are rocks too (`tree-sitter-<lang>`, published by NURR every 7 hours, with prebuilt binaries in rocks-binaries). A rockspec could depend on them. NURR warns that many plugins that claim to depend on nvim-treesitter "only depend on the parsers" ([NURR README "Tree-sitter parsers"](https://github.com/lumen-oss/nurr)). Today the Core takes parsers from the user's setup (ADR-0002).
- lazy.nvim does not use any of this for a Git-installed plugin. Its dependency metadata comes from a committed `lazy.lua` (recommended) or a committed `*-scm-1.rockspec`, or else the user writes `dependencies` by hand (ADR-0007 already expects users to list Language Plugins as `dependencies` of codestyle.nvim).

## What users lose if a plugin is not on LuaRocks

- **rocks.nvim users:** They cannot run `:Rocks install codestyle.nvim`, and they get no name or version completion. They must install rocks-git.nvim and add `[plugins] codestyle = { git = "a1exk-dev/codestyle.nvim" }`. Then they must add snacks.nvim and each Language Plugin themselves, because rocks-git has no dependency resolution, and they track Git tags and get no SemVer ranges ([rocks-git.nvim README](https://github.com/lumen-oss/rocks-git.nvim)).
- **lazy.nvim, `vim.pack`, and manual or packpath users:** They lose nothing. They install from Git in every case. lazy.nvim reads metadata from the repo and not from luarocks.org.
- **Third-party packaging may happen anyway.** NURR adds plugins to `plugins.json`, which "is currently updated manually", and uploads them as user `neorocks`. A plugin can appear on LuaRocks without its author's work, but the author then controls neither the dependency list nor the timing ([NURR README](https://github.com/lumen-oss/nurr)).
