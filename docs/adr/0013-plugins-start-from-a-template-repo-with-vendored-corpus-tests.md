# Language Plugins start from a template repo with vendored corpus tests

Every Language Plugin starts from one GitHub template repo, `codestyle-language-template.nvim`. "Use this template" copies it, and `nvim -l scripts/init.lua <id> <Name>` fills in the placeholders and deletes itself. Plugin repos are named `codestyle-<id>.nvim`. The Research Corpus is a local folder and no repo or CI runner can reach it, so each plugin commits its own unchanged copy of its language's part of the corpus. Its tests run headless with nothing outside Neovim and Lua ("What does the Language Plugin template repo contain?", #31).

## Layout

- `lua/codestyle/languages/<id>.lua` (the spec) and the lazy `formatter`, `scheme` and `arrangement` modules of ADR-0007. The `arrangement` table and module are optional (ADR-0011, ADR-0012).
- An Option that the plugin offers but cannot match carries `flagged = '<reason>'` in the spec. The Menu shows the flag, and the tests expect that Option's records to fail. The fields of an Option that v1 leaves out are in the `scheme` module's left-out list (ADR-0007), so their records are skipped.
- `test/corpus/`: an unchanged copy of the language's Behaviour Records, its `arrangement-*` cases (`tests/gui/arrangement/<lang>/`) and its `presets.json` entries, with a `SOURCE` file that names the PhpStorm build. A Core dev script (`nvim -l`, run by a maintainer who has the Research Corpus) writes it. The files are committed and never edited by hand.
- `test/cases/<name>/`: hand-written cases with `input.<ext>`, `codestyle.json` (the stored `languages.<id>` shape of ADR-0001 and ADR-0003, `arrangement` included) and `output.<ext>`, and an optional `range` for selection tests. They serve languages with no records (Makefile, third parties) and regression cases.
- `test/expected_failures.lua`: case id (`<record>/<base>/<value>/<file>` or `case/<name>`) → reason, for single cases such as the fixed CSS `;` bug (ADR-0011).
- `test/run.lua` and `test/deps.lua`. `README.md`, `CONTRIBUTING.md`, and a hand-written `doc/codestyle-<id>.txt` that points to `:help codestyle`.

## Tests and CI

- `nvim --headless -l test/run.lua` runs `codestyle.testing` over `test/corpus/` and `test/cases/`. The formatter records run with Arrangement off, and the `arrangement-*` cases run on their own (ADR-0011). Presets are checked against their `presets.json` diff (ADR-0006). An unexpected failure fails the run, and so does an unexpected pass, so the list of expected failures only shrinks. No test framework is used.
- The run clones its dependencies into a gitignored `.tests/` at the refs in `test/deps.lua`: the Core at a release tag, nvim-treesitter at a pinned commit (its lockfile pins every grammar revision, and the goldens depend on them), and every `uses` plugin. It installs the parsers that the spec and its Embed Points name. The same command runs locally and in CI.
- The required checks are the tests on Neovim 0.11 and stable, `typos`, `stylua --check`, and `lua-language-server --check` against the Core's LuaCATS annotations of the contract. Tests also run on nightly, but that check is not required.
- A weekly canary job (not a required check) runs the tests against Core `develop` and opens one issue when they fail.

## Corpus scaffold

The Core dev script can also write a first draft (`--scaffold`) of the spec and the `scheme` module from the Research Corpus. The draft has Tabs, Groups and Options in UI order with labels, types, defaults and fields, plus the Presets and the `arrangement` data. Own keys are `TODO_` placeholders, and dependencies are comments. After that the files are edited only by hand and never regenerated, because own keys (ADR-0003), flags and merged Options are human choices. PhpStorm's Preview samples come from closed JetBrains code, so the script copies them only into a gitignored reference file. Each plugin writes its own sample per Tab, with the same constructs.

## Following the Core

- A contract `api` bump comes with a migration section in the Core's release notes. The template gets the same change in a commit tagged `api-<N>`, and a plugin applies `git diff api-<N-1> api-<N>` of the template by hand.
- The template's own CI runs `init.lua` on a throwaway copy, with Neovim's bundled `query` parser, and runs every check on the result. So the template keeps working between plugin launches.

## Repo process

Plugin repos follow the Core's process: Git Flow with `develop` and `main`, and the same commit policy and release workflow. They carry full copies of the Core's skills (through `skills-lock.json`), `AGENTS.md`, `CLAUDE.md` and `docs/agents/`. The Core's ADRs and `GLOSSARY.md` are copied into `docs/core/`, and plugins never edit them there. A weekly workflow copies them from the Core's `main` and opens a PR into `develop` when they changed. A plugin records its own decisions in `docs/adr/` from 0001, and its own terms in its own `GLOSSARY.md`.

## Considered Options

- **A generator in the Core**, or **the JSON plugin as the only example**. Rejected: a third party would need the Core checked out, and an example mixes JSON details into the shared layout.
- **Records converted to our own format**, or **the corpus published and fetched by CI**. Rejected: a converter must be right before any test means anything and leaves the `scheme` mapping untested, and publishing makes the 140 MB corpus a public interface that every CI run downloads.
- **busted or mini.test.** Rejected: luarocks or a test-only dependency, and `codestyle.testing` already runs the cases. The Core itself uses mini.test for its Menu screenshots (ADR-0017).
- **The newest parsers, or the developer's own setup.** Rejected: a red run could come from an upstream grammar or from one developer's machine, not from the change.
- **A spec regenerated from the corpus plus an overrides file.** Rejected: hand decisions would live in a layer that is harder to read than the spec.
- **PhpStorm's Preview samples as they are.** Rejected: the public repos would carry closed-source JetBrains text.
- **Trunk with release-please**, or **a short AGENTS.md**. The operator chose one process and one agent setup across all repos.
