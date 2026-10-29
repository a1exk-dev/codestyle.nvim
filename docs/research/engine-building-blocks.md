# Building blocks for our own formatting engine

Research for issue [#3](https://github.com/a1exk-dev/codestyle.nvim/issues/3) (map: [#1](https://github.com/a1exk-dev/codestyle.nvim/issues/1)).
Question: which building blocks exist for our own formatting engine, and which runtime suits it: pure Lua on Neovim's Tree-sitter, or a compiled helper (Rust/Go)?

Date of research: 2026-10-29. Machine for all timings: AMD Ryzen 7 7800X3D, Linux 7.2.8, Neovim 0.12.6 (LuaJIT 2.1). Terms follow `GLOSSARY.md`.

## Answer

- **Recommended runtime: pure Lua on Neovim's Tree-sitter, with a port of PhpStorm's own formatting model.** A compiled helper gives no fidelity advantage, because the hard part is the per-language rules, and they must be written by hand in either runtime. Lua is fast enough. A toy engine (walk all leaves, decide each whitespace gap, rebuild the text) takes **1.2 ms for the 138-line PHP Preview**, **10 ms for a 2,335-line PHP file**, and **37 ms for a 4,091-line TypeScript file**, parse included (see "Speed of Lua tree walking"). A per-call helper process costs about 1 ms to start, plus its own start-up: Biome needs 37 ms even for a 3 KB file.
- **Reproduce PhpStorm's model, not a Prettier-style printer.** PhpStorm builds a tree of blocks and changes only the whitespace between leaf blocks. Each pair of adjacent blocks has a Spacing (min/max spaces, min line feeds, keep line breaks, keep blank lines). Each block also has an Indent, a Wrap (`NONE`/`NORMAL`/`ALWAYS`/`CHOP_DOWN_IF_LONG`) and an Alignment [S1][S2][S3]. The generic engine that runs this model (`FormatProcessor`, `WrapProcessor`, `AlignmentHelper`, …) is Apache-2.0 in `intellij-community` [S4], so we can port its algorithm. The PHP, JavaScript and CSS rule classes that the Research Corpus cites (for example `PhpSpacingProcessor`) are not in the public repositories, so their rules must come from the Behaviour Records.
- **Tree-sitter fits this model well.** Grammars never make whitespace into nodes, but every leaf has exact byte ranges, so each gap is known. Comments are named `extras` nodes in almost every grammar, so they become leaf blocks [S5]. A small check shows the approach works: rewriting only the gaps that a Tree-sitter node mapping selects reproduces the Behaviour Record of `ij_php_space_before_method_call_parentheses` in **8/8 files**. The first, naive mapping matched only 6/8. PhpStorm treats `isset`/`empty`/`die`/`eval` and variable calls differently, and it treats `echo (…)`/`include (…)` like calls. So the rules must be tuned against the records.
- **Grammars exist for every Research Corpus language that has Options**, but their quality varies (corpus parse results below):
  - **Good**: PHP, Blade, Twig, HTML, Vue, XML, YAML, Markdown, Gherkin, EditorConfig, Bash, and JavaScript/TypeScript (use `tsx` for the TypeScript Preview).
  - **Weak**: CSS family (CSS 5/24 test inputs with errors, SCSS 10/31, Less 10/31, Sass 6/11; every SCSS/Less/Sass Preview fails), Angular (6/6 Previews fail), Mermaid (21/27), HTTP Request (6/6 Previews).
  - **Unusable for fidelity: SQL**. 108 of 177 test inputs and 67 of 77 dialect Previews have errors.
  - **Not in nvim-treesitter**: Less, Sass and Gherkin come only from small third-party grammars. The Gherkin grammar with recent commits has no licence file.
- **Embedded languages work through injections**, not one tree:
  - PHP: HTML is `text` nodes that Neovim parses as one combined `html` tree.
  - Twig: HTML is opaque `content` nodes, also parsed as combined `html`.
  - Blade: the grammar extends the HTML grammar, and PHP comes in as `php_only` injections.
  - Vue: `<script>`/`<style>` are `raw_text` nodes that are injected, and `{{ }}` is `raw_text`.
  - Angular: parses its expressions itself.

  The engine must merge the host and injected block trees by byte range, as PhpStorm's `TemplateXmlBlock` does [S6].
- **Native building blocks exist, but none fits as an engine.** Mago (PHP), oxc/Biome (JS/TS), dprint plugins, Malva (CSS family) and markup_fmt (HTML/Vue/Twig) all discard or reflow the original layout: they are Prettier-style. Topiary has no right margin at all. Their parsers (mago-syntax, oxc_parser, raffia, the tree-sitter crates) are usable under MIT/Apache-2.0 licences, but parsers are not the bottleneck. Exception: **Shell Script**. PhpStorm itself calls the external `shfmt` [corpus README], so that Language Plugin should call `shfmt` over stdin too.
- **If a native helper is ever needed**, the established ways are:
  - a prebuilt `mlua` Lua module downloaded from GitHub releases and checked by checksum, with a `cargo build` fallback (blink.cmp);
  - a build hook (lazy.nvim `build`, `vim.pack` `PackChanged`, luarocks `rust-mlua`);
  - a persistent child process over a pipe, msgpack-RPC or LSP, instead of one process per call.

  Neovim release builds cannot load WASM grammars (they need `ENABLE_WASMTIME`) [S7].
- **Pin grammars per Language Plugin.** Node types change between grammar versions. `vim.treesitter.language.add(name, {path, symbol_name})` lets a Language Plugin load its own pinned parser under a private name, so it does not depend on the user's nvim-treesitter install [S7]. This was checked locally. Luarocks has parser rocks such as `tree-sitter-php` [S8].

## 1. What the engine must reproduce: PhpStorm's formatting model

The IntelliJ Platform SDK describes the model [S1]:

- A tree of `Block`s covers the file. "The formatter modifies only characters between blocks." Blocks must cover all non-whitespace text.
- **Indent** per block, relative to the parent: none, normal (the indent Option), continuation (the continuation indent Option), and others. "An indent is ignored if a corresponding block doesn't start with a new line."
- **Spacing** between adjacent children: `createSpacing(minSpaces, maxSpaces, minLineFeeds, keepLineBreaks, keepBlankLines)` [S2]. Read-only spacing and dependent line-feed spacing also exist.
- **Wrap**: `WrapType` is `ALWAYS`, `NORMAL` (wrap if long), `NONE`, or `CHOP_DOWN_IF_LONG` [S3]. These are the four Research Corpus wrap values `split_into_lines | normal | off | on_every_item`.
- **Alignment**: blocks that share an `Alignment` object are aligned, with optional backward shift [S1].
- **Pre- and post-processors** make non-whitespace edits (braces, trailing commas, letter case), and the **Rearranger** makes the Arrangement [S1].

The Behaviour Records confirm that PhpStorm keeps the user's layout unless an Option says otherwise. `ij_php_keep_line_breaks` (default `true`) "Joins user-wrapped constructs onto one line" only when it is turned off (`data/behavior/php/ij_php_keep_line_breaks.json`). The Research Corpus also names block classes from the bytecode (for example `PhpSpacingProcessor`, `SqlFlowBlock`, `JSSpacingProcessor`; `docs/notes/BEHAVIOR-NOTES.md`).

Where the code is:

- Open (Apache-2.0, `intellij-community` tag `idea/262.10968.63`): the generic engine in `platform/code-style-impl/src/com/intellij/formatting/engine/` (`WrapProcessor`, `AdjustWhiteSpacesState`, `AlignmentHelper`, `IndentAdjuster`, …) [S4]. Language formatters for JSON (`json/…/formatter`), YAML (`plugins/yaml`), Markdown, XML/HTML (`xml/xml-ui-common/…/formatter/xml/XmlBlock.java`, with template support in `TemplateXmlBlock.java`), Shell Script (`plugins/sh`), and Gherkin (`intellij-plugins`, `cucumber/…/GherkinBlock.java`) [S6].
- Not found in the public repositories: `PhpSpacingProcessor`. The PHP, JavaScript/TypeScript, CSS-family, Twig, Blade and SQL formatters ship inside the proprietary IDE. Their rules can only come from the Behaviour Records and the bytecode notes in the Research Corpus.

Consequence: the main work in any runtime is the same. It is a block builder per language plus spacing, indent, wrap and alignment rules tuned against the Behaviour Records. The runtime choice only changes where that code runs.

## 2. Tree-sitter grammars for the Research Corpus languages

Sources: the nvim-treesitter `main` branch at commit `a2f6944` (2026-10-24) [S9]. It lists each grammar's repository, pinned revision and tier, and every grammar listed here is tier "unstable" (follows HEAD) except `editorconfig` (stable). Each grammar's `grammar.js` [S10] and the GitHub API (last commit, licence; queried 2026-10-29). I built each parser from source with `cc` at the revision that nvim-treesitter pins (Less/Sass/Gherkin at HEAD) and loaded it with `vim.treesitter.language.add`.

"Errors" = number of files whose tree has an `ERROR` or `MISSING` node, over the Research Corpus test inputs (`tests/formatter/<language>/`) and Preview samples (`data/code-samples/<Language>/`, empty files skipped).

| Corpus language | Grammar | nvim-treesitter | Last commit | Licence | Comments / whitespace | Errors: tests | Errors: Previews |
|---|---|---|---|---|---|---|---|
| PHP | tree-sitter/tree-sitter-php (`php`, `php_only`) | yes | 2026-10-06 (v0.25.1) | MIT | `comment` extra; whitespace regex extra | 6/151 | 3/6 |
| Blade | EmranMR/tree-sitter-blade (extends HTML grammar) | yes | 2026-08-31 | MIT | `comment` extra | 0/21 | 0/6 |
| Twig | gbprod/tree-sitter-twig | yes | 2026-08-31 | MIT | whitespace extra; `comment` is a regular node | 1/24 | 0/6 |
| JavaScript | tree-sitter/tree-sitter-javascript | yes | 2025-09-15 | MIT | `comment`, `html_comment` extras | 5/72 | 1/6 |
| TypeScript | tree-sitter/tree-sitter-typescript (`typescript`, `tsx`) | yes | 2025-01-30 | MIT | as JavaScript | 3/102 (`tsx`: 8/102) | 3/6 (`tsx`: 0/6) |
| HTML | tree-sitter/tree-sitter-html | yes | 2025-09-15 | MIT | `comment` extra | 0/19 | 0/6 |
| Vue | tree-sitter-grammars/tree-sitter-vue (extends HTML) | yes | 2026-01-24 | MIT | as HTML | 0/14 | 0/6 |
| Angular HTML | dlvandenberg/tree-sitter-angular | yes | 2026-05-15 | MIT | as HTML | none | 6/6 |
| XML | tree-sitter-grammars/tree-sitter-xml | yes | 2026-01-21 | MIT | `extras: []`, whitespace explicit | 0/11 | 0/1 |
| CSS | tree-sitter/tree-sitter-css | yes | 2025-09-28 | MIT | `comment`, `js_comment` extras | 5/24 | 0/6 |
| SCSS | serenadeai/tree-sitter-scss (pinned); tree-sitter-grammars/tree-sitter-scss | yes (serenade) | 2022-02-03; 2026-10-05 | MIT | `comment`, `single_line_comment` | 10/31 (both) | 6/6 (both) |
| Less | jimliang/tree-sitter-less; fork mdovale/tree-sitter-less (built) | **no** | 2025-10-29; 2026-04-15 | MIT | CSS-based | 10/31 | 6/6 |
| Sass | bajrangCoder/tree-sitter-sass | **no** | 2026-01-18 | MIT | `comment`, `single_line_comment` | 6/11 | 6/6 |
| JSON | tree-sitter/tree-sitter-json | yes | 2026-08-17 | MIT | `comment` extra | 1/31 | 6/6 (trailing commas) |
| YAML | tree-sitter-grammars/tree-sitter-yaml | yes | 2026-05-22 | MIT | `comment` extra; layout from external scanner | 0/15 | 0/6 |
| Markdown | tree-sitter-grammars/tree-sitter-markdown (+ `markdown_inline`) | yes | 2026-10-24 | MIT | `extras: []` | 0/23 | 0/6 |
| Mermaid | monaqa/tree-sitter-mermaid | yes | 2024-04-22 | MIT | `comment` extra | 21/27 | 2/6 |
| Gherkin | binhtddev/tree-sitter-gherkin (built); SamyAB/tree-sitter-gherkin | **no** | 2026-09-28 (**no licence**); 2024-07-04 (MIT) | see left | `comment` extra | 0/5 | 0/6 |
| HTTP Request | rest-nvim/tree-sitter-http | yes | 2025-03-29 | MIT | `extras: []` | 1/14 | 6/6 |
| EditorConfig | ValdezFOmar/tree-sitter-editorconfig | yes (stable) | 2026-10-07 | MIT | n/a | 1/13 | 0/6 |
| Shell Script | tree-sitter/tree-sitter-bash | yes | 2025-12-02 | MIT | `comment` | 0/2 | (empty) |
| Makefile | tree-sitter-grammars/tree-sitter-make | yes | 2026-02-26 | MIT | n/a | no Options | n/a |
| SQL (11 dialects) | DerekStride/tree-sitter-sql (generated code on `gh-pages`) | yes | 2026-10-17 | MIT | `comment`, `marginalia` | **108/177** | **67/77** |
| Other File Types | none needed (indent Options only) | n/a | n/a | n/a | n/a | n/a | n/a |

What fails, with examples (from the error locations):

- **PHP**: removed pre-PHP-8 syntax `$val{…}` (in the PhpStorm Preview), and upper-case keywords such as `ENUM Suit: STRING`.
- **JavaScript**: Flow types, parameter decorators and `implements` in the JS Preview.
- **TypeScript**: the Previews contain JSX, so they need `tsx`. Some test inputs contain `<T>x` casts, which `tsx` rejects. A Language Plugin must choose the parser by content or try both.
- **CSS**: `@page :first`.
- **SCSS**: nested properties (`font: {`) and maps.
- **Less**: guards (`when (iscolor(@c))`).
- **Sass**: nested properties.
- **Angular**: `*ngIf="a else b"` without `;`.
- **JSON**: trailing commas, which PhpStorm's JSON accepts.
- **Mermaid**: `style A fill:#f9f`.
- **HTTP Request**: response-handler scripts.
- **SQL**: dialect-specific statements in every category.

### Comments and whitespace

The Tree-sitter grammar DSL says `extras` are "tokens that may appear anywhere in the language … often used for whitespace and comments", and the default is whitespace [S5]. Whitespace that matches a regex extra never becomes a node. Comments listed as named extras become named nodes that can appear between any two tokens. For the engine:

- Gaps (whitespace) are not in the tree, but each node's byte range is (`TSNode:range(true)`), so the gap between two leaves is the source text between them [S7]. This is the same idea as IntelliJ's "the formatter modifies only characters between blocks".
- Comments are leaf nodes in every grammar above except Twig, where a comment is a regular child node.
- Some grammars have no whitespace extras (`extras: []`: XML, Markdown, HTTP). Some get their layout from an external scanner (YAML, Sass: indentation-sensitive). For these, line structure is part of the grammar, and the engine must treat some gaps as fixed.

### Error recovery

Tree-sitter aims to be "robust enough to provide useful results even in the presence of syntax errors" [S11]. On broken input it inserts `MISSING` nodes and wraps unknown tokens in `ERROR` nodes. The rest of the file still parses. Example (local run):

```
<?php function f($a { return $a }  class A { public function g() {} }
→ (function_definition … (formal_parameters … (MISSING ")")) body: (compound_statement (ERROR (variable_name (name)))))
  (class_declaration … (method_declaration …))   ← later code is intact
```

The engine can detect these with `TSNode:has_error()` and `TSNode:missing()` [S7]. The safe rule is: keep the original gaps inside and around an `ERROR` node. That matches the "never approximate" rule from #1. Note that Biome refuses to format files with parse errors unless `formatWithErrors` is set. It refused the PhpStorm TypeScript Preview.

### Embedded languages

Neovim parses injected languages as child `LanguageTree`s. `injection.combined` parses all matching nodes "as one nested document" [S7]. Injection queries come from nvim-treesitter [S9]:

| Host | How the embedded code appears | Injection query (nvim-treesitter) | Local result (`parse(true)` on the Corpus Preview) |
|---|---|---|---|
| PHP | HTML outside `<?php ?>` is `text` (inside `text_interpolation`) | `(text) → html, combined` | n/a |
| Blade | HTML is parsed by the Blade grammar itself; `{{ }}`/directive args are `php_only`/`parameter` | `php_only` per node; JS for Alpine/Livewire attributes | `blade=1 php_only=6`, 0.53 ms |
| Twig | HTML is opaque `content` nodes; Twig tags/outputs are nodes | `(content) → html, combined` | `twig=1 html=1`, 0.19 ms |
| Vue | `<script>`/`<style>` bodies and `{{ }}` are `raw_text` | by `lang` attribute (js/ts/css/scss; less/sass mapped to scss) | `vue=1 javascript=1 typescript=2 css=1`, 0.19 ms |
| Angular | expressions, bindings, control flow are parsed by the grammar | n/a | n/a |
| HTML | `<script>`/`<style>` are `raw_text` | JS/CSS | n/a |

Consequence: for PHP+HTML and Twig, the HTML tree and the host tree are separate, and the HTML tree spans across the host's tags. The engine needs a merge step that orders the leaves of both trees by byte offset and decides which tree owns each gap. PhpStorm solves the same problem with `TemplateXmlBlock` in the open XML formatter [S6]. Vue and Blade are simpler, because the host tree contains the HTML structure.

### Grammar versions

nvim-treesitter states it "is only guaranteed to work with specific versions of language parsers" [S9]. Neovim takes the first `parser/{lang}.*` on `runtimepath` [S7]. A formatter that depends on node types must not take whatever the user installed. `vim.treesitter.language.add(lang, {path=…, symbol_name=…})` loads a parser file under any name [S7]. Locally, `language.add('codestyle_scss', {path=…, symbol_name='scss'})` loaded and parsed. A Language Plugin can therefore ship or install its own pinned parser: compiled at install, prebuilt, or a luarocks `tree-sitter-<lang>` rock [S8]. Building needs a C compiler, and nvim-treesitter needs `tree-sitter-cli` [S9]. The parsers built here have ABI 14/15, and Neovim 0.12.6 accepts ABI 13–15 (`vim.treesitter.minimum_language_version`/`language_version`).

## 3. Speed of Lua tree walking and text rebuilding

Method: `nvim --headless --clean -l bench.lua` gives the median of 15 runs. Steps:

- **parse**: a fresh `get_string_parser(...):parse()`, no injections.
- **walk**: a recursive `iter_children()` visit that stores each leaf's type, parent type and byte/row range.
- **token rebuild**: emit the leaf text with a spacing lookup per token, keep line breaks, clamp blank lines, and indent by brace depth.
- **doc IR / print**: a Wadler-style document (group/indent/line per node) printed at width 120 with a fits check.

The engine is a toy. A real block engine does more work per leaf (rule lookup, wrap and alignment passes), so read the numbers as the floor of Lua cost, not as the full engine.

| File | Lines | Leaves | parse | walk | token rebuild | end-to-end (tokens) | doc IR + print | end-to-end (doc) |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| PHP Preview `WRAPPING_AND_BRACES_SETTINGS` | 138 | 1,016 | 0.42 ms | 0.71 ms | 0.07 ms | **1.16 ms** | 0.73 + 0.10 ms | 1.27 ms |
| TypeScript Preview `WRAPPING_AND_BRACES_SETTINGS` | 109 | 838 | 0.33 ms | 0.54 ms | 0.05 ms | **0.90 ms** | 0.54 + 0.08 ms | 0.94 ms |
| Laravel `Eloquent/Builder.php` (67 KB) | 2,335 | 8,440 | 3.37 ms | 5.68 ms | 0.68 ms | **10.0 ms** | 6.14 + 0.78 ms | 10.3 ms |
| Laravel `Collections/Collection.php` (54 KB) | 2,001 | 6,721 | 3.41 ms | 5.89 ms | 0.52 ms | **9.8 ms** | 6.37 + 0.97 ms | 10.8 ms |
| TypeScript `src/compiler/scanner.ts` v5.6.2 (219 KB) | 4,091 | 32,271 | 12.9 ms | 21.9 ms | 2.38 ms | **36.9 ms** | 21.0 + 2.45 ms | 36.5 ms |
| Bootstrap 5.3.3 `bootstrap.css` (281 KB) | 12,056 | 48,068 | 28.8 ms | 35.0 ms | 3.28 ms | **83.0 ms** | 38.3 + 7.0 ms | 82.3 ms |

Repeated runs vary by about ±20% (Collection.php parse: 2.6 ms in one run, 3.4 ms in another).

Findings:

- **Cost is about 1 µs per leaf** for walk plus rebuild. The C-side parse is about a third of the total.
- **`TSNode:parent()` is expensive.** A walk that calls `node:parent()` per leaf took 14.5 ms on Builder.php against 5.7 ms when the walk passes the parent down (61 vs 22 ms on scanner.ts). The engine should carry its context down the walk and never ask a node for its parent.
- **The Preview does not need a re-parse when an Option changes**, because the sample text stays the same. Only the engine pass runs again: about 0.8 ms for the toy on the PHP Preview. Even with a real engine 10× heavier, the Preview stays at about 10–15 ms per Option change (an extrapolation, not a measurement).
- **Real buffers**: a 2,000-line PHP file costs about 10 ms for the toy. With a heavier real engine, formatting on save or by command stays well below typical expectations, but files above about 10k lines may need range formatting or async work.
- **Applying the result**: `vim.text.diff(old, new, {result_type='indices'})` took 0.22 ms on Builder.php and 1.2 ms on bootstrap.css. Minimal hunks can then be applied with `nvim_buf_set_text`/`set_lines`, which keeps marks and undo granular.

## 4. Building blocks for a compiled helper

Licences and versions from crates.io and GitHub (2026-10-29).

| Building block | What it is | Licence | Status | Fit for PhpStorm fidelity |
|---|---|---|---|---|
| `tree-sitter` crate [S12] | Rust bindings to the same C runtime | MIT | 0.27.1 (2026-10-08) | Same grammars as Lua; gives no parser gain, only CPU speed |
| `tree-sitter-php` etc. crates | Grammar crates | MIT | e.g. tree-sitter-php 0.25.1 | same grammar quality as in the table above |
| `go-tree-sitter` | Official Go bindings (cgo) | MIT | last push 2025-11-16 | as above |
| Topiary (`topiary-core`) [S13] | Tree-sitter formatter driven by query captures (`@append_space`, `@prepend_hardline`, indent start/end, softlines that break when the node was multi-line in the input) | MIT | 0.8.0 (2026-10-01) | **No right margin**: the code and book never mention a line width, and softlines break only by input layout. No Wrap if long, no Chop down, no alignment. Ships CSS, JSON, Bash, TOML; no PHP/JS |
| Mago (`mago-syntax`, `mago-formatter`, `mago-twig-syntax`) [S14] | Rust PHP toolchain: lossless lexer/CST with trivia (whitespace, comments, docblocks), formatter, Twig parser | MIT OR Apache-2.0 | 1.59.0 (2026-10-25) | Formatter "discard[s] the original formatting … reprint[s] the CST from scratch", Prettier-style document IR (`Group`, `IfBreak`, `IndentIfBreak`); ~96 options of its own and presets (PER-CS, PSR-12, Pint, …). Different model from PhpStorm. **The parser is a good PHP building block** (lossless, trivia, PHP-8 grammar). |
| oxc (`oxc_parser`, `oxc_formatter`/oxfmt) [S15] | Rust JS/TS parser and Prettier-compatible formatter | MIT | oxc_parser 0.156.0; `oxc_formatter` is `publish = false` (only as the oxfmt binary) | Formatter is "Based on Biome formatter", so Prettier-style; the parser is usable |
| Biome (`biome_formatter`, `biome_rowan`) [S16] | Generic formatter IR/printer and lossless CST (rowan) | MIT OR Apache-2.0 | `biome_formatter` last on crates.io 0.5.7 (2024-03-12); `biome_rowan` 0.7.0 | Prettier-style; crates not kept current on crates.io |
| swc (`swc_ecma_parser`) | Rust JS/TS parser | Apache-2.0 | 46.1.2 | parser only (no style formatter) |
| dprint (`dprint-core`, plugins) [S17] | Formatter platform: IR of texts, infos, conditions (resolved against output position, with reprint on late resolution), signals; plugins as Wasm (schema 4, recommended) or process plugins; editors use `dprint lsp` | MIT | dprint-core 0.71.1 | Closest IR to PhpStorm, because conditions can read the original AST and the output position. dprint-plugin-typescript's schema has 185 properties, `preferSingleLine` default `false` (keeps multi-line code), and `preferHanging`. Still a different option set. Wasm plugins need a Wasm runtime in the helper |
| Malva + raffia [S18] | CSS/SCSS/Sass/Less formatter + parser | MIT | malva 0.16.0, raffia active | raffia covers all four CSS-family syntaxes in one parser, which may help where Tree-sitter is weak (see table) |
| markup_fmt [S18] | HTML/Vue/Svelte/Astro/Angular/Jinja/Twig/XML formatter | MIT | 0.27.6 | formats markup only; delegates `<script>`/`<style>` |
| `sqlparser` (Apache DataFusion) [S19] | SQL parser with many dialects | Apache-2.0 | active | Drops comments ("with comments removed, normalized whitespace"), so unusable for a formatter |
| `shfmt` (mvdan/sh) | Shell formatter | BSD-3-Clause | active | **What PhpStorm itself calls** for Shell Script (corpus README). Use it directly. |
| VKCOM/php-parser (Go) | PHP parser | MIT | last push 2023-09-23 | stale |

Summary: there are good **parsers** (mago-syntax for PHP, oxc/swc for JS/TS, raffia for the CSS family), but no **formatting engine** with PhpStorm's model. Each available engine either reprints from scratch (Mago, oxc, Biome, Malva, markup_fmt) or has no line width (Topiary). Fitting PhpStorm's Options into them means rewriting their printers, which is the same work as writing our own engine.

## 5. How Neovim plugins ship and call native helpers

| Way | Example | How it works | Cost and risk |
|---|---|---|---|
| Prebuilt Lua C module + download | blink.cmp [S20] | Rust crate with `mlua` (`features = ["module", "luajit"]`), loaded by `require` after setting `package.cpath`. Downloads `…/releases/download/<tag>/…` matching the git tag, checks a `.sha256`, and on failure tells the user to set `build = 'cargo build --release'`. Has a pure-Lua fallback (`fuzzy.implementation = 'prefer_rust_with_warning'`) | CI must build per OS/arch; ABI tied to LuaJIT; in-process crash takes Neovim down |
| LuaJIT FFI on a C library | telescope-fzf-native [S21] | `ffi.load(library_path)` + `ffi.cdef`; built by `make`/`cmake` in the plugin manager's build step; "we do not ship binaries" | needs a compiler on the user's machine |
| Build hooks | lazy.nvim `build` (string command, Lua function, `build.lua`, or `"rockspec"` → `luarocks make`) [S22]; `vim.pack` `PackChanged` autocmd with `kind = install/update` [S23]; luarocks backend `luarocks-build-rust-mlua` [S24] | runs at install/update | per plugin manager; failures are silent for users who skip them |
| Job per call over stdin | conform.nvim [S25] | `vim.system(cmd, {stdin = buffer_text})`, reads stdout | Measured: `vim.system({'cat'})` with 3 KB stdin 0.87 ms, with 219 KB 1.82 ms; Biome 2.6.3 per call 37 ms (3 KB) and 53 ms (219 KB). A cold start on every Option change works against the Preview |
| Persistent process | `jobstart(…, {rpc = true})` msgpack-RPC [S26]; or an LSP server (`dprint lsp` [S17]) | one long-lived helper, requests over a pipe | Measured pipe round trip with a long-lived `cat`: 0.02 ms for 3 KB. Note: "rpc channels are implicitly trusted and the process at the other end can invoke any API function" [S26] |
| WASM | `vim.treesitter.language.add` with a `.wasm` grammar | only "If Nvim is built with `ENABLE_WASMTIME`" [S7]; the local 0.12.6 release build has `has('wasm') == 0` | not available to most users |
| Rust with Neovim API | nvim-oxi (MIT) | Rust plugin as a Lua module with Neovim API bindings | same shipping problem as blink.cmp |

Any of these adds a release pipeline per OS/arch. Our first-party Language Plugins are separate repositories (#1), so each would carry that pipeline.

## 6. How each approach reproduces PhpStorm's indent, spacing, wrapping, braces and blank lines

Three approaches:

- **A**: pure Lua engine on Neovim Tree-sitter, porting the IntelliJ block model.
- **B**: the same engine in a Rust/Go helper on tree-sitter crates or mago-syntax/oxc.
- **C**: adapting an existing formatter (Mago, oxc/Biome, dprint plugins, Malva, markup_fmt, Topiary).

| Concern | PhpStorm mechanism | A: Lua + Tree-sitter | B: Rust helper, own engine | C: adapt an existing formatter |
|---|---|---|---|---|
| Indent (`indent_size`, continuation indent, "indent case branches", keep indents on empty lines) | `Indent` per block (none/normal/continuation/space-based), applied when a block starts a line [S1] | Block builder maps TS node types to Indent kinds; the whitespace pass computes the indent of each line start from the block's parent chain | same algorithm in Rust | IR `indent()` exists, but continuation versus normal indent per construct is fixed by each formatter's style |
| Spacing (73 PHP "Spaces" Options) | `Spacing(min, max, minLF, keepLineBreaks, keepBlankLines)` between adjacent blocks [S2] | A rule function per (parent type, left leaf, right leaf) returns a Spacing; the gap text is read from byte ranges. Demonstrated on `space_before_method_call_parentheses`: 8/8 files match | same | every reprinter recomputes all whitespace; per-pair rules require changing the printer |
| Wrapping (Do not wrap / Wrap if long / Chop down if long / Wrap always, right margin, "align when multiline") | `Wrap` objects with `WrapType`, shared between siblings for chop-down; `WrapProcessor` decides on the right margin [S3][S4] | Port `WrapProcessor` and `AlignmentHelper`: needs column tracking in the whitespace pass and a backtrack to the last wrap point. The Wadler toy above shows the fits check costs < 1 ms on a Preview | same | A Prettier-style group breaks as a unit, which matches "Chop down if long". "Wrap if long" needs a fill primitive, and Mago's `Document` enum has none (`Group`, `IfBreak`, `Indent`, `Align`, `Line`, …). "Do not wrap" with kept line breaks needs `preserve_*`-style options such as Mago's `preserve_breaking_argument_list` |
| Braces (`end_of_line`, `next_line`, `next_line_if_wrapped`, `whitesmiths`, `gnu`; force braces) | Spacing with `minLineFeeds` before `{`, plus Indent of the brace block; force braces is a pre-processor edit. The Research Corpus notes that in PHP "Next line if wrapped" gives the same output as "Next line" (`BEHAVIOR-NOTES.md`) | Spacing rule on the gap before `{` + Indent on the `{…}` block. Force braces and other Code Conversion Options are token edits before the whitespace pass, then a re-parse | same | Mago has `same_line/next_line/always_next_line`; no shifted (whitesmiths/gnu) styles |
| Blank lines ("Keep maximum blank lines", "Minimum blank lines after …") | `keepBlankLines` caps kept blank lines; `minLineFeeds` sets minimum | Gap rule: count `\n` in the original gap, clamp to `[min, keep+1]` | same | reprinters keep at most one blank line or none; per-construct minimums need printer changes |
| Alignment (align assignments, key-value pairs, parameters) | `Alignment` objects with backward shift [S1] | Port `AlignmentHelper`; needs a second pass over the lines of a group | same | partly (e.g. dprint conditions on column) |
| Embedded languages | Template blocks merge outer and inner block trees (`TemplateXmlBlock`) [S6] | Merge the host and injected Tree-sitter trees by byte range | same, with the helper parsing both languages | markup_fmt delegates script/style to other formatters, which then need the same Options |

Notes:

- A and B have the same algorithm, so fidelity is the same. B is faster per leaf, but it adds start-up or IPC costs and a shipping pipeline per Language Plugin repository. A reaches the Preview budget already (part 3).
- C only gives fidelity where PhpStorm's Options match the formatter's own options. #1 forbids approximating, so for C most Options would be "left out or flagged".

### Fidelity check (delta method)

`data/behavior/php/ij_php_space_before_method_call_parentheses.json` gives PhpStorm's Default output and its output with the Option `true` for 8 input files. The check takes the Default output, inserts a space in the gap before `arguments` of `function_call_expression`, `member_call_expression`, `nullsafe_member_call_expression` and `scoped_call_expression`, and compares the result with the record.

- Naive node mapping: **6/8 files** match. The differences are PhpStorm rules:
  - No space for `isset`/`empty`/`die`/`eval` (Tree-sitter parses these as function calls).
  - No space for `$cb(…)` and `(function () {})()` (the callee is not a name).
  - A space **is** added in `echo ('x')`, `include ('file.php')` and `require_once (…)` (Tree-sitter: statement + `parenthesized_expression`).
- Refined mapping (exclude these callees, add the gap before the parenthesised argument of `echo`/`include*`/`require*`): **8/8 files** match.

So the Tree-sitter node mapping can match PhpStorm, but each Option's rule must be fitted against its Behaviour Record, because the PSI that PhpStorm uses and the Tree-sitter tree differ in places. The Behaviour Records are the golden tests for this.

## 7. Risks and open points

- **SQL** (207 records, 11 dialects): tree-sitter-sql fails on 61% of the test inputs. No other parser keeps comments (`sqlparser` drops them). SQL needs its own grammar work, or it is flagged or deferred. This matters to the language list in #1.
- **CSS family, Angular, Mermaid, HTTP Request**: grammar gaps hit the Preview samples themselves. Each needs grammar fixes upstream or in a pinned fork, or the affected Options are flagged.
- **Less, Sass, Gherkin** have no nvim-treesitter grammar. The recent Gherkin grammar has no licence, so use SamyAB's (MIT) or ask for a licence.
- **Code Conversion, PHPDoc, Arrangement**: these are token or tree edits, not whitespace. They need a pre-pass and a re-parse. PHPDoc needs the `phpdoc` grammar (claytonrcarter/tree-sitter-phpdoc, MIT) via injection.
- **Two trees for templates** (PHP+HTML, Twig): the merge of host and combined HTML trees is the hardest part of the engine. A prototype should prove it before the Language Plugin contract is fixed.
- **Vocabulary**: "block", "gap" and "Spacing" are not in `GLOSSARY.md` yet. They are candidates for `/domain-modeling` when the engine is specified.

## Method and reproduction

All experiments ran in `/tmp/opencode` (not committed):

- `grammars/`: shallow clones of each grammar, built with `cc -O2 -shared -fPIC -I src src/parser.c [src/scanner.c]`. SQL is built from the `gh-pages` branch, which carries `parser.c`.
- `bench.lua`: the timing table. `nvim --headless --clean -l bench.lua <lang> <file> 15`.
- `corpus_parse.lua`, `errloc.lua`: corpus parse counts and error locations.
- `inject.lua`: `LanguageTree:parse(true)` on the Blade/Twig/Vue Previews with nvim-treesitter's queries on `runtimepath`.
- `spawn.lua`: `vim.system` and persistent-pipe timings, Biome from mason.
- `delta_demo.lua`: the fidelity check; `REFINED=1` for the refined mapping.

Inputs: Laravel `12.x` `Builder.php` and `Collection.php`, TypeScript `v5.6.2` `src/compiler/scanner.ts`, Bootstrap `v5.3.3` `dist/css/bootstrap.css`, and Research Corpus Previews and test inputs.

## Sources

- [S1] IntelliJ Platform Plugin SDK, "Code Formatter" (updated 2026-08-18): https://plugins.jetbrains.com/docs/intellij/code-formatting.html
- [S2] `Spacing.java`, intellij-community `idea/262.10968.63`: https://github.com/JetBrains/intellij-community/blob/idea/262.10968.63/platform/code-style-api/src/com/intellij/formatting/Spacing.java
- [S3] `WrapType.java`, same tag: https://github.com/JetBrains/intellij-community/blob/idea/262.10968.63/platform/code-style-api/src/com/intellij/formatting/WrapType.java
- [S4] Formatting engine package (Apache-2.0 file headers): https://github.com/JetBrains/intellij-community/tree/idea/262.10968.63/platform/code-style-impl/src/com/intellij/formatting/engine
- [S5] Tree-sitter, "The Grammar DSL" (`extras`): https://tree-sitter.github.io/tree-sitter/creating-parsers/2-the-grammar-dsl.html
- [S6] Open IntelliJ formatters: `xml/xml-ui-common/src/com/intellij/psi/formatter/xml/XmlBlock.java`, `xml/xml-ui-common/src/com/intellij/xml/template/formatter/TemplateXmlBlock.java`, `json/src/com/intellij/json/formatter/`, `plugins/yaml`, `plugins/markdown/core/src/org/intellij/plugins/markdown/lang/formatter/`, `plugins/sh` in https://github.com/JetBrains/intellij-community; `cucumber/src/org/jetbrains/plugins/cucumber/psi/formatter/GherkinBlock.java` in https://github.com/JetBrains/intellij-plugins
- [S7] Neovim 0.12.6 `:help treesitter` (local `runtime/doc/treesitter.txt`): `treesitter-parsers`, `treesitter-parsers-wasm`, `vim.treesitter.language.add()`, `treesitter-language-injections`, `LanguageTree:parse()`, `TSNode:range()`, `TSNode:has_error()`, `TSNode:missing()`; https://neovim.io/doc/user/treesitter.html
- [S8] luarocks `tree-sitter-php` rock (neorocks): https://luarocks.org/modules/neorocks/tree-sitter-php
- [S9] nvim-treesitter `main` @ `a2f6944`: `README.md`, `SUPPORTED_LANGUAGES.md`, `lua/nvim-treesitter/parsers.lua`, `runtime/queries/{php,blade,twig,vue}/injections.scm`: https://github.com/nvim-treesitter/nvim-treesitter
- [S10] Grammar repositories (each `grammar.js` `extras`): tree-sitter/tree-sitter-{php,html,css,javascript,typescript,json,bash}, tree-sitter-grammars/tree-sitter-{vue,xml,yaml,markdown,make,scss}, EmranMR/tree-sitter-blade, gbprod/tree-sitter-twig, dlvandenberg/tree-sitter-angular, serenadeai/tree-sitter-scss, jimliang/tree-sitter-less, mdovale/tree-sitter-less, bajrangCoder/tree-sitter-sass, binhtddev/tree-sitter-gherkin, SamyAB/tree-sitter-gherkin, monaqa/tree-sitter-mermaid, rest-nvim/tree-sitter-http, ValdezFOmar/tree-sitter-editorconfig, DerekStride/tree-sitter-sql, claytonrcarter/tree-sitter-phpdoc (all on GitHub)
- [S11] Tree-sitter introduction: https://tree-sitter.github.io/tree-sitter/
- [S12] crates.io API, `tree-sitter`, `tree-sitter-php`, and the other crates in part 4: https://crates.io/crates/tree-sitter
- [S13] Topiary: https://github.com/tweag/topiary; book "Design principles", "The formatting pipeline", "Language support", "Scopes", "Vertical spacing" in `docs/book/src/`
- [S14] Mago @ `9a9703e`: https://github.com/carthage-software/mago; `docs/content/en/tools/formatter/overview.md`, `crates/formatter/src/settings.rs`, `crates/formatter/src/document/mod.rs`, `crates/syntax/src/cst/trivia.rs`, `Cargo.toml` (`license = "MIT OR Apache-2.0"`)
- [S15] oxc: https://github.com/oxc-project/oxc; `crates/oxc_formatter/Cargo.toml` (`publish = false`), `crates/oxc_formatter/README.md`
- [S16] Biome: https://github.com/biomejs/biome; `crates/biome_formatter/Cargo.toml`; crates.io `biome_formatter`, `biome_rowan`
- [S17] dprint: `crates/core/README.md`, `docs/overview.md`, `docs/wasm-plugin-development.md`, `docs/editor-extension-development.md` in https://github.com/dprint/dprint; schema https://plugins.dprint.dev/dprint/dprint-plugin-typescript/latest/schema.json
- [S18] Malva https://github.com/g-plane/malva, raffia https://github.com/g-plane/raffia, markup_fmt https://github.com/g-plane/markup_fmt (READMEs)
- [S19] datafusion-sqlparser-rs README ("Preserves Syntax Round Trip"): https://github.com/apache/datafusion-sqlparser-rs
- [S20] blink.cmp (local copy @ `78336bc`): `lua/blink/cmp/fuzzy/download/{init,files}.lua`, `lua/blink/cmp/fuzzy/rust/init.lua`, `lua/blink/cmp/config/fuzzy.lua`, `Cargo.toml`; https://github.com/saghen/blink.cmp
- [S21] telescope-fzf-native: `README.md`, `lua/fzf_lib.lua`; https://github.com/nvim-telescope/telescope-fzf-native.nvim
- [S22] lazy.nvim `doc/lazy.nvim.txt`, "Building" and "Rockspec": https://github.com/folke/lazy.nvim
- [S23] Neovim 0.12.6 `:help vim.pack-events` (`PackChanged`)
- [S24] luarocks-build-rust-mlua: https://github.com/mlua-rs/luarocks-build-rust-mlua
- [S25] conform.nvim (local copy @ `016802d`), `lua/conform/runner.lua` (`vim.system` with `stdin`): https://github.com/stevearc/conform.nvim
- [S26] Neovim 0.12.6 `:help channel-rpc`
- Research Corpus (`~/Projects/phpstorm-editorconfig/`): `README.md`, `data/behavior/php/ij_php_keep_line_breaks.json`, `data/behavior/php/ij_php_space_before_method_call_parentheses.json`, `docs/notes/BEHAVIOR-NOTES.md`, `data/code-samples/`, `tests/formatter/`
