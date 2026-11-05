# The Preview has no time budget and catches up to the latest Draft

The spec sets no latency budget, neither for the Preview nor for a large real buffer, and no check measures speed. The Core ships a bench script that a developer runs by hand, `nvim -l bench/run.lua`, which formats the Preview samples of every installed Language Plugin and prints the time of each step. It is never a CI check. Instead of a number, the Menu keeps two rules: keys never wait for the Preview, and Language Plugins keep no state between runs, so the Core may cache and re-run them ("What latency budget does the Preview keep when an Option changes?", #38). A toy engine formats the PHP Preview in about 1.2 ms (#3), and no sampled Neovim plugin benchmarks in CI (#39).

## Considered Options

- **A budget of 16 ms per Option change**, measured on the operator's machine or a GitHub runner. The operator first picked 16 ms, then dropped the number: speed is not a goal for v1, and a timing check on CI is noisy (mini.nvim multiplies its limits by 2 to 15, #39).
- **A budget for a large real file** (for example 5,000 lines of PHP). Dropped with the Preview budget. conform's `timeout_ms` cannot stop a synchronous Lua formatter: conform still applies the result, and only the formatters after ours in the chain time out (conform `runner.lua`).
- **A synchronous re-format in each key handler.** Simplest, but a slow third-party Language Plugin would make every key wait, and a held `l` would keep stepping after the key is released.
- **A debounce timer.** One run per burst of keys, but every single key press would wait for the timer.
- **A bench script that also times files the user names.** Rejected for samples only.
- **A caching API**, where plugins declare which Options change their Blocks. More speed, and more contract, for a goal v1 does not have.

## Consequences

- **Update path:** an Option change writes the Draft at once and marks the Preview out of date. The Core queues one re-format with `vim.schedule`, and a change that arrives while one is queued adds nothing. Neovim handles typed keys before scheduled callbacks (`src/nvim/state.c`), so a held key skips values in between, and the Preview always ends on the latest Draft. While the Preview is out of date, it shows the previous output with no marker.
- **Failure:** when a Language Plugin's code raises an error in a Preview run, or `shfmt` exits with an error, the Preview keeps the last good output. Its status line shows `⚠ <language id>: formatter error`, the full error goes to `:messages`, and the next run that succeeds clears the marker. The Draft keeps the change. Syntax errors and missing parsers keep the rules of ADR-0002 and ADR-0014.
- **Plugin state (ADR-0007 amended):** `build`, `rules`, the `before`/`after` steps, `format` and `entries` read only `ctx` and their arguments, and keep nothing between runs. So the same input gives the same output. The Core may cache its own work, such as the parse of a Preview sample, which does not change with an Option, and it may run any plugin function again at any time. `codestyle.testing` runs each case twice and fails when the outputs differ. The contract has no caching API.
- **Real buffers** stay synchronous with no size limit (ADR-0014).
