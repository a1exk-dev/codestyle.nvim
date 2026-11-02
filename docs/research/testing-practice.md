# How do popular Neovim plugins test their Lua code and floating UI?

Research for issue [#39](https://github.com/a1exk-dev/codestyle.nvim/issues/39) (map: [#1](https://github.com/a1exk-dev/codestyle.nvim/issues/1)). It feeds the ticket that #39 blocks ([#40](https://github.com/a1exk-dev/codestyle.nvim/issues/40)), which decides how the Core is tested.
Question: how do popular Neovim plugins test their Lua code and their floating UI, headless and in CI, and what does each way need installed?

Date of research: 2026-11-03. Sources: snacks.nvim `882c996`, mini.nvim `6d5a29e` (v0.18.0), lazy.nvim `306a055`, conform.nvim `016802d`, nvim-treesitter `0195cd6` (`main`) and `cf12346` (`master`), neogit `697ad3e`, telescope.nvim `40aedd8`, plenary.nvim `74b06c6`, plentest.nvim `bff0bf2`, folke/github `d1cb00f` (the shared CI of snacks.nvim and lazy.nvim), and Neovim v0.12.6 on this machine. Full links are in "Sources". Line numbers are for these commits. The repos were read, not run. Terms follow `GLOSSARY.md`. This note gives facts and no design.

The project rule is "nothing outside Neovim, Neovim plugins and Lua" (ADR-0002), with the user's `shfmt` as the only exception. No runner below ships with a plugin: each is a test-only dependency. Where a runner needs more than Neovim and Neovim plugins, the note says what.

## Answer

- **Four runners are in use.**

  | Runner | Used by | Needs, besides Neovim | Outside the rule? |
  |---|---|---|---|
  | mini.test, `MiniTest.run()` in `nvim --headless` | mini.nvim [MN1 L12–19] | mini.nvim (or the `mini.test` repo). Nothing else [MN3 L50–60] | no |
  | mini.test or busted through `lazy.minit` (`nvim -l tests/minit.lua --minitest` or `--busted`) | snacks.nvim, lazy.nvim [SN1; LZ2] | lazy.nvim, network access to GitHub, luassert or busted as rocks, so luarocks. With no `luarocks` on `PATH`, lazy.nvim builds one with hererocks, which needs `python3`, a C compiler and `libreadline-dev` [LZ1 L149–168, L188–204; LZ3 L26–52; LZ4 L238–242; FG1 L74–75] | yes: Python, a C toolchain, luarocks |
  | plenary.busted (`PlenaryBustedDirectory`, `plenary.test_harness`) | conform.nvim, neogit (unit), telescope.nvim [CF1 L10–15; NG3; TS1 L3–4] | plenary.nvim, which vendors luassert and say [PL3]. plenary "is no longer actively maintained and will be officially archived soon" [PL1 L7] | no, but unmaintained |
  | plentest.nvim, nvim-treesitter's own fork of the plenary harness with vendored luassert and say | nvim-treesitter [NT1 L89–95, L129–133] | plentest.nvim. Its README says "**Not for public use.**" [PT1] | no, but private |

  Plain `nvim -l` scripts are used for checks that are not test suites: nvim-treesitter's `check-parsers.lua` and `install-parsers.lua` [NT2 L35, L42; NT4], and the `tests/minit.lua` bootstrap of `lazy.minit` [SN2; LZ5]. No sampled repo runs busted through luarocks directly (`luarocks test`, nlua); luarocks appears only to install linters (luacheck, llscheck) [CF2 L18–26; NG2; PL2; TS3].
- **mini.test runs every case in a child Neovim.** `MiniTest.new_child_neovim()` starts `nvim --clean -n --listen <pipe> --headless --cmd 'set lines=24 columns=80'` with `jobstart` and talks to it over RPC [MN4 L1122–1158]. `child.lua()`, `child.api`, `child.o` and friends run code in the child. `child.type_keys()` sends keys with `nvim_input` and fails when the child reports an error [MN4 L1276–1301]. mini.nvim restarts the child before each case with its `scripts/minimal_init.lua` [MN5 L61–76].
- **Screenshot tests exist only in mini.test.** `child.get_screenshot()` reads `screenstring()` and `screenattr()` for every cell. The result has a `text` layer and an `attr` layer, where `attr` codes only "same or different look" per cell, not the highlight group [MN4 L1368–1390; MN2 L892–901]. `expect.reference_screenshot()` writes `tests/screenshots/<case id>` on the first run and compares later runs exactly. `force = true` rewrites it, and `ignore_text`/`ignore_attr` skip lines [MN4 L755–800; MN2 L903–962]. Floats appear in the screenshot with their borders and titles, for example the `mini.pick` window [MN7]. mini.nvim has 2632 reference screenshots in `tests/screenshots` [MN-count]. To keep screenshots the same across Neovim versions, its `minimal_init.lua` fixes the colour scheme, `ruler`, `statusline` and `termguicolors` [MN6 L5–30].
- **The others test UI as text, layout and state, not as screenshots.**
  - mini.nvim also checks floats through `nvim_win_get_config` (`relative`, `focusable`, `zindex`) and window options [MN8 L482–495].
  - neogit's end-to-end tests are Ruby: RSpec drives a child Neovim through the `neovim` gem, sends keys one by one with `input` and a 0.1 s sleep, and compares `screenstring()` rows (text only) against an expected `view` [NG4 L64–79, L174–189; NG5 L6–25]. Its unit tests are plenary.busted and check buffers and extmarks [NG6].
  - telescope.nvim's harness starts `nvim --headless --embed` with `jobstart`, types with `nvim_feedkeys` and fixed `vim.defer_fn` delays, and asserts on the prompt text, the best result and the selected file [TS4 L9–22; TS5 L33, L128–149; TS6]. Its picker tests are skipped on macOS and Windows as flaky [TS7 L1–4]. Layout code is tested as pure functions: `resolve_height` and `_validate_layout_config` with fixed `max_columns`/`max_lines` [TS8 L14–23].
  - snacks.nvim, which the Menu uses (ADR-0004), has no tests for `snacks.win` or `snacks.layout`. Its tests cover config, gitbrowse, scope, terminal, util and picker helpers [SN3].
- **Files under `stdpath()` and a repo root are kept in a temporary directory.**
  - `lazy.minit` points `XDG_CONFIG_HOME`, `XDG_DATA_HOME`, `XDG_STATE_HOME` and `XDG_CACHE_HOME` at `.tests/<name>` when `LAZY_STDPATH` is set [LZ1 L56–62], and lazy.nvim has a test that `stdpath()` really is under `.tests/` [LZ6 L3–10]. Its file tests write under `./.tests/fs` [LZ7 L5–35].
  - conform.nvim's `run_tests.sh` sets all five `XDG_*` variables to `.testenv/…` [CF3 L1–30].
  - mini.nvim sets `XDG_DATA_HOME` in the child per case [MN9 L146–148] and uses `child.fn.tempname()` for directories [MN10 L318].
  - neogit sets `NVIM_APPNAME=neogit-test`, `GIT_CONFIG_GLOBAL=/dev/null` and `GIT_CONFIG_SYSTEM=/dev/null` [NG1 L2], builds a fresh Git repo in a temporary directory for each case and `cd`s into it [NG7 L35–51]. The RSpec suite uses `Dir.mktmpdir` [NG8 L42–46].
- **Tree-sitter in tests comes from one of two places.**
  - **Neovim's bundled parsers**, which need nothing: v0.12.6 ships `c`, `lua`, `markdown`, `markdown_inline`, `query`, `vim` and `vimdoc` [NV1]. mini.nvim tests its Tree-sitter textobjects on the bundled `lua` parser with its own query files in `tests/mock-treesitter`, added to `runtimepath` [MN11 L744–756]. snacks.nvim's scope tests start Tree-sitter on a `lua` buffer [SN4 L6–19].
  - **nvim-treesitter, compiled in CI.** conform.nvim clones nvim-treesitter `main` at its newest commit (`--depth=1`, not pinned) and installs `markdown`, `markdown_inline`, `lua`, `typescript` and `html` in `minimal_init.lua` with `install(...):wait(30000)` [CF3 L17–21; CF1 L7–8]; its CI adds the tree-sitter CLI [CF2 L62–65]. nvim-treesitter itself installs every parser at the revision in `parsers.lua` [NT5 L5; NT6 L382–429]. On `main`, installing needs `tar`, `curl`, `tree-sitter-cli` 0.26.1 or later and a C compiler [NT7 L17–22; NT6 L206, L309–315]. On the frozen `master` (for 0.11) it needs `tar` and `curl` (or `git`), a C compiler with libstdc++, and `tree-sitter-cli` up to 0.25.x; its pins are in `lockfile.json` [NT8 L33, L67–72; NT9]. These are test-only, outside the rule, and the same as ADR-0013 already accepts for Language Plugins.
- **nvim-treesitter's indent tests have the shape of a corpus test.** Each language has a directory of files. The runner opens each, runs `silent normal gg=G`, and compares the indent of every line with the file. An `expected_failures` list makes a known failure pass, and the test then asserts that the indent is *not* the same [NT10 L71–80, L116–120, L172–192; NT11 L3–15]. conform.nvim tests its `injected` Lua formatter the same way: every file in `tests/injected/` is formatted and compared with `<file>.formatted` [CF4 L58–80], and a fuzzer sends random line changes through `runner.apply_format` and checks the buffer [CF5 L21–29].
- **No sampled repo measures coverage.** No repo has `luacov` in a workflow, Makefile, script or `.busted` file; lazy.nvim's `.busted` sets `coverage = false` [LZ8].
- **No sampled repo runs a benchmark in CI.** There are only timing assertions in normal tests: mini.nvim checks that a command takes 10–14 time units [MN12 L2408–2411], telescope.nvim gives its previewer a 250 ms timeout [TS9 L18–21], and plenary.nvim asserts that a job ends within 1 s [PL4 L327–333]. mini.nvim scales all its time constants in CI: ×2 on Linux, ×5 on Windows, ×15 on macOS [MN5 L303–311], and it skips some timing cases on slow runners [MN5 L298–301]. Benchmark helpers exist as libraries only: `MiniMisc.bench_time()` [MN13 L93] and `plenary.benchmark` [PL5].
- **CI matrices.**

  | Repo | Neovim versions | OS | Neovim install |
  |---|---|---|---|
  | mini.nvim | v0.10.4, v0.11.7, v0.12.5, nightly | Ubuntu; Windows only on v0.12.5 | `rhysd/action-setup-vim` [MN3 L40–57] |
  | snacks.nvim, lazy.nvim | stable only | Ubuntu | `folke/github/neovim` AppImage, default `stable` [FG1 L66–82; FG2 L4–7] |
  | conform.nvim | v0.12.2 only | self-hosted Ubuntu | AppImage script [CF2 L49–65; CF6] |
  | nvim-treesitter | stable, nightly | Ubuntu, macOS, Windows (no highlight or indent tests on Windows) | release tarball [NT2 L17–18, L52–58; NT3] |
  | neogit | stable, nightly; the job has `continue-on-error: true` | Ubuntu | `rhysd/action-setup-vim`, plus Ruby [NG2 L13–23] |
  | telescope.nvim | stable, nightly | Ubuntu, macOS, Windows | `rhysd/action-setup-vim`, plus ripgrep [TS2 L19–27, L37–48] |
  | plenary.nvim | v0.8.3, v0.9.5, v0.10.4, nightly | Ubuntu 22.04 | release tarball [PL2 L11–19, L27–33] |

## Details

### 1. mini.nvim and mini.test

- `make test` runs `nvim --headless --noplugin -u ./scripts/minimal_init.lua -c "lua require('mini.test').setup()" -c "lua MiniTest.run()"` for each `NVIM_EXEC` [MN1 L12–19]. `make test_<module>` runs one file [MN1 L21–31].
- The child gets `scripts/minimal_init.lua`, which adds the repo to `runtimepath` and fixes the look: a fixed `mini.hues` palette, `ruler` off, a fixed `statusline`, `PmenuMatch` links on 0.11+, `foldmethod=manual` for Lua and `termguicolors` [MN6 L1–34].
- `tests/helpers.lua` wraps the child: `child.setup()` restarts with the minimal init, and there are `set_lines`, `get_lines`, `set_cursor`, `set_size` and `expect_screenshot` (which can ignore the command line rows) [MN5 L61–140, L240–262]. Each helper fails at once if the child is blocked, for example waiting on a prompt, instead of hanging [MN5 L64–69].
- Screenshot files hold the text layer and the attr layer with line numbers and a column ruler, so a diff shows the changed cells [MN2 L934–960]. The file name comes from the case id. The docs warn about case-insensitive file systems and names longer than 143 bytes [MN2 L993–996].
- `screenattr()` cannot tell which highlight group a cell has, only whether two cells look the same; the docs say this is a Neovim limit [MN2 L899–901].
- mini.nvim mocks outside programs instead of calling them: `tests/mock-lsp`, `tests/mock-system`, `tests/mock-treesitter` [MN-ls].
- The CI job runs only when `colors/`, `lua/`, `tests/`, `scripts/minimal_init.lua` or a workflow changed [MN3 L14–38]. Other jobs: stylua `--check`, `typos`, docs regenerated and diffed, commit messages linted, file name lengths [MN3 L62–140].

### 2. snacks.nvim and lazy.nvim (`lazy.minit`)

- `scripts/test` is `nvim -l tests/minit.lua --minitest "$@"` [SN1; LZ9]. snacks.nvim's `tests/minit.lua` sets `LAZY_STDPATH=.tests`, loads lazy.nvim from `~/projects/lazy.nvim` or else downloads `bootstrap.lua` with `curl`, and calls `lazy.minit.setup` with the repo as the only spec [SN2 L1–17].
- With `--minitest`, `lazy.minit` adds `lunarmodules/luassert` and `echasnovski/mini.test` to the spec, sets `rocks.hererocks = true`, collects `tests/**/*_spec.lua`, replaces the global `assert` with luassert and calls `MiniTest.run()` [LZ1 L106–168]. So the busted-style `describe`/`it` files run under mini.test, in the same process, without a child Neovim. With `--busted` it adds `lunarmodules/busted` and calls `busted.runner` [LZ1 L170–211].
- Unless `--offline`, each run calls `require("lazy").update():wait()`, so it fetches every dependency's newest commit [LZ1 L68–70].
- hererocks runs `python3 hererocks.py -l 5.1 -r latest` [LZ3 L32–51]. The shared CI installs `libreadline-dev` for it and caches `.tests` keyed on `tests/minit.lua` and `scripts/test` [FG1 L74–82].
- The shared CI also runs stylua `--check` and a grep that fails on leftover `dd(` debug calls [FG1 L41–64].

### 3. conform.nvim

- `run_tests.sh` clones plenary.nvim and nvim-treesitter into `.testenv/data/nvim/site/pack/plugins/start` (or pulls them), sets all `XDG_*` variables under `.testenv`, and runs `nvim --headless -u tests/minimal_init.lua -c "RunTests"` [CF3 L1–30].
- `tests/test_util.lua` `reset_editor()` closes all other tabs and windows, deletes every buffer, clears conform's formatter tables and its augroup between cases [CF7 L6–21].
- `tests/fake_formatter.sh` is a shell script used as a command formatter in tests [CF5 L8–13].
- Lint jobs: luacheck (installed with luarocks), `stevearc/nvim-typecheck-action` (lua-language-server), stylua `--check` [CF2 L12–47].

### 4. nvim-treesitter

- `make tests` downloads Neovim, `highlight-assertions` (a Rust binary) and plentest.nvim into `.test-deps`, then runs `plentest.test_directory('tests/$(TESTS)')` with `scripts/minimal_init.lua` [NT1 L76–95, L129–133]. That init enables `vim.treesitter.start()` and the nvim-treesitter `indentexpr` on every `FileType` [NT4 L1–21].
- Highlight tests read assertions from comments in the sample files with `highlight-assertions` and compare the captures [NT12 L9–40].
- `scripts/ci-install.sh` downloads the release tarball and is meant to delete Neovim's bundled parsers so the compiled ones are used. On Linux the directory name in that `rm -rf` is misspelt (it does not match the extracted `nvim-linux-x86_64`), so the delete does nothing there [NT3 L12].

### 5. neogit

- `make test` runs `nvim --headless -S ./tests/init.lua` with an isolated `NVIM_APPNAME` and no global or system Git config [NG1 L2]. In CI, plenary.nvim and telescope.nvim come from `tmp/` clones; locally `ensure_installed` clones them [NG3 L3–19]. Cases run with `sequential = true` [NG3 L17–19].
- CI also clones diffview.nvim and builds telescope-fzf-native with `make` [NG2 L34–40].

### 6. telescope.nvim

- `make test` runs `PlenaryBustedDirectory lua/tests/automated/` with `scripts/minimal_init.vim`, which adds `../plenary.nvim` and sets `g:telescope_test_delay = 100` [TS1 L3–4; TS10 L1–7]. CI clones plenary.nvim and nvim-web-devicons next to the repo [TS2 L42–43].

### 7. plenary.nvim

- `plenary.test_harness.test_directory` starts one `nvim --headless` per spec file (in parallel unless `sequential`), with a default timeout of 50 000 ms [PL6 L44–54, L84–104, L137–161].

## Bearing on other tickets

- **#38 (Preview latency budget).** No sampled repo checks speed in CI. The timing checks that exist use wide windows and multiply their constants on CI runners (mini.nvim: ×2 Linux, ×5 Windows, ×15 macOS) [MN5 L303–311]. So a hard time limit in CI is noisy unless it has a wide margin.
- **#37 (How does a user format a real buffer?).** conform.nvim tests the write of a format result to the buffer (`runner.apply_format`) with a fuzzer [CF5], and its Lua formatter with input files and `.formatted` goldens [CF4]. nvim-treesitter tests `=` on whole files [NT10].

## Sources

- **SN** snacks.nvim [`882c996`](https://github.com/folke/snacks.nvim/tree/882c996cf28183f4d63640de0b4c02ec886d01f2): SN1 `scripts/test`; SN2 `tests/minit.lua`; SN3 `tests/` (`config_spec.lua`, `gitbrowse_spec.lua`, `scope_spec.lua`, `terminal_spec.lua`, `util_spec.lua`, `picker/*_spec.lua`); SN4 `tests/scope_spec.lua`.
- **LZ** lazy.nvim [`306a055`](https://github.com/folke/lazy.nvim/tree/306a05526ada86a7b30af95c5cc81ffba93fef97): LZ1 `lua/lazy/minit.lua`; LZ2 `.github/workflows/ci.yml`; LZ3 `lua/lazy/pkg/rockspec.lua`; LZ4 `lua/lazy/core/config.lua`; LZ5 `tests/minit.lua`; LZ6 `tests/core/init_spec.lua`; LZ7 `tests/helpers.lua`; LZ8 `.busted`; LZ9 `scripts/test`.
- **FG** folke/github [`d1cb00f`](https://github.com/folke/github/tree/d1cb00f0473c256299c7b35b6e199559366e56bc): FG1 `.github/workflows/ci.yml`; FG2 `neovim/action.yml`.
- **MN** mini.nvim [`6d5a29e`](https://github.com/nvim-mini/mini.nvim/tree/6d5a29e86a7352739506c28e0bc50fe214b5216f) (v0.18.0): MN1 `Makefile`; MN2 `TESTING.md`; MN3 `.github/workflows/quality-control.yml`; MN4 `lua/mini/test.lua`; MN5 `tests/helpers.lua`; MN6 `scripts/minimal_init.lua`; MN7 `tests/screenshots/tests-test_pick.lua---start()---works`; MN8 `tests/test_pick.lua`; MN9 `tests/test_visits.lua`; MN10 `tests/test_sessions.lua`; MN11 `tests/test_ai.lua`; MN12 `tests/test_git.lua`; MN13 `lua/mini/misc.lua`; MN-ls and MN-count: directory listings of `tests/` and `tests/screenshots/`.
- **CF** conform.nvim [`016802d`](https://github.com/stevearc/conform.nvim/tree/016802de402556da54c36bd7359b441266b01cdd): CF1 `tests/minimal_init.lua`; CF2 `.github/workflows/tests.yml`; CF3 `run_tests.sh`; CF4 `tests/injected_spec.lua`; CF5 `tests/fuzzer_spec.lua`; CF6 `.github/workflows/install_nvim.sh`; CF7 `tests/test_util.lua`.
- **NT** nvim-treesitter `main` [`0195cd6`](https://github.com/nvim-treesitter/nvim-treesitter/tree/0195cd62fa89950f34c0e0d648ea7897ab85d4d3): NT1 `Makefile`; NT2 `.github/workflows/test-core.yml`; NT3 `scripts/ci-install.sh`; NT4 `scripts/minimal_init.lua`, `scripts/check-parsers.lua`; NT5 `lua/nvim-treesitter/parsers.lua`; NT6 `lua/nvim-treesitter/install.lua`; NT7 `README.md`; NT10 `tests/indent/common.lua`; NT11 `tests/indent/lua_spec.lua`; NT12 `tests/query/highlights_spec.lua`. `master` [`cf12346`](https://github.com/nvim-treesitter/nvim-treesitter/tree/cf12346a3414fa1b06af75c79faebe7f76df080a): NT8 `README.md`; NT9 `lockfile.json`.
- **PT** plentest.nvim [`bff0bf2`](https://github.com/nvim-treesitter/plentest.nvim/tree/bff0bf281e65163f2237327e0b4af8d4de1fb9a6): PT1 `README.md`.
- **NG** neogit [`697ad3e`](https://github.com/NeogitOrg/neogit/tree/697ad3ee86a73cf6b6758b838d7a7d76cf3b9f86): NG1 `Makefile`; NG2 `.github/workflows/test.yml`; NG3 `tests/init.lua`; NG4 `spec/support/neovim_client.rb`; NG5 `spec/popups/branch_popup_spec.rb`; NG6 `tests/specs/neogit/lib/buffer_spec.lua`; NG7 `tests/util/git_harness.lua`; NG8 `spec/spec_helper.rb`.
- **TS** telescope.nvim [`40aedd8`](https://github.com/nvim-telescope/telescope.nvim/tree/40aedd8a68c78a656a10a8d62d80c54af59420fb): TS1 `Makefile`; TS2 `.github/workflows/ci.yml`; TS3 `.github/workflows/lint.yml`; TS4 `lua/telescope/testharness/init.lua`; TS5 `lua/telescope/testharness/runner.lua`; TS6 `lua/telescope/testharness/helpers.lua`; TS7 `lua/tests/automated/pickers/find_files_spec.lua`; TS8 `lua/tests/automated/layout_strategies_spec.lua`; TS9 `lua/tests/automated/previewer_spec.lua`; TS10 `scripts/minimal_init.vim`.
- **PL** plenary.nvim [`74b06c6`](https://github.com/nvim-lua/plenary.nvim/tree/74b06c6c75e4eeb3108ec01852001636d85a932b): PL1 `README.md`; PL2 `.github/workflows/default.yml`; PL3 `lua/luassert/`, `lua/say.lua`; PL4 `tests/plenary/job_spec.lua`; PL5 `lua/plenary/benchmark/init.lua`; PL6 `lua/plenary/test_harness.lua`.
- **NV** NV1 `nvim_get_runtime_file('parser/*', true)` on Neovim v0.12.6 (Arch package).
