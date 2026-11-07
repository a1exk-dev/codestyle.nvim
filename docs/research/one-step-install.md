# How do Neovim plugin families with extensions in separate repos let a user install the core plus chosen extensions in one step?

Research for issue [#85](https://github.com/a1exk-dev/codestyle.nvim/issues/85) (map: [#83](https://github.com/a1exk-dev/codestyle.nvim/issues/83)). It feeds the grilling ticket [#87](https://github.com/a1exk-dev/codestyle.nvim/issues/87), which decides.
Question: how do plugin families whose extensions live in separate repos tell users to install the core and the extensions they choose, and which mechanisms in lazy.nvim, LazyVim, `vim.pack` and luarocks install several plugins from one entry?

Date of research: 2026-11-07. Sources: Neovim `v0.12.6` (current stable) and `v0.11.7`, lazy.nvim `306a055` (v11.17.5) and its docs site source (branch `docs`, `cef6b39`), LazyVim `301a3f7` and its docs site `d6430ed`, neotest `27bf921`, neotest-python `1b56ca4`, nvim-dap `cfa2d58`, nvim-dap-ui `cc9dd33`, nvim-dap-virtual-text `fbdb48c`, nvim-dap-python `1808458`, mason-nvim-dap.nvim `9a10e09`, telescope.nvim `40aedd8`, telescope-fzf-native.nvim `b25b749`, nvim-cmp `fe29aba`, cmp-nvim-lsp `cd4ee08`, cmp-buffer `b74fab3`, blink.cmp `7b31e1b`, mini.nvim `9b132c1`, mini.ai `a4f5648`, conform.nvim `016802d`, nvim-lint `52107ce`, mason-lspconfig.nvim `55eceab`, nvim-treesitter `main` `19bdfc0` and `master` `cf12346`, nvim-treesitter-textobjects `5c7b026`, noice.nvim `7bfd942`, render-markdown.nvim `8e87953`, snacks.nvim `882c996`, rocks.nvim `8a2fbfd`. Full hashes are in "Sources". Line numbers are for these versions. Terms follow `GLOSSARY.md`: the **Core** is codestyle.nvim, a **Language Plugin** is one `codestyle-<id>.nvim` repo. This note gives facts and no design.

## Answer

- **No family in this sample installs core plus extensions from one entry in a plugin manager.** In every family the user lists the core and each extension as separate entries. The one-entry mechanisms that exist are in the plugin managers, not in the families: lazy.nvim's `dependencies`, `import` and package specs (`lazy.lua`, rockspec, `pkg.json`), LazyVim extras, and luarocks dependencies (rocks.nvim, or lazy.nvim's rockspec source). `vim.pack` has none.
- **Install snippets put the extension in the user's list, either next to the core or as a `dependencies` entry.**
  - neotest: core plus `nvim-nio` as `dependencies` (lazy.nvim) or `requires` (packer), or flat `Plug` lines. Then "you will also need to install an adapter", with no snippet [NT1 L28–85].
  - nvim-dap-ui lists `nvim-dap` and `nvim-nio` as `dependencies` of itself, so the extension pulls in the core, not the other way round [DUI L10–40]. mason-nvim-dap lists `mason.nvim`, `nvim-dap` and itself as three flat entries and warns that load order matters [MND L42–79].
  - telescope: core with `plenary.nvim` and `telescope-fzf-native.nvim` (`build = 'make'`) in `dependencies` [TS1 L68–83].
  - nvim-cmp: eight flat `Plug` lines, core and sources side by side [CMP1 L28–59].
  - blink.cmp: `dependencies = { 'saghen/blink.lib', 'rafamadriz/friendly-snippets' }` for lazy.nvim, and both repos in one `vim.pack.add` list [BL2 L8–64].
  - render-markdown.nvim: deps in `dependencies` (lazy.nvim), in the same `vim.pack.add` list, `requires`/`after` (packer), and one `:Rocks install` [RM1 L69–118].
- **Registration of extensions falls into five kinds.**
  - *Explicit list in the core's `setup()`.* neotest needs `adapters = { require("neotest-python"), … }`. Its default is `adapters = {}` [NT1 L139–155; NT2 L161]. nvim-cmp and blink.cmp enable sources by name in `sources` / `sources.default` [CMP1 L95–104; BL3 L11–35].
  - *Self-registration by the extension.* cmp sources call `require('cmp').register_source(...)` from their own `after/plugin/` file [CMP2 L960; CMP3 L1; CMP4 L1]. nvim-dap extensions write into `dap.listeners`, `dap.providers.configs`, `dap.adapters` and `dap.configurations` when the user calls their `setup()` [DP2 L1252–1278, L1396–1420; DPY2 L248, L304–313; DUI L168–184].
  - *Runtimepath module namespace, loaded on first use.* telescope does `require("telescope._extensions." .. name)` on first access to `extensions[name]`. `load_extension(name)` loads it early; without it the extension is loaded lazily but tab completion is missing [TS2 L7–26; TS1 L521–532]. nvim-lint and conform look up a missing linter or formatter by `require('lint.linters.' .. name)` / `require("conform.formatters." .. name)` [NL L155–165; CF L716].
  - *Monorepo with standalone mirrors.* mini.nvim ships all modules in one repo and mirrors each module to its own repo (`nvim-mini/mini.ai`). The user installs either the library or the mirror, and calls each module's `setup()` [MI1 L36–90; MI2 L55–87].
  - *Bridge plugin.* mason-lspconfig and mason-nvim-dap connect two cores and need both installed and set up first [MLC L50–87; MND L35–79].
- **lazy.nvim `dependencies`** are "plugin names or plugin specs that should be loaded when the plugin loads", and are "always lazy-loaded unless specified otherwise" [LZD1 L23]. In code, a plugin that appears only as a dependency gets `lazy = true` [LZ1 L233–243]. On load, lazy.nvim adds the parent to the runtimepath, then loads every dependency, then runs `:packadd` and `config` for the parent [LZ2 L343–363]. A bare name such as `dependencies = "mason.nvim"` refers to a spec defined elsewhere [LZD1 L23; LV6 L109].
- **lazy.nvim merges several specs of one plugin.** "`opts`, `dependencies`, `cmd`, `event`, `ft` and `keys` are always merged with the parent spec. Any other property will override" [LZD2 L62–66]. A table `opts` is deep-merged. A function `opts(plugin, opts)` may change the table in place or return a new one that replaces it [LZD1 L33; LZ1 L447–486]. `opts_extend = { "a.b" }` makes the list at that dotted path concatenate instead of being replaced [LZ1 L470–483]. `opts_extend` is in lazy.nvim's code but not on its docs pages (searched `docs/`). LazyVim uses it for `ensure_installed` of nvim-treesitter and mason, and for blink's `sources.default` [LV4 L25; LV5 L287; LV10 L19–23].
- **lazy.nvim `import`** loads every spec module under a Lua module path, for example `{ import = "lazyvim.plugins.extras.coding.copilot" }` [LZD2 L38–60; LZ1 L118–211]. When the module is in a plugin that is not installed yet, lazy.nvim installs it and parses again: "multiple rounds can happen when importing a spec from a missing plugin", with at most 5 rounds [LZ2 L36–52, L66–67].
- **lazy.nvim package specs let a plugin repo declare its own dependencies.** Sources are `lazy.lua` at the repo root (recommended), a `*-scm-1.rockspec`, and `pkg.json` (experimental). The first source found wins. The default is `pkg.sources = { "lazy", "rockspec", "packspec" }` [LZD3 L6–41; LZD4 L53–62]. The docs tell plugin authors to "include a package spec in your repo" [LZD5 L7–21].
  - lazy.nvim reads the package file only after the plugin is cloned [LZ5 L49–72; LZ6 L9–26]. It wraps the content as `{ <plugin name>, specs = <content> }` [LZ5 L103] and tags the plugin's own top-level fragments `optional` [LZ3 L31–51]. So a `lazy.lua` cannot add its own plugin. It adds specs only inside the scope of a plugin that the user already lists, and they go away when that plugin is disabled [LZD3 L15–18; LZD1 L91].
  - Example: noice.nvim's `lazy.lua` adds `{ "MunifTanjim/nui.nvim", lazy = true }` [NO1 L1–7]. Its README still lists `nui.nvim` in `dependencies` [NO2 L38–58].
  - After a clone, lazy.nvim refreshes the package cache and reloads the spec. At startup, newly named plugins are installed in the next round [LZ9 `manage/init.lua` L85–96; LZ1 L380–383; LZ2 L44–50]. `Runner:update` only refreshes plugins already in a run [LZ9 `runner.lua` L54–58]. Whether a dependency that a `lazy.lua` names is installed in the same interactive `:Lazy install` run is unverified.
  - Rockspec source: when the rockspec names Neovim plugin rocks, lazy.nvim maps them to git specs through a generated luarocks name→repo table, for example `plenary.nvim` → `{ "nvim-lua/plenary.nvim", lazy = true }` [LZ7 L21–24, L264–343; LZ8]. Telescope's rockspec lists `plenary.nvim`. nvim-dap-python's lists `nvim-dap` [TS4 L18–21; DPY3 L19–22]. The rockspec source only runs when `rocks.enabled` is true (default true) [LZ5 L35–41; LZD4 L63–72].
- **lazy.nvim auto-loads a lazy plugin when one of its Lua modules is `require`d** [LZD1 L65; LZ2 L531–575]. This works through the module loader. It does not cover a runtime-file search such as `nvim_get_runtime_file`. That is why ADR-0007 tells lazy.nvim users to list Language Plugins as `dependencies`.
- **LazyVim extras** are spec modules in `lua/lazyvim/plugins/extras/<category>/<name>.lua` inside the LazyVim repo [LV8 L30–33].
  - Users enable one with `:LazyExtras`, which writes the module name to `lazyvim.json` [LVD1 L3; LV8 L179–189; LV9 L143]. `plugins/xtras.lua` turns that list into `{ import = … }` specs in a fixed priority order. `test.core` and `dap.core` come first, so language extras can add to them [LV7 L1–81]. The other way is to write `{ import = "lazyvim.plugins.extras…" }` [LZD2 L53–60].
  - `:LazyExtras` lists two sources only: LazyVim's own extras and the user's `plugins.extras` [LV8 L30–33]. A plugin repo cannot add an extra to that list from outside.
  - A language extra marks specs of other families `optional = true`, so they apply only when the user enabled the matching core extra. Example: `lang.python` adds `neotest-python` to neotest's `dependencies` and `opts.adapters`, `nvim-dap-python` to nvim-dap, parsers to nvim-treesitter's `ensure_installed`, and sets an empty `mason-nvim-dap` handler for `python` so mason does not replace the adapter of nvim-dap-python [LV3 L26–29, L64–93, L119–128]. `test.core` converts adapter names in `opts.adapters` into `require(name)` and the adapter's `setup(config)`, then calls `neotest.setup` [LV2 L1–104].
  - Upstream rules (CONTRIBUTING): the plugin "should be well-known and require significant configuration"; "simple specs containing just the plugin with some options will not be accepted"; language extras need ecosystem experience, the most widely used setup, and a `recommended` section [LV1 L13–31]. The rules name no star count. They do not say that the plugin author must maintain the extra. Extras live in the LazyVim repo and go through LazyVim's PR template [LV1; LV12].
- **`vim.pack` ships with Neovim 0.12** ("Built-in plugin manager: `vim.pack`" in news). It is absent in 0.11.7 [NP3 L374; NP4]. It is still "experimental" [NP1 L210–211].
  - API: `vim.pack.add(specs, opts)`, `del`, `get`, `update`. A spec has `src`, `name`, `version` (branch, tag, commit or `vim.version.range()`) and `data` [NP1 L403–455].
  - The lockfile is `$XDG_CONFIG_HOME/nvim/nvim-pack-lock.json` [NP1 L226–235].
  - It has no dependency resolution. The words "depend", "pkg.json" and "packspec" do not appear in `pack.lua`. A second `add` of the same plugin does nothing ("allows users to put plugin first to fully control its spec") [NP2 L790–806].
  - Plugin READMEs document dependencies by listing them in the same `vim.pack.add` call before the plugin [BL2 L56–64; RM1 L71–82].
  - There are no lazy-load handlers. `opts.load` is `false` during `init.lua` (like `:packadd!`) or a custom function [NP1 L445–452]. Build steps are user autocmds on `PackChanged` / `PackChangedPre`, with `kind` = install, update or delete [NP1 L359–400].
- **How plugins declare required plugins and parsers.**
  - *README "Requirements"*: telescope (plenary), noice (nui, optional nvim-treesitter with named parsers), render-markdown (named parsers, required and optional), mason-lspconfig (with minimum versions) [TS1 L44–47; NO2 L28–36; RM1 L47–67; MLC L50–56].
  - *A sentence in the install section*: neotest says "Most adapters will also require a treesitter parser"; neotest-python says "Requires the treesitter parser for python"; nvim-dap-python points to `:TSInstall python` [NT1 L34; NTP L6; DPY1 L15–17, L51–60].
  - *`dependencies` in the recommended spec*: neotest, dap-ui, telescope, blink, render-markdown, noice [above].
  - *Package files*: noice `lazy.lua`, rockspecs of telescope, nvim-dap-python, nvim-cmp, nvim-dap, nvim-lint and rocks.nvim. No `pkg.json` in this sample.
  - *`:checkhealth`*: telescope checks that `plenary` can be `require`d and runs each loaded extension's `health` [TS3 L31–33, L103–116]. noice checks six parsers with `pcall(vim.treesitter.language.add, lang)` and warns [NO3 L125–139; NO4 L16–24]. render-markdown checks `markdown` (error) and `markdown_inline` (warning) with `vim.treesitter.get_parser` and `language.inspect` [RM2 L39–40, L136–160]. snacks has `Snacks.health.has_lang(langs)` built on `vim.treesitter.language.add` [SN2 L124–145; SN3 L40–48]. neotest has no health file.
  - *Version notes*: neotest no longer needs plenary; it uses `plenary.path` only if present [NT3 L68–70]. nvim-dap-virtual-text says nvim-treesitter is no longer a hard dependency, only the parsers are [DVT L1–17].
- **Who installs Tree-sitter parsers.** No extension plugin in this sample installs parsers itself. The ones that do:
  - nvim-treesitter `main` (Neovim 0.12+) through `require('nvim-treesitter').install{…}`. It needs `tree-sitter-cli` and a C compiler and "does not support lazy-loading" [TSM L13–70].
  - nvim-treesitter `master`, frozen for 0.11, through `ensure_installed` and `auto_install` [TSL L33, L83–130].
  - LazyVim installs its merged `ensure_installed` list on start. On Neovim < 0.12 it pins nvim-treesitter `main` to commit `7caec27` [LV4 L6–25, L79–96].
  - rocks.nvim installs parser rocks (`tree-sitter-<lang>`) and lets a rockspec list them as dependencies [RK L137–176].
- **rocks.nvim / luarocks** put dependencies in the plugin's rockspec, so `:Rocks install foo.nvim` installs the plugin with its plugin and parser rocks. The example is `dependencies = { "neotest", "tree-sitter-haskell" }` [RK L36–41, L60–98, L156–172]. lazy.nvim reads the same rockspecs (above). neotest, nvim-dap and render-markdown publish to luarocks [NT1 L30; DP1 L15; RM1 L98–104].

## Comparison of families

| Family | Repo layout | lazy.nvim install shape | `vim.pack` shape | Registration | Declares deps | Health check |
|---|---|---|---|---|---|---|
| neotest | core + one repo per adapter | core with `dependencies = { nvim-nio, FixCursorHold }`; adapters added by the user [NT1 L72–85] | none in README | explicit `setup{ adapters = {…} }` [NT1 L139–155] | README, rockspec on luarocks [NT1 L30] | none |
| nvim-dap | core + UI/virtual-text/language/bridge repos | each extension lists `nvim-dap` as its own dependency [DUI L36–40] | none | extension's `setup()` writes into `dap.*` tables [DP2 L1252–1278] | README "Requires" lines, rockspecs [DPY1 L6–13; DPY3 L19–22] | none read |
| telescope | core + extension repos | core with `dependencies = { plenary, { fzf-native, build = 'make' } }` [TS1 L74–83] | none | `telescope._extensions.<name>` module, `load_extension` optional [TS2 L7–26] | README, rockspec `plenary.nvim` [TS4 L18–21] | plenary + each extension's `health` [TS3] |
| nvim-cmp | core + one repo per source | flat list [CMP1 L28–59] | none | source self-registers from `after/plugin` + user `sources` list [CMP3; CMP1 L95–104] | none | — |
| blink.cmp (v2 on `main`) | core with built-ins + community sources | `dependencies = { blink.lib, friendly-snippets }`, `build` [BL2 L8–54] | one `add` list [BL2 L56–64] | `sources.providers[id].module` + `sources.default` [BL3 L11–35] | README | `:BlinkCmp status` [BL3 L87–89] |
| mini.nvim | monorepo + per-module mirrors | `{ 'nvim-mini/mini.nvim', version = '*' }` [MI1 L74–86] | `vim.pack.add({ … })` [MI1 L38–52] | per-module `setup()` [MI1 L90] | — | — |
| conform / nvim-lint | one repo with bundled registry | single plugin | — | `require('<ns>.' .. name)` lookup [CF L716; NL L155–165] | — | — |
| LazyVim extras | specs inside the LazyVim repo | `:LazyExtras` or `{ import = … }` [LVD1 L3; LZD2 L53–60] | — | spec merge + `optional` + `opts_extend` [LV3; LV4 L25] | in the extra's specs | — |

## Sources

Neovim (https://github.com/neovim/neovim, tag `v0.12.6` = `779c36969e31080503be2dfccbcc3f999e289606`):

- [NP1] `runtime/doc/pack.txt`: `packload-two-steps` L191–206, `vim.pack` L208–235, `vim.pack-examples` L237–265, `vim.pack-events` L359–400, `vim.pack.Spec` L403–418, `vim.pack.add()` L420–455.
- [NP2] `runtime/lua/vim/pack.lua`: `pack_add` L790–806, `M.add` L1004.
- [NP3] `runtime/doc/news.txt` L374.
- [NP4] `runtime/lua/vim/pack.lua` returns HTTP 404 at tag `v0.11.7` and 200 at `v0.12.0` (raw.githubusercontent.com).

lazy.nvim (https://github.com/folke/lazy.nvim, `306a05526ada86a7b30af95c5cc81ffba93fef97`, v11.17.5 per `lua/lazy/core/config.lua` L245). Docs site source, branch `docs` `cef6b397011701d900f9ba96cecc2eda1f8bc260` (rendered at https://lazy.folke.io):

- [LZD1] `docs/spec/index.md` (https://lazy.folke.io/spec): `dependencies` L23, `opts` L33, `lazy` L65, `optional`/`specs` L90–91, `import` L93.
- [LZD2] `docs/usage/structuring.md` (https://lazy.folke.io/usage/structuring) L38–66.
- [LZD3] `docs/packages.md` (https://lazy.folke.io/packages) L6–41.
- [LZD4] `docs/configuration/index.md` (https://lazy.folke.io/configuration): `pkg` L53–62, `rocks` L63–72.
- [LZD5] `docs/developers.md` (https://lazy.folke.io/developers) L7–60.
- [LZ1] `lua/lazy/core/plugin.lua`: `Spec:import` L118–211, `lazy` default L233–243, package reload L380–383, `M.values`/`M._values` with `opts_extend` L429–486.
- [LZ2] `lua/lazy/core/loader.lua`: install rounds L36–52, `install_missing` L66–93, load order L343–363, `auto_load`/`loader` L531–575.
- [LZ3] `lua/lazy/core/meta.lua`: `load_pkgs` L31–51.
- [LZ4] `lua/lazy/core/fragments.lua`: dependencies and child `specs` L149–170.
- [LZ5] `lua/lazy/pkg/init.lua`: `update` L32–83, wrapping in `specs` L103.
- [LZ6] `lua/lazy/pkg/lazy.lua` L1–27.
- [LZ7] `lua/lazy/pkg/rockspec.lua`: `skip`/`rewrites` L21–24, `get` L264–343.
- [LZ8] `lua/lazy/community/specs.lua` L1–7, `lua/lazy/community/init.lua` L1–28, `lua/lazy/community/_generated.lua`.
- [LZ9] `lua/lazy/manage/init.lua` L80–96 (install pipeline); `lua/lazy/manage/runner.lua` L54–58.

LazyVim (https://github.com/LazyVim/LazyVim, `301a3f71007c4aa5da5dab82f1a7a08389091224`); docs site https://github.com/LazyVim/lazyvim.github.io `d6430ed7125e9ab5f897b083f26a0dd308d88b74` (rendered at https://www.lazyvim.org):

- [LV1] `CONTRIBUTING.md` L1–31.
- [LV2] `lua/lazyvim/plugins/extras/test/core.lua` L1–104.
- [LV3] `lua/lazyvim/plugins/extras/lang/python.lua` L12–29, L64–93, L119–128.
- [LV4] `lua/lazyvim/plugins/treesitter.lua` L6–25, L79–96.
- [LV5] `lua/lazyvim/plugins/lsp/init.lua` L281–292.
- [LV6] `lua/lazyvim/plugins/extras/dap/core.lua` L19–30, L56–58, L81–128.
- [LV7] `lua/lazyvim/plugins/xtras.lua` L1–81.
- [LV8] `lua/lazyvim/util/extras.lua` L30–33, L43–57, L111–133, L179–189.
- [LV9] `lua/lazyvim/config/init.lua` L143.
- [LV10] `lua/lazyvim/plugins/extras/coding/blink.lua` L15–23.
- [LV11] `README.md` L59 (Neovim >= 0.11.2).
- [LV12] `.github/PULL_REQUEST_TEMPLATE.md`.
- [LVD1] `docs/extras/index.md` L3.
- [LVD2] `docs/extras/test/core.md` L1–22.

Plugin families:

- [NT1] neotest `README.md` L28–85, L139–155. [NT2] `lua/neotest/config/init.lua` L161. [NT3] `lua/neotest/lib/subprocess.lua` L68–70. https://github.com/nvim-neotest/neotest `27bf921498043f7ecd821d6db68d05de244bbd02`.
- [NTP] neotest-python `README.md` L1–14. https://github.com/nvim-neotest/neotest-python `1b56ca4ba51c6014f986d6548ee629bdc95589d1`.
- [DP1] nvim-dap `README.md` L13–35, L109–113. [DP2] `doc/dap.txt` `dap-extensions` L1252–1258, `dap-listeners` L1261–1278, `dap-providers` L1396–1420. https://github.com/mfussenegger/nvim-dap `cfa2d58f4537aca6ca83e2de1a0d9f1491121264`.
- [DUI] nvim-dap-ui `README.md` L10–40, L168–184. https://github.com/rcarriga/nvim-dap-ui `cc9dd33aade7f20bae414d0cba163bc60d4d4b43`.
- [DVT] nvim-dap-virtual-text `README.md` L1–17. https://github.com/theHamsta/nvim-dap-virtual-text `fbdb48c2ed45f4a8293d0d483f7730d24467ccb6`.
- [DPY1] nvim-dap-python `README.md` L6–17, L51–69. [DPY2] `lua/dap-python.lua` L248, L304–313. [DPY3] `nvim-dap-python-scm-1.rockspec` L19–22. https://github.com/mfussenegger/nvim-dap-python `1808458eba2b18f178f990e01376941a42c7f93b`.
- [MND] mason-nvim-dap.nvim `README.md` L35–79. https://github.com/jay-babu/mason-nvim-dap.nvim `9a10e096703966335bd5c46c8c875d5b0690dade`.
- [TS1] telescope.nvim `README.md` L44–91, L507–549. [TS2] `lua/telescope/_extensions/init.lua` L1–73. [TS3] `lua/telescope/health.lua` L31–33, L103–116. [TS4] `telescope.nvim-scm-1.rockspec` L18–21. https://github.com/nvim-telescope/telescope.nvim `40aedd8a68c78a656a10a8d62d80c54af59420fb`.
- [FZF] telescope-fzf-native.nvim `README.md` L32–79, L99–100. https://github.com/nvim-telescope/telescope-fzf-native.nvim `b25b749b9db64d375d782094e2b9dce53ad53a40`.
- [CMP1] nvim-cmp `README.md` L28–59, L95–104. [CMP2] `doc/cmp.txt` L960. https://github.com/hrsh7th/nvim-cmp `fe29aba4117227a6df637bc41e4b4fb4e98864a0`.
- [CMP3] cmp-nvim-lsp `after/plugin/cmp_nvim_lsp.lua` L1. https://github.com/hrsh7th/cmp-nvim-lsp `cd4ee08a988deb47ac3726f418fb27fe1a95729d`.
- [CMP4] cmp-buffer `after/plugin/cmp_buffer.lua` L1. https://github.com/hrsh7th/cmp-buffer `b74fab3656eea9de20a9b8116afa3cfc4ec09657`.
- [BL1] blink.cmp `README.md` L2 (v2 on `main`, v1 on `branch = 'v1'`). [BL2] `doc/installation.md` L1–64. [BL3] `doc/configuration/sources.md` L11–35, L87–89. https://github.com/saghen/blink.cmp `7b31e1b6497be70f620bbad83a789929248697ac`.
- [MI1] mini.nvim `README.md` L36–90. https://github.com/nvim-mini/mini.nvim `9b132c10d34675315327a7d58cc6684cb4e8faf2`.
- [MI2] mini.ai `README.md` L14–20, L55–100. https://github.com/nvim-mini/mini.ai `a4f5648dedf435e6306205135d1babb563b55d28`.
- [CF] conform.nvim `lua/conform/init.lua` L716; `lua/conform/formatters/` holds 265 files. https://github.com/stevearc/conform.nvim `016802de402556da54c36bd7359b441266b01cdd`.
- [NL] nvim-lint `lua/lint.lua` L155–165; `lua/lint/linters/` holds 191 files. https://github.com/mfussenegger/nvim-lint `52107ce2076a27a285af781248e2c59bad817cd0`.
- [MLC] mason-lspconfig.nvim `README.md` L50–87. https://github.com/mason-org/mason-lspconfig.nvim `55eceab8975036ac43a4176cbfe0d4bf1ddae93f`.
- [TO] nvim-treesitter-textobjects `README.md` L9–36 (lazy.nvim spec with `branch = "main"`, no dependency on nvim-treesitter; queries under `queries/<lang>/`). https://github.com/nvim-treesitter/nvim-treesitter-textobjects `5c7b0263797dfd1bd6202f2b219f3b53a80b2187`.
- [TSM] nvim-treesitter `main` `README.md` L13–70. https://github.com/nvim-treesitter/nvim-treesitter `19bdfc04f40ed2ccb3340591d125f759b0406875`.
- [TSL] nvim-treesitter `master` `README.md` L33, L83–89, L112–130. Same repo, `cf12346a3414fa1b06af75c79faebe7f76df080a`.
- [NO1] noice.nvim `lazy.lua` L1–7. [NO2] `README.md` L28–58. [NO3] `lua/noice/health.lua` L125–139. [NO4] `lua/noice/text/treesitter.lua` L16–24. https://github.com/folke/noice.nvim `7bfd942445fb63089b59f97ca487d605e715f155`.
- [RM1] render-markdown.nvim `README.md` L47–118. [RM2] `lua/render-markdown/health.lua` L39–40, L136–160. https://github.com/MeanderingProgrammer/render-markdown.nvim `8e8795368391036643b622875a6da6a51bcd33f4`.
- [SN1] snacks.nvim `README.md` L54–80. [SN2] `lua/snacks/health.lua` L124–145. [SN3] `lua/snacks/util/init.lua` L40–48. https://github.com/folke/snacks.nvim `882c996cf28183f4d63640de0b4c02ec886d01f2`.
- [RK] rocks.nvim `README.md` L36–54, L60–98, L137–176. https://github.com/nvim-neorocks/rocks.nvim (now `lumen-oss`) `8a2fbfd4fb9afce100b06da07203e1cd48313eb4`.

Not checked: packer.nvim and vim-plug source (their snippets are quoted only from the plugin READMEs above); dein; plugins other than snacks.nvim that require snacks.nvim; the luarocks.org pages themselves.
