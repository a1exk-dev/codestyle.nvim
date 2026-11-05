# The Core tests with mini.test on fake languages

The Core's own tests run on mini.test. They format small fake Language Plugins that live in the Core repo and use the parsers that ship with Neovim. Only a few key Menu screens are compared as screenshots. The real first-party plugins run against each Core pull request in a job that is not required ("How is the Core tested beyond the Behaviour Record golden tests?", #40). mini.test is the only sampled runner that needs nothing but Neovim and a Neovim plugin, and the only one that compares screenshots. snacks.nvim and lazy.nvim run their tests on it, and plenary.busted is about to be archived (#39).

## Runner

- One headless command runs mini.test over `tests/`. Each Menu case runs in a child Neovim with a fixed size, colour scheme and status line, so screenshots stay the same across Neovim versions.
- mini.test, snacks.nvim and conform.nvim are test dependencies, pinned to commits like the plugins' `test/deps.lua` (ADR-0013), in a gitignored `.tests/`.
- Language Plugins keep their no-framework runner (ADR-0013). The Core's tests test `codestyle.testing` itself, including the run-twice check (ADR-0016), on the fake languages.

## What is tested

- Each part has its own tests, written against what it offers the rest of the Core: the engine (Blocks, Gaps, Indent, Wrap, Alignment, the host/HTML merge, Embed Points), Arrangement, Code Style storage and migrations, the Scheme XML reader and import, the Draft with undo/redo, Presets, plugin discovery and the `api` check, the format entry points (`<Plug>` map, `formatexpr`, `:Codestyle format`, the conform formatter), and the Menu.
- No coverage is measured. No speed is checked; the bench script stays hand-run (ADR-0016).
- Storage tests point the `XDG_*` folders and the repo root at a temporary directory.

## Fake languages

- A few Language Plugins in `tests/fixtures/` on Neovim's bundled parsers (`lua`, `c`, `markdown`), each with only the rules that a case needs. Markdown with a fenced Lua block covers Embed Points.
- One fake plugin raises an error, to test the Preview's failure marker (ADR-0016).
- So the required tests need no parser download, no `tree-sitter-cli` and no C compiler.

## Menu

- About 10–20 reference screenshots: the Menu just opened, each kind of value control, the filter, the Arrangement rule float, the failure marker, a narrow window. Every other Menu test checks facts: the Draft, buffer lines, marks.
- One test holds a key and checks that the Preview ends on the latest Draft (ADR-0016).

## CI

- Required checks, on Linux: the tests on Neovim 0.11 and stable, `typos`, `stylua --check`, `lua-language-server --check`. The same set as the Language Plugins (ADR-0013). The tests also run on nightly, but that check is not required.
- A job that is not required runs the tests of every first-party Language Plugin against the pull request's Core, so a break shows up before the plugins' weekly canary.

## Considered Options

- **No framework, like the Language Plugins.** Rejected: the Menu is the largest part of the Core, and only screenshots check its floats as the user sees them.
- **plenary.busted** (telescope, conform, neogit). Rejected: about to be archived. **busted or `lazy.minit`** need luarocks, Python and a C compiler.
- **The JSON plugin as the only test language.** Rejected: the Core's required tests would depend on another repo and a compiled parser, and JSON has no Embed Points.
- **A screenshot in every Menu test.** Rejected: every layout change would rewrite hundreds of files.
- **macOS and Windows runs.** Rejected: nothing in the spec depends on the OS, and checks that never block get ignored.
