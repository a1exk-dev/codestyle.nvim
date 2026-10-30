# The Menu is a float dialog on snacks.nvim, for Neovim 0.11+

The Menu is a modal dialog, like PhpStorm's Settings dialog: three floats over a dim backdrop. They hold the language list, the Options of one Tab, and the Preview. The operator chose this layout after trying three variants in the Menu prototype ([`prototype/menu`](https://github.com/a1exk-dev/codestyle.nvim/tree/prototype/menu/prototype/menu), "How should the Menu look and behave?", #11). The other two variants were splits in a tabpage and a single page buffer. The floats are laid out by `snacks.layout` and `snacks.win`, so snacks.nvim is a required dependency. The Core requires Neovim 0.11, the same minimum as LazyVim (0.11.2), NvChad and AstroNvim v6.

## Considered Options

- **No UI dependency**, with our own float layout and `VimResized` handler. The research recommended it ("Which Neovim UI patterns fit a form-style Menu with live Preview?", #7). It was rejected for snacks.nvim, which already handles nested boxes, `VimResized`, `WinResized`, the backdrop, and `fixbuf`.
- **snacks.nvim only when it is installed.** Rejected, because it needs two layout code paths.
- **A tabpage with splits** (no layout code), or **one page buffer** (lazy.nvim style). Both were tried in the prototype and not chosen.
- **Neovim 0.10** (the lowest version that runs the Menu pattern) or **0.12** (current stable, and nvim-treesitter's `main` branch). With 0.10, the engine would need a second code path for the old Tree-sitter match API. 0.12 would exclude distribution users who are still on 0.11.

## Consequences

- Every user installs snacks.nvim. Like the parsers, it is a Neovim plugin, so the rule "nothing outside Neovim, Neovim plugins and Lua" holds.
- The Menu still renders each pane as a scratch buffer drawn from a view model. Option labels are buffer text, so `/` finds them. `vim.ui.select` and `vim.ui.input` route to the user's own picker.
- Users with 0.11 get parsers from nvim-treesitter's locked `master` branch. The engine uses only Tree-sitter APIs that 0.11 has.
