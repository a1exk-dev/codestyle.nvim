# PROTOTYPE: Menu (throwaway)

Answers "How should the Menu look and behave?" ([#11](https://github.com/a1exk-dev/codestyle.nvim/issues/11), map [#1](https://github.com/a1exk-dev/codestyle.nvim/issues/1)).
Three Menu variants in one throwaway Lua plugin, switched with `]v` / `[v`. This branch is never merged.

## Run

From the repository root, in your own Neovim, so that your Tree-sitter parsers and `vim.ui.select` picker are used:

```sh
nvim -c 'source prototype/menu/init.lua'
```

`q` closes the Menu. `:CodestyleProto [1|2|3]` opens it again. `g?` lists the keys.

## Variants

| | Layout | Language and Tab navigation | Where the Tab strip lives |
|---|---|---|---|
| **A · Dialog** | A modal dialog of floats over a dim backdrop: language list, Options, Preview (like PhpStorm) | Moving the cursor in the language list switches the language. `<Tab>`/`<S-Tab>` switch the Tab, or click it. `<C-h>`/`<C-l>` move between panes | Fixed `winbar` of the Options float: it stays visible while scrolling and can be clicked |
| **B · Workspace** | Its own tabpage with normal splits: tree, Options, Preview. Neovim resizes them, `<C-w>` and the mouse move between them | One tree of languages with their Tabs (the operator's sketch). Moving the cursor over a Tab opens it, `<CR>` opens it and jumps to the Options. `]t`/`[t` next/prev Tab | Tree nodes in the sidebar, plus a breadcrumb `PHP › Spaces` in the `winbar` |
| **C · Page** | Its own tabpage: one page buffer (lazy.nvim style) above, Preview below | Pills: `1`–`5` pick the language, `H`/`L` the Tab, or click a pill. `f` filters the Options of **every** Tab of the language, with breadcrumbs. The Preview follows the Tab of the Option under the cursor | Buffer text: `/` finds anything, but it scrolls away |

## Same in every variant

- **Option rows**: `[x]` checkbox, `‹ choice ›`, `[ 4 ]` integer, `"string"`, `order` as a summary. `<Space>` toggles or cycles, `<CR>` edits (`vim.ui.select` for a choice, `vim.ui.input` with a range check for an integer, a small float for an `order`: `<C-j>`/`<C-k>` move, `<CR>` apply), `l`/`h` next/previous value (integers step by 1), `x` resets to the default.
- **Groups** fold with `<CR>`/`za`. A Group with its own Option (a wrap choice) shows its value on the header row. `za` folds it, the other keys edit it.
- **Changed values** (not the default) use a blue label, and each language shows `•N` changed values: the files store only these.
- **Dependent Options** (Smart tabs, the trailing-comma Style radios, formatter markers) are dimmed and refuse edits, with a message that names the Option they need.
- **Inherited value**: "Hard wrap at" shows `Default: 120` from General until it is set. An empty input inherits again.
- **Scope**: the Menu shows "Global Code Style" or "Project Code Style" and its path. `s` switches. The first switch offers: copy the Global Code Style, start from the defaults, or import `.idea/codeStyles/Project.xml`. `i` imports it at once (the prototype pretends that the file exists).
- **Kept values**: `⚠ yaml: not installed, 3 kept values`.
- **Set from…** (`p`) lists the language's Presets and "Copy from <language>". It only notifies: Presets are decided in their own ticket.
- **Preview**: re-formatted on each change. The lines that changed stay marked until the output changes again. The status shows the highlighter (`treesitter` or the Vim `syntax` fallback), how many lines changed, and when the toy engine ignores the Option under the cursor. Whitespace is visible (`list`).

## Stubs and limits

- No file is read or written. Values live in memory and survive variant switches, not a restart.
- The Preview uses a **toy** regex formatter (`engine.lua`), not the ADR-0002 engine. It knows indents, "Before parentheses", class and function brace placement, "Keep maximum blank lines in code", PHP True/False/Null case and else if, TypeScript quotes and semicolons, and the Shell case indent and redirect spaces.
- Data comes from the Research Corpus (`gen_data.py` → `lua/codestyle_proto/data.lua`): General, PHP, TypeScript, Shell Script, JSON. Code Generation and TypeScript Imports are left out (Reformat never applies them), as are "Wrap on typing" and "Visual guides". The Arrangement Tab is a placeholder.
- Only Neovim 0.10 APIs are used.
