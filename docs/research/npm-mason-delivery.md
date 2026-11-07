# Can npm or Mason deliver a Neovim plugin like codestyle.nvim?

Research for issue [#84](https://github.com/a1exk-dev/codestyle.nvim/issues/84) (map: [#83](https://github.com/a1exk-dev/codestyle.nvim/issues/83)).
Question: can the Core and its 16 first-party Language Plugins (pure Lua, found on Neovim's runtimepath, ADR-0007) be published and installed through npm or through mason.nvim's registry in a way that users actually use? What would each channel take and cost, and does any popular Neovim plugin do it?

Date of research: 2026-11-07. Sources: mason-registry `CONTRIBUTING.md` (main), mason.nvim `README.md` and `doc/mason.txt` (main), mason.nvim issue #279, Neovim `runtime/doc/pack.txt` (master), lazy.nvim spec docs and README, npm docs, the npm registry search API, and the coc.nvim and omp.nvim docs. Terms follow `GLOSSARY.md`. This note gives facts and a verdict, and no design.

## Answer

- **Mason: no.** The mason.nvim maintainer closed a request to add a Neovim plugin (flutter-tools.nvim) with: "flutter-tools.nvim is a Neovim plugin, not a package that would be a candidate for addition in Mason" [M4]. Mason manages "external editor tooling such as LSP servers, DAP servers, linters, and formatters" and links their executables into a `bin/` directory that it adds to Neovim's `PATH` [M2]. The package schema allows only the categories `Compiler`, `DAP`, `Formatter`, `LSP`, `Linter` and `Runtime` [M1 `categories`], and it links files only to `$MASON/bin`, `$MASON/share` and `$MASON/opt` [M1 `bin`, `share`, `opt`]. Nothing puts a package on the runtimepath, so the Core could not find a Language Plugin spec with `nvim_get_runtime_file` (ADR-0007) without a manual `runtimepath` line per plugin.
- **npm: no.** Nothing in the Neovim plugin world installs Lua plugins from npm. `npm install` puts packages in `./node_modules` or `{prefix}/lib/node_modules` [N1], neither of which is on the runtimepath. Users would need Node.js and npm, which the rule "nothing outside Neovim, Neovim plugins and Lua" (ADR-0002) is meant to avoid, plus a `runtimepath` line per plugin. The few `.nvim` packages on npm are not installed into Neovim from npm (see "Real examples").
- **What users actually use: Git.** Neovim's own manager `vim.pack` takes a `src` that is "URI from which to install and pull updates. Any format supported by `git clone` is allowed", and it requires the `git` executable and version tags [V1 L221–222, L518–519]. lazy.nvim's spec sources are a short GitHub name, a Git `url`, or a local `dir` [L1]; its only non-Git channel is LuaRocks rockspecs [L2]. So the channel that costs nothing extra is the GitHub repos that the project already has.

## Mason in detail

### What a package is

The schema [M1 "Package specification"]:

```yaml
name: string
description: string
homepage: URL
licenses: SPDXLicense[]
languages: string[]
categories: Category[]
source:
    id: string        # a purl with a version, e.g. pkg:npm/..., pkg:luarocks/..., pkg:github/...
bin?:   { [executable]: string }
share?: { [share_location]: string }
opt?:   { [...]: string }
```

- `bin` is "The executables the package provides". Mason symlinks each one into its global `bin/` directory [M1 `bin`].
- `share` is "The architecture independent files the package provides", symlinked to `$MASON/share/...` (the example is jdtls's `lombok.jar` and `plugins/`) [M1 `share`].
- `opt` holds add-on files that "should not be linked to the 'global' Mason `bin/` directory" [M1 `opt`].
- Sources include `cargo`, `composer`, `gem`, `github` (release assets or build from source), `golang`, `luarocks`, `npm`, `nuget`, `opam`, `pypi` and `openvsx` [M1 "Examples"]. The five `luarocks` packages in the core registry are all tools with executables: `luacheck`, `luaformatter`, `digestif`, `fennel-ls`, `teal-language-server` [M5].

Packages install under Neovim's data directory (`install_root_dir = stdpath("data")/mason`), and Mason prepends its `bin/` to `PATH` [M2 L42–44, L216–224]. `doc/mason.txt` has no mention of `runtimepath` or `rtp` [M3].

### What may be added to the core registry

"At least one of the following conditions MUST be fulfilled": 100 GitHub stars, 5000 VS Code marketplace downloads, approval at nvim-lspconfig, or an official recommendation by "a reputable consortium, foundation, or company". "Even if one, or all, of the previous conditions are fulfilled, new package additions may be rejected for other reasons" [M1 "Requirements"]. codestyle.nvim has 1 star today (GitHub API, 2026-11-07). On top of that, the maintainer's ruling in #279 rejects Neovim plugins as a kind [M4].

### A custom registry

Mason accepts more registries, for example `registries = { "lua:my-registry", "github:mason-org/mason-registry" }` [M3 "REGISTRIES"; M2 L238–242]. That avoids the star rule, but:

- the package still lands in `$MASON/packages/<name>` with links in `bin/`, `share/` or `opt/`, not on the runtimepath;
- the user must install and set up mason.nvim first, add our registry to its `setup()`, run `:MasonInstall` for the Core and each Language Plugin, and add each install path to `runtimepath` by hand;
- Mason installs at run time, after `init.lua` has run, so a plugin that it installs is not on the runtimepath when the plugin manager loads codestyle.nvim (inference from the install flow in [M3 "HOW TO INSTALL PACKAGES"]);
- Mason itself needs `git`, `curl` or `wget`, `unzip`, `tar` and `gzip` on Unix [M2 "Requirements"].

Cost for us: one more repo (the registry) with a YAML file per plugin to keep in step with every release, on top of the Git tags that plugin managers already read. Gain for the user: none over a plugin-manager line.

## npm in detail

- **Where it installs.** Local installs go to `./node_modules` of the package root, global installs to `{prefix}/lib/node_modules` on Unix; only executables are linked, to `{prefix}/bin` or `./node_modules/.bin` [N1]. A package cannot pick its own install directory; `prefix` is user configuration [N1].
- **What publishing takes.** An npm account, a `package.json` per repo (17 of them), `npm publish` on each release, and a name per package (`codestyle.nvim` is free on npm today [N2]). Users need Node.js and npm, then a `runtimepath` entry per installed plugin pointing into `node_modules`, and no plugin manager, `:checkhealth` or lock file knows about those paths.
- **Who installs editor extensions from npm.** coc.nvim does, for its own extensions, which "are Node.js code that can use Node.js and coc.nvim APIs"; its registry is set with `coc.nvim:registry` in `~/.npmrc` [C2]. That works because coc runs a Node.js host (Node ≥ 22.15.0) [C1]. Lua plugins have no such host. Even coc.nvim itself is installed with an install script that "uses the selected editor's native `pack` mechanism", not with npm [C1], and coc extensions can also be installed as runtimepath plugins with a plugin manager, because "coc.nvim tries to load extensions from your &rtp" [C2].

## Real examples

- **Mason:** none. The core registry has no Neovim plugin, and the maintainer refuses them [M4]. mason.nvim itself says "Install using your plugin manager of choice" [M2 L52], and bridge plugins such as mason-null-ls.nvim are separate Neovim plugin repos, not Mason packages [M6].
- **npm:** a search for the keyword `neovim-plugin` returns 0 packages; `keywords:neovim` returns 207 and `keywords:nvim` 54 (2026-11-07) [N2]. The hits are Node.js clients (`neovim`, the msgpack API client and remote-plugin host, about 19k downloads a week), coc.nvim and its Node.js extensions, colour-scheme generators, and CLIs or MCP servers that talk to Neovim. One Lua plugin repo, omp.nvim, also publishes to npm, but its README installs the Neovim plugin with lazy.nvim from GitHub (`"rauls-kjarners/omp.nvim"`); the npm package is for the OMP CLI side [N3]. No popular Lua plugin tells users to install it with npm.

## Verdict

| Channel | Possible? | What it takes from us | What it takes from the user | Used by Neovim plugins? |
| --- | --- | --- | --- | --- |
| Core mason-registry | No: plugins are out of scope [M4]; 100-star rule [M1] | n/a | n/a | No |
| Own Mason registry | Technically | A registry repo, YAML per plugin per release | mason.nvim, registry setup, `:MasonInstall`, manual `runtimepath` | No |
| npm | Technically | npm account, 17 `package.json`, publish per release | Node.js + npm, manual `runtimepath` | No (only Node.js-based coc extensions) |
| Git (GitHub repos + semver tags) | Yes, today | Tags per release | One plugin-manager line | Yes: `vim.pack` [V1], lazy.nvim [L1] |

Neither npm nor Mason is a viable way to publish codestyle.nvim or its Language Plugins. Both add a non-Neovim tool and a manual runtimepath step, and neither is how users install Lua plugins. The other non-Git channel that Neovim plugin managers do read is LuaRocks (lazy.nvim's `rockspec` source [L2]); it is outside the scope of this ticket.

## Sources

- [M1] mason-registry `CONTRIBUTING.md`, main: https://github.com/mason-org/mason-registry/blob/main/CONTRIBUTING.md — sections "Requirements", "Package specification", `categories`, `bin`, `share`, `opt`, "Examples" (LuaRocks, npm).
- [M2] mason.nvim `README.md`, main: https://github.com/mason-org/mason.nvim/blob/main/README.md — introduction L38–44, "Requirements" L75–89, settings L216–242.
- [M3] mason.nvim `doc/mason.txt`, main: https://github.com/mason-org/mason.nvim/blob/main/doc/mason.txt — "REGISTRIES", "HOW TO INSTALL PACKAGES".
- [M4] mason.nvim issue #279 "[New package]: flutter-tools.nvim", maintainer comment: https://github.com/mason-org/mason.nvim/issues/279
- [M5] GitHub code search `repo:mason-org/mason-registry "pkg:luarocks"` (2026-11-07): `packages/{digestif,luacheck,fennel-ls,luaformatter,teal-language-server}/package.yaml`.
- [M6] mason.nvim issue #324 "`mason-null-ls.nvim`": https://github.com/mason-org/mason.nvim/issues/324
- [V1] Neovim `runtime/doc/pack.txt`, master: https://github.com/neovim/neovim/blob/master/runtime/doc/pack.txt — L221–222 (Git required), L518–519 (`src`).
- [L1] lazy.nvim, Plugin Spec, "Spec Source": https://lazy.folke.io/spec
- [L2] lazy.nvim `README.md` L64–65 (luarocks rockspecs): https://github.com/folke/lazy.nvim/blob/main/README.md
- [N1] npm docs, "folders": https://docs.npmjs.com/cli/v10/configuring-npm/folders
- [N2] npm registry search API, `https://registry.npmjs.org/-/v1/search?text=keywords:neovim-plugin` (and `keywords:neovim`, `keywords:nvim`); `https://registry.npmjs.org/codestyle.nvim` returns "Not found" (2026-11-07).
- [N3] omp.nvim README: https://github.com/rauls-kjarners/omp.nvim
- [C1] coc.nvim install page: https://cocnvim.com/install
- [C2] coc.nvim "Using coc extensions": https://cocnvim.com/docs/using-coc-extensions
