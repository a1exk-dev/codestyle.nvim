# How do Neovim formatter plugins and built-in paths start a format run?

Research for issue [#36](https://github.com/a1exk-dev/codestyle.nvim/issues/36) (map: [#1](https://github.com/a1exk-dev/codestyle.nvim/issues/1)). It feeds the grilling ticket "How does a user format a real buffer?" ([#37](https://github.com/a1exk-dev/codestyle.nvim/issues/37)), which decides.
Question: how do users and formatter plugins start a format run on a real buffer, and where can a pure Lua formatter (ADR-0002) hook in?

Date of research: 2026-11-02. Sources: Neovim v0.11.7 and v0.12.6 (current stable) runtime and C source, conform.nvim `016802d`, LazyVim `301a3f7`, kickstart.nvim `8e35dbe`, none-ls.nvim `c4b82bb` and its wiki `1da216b`, guard.nvim `addb8d2`, formatter.nvim `b9d7f85`, neoformat `9d95e5c`, and the Research Corpus. Full hashes are in "Sources". Line numbers are for these versions. Where 0.11.7 and 0.12.6 behave the same, the 0.12.6 line is given and the 0.11.7 line is in the source list. Terms follow `GLOSSARY.md`. A **Section** is an `.editorconfig` glob block. "Format run" is the term of ADR-0002. This note gives facts and no design.

## Answer

- **conform.nvim accepts a formatter that is a Lua function.** A formatter config with a `format(self, ctx, lines, callback)` field and no `command` is a Lua formatter [CF1 L22–25]. conform calls it with a copy of the whole buffer's lines and a `ctx` with `buf`, `filename`, `dirname`, `range` and `shiftwidth` [CF1 L46–51; CF2 L340–357, L486–536]. The function returns the complete new lines through `callback(err, new_lines)`. conform then diffs old and new lines and applies only the changed hunks with `vim.lsp.util.apply_text_edits` [CF2 L182–293]. Its own `trim_whitespace`, `trim_newlines` and `injected` formatters work this way [CF6]. The author's limits: the function must not change the buffer, must not depend on buffer state, must not change the `lines` table, and must pass the full result to the callback [CF7].
- **conform has no real range formatting for Lua formatters.** Range formatting is "real" only when every formatter in the chain has `range_args`, which is a command-line field. Otherwise conform runs the formatter on the whole buffer and drops the diff hunks that lie outside the range ("aftermarket" range formatting, "best effort") [CF2 L248–251, L274–277, L620, L707; CF5 L17–21]. A Lua formatter still gets `ctx.range`, so it can limit itself to the range [CF6 `injected.lua` L268–270].
- **Users start a conform run in four ways:** the `format_on_save` option, which is a synchronous `BufWritePre` autocmd [CF3 L89–122]; the `format_after_save` option, which is an asynchronous `BufWritePost` autocmd followed by `:update` [CF3 L124–175]; a key or command that calls `require('conform').format()` [CF4 L16–30, L145–163]; and `gq` through `formatexpr = "v:lua.require'conform'.formatexpr()"` [CF3 L822–856]. conform itself defines only the `:ConformInfo` command and no key [CF8].
- **`lsp_format` decides whether LSP formatting runs with or instead of conform's formatters.** The values are `never` (the default), `fallback` (LSP only when no conform formatter is available), `prefer` (only LSP when a client is available), `first` and `last` [CF3 L515–537, L487–489; CF9 README "format(opts, callback)"]. LazyVim and kickstart.nvim both set `fallback` as the default [LV2 L66–72; KS L838–840].
- **LazyVim adds its own registry above conform.** `LazyVim.format.register{ name, priority, primary, format(buf), sources(buf) }` adds a formatter [LV1 L9–24]. On each run, only the highest-priority `primary` formatter that has sources runs, plus every non-primary formatter that has sources [LV1 L35–48, L119–139]. conform registers at priority 100 [LV2 L36–55], LSP at 1 [LV5 L5–32], none-ls at 200 [LV6 L10–28], and the ESLint extra adds a non-primary one at 200 [LV7 L29–37]. LazyVim owns the `BufWritePre` autocmd and the `:LazyFormat` and `:LazyFormatInfo` commands [LV1 L158–178]. It removes `format_on_save`/`format_after_save` from the conform options with a warning [LV2 L4–18]. Keys: `<leader>cf` (format, normal and visual) [LV3 L120–122], `<leader>cF` (conform's `injected` formatter) [LV2 L26–35], `<leader>uf`/`<leader>uF` (autoformat toggle, global and buffer) [LV3 L145–146]. `vim.g.autoformat`/`vim.b.autoformat` turn format on save off [LV1 L84–96; LV4 L6]. LazyVim sets `formatexpr` to conform's `formatexpr()` [LV1 L26–31; LV4 L74].
- **kickstart.nvim leaves format on save off.** Its `format_on_save` function returns options only for filetypes in an empty `enabled_filetypes` table. `<leader>f` in normal and visual mode runs `conform.format{ async = true }` [KS L819–853]. It turns off `lua_ls` formatting so that stylua is the only formatter for Lua [KS L752, L776].
- **Neovim's own entry points.**
  - `vim.lsp.buf.format()` sends `textDocument/formatting`, `rangeFormatting` or `rangesFormatting` to every attached client that supports the method, one after another, unless `filter`, `id` or `name` limits them [NV1 L610–695]. It reaches only LSP clients.
  - `gq` uses `formatexpr`, else `formatprg`, else the internal formatter [NV9 L1417–1426; NV11 L3776–3790]. When a client supports `rangeFormatting`, Neovim sets `formatexpr` to `vim.lsp.formatexpr()` on attach, but only if the option is empty or was last set by a script under `$VIMRUNTIME` [NV2 L826–843, L846–866; NV8 L120–122].
  - `=` uses `equalprg`, else `indentexpr`, else C-indenting. It calls `indentexpr` once per line and requires it to have no side effects (textlock) [NV9 L581–593; NV10 'indentexpr'; NV11 L3741–3756].
  - Every LSP client that supports `textDocument/willSaveWaitUntil` gets a synchronous request on each `BufWritePre`, and its edits are applied [NV2 L912–937].
- **What a range or selection gives the callee.**
  - `gq` and `=` are linewise operators [NV11 L85, L100–101]. `formatexpr` gets only `v:lnum` (first line), `v:count` (number of lines) and `v:char`. It also runs in Insert mode when text goes past `textwidth`, and a non-zero result falls back to the internal formatter [NV10 'formatexpr'; NV12 L870–899].
  - A user command with `range` gets `line1`/`line2` only [NV13 `nvim_create_user_command()`].
  - A Lua key map in Visual mode runs while Visual mode is still active. conform and `vim.lsp.buf.format` then read the selection from `getpos('v')`/`getpos('.')`, with columns for `v`, whole lines for `V`, and nothing for blockwise mode [CF3 L311–337, L439–442; NV1 L529–552, L615–619].
  - `g@` with `operatorfunc` gets `"line"`, `"char"` or `"block"` and the `'[`/`']` marks [NV14 `g@`].
- **Neovim's built-in editorconfig changes only options when a file is opened, plus two `BufWritePre` actions.** On `BufNewFile`, `BufRead` and `BufFilePost` it sets `fileencoding`/`bomb`, `fileformat`, `expandtab`, `shiftwidth`/`softtabstop`/`tabstop`, `textwidth` (from `max_line_length`), `fixendofline` and `spelllang` [NV5; NV4 L87–204, L312–353]. Only two properties change text, and both do it at write time:
  - `trim_trailing_whitespace = true` adds a buffer-local `BufWritePre` autocmd that runs `silent! undojoin` and then `%s/\s\+$//e` on the whole buffer [NV4 L160–183].
  - `insert_final_newline` sets `fixendofline` and, once, `endofline` before the write [NV4 L187–204].

  `indent_size`, `indent_style` and `max_line_length` change no text. They change what `ctx.shiftwidth` (conform), `FormattingOptions` (LSP) and Insert-mode wrapping see [CF2 L493–496; NV3 L2251–2261]. Behaviour is the same in 0.11.7 [NV4'].
- **editorconfig can undo one Code Style Option.** `trim_trailing_whitespace = true` strips every whitespace-only line, so it removes the indents that "Keep indents on empty lines" (`ij_php_keep_indents_on_empty_lines`, off by default) writes [C1; NV4 L160–183]. Autocmds for an event run in the order in which they were defined [NV6 L54–55]. So whether this trim runs before or after a format-on-save autocmd depends on when each was created. The editorconfig autocmd is created per buffer on `BufRead`. A formatter's global autocmd made in `setup()` at startup is older and runs first. If the formatter is lazy-loaded on `BufWritePre` (conform's lazy.nvim recipe [CF4 L145–153]), its autocmd is created after the editorconfig autocmd of an already open buffer. PhpStorm treats both properties as save actions, not Code Style Options, and leaves trailing blanks alone on lines that were not changed when the property is unset [C2 L22, L218–249].
- **Formatting twice is avoided only by configuration.**
  - `vim.lsp.buf.format` runs all matching clients in turn [NV1 L670–695].
  - none-ls is an LSP client named `null-ls` [NL1 L130]. It always advertises `documentFormattingProvider` and `documentRangeFormattingProvider` [NL2 L38–39], so Neovim sets `formatexpr` to `vim.lsp.formatexpr()` as soon as it attaches, even when no source formats. Then `gq` does nothing, because `vim.lsp.formatexpr()` returns 0 [NL3 L50–56; NV2 L1402–1450].
  - The recipes that avoid double formatting are: a `filter` on `vim.lsp.buf.format` [NL3 L1–32]; turning off the server's capability or setting [NL3 L34–44; KS L752, L776]; conform's `lsp_format` [CF3 L515–537]; and LazyVim's single `primary` formatter [LV1 L35–48].
  - LazyVim's default `formatters_by_ft` already has `sh = { "shfmt" }` [LV2 L76].
- **Other plugins.**

  | Plugin | Commands | Keys | Format on save | Lua function as formatter | Range |
  |---|---|---|---|---|---|
  | conform.nvim | `:ConformInfo` [CF8]; `:Format` only as a recipe [CF4 L16–30] | none; recipes use `<leader>f` [CF4 L145–211] | `format_on_save` (`BufWritePre`), `format_after_save` (`BufWritePost`) [CF3 L89–175] | yes, `format` field [CF1 L22–25] | Visual mode or `range`; aftermarket for Lua [CF2 L248–251] |
  | guard.nvim | `:Guard fmt\|lint\|enable-fmt\|disable-fmt\|enable-lint\|disable-lint\|info` [GD1 L11–60] | none | `fmt_on_save = true` by default: `BufWritePre`, then by default writes again with `noautocmd write!` (`save_on_fmt`) [GD2 L94–107; GD3 L39–43, L127–133; GD4 L25–47] | yes, `fn(buf, range, text) → text` [GD5 L14; GD4 L69–78] | Visual mode. With a selection only the selected lines are passed and replaced [GD4 L137–146, L193–204] |
  | formatter.nvim | `:Format`, `:FormatWrite`, `:FormatLock`, `:FormatWriteLock`, all `-range=%` [FM1 L5–19] | none; README suggests `<leader>f`/`<leader>F` [FM2 L139–142] | README recipe: `BufWritePost * FormatWrite` [FM2 L145–162] | no, every formatter is an `exe` | the command range; only those lines are sent [FM3 L8–20, L62] |
  | neoformat | `:Neoformat[!] [filetype] [formatter]`, `-range=%` [NF1] | none | README recipe: `BufWritePre * undojoin \| Neoformat` [NF2 L47–56] | no; without a formatter it falls back to `gg=G`, `retab` and trim if enabled [NF3 L316–345] | the command range [NF3 L24, L83, L116–125] |
  | LazyVim | `:LazyFormat`, `:LazyFormatInfo` [LV1 L158–178] | `<leader>cf`, `<leader>cF`, `<leader>uf`, `<leader>uF` | its own `BufWritePre` [LV1 L162–167] | through `register{ format = fn }` [LV1 L9–24] | through conform's Visual-mode check |

  The shared conventions: one command that formats the whole buffer by default and a range when given; format on save off or user-controlled per buffer and globally; Visual mode means "format the selection"; and a user-level `<leader>f`-style key that the plugins suggest but do not map themselves.

## Details

### 1. conform.nvim

- **Registration.** A formatter is a named entry in `require('conform').formatters` (a public table, set directly or through `setup{ formatters = … }`) [CF3 L6–7, L73; CF9 "Options"]. It runs for a buffer when its name is in `formatters_by_ft[ft]`. The `"*"` key adds a formatter to every filetype, and `"_"` covers filetypes with no other entry. Compound filetypes such as `markdown.vimwiki` are tried part by part [CF3 L230–287]. A config that has both `command` and `format` is rejected [CF3 L701–702]. A Lua formatter is "available" unless its `condition` fails. There is no executable check [CF3 L775–787].
- **The run.** `format()` merges the per-filetype options and `default_format_opts` (defaults: `timeout_ms = 1000`, `async = false`, `lsp_format = "never"`, `undojoin = false`) [CF3 L396–428]. In mode `v` or `V` with no `range`, it takes the selection [CF3 L439–442]. Formatters run in sequence, and each gets the output of the one before it [CF2 L597–625, L671–707]. A synchronous run waits with `vim.wait` until `timeout_ms` [CF2 L709–711]. An asynchronous run throws its result away if `changedtick` moved [CF2 L556–589]. A Lua formatter that calls its callback before it returns is applied in the same call, even with `async = true` [CF2 L340–357, L558–588].
- **Writing.** conform adds a final empty line to both texts, diffs them with `vim.text.diff` on 0.12 (`vim.diff` on 0.11) using `histogram`, turns each hunk into an LSP `TextEdit`, trims the common prefix and suffix of replaced lines, and applies all edits with one `vim.lsp.util.apply_text_edits` call [CF2 L120–172, L199–293]. When `undojoin` is set, it runs `undojoin` first [CF2 L283–287]. It aborts when the output is only whitespace but the input is not [CF2 L210–215]. Its docs say that this piecewise write keeps extmarks, cursor, folds and viewport better than replacing the buffer [CF5 L11–15].
- **Events.** Each formatter run fires `User ConformFormatPre` and `User ConformFormatPost` with the formatter name [CF2 L314–339].
- **`format_on_save` details.** The option can be a function `(bufnr) → opts, callback`. It skips buffers whose `buftype` is not empty, and it forces `async = false` [CF3 L94–121]. The autocmd passes the buffer as `buf`, but `format()` reads `bufnr` and defaults to the current buffer [CF3 L113–116, L418, L426–428]. During `BufWritePre`, Neovim makes the written buffer the current buffer [NV6 L1742–1745], so the run reaches the right buffer.
- **`formatexpr`.** `conform.formatexpr()` returns 1 in Insert and Replace modes, so the internal formatter handles `textwidth` wrapping. It turns `v:lnum`/`v:count` into a linewise range, treats a range that covers the whole buffer as no range, and runs synchronously [CF3 L822–856].
- **LSP inside conform.** conform has its own copy of LSP formatting. It picks clients by `textDocument/formatting` or `rangeFormatting`, applies a single full-file edit as a diff, and otherwise calls `apply_text_edits` [CF10 L1–197].
- **Tree-sitter in a Lua formatter.** conform's own `injected` formatter does not use the buffer's parser. It parses the `lines` it was given with `vim.treesitter.get_string_parser` [CF6 `injected.lua` L209–229]. The buffer's parse tree matches `lines` only when the formatter runs first in its chain.

### 2. LazyVim and kickstart.nvim

- LazyVim's `BufWritePre` autocmd calls `LazyVim.format{ buf = event.buf }`. It returns at once when autoformat is off for that buffer. `:LazyFormat` and `<leader>cf` pass `force = true`, which ignores the autoformat switches [LV1 L119–124, L158–172; LV3 L120–122].
- `formatter.format(buf)` gets only the buffer number, never a range [LV1 L12, L131]. In Visual mode, the range reaches conform because conform checks the mode itself [CF3 L439–442].
- LazyVim's LSP formatter goes through `conform.format` with `formatters = nil` when conform is installed, else through `vim.lsp.buf.format` [LV5 L37–49]. It counts as having sources when any attached client supports `textDocument/formatting` or `rangeFormatting` [LV5 L18–29]. Because conform (100) and LSP (1) are both `primary`, the LSP formatter is active only when conform lists no formatter for the buffer [LV1 L35–48].
- So in LazyVim, a third-party formatter starts in one of two ways: as a conform formatter named in `formatters_by_ft` (it then runs under the conform entry), or as its own `LazyVim.format.register` entry. A primary entry with a priority above 100 replaces conform for buffers where it has sources. A non-primary entry runs in addition to conform [LV1 L35–48; LV7 L29–37].
- kickstart.nvim installs conform with `vim.pack.add` (a 0.12 API) and calls `setup` inline [KS L819–850].

### 3. Neovim built-in paths

- **`vim.lsp.buf.format(opts)`** (0.11.7 and 0.12.6). It is synchronous by default with `timeout_ms = 1000`. A list of ranges needs `textDocument/rangesFormatting`. With no matching client it only shows a message [NV1 L555–695]. Its Visual-mode check is written `not range and mode == 'v' or mode == 'V'`, so in `V` mode the selection replaces an explicit `range` [NV1 L618]. `FormattingOptions` default to the effective `tabstop` and `expandtab` [NV3 L2251–2261].
- **`vim.lsp.formatexpr()`** asks only the first client that supports `rangeFormatting`, with a 500 ms default timeout. It returns 0 in every case except Insert/Replace mode, even when no client answered, so the internal `gq` formatter never runs then [NV2 L1402–1450]. To opt out, `:help lsp-defaults` says to use `gw` or to clear `formatexpr` in `LspAttach` [NV8 L120–122, L128–138].
- **Where the LSP default stops.** `is_empty_or_default` lets Neovim set `formatexpr` only when it is empty or was last set by a `$VIMRUNTIME` script, for example `ftplugin/xml.vim`, which sets `xmlformat#Format()` [NV2 L826–843; NV7 L25]. A value that a plugin or user config set before the client attached is kept. A value set after the attach replaces the LSP one.
- **Format on save in the LSP docs.** `:help lsp-format` shows a `BufWritePre` autocmd that calls `vim.lsp.buf.format{ bufnr, id, timeout_ms }`, and says it is "usually not needed if server supports `textDocument/willSaveWaitUntil`" [NV8 L271–301]. The FAQ shows `autocmd BufWritePre *.rs lua vim.lsp.buf.format({ async = false })` [NV8 L326–332].
- **On-type formatting** (`textDocument/onTypeFormatting`) is new in 0.12 and runs only after `vim.lsp.on_type_formatting.enable()` [NV15; NV8 `lsp-on_type_formatting`]. 0.11.7 has no such module.
- **Operators and undo.** `gq` with `formatexpr` calls `fex_format(start, line_count, NUL)`, and a non-zero result falls back to `op_format` [NV12 L855–866]. `gw` never uses `formatexpr` or `formatprg` [NV9 L1444–1449]. `=` with `indentexpr` calls `op_reindent(oap, get_expr_indent)`, which saves the whole line range for undo once and sets each line's indent [NV11 L3741–3756; NV16 L982–1002]. `:help undo-blocks`: one undo command undoes one typed command, however many changes it makes, and `:undojoin` joins the next change to the previous undo block [NV17 L84–110].
- **Tree-sitter indent.** The 0.12.6 runtime has no Tree-sitter `indentexpr` in `lua/vim/` (searched for `indentexpr`; only the generated option and variable stubs match).

### 4. Neovim's built-in editorconfig

- Enabled by default. It is turned off with `vim.g.editorconfig = false` or per buffer with `vim.b.editorconfig = false`. The applied properties are stored in `b:editorconfig` [NV4 L23–33; NV5 L5–9]. It runs after ftplugins and `FileType` autocmds, skips buffers with a `buftype`, unmodifiable buffers and unnamed buffers, and walks parent directories until `root = true` [NV4 L1–5, L312–334].
- Properties and their effects [NV4 L87–204]:

  | Property | Effect | When |
  |---|---|---|
  | `charset` | `fileencoding`, `bomb` | on open |
  | `end_of_line` | `fileformat` | on open |
  | `indent_style` | `expandtab`; with `tab` and no `indent_size`: `shiftwidth = 0`, `softtabstop = 0` | on open |
  | `indent_size` | `shiftwidth`, `softtabstop = -1`, and `tabstop` when `tab_width` is unset | on open |
  | `tab_width` | `tabstop` | on open |
  | `max_line_length` | `textwidth` (0 for `off`) | on open |
  | `trim_trailing_whitespace` | `true`: buffer-local `BufWritePre` with `undojoin` + `%s/\s\+$//e`; `false`: removes that autocmd | every write |
  | `insert_final_newline` | `fixendofline`; a one-time `BufWritePre` that sets `endofline` | on open, and the next write |
  | `spelling_language` | `spelllang` | on open |

- Custom properties are added through `require('editorconfig').properties.<name> = fn(bufnr, val, opts)` [NV4 L35–54]. Every other key, including all `ij_*` keys, is ignored and not stored (see `docs/research/editorconfig-compat.md`, #4).
- `trim_trailing_whitespace`'s `undojoin` puts the trim into the same undo block as the change before it, which on save can be a formatter's edit [NV4 L170–172; NV17 L94–98].
- `max_line_length` sets `textwidth`. With a `t` or `c` flag in `formatoptions`, typing past it calls `formatexpr` in Insert mode [NV10 'formatexpr', 'formatoptions'].
- 0.11.7 has the same properties, the same timing and the same write actions [NV4']. The help moved from `editorconfig.txt` (0.11) to `plugins.txt` (0.12) [NV5].

### 5. LSP and none-ls overlap

- none-ls sources declare `null_ls.methods.FORMATTING` or `RANGE_FORMATTING`. Their generator gets `params.content` (the buffer lines), `bufnr`, `range` and other fields, and returns edits `{ row, col, end_row, end_col, text }` [NL4 L60–100, L355–383]. Formatting sources run in sequence, in the order they were registered [NL4 L369–374]. Users start a none-ls format with `vim.lsp.buf.format()` [NL5 L249–262].
- none-ls's wiki recommends a `filter` that keeps only `null-ls`, or turning off another server's `documentFormattingProvider` (it marks the second option "not recommended") [NL3 L1–44]. Its format-on-save recipe is an `LspAttach`/`on_attach` `BufWritePre` autocmd per buffer [NL6 L1–26].
- guard.nvim can use LSP as its fallback formatter (`lsp_as_default_formatter`, off by default). Its `lsp` tool applies the first client's edits to a scratch buffer and passes the text on through the chain [GD3 L207–243; GD6 L10–40].

## Facts that #37 waits on

1. A pure Lua formatter can run inside conform as a `format(self, ctx, lines, callback)` formatter. conform owns the diff, the write and the undo join. Range formatting is then conform's "aftermarket" filter on top of whatever the formatter does with `ctx.range` [CF1; CF2 L248–251].
2. ADR-0002 says the Core writes only the changed text as one undo step. conform already does this for its Lua formatters, and the Core would do it on its own paths [CF2 L182–293].
3. `gq`/`formatexpr`, `=`/`indentexpr` and range user commands give whole lines only. Only Lua key maps in Visual mode (and `g@`) can see charwise columns [NV11 L85, L100–101; NV12 L870–899; CF3 L311–337; NV14].
4. Neovim's LSP default takes over `formatexpr` only when the option is empty or was set from `$VIMRUNTIME`. LazyVim sets its own global `formatexpr` [NV2 L826–866; LV4 L74].
5. LazyVim removes conform's `format_on_save` and runs its own registry, where one primary formatter wins by priority [LV1 L35–48; LV2 L4–18].
6. kickstart.nvim's format on save is off by default. LazyVim's is on by default [KS L826–837; LV4 L6].
7. Neovim's editorconfig `trim_trailing_whitespace` removes the indents of "Keep indents on empty lines" when the file is saved. Whether it runs before or after a format-on-save autocmd depends on when each autocmd was created [NV4 L160–183; NV6 L54–55; C1].
8. LazyVim's default `formatters_by_ft` already runs the user's `shfmt` for `sh` [LV2 L76], the same program ADR-0002 lets the Shell Script Language Plugin call.
9. No compared plugin maps a key by default. Each offers a command whose default range is the whole file (`-range=%`) and documents a `<leader>f`-style key in its README [FM1; NF1; CF4; GD1].

## Method

- Neovim v0.11.7 and v0.12.6: `runtime/` and `src/nvim/{normal,ops,indent,textformat}.c` from the GitHub tag tarballs, read with `grep` and `sed`. No code was run.
- Plugins: shallow clones of each default branch in `/tmp/claude-1000/fmt-triggers-src/`, read only. conform.nvim issue #653 was read with `gh issue view`.
- Research Corpus: `data/behavior/php/ij_php_keep_indents_on_empty_lines.json` and `docs/languages/general.md`, read with `grep` and `python3 -I`.

## Sources

Neovim (https://github.com/neovim/neovim, tags `v0.12.6` and `v0.11.7`):

- [NV1] `runtime/lua/vim/lsp/buf.lua`: `range_from_selection` L529–552, `vim.lsp.buf.format.Opts` L555–604, `M.format` L610–695 (0.11.7: L459, L540–622). `:help vim.lsp.buf.format()`.
- [NV2] `runtime/lua/vim/lsp.lua`: `is_empty_or_default` L826–843, `_set_defaults` L846–880, `buf_attach` (`willSave`/`willSaveWaitUntil` on `BufWritePre`) L903–937, `lsp.formatexpr` L1388–1450 (0.11.7: L804, L825–842, L939–970, L1395). `:help vim.lsp.formatexpr()`.
- [NV3] `runtime/lua/vim/lsp/util.lua`: `make_formatting_params` L2251–2261, `apply_text_edits` L314.
- [NV4] `runtime/lua/editorconfig.lua` (0.12.6): brief L1–54, `charset` L89, `end_of_line` L107, `indent_style` L115, `indent_size` L128, `tab_width` L143, `max_line_length` L149, `trim_trailing_whitespace` L160–183, `insert_final_newline` L187–204, `spelling_language` L208, `M.config` L312–353. [NV4'] the same file in 0.11.7: `indent_size` L115, `max_line_length` L136, `trim_trailing_whitespace` L147, `insert_final_newline` L174, `M.config` L302. Only the docs, `tonumber`→`vim._tointeger` and `bufnr`→`buf` differ.
- [NV5] `runtime/plugin/editorconfig.lua` L1–13. `:help editorconfig` (`runtime/doc/plugins.txt` L86–150 in 0.12.6, `runtime/doc/editorconfig.txt` in 0.11.7), `:help g:editorconfig`, `:help editorconfig-properties`.
- [NV6] `runtime/doc/autocmd.txt`: `:autocmd` "Nvim always adds {cmd} after existing autocommands" L54–55 (0.11.7: L49), `BufWritePre` L385–386, "the buffer … temporarily becomes the current buffer" L1742–1745.
- [NV7] `runtime/ftplugin/xml.vim` L25.
- [NV8] `runtime/doc/lsp.txt`: `lsp-defaults` L69–122, `lsp-defaults-disable` L128–138, `lsp-format` L271–301, `lsp-faq` L326–332, `lsp-on_type_formatting` L2592.
- [NV9] `runtime/doc/change.txt`: `=` L581–593, `gq` L1417–1426, `v_gq` L1440, `gw` L1444–1449, `format-formatexpr` L1484–1530.
- [NV10] `runtime/doc/options.txt`: `'equalprg'` L2471, `'formatexpr'` L3137–3177, `'formatoptions'`, `'formatprg'` L3203, `'indentexpr'` L3690–3732.
- [NV11] `src/nvim/ops.c`: `OPF_LINES` L85, operator table L94–118, `OP_INDENT` L3741–3756, `OP_FORMAT`/`OP_FORMAT2` L3776–3790.
- [NV12] `src/nvim/textformat.c`: `op_formatexpr` L855–866, `fex_format` L870–899.
- [NV13] `runtime/doc/api.txt` `nvim_create_user_command()` L2912–2950. `runtime/doc/map.txt` `:command-range` L1486–1506.
- [NV14] `runtime/doc/map.txt` `g@` L869–878. `runtime/doc/motion.txt` `'<` L902–910. `:help getregionpos()` (both versions).
- [NV15] `runtime/lua/vim/lsp/on_type_formatting.lua` L1–20, `M.enable` L220–245 (0.12.6 only).
- [NV16] `src/nvim/indent.c` `op_reindent` L982–1002.
- [NV17] `runtime/doc/undo.txt` `undo-blocks`, `:undojoin` L84–110.

conform.nvim (https://github.com/stevearc/conform.nvim, `016802de402556da54c36bd7359b441266b01cdd`, 2026-08-11):

- [CF1] `lua/conform/types.lua`: `JobFormatterConfig` L9–20, `LuaFormatterConfig` L22–25, `FormatterConfigOverride` L35–41, `Context` L46–51, `Range` L58–60, `FormatOpts` L82–89.
- [CF2] `lua/conform/runner.lua`: `create_text_edit` L120–172, `apply_format` L182–293, `run_formatter` L313–357, `build_context` L486–536, `format_async` L543–589, `format_lines_async` L597–625, `format_sync` L634–661, `format_lines_sync` L671–720.
- [CF3] `lua/conform/init.lua`: `setup` with `format_on_save` L89–122 and `format_after_save` L124–200, filetype matching L230–306, `range_from_selection` L311–337, `format` L396–556, `get_formatter_config` L692–749, `get_formatter_info` L755–820, `formatexpr` L822–856.
- [CF4] `doc/recipes.md`: "Format command" L16–30, "Lazy loading with lazy.nvim" L145–190, "Leave visual mode after range format" L195–211.
- [CF5] `doc/advanced_topics.md`: "Minimal format diffs" L11–15, "Range formatting" L17–21.
- [CF6] `lua/conform/formatters/trim_whitespace.lua`, `trim_newlines.lua`, `injected.lua` (`condition`/`format` L209–229, range filter L268–270).
- [CF7] conform.nvim issue #653, "feature request: lua function formatter", maintainer's answer: https://github.com/stevearc/conform.nvim/issues/653
- [CF8] `plugin/conform.lua` L1 (`:ConformInfo`).
- [CF9] `README.md`: "Setup" L125–172, "Customizing formatters" L447–516, "Options" L563–675, "API" L689–812, "FAQ" L814–823.
- [CF10] `lua/conform/lsp_format.lua` L1–197.

LazyVim (https://github.com/LazyVim/LazyVim, `301a3f71007c4aa5da5dab82f1a7a08389091224`, 2026-10-28):

- [LV1] `lua/lazyvim/util/format.lua` L1–196.
- [LV2] `lua/lazyvim/plugins/formatting.lua` L1–100.
- [LV3] `lua/lazyvim/config/keymaps.lua` L120–122, L145–146.
- [LV4] `lua/lazyvim/config/options.lua` L6 (`vim.g.autoformat = true`), L74 (`formatexpr`).
- [LV5] `lua/lazyvim/util/lsp.lua` `M.formatter` L5–32, `M.format` L37–49. `lua/lazyvim/plugins/lsp/init.lua` L167.
- [LV6] `lua/lazyvim/plugins/extras/lsp/none-ls.lua` L10–28.
- [LV7] `lua/lazyvim/plugins/extras/linting/eslint.lua` L29–37.

kickstart.nvim (https://github.com/nvim-lua/kickstart.nvim, `8e35dbedb7966e3a95e1f26f9fc1179ab6c68db4`, 2026-10-03):

- [KS] `init.lua`: `lua_ls` formatting off L750–777, "SECTION 7: FORMATTING" L818–853.

none-ls.nvim (https://github.com/nvimtools/none-ls.nvim, `c4b82bb63b13856ba4d6b971b7aad3bb38fc6fe2`, 2026-08-11; wiki `1da216b83a94f8fe4201deb4c094e08890ef042a`):

- [NL1] `lua/null-ls/client.lua` L130 (`name = "null-ls"`).
- [NL2] `lua/null-ls/rpc.lua` L27–54 (advertised capabilities).
- [NL3] Wiki `Avoiding-LSP-formatting-conflicts.md` L1–70: https://github.com/nvimtools/none-ls.nvim/wiki/Avoiding-LSP-formatting-conflicts
- [NL4] `doc/MAIN.md`: methods L60–70, params L74–100, formatting L355–383.
- [NL5] `README.md` L249–262.
- [NL6] Wiki `Formatting-on-save.md` L1–50: https://github.com/nvimtools/none-ls.nvim/wiki/Formatting-on-save

guard.nvim (https://github.com/nvimdev/guard.nvim, `addb8d2f40662b8b62d60dd7d18f503beb2332e7`, 2026-01-31):

- [GD1] `plugin/guard.lua` L11–60.
- [GD2] `README.md` "Usage" L86–121.
- [GD3] `lua/guard/events.lua`: `lazy_fmt` L39–43, `try_attach_fmt_to_buf` L123–134, `maybe_default_to_lsp` and `LspAttach` L207–243.
- [GD4] `lua/guard/format.lua`: `update_buffer` L25–47, `apply_pure_formatter` L69–78, `do_fmt` L132–258.
- [GD5] `CUSTOMIZE.md` L1–30, L48. `ADVANCED.md` L60–77.
- [GD6] `lua/guard/lsp.lua` L10–40. `lua/guard/filetype.lua` L5–6.

formatter.nvim (https://github.com/mhartington/formatter.nvim, `b9d7f853da1197b83b8edb4cc4952f7ad3a42e41`, 2025-05-29):

- [FM1] `plugin/formatter.vim` L1–19.
- [FM2] `README.md` "Map keys" L137–142, "Format after save" L144–162, `FormatLock` L183–184.
- [FM3] `lua/formatter/format.lua` `M.format` L8–49, `M.start_task` L53–75.

neoformat (https://github.com/sbdchd/neoformat, `9d95e5ca3ab263363758d5b1d7a174a30556ab2d`, 2026-02-24):

- [NF1] `plugin/neoformat.vim` (`:Neoformat`, `-range=% -bang`).
- [NF2] `README.md` "Basic Usage" L18–56, "Managing Undo History" L198–216.
- [NF3] `autoload/neoformat.vim`: `s:neoformat` L18–130, `s:basic_format` L316–345.

Research Corpus (`~/Projects/phpstorm-editorconfig/`, PhpStorm 2026.2.3):

- [C1] `data/behavior/php/ij_php_keep_indents_on_empty_lines.json` ("Keep indents on empty lines", Tabs and Indents, default `false`).
- [C2] `docs/languages/general.md` L22 (`insert_final_newline` is not a Code Style option), L218–249 (`insert_final_newline` and `trim_trailing_whitespace` on save).

ADRs: `docs/adr/0001-own-json-store-import-scheme-xml-only.md`, `docs/adr/0002-pure-lua-engine-on-users-tree-sitter.md`, `docs/adr/0007-language-plugins-are-runtimepath-specs-with-lazy-lua-modules.md`. Related research: `docs/research/editorconfig-compat.md` on branch `research/editorconfig-compat` (#4).
