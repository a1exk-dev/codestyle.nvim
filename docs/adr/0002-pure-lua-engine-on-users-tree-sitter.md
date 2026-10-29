# Pure Lua formatting engine on the user's Tree-sitter parsers

The Core owns one formatting engine, written in pure Lua. It ports IntelliJ's block model: blocks, with Spacing, Indent, Wrap and Alignment between and on them, and the formatter changes only the gaps between blocks. The engine formats the Preview and real buffers. It knows no specific Option: each Language Plugin turns its own Options into a block builder and rules. Like PhpStorm, the engine keeps the user's layout unless an Option says otherwise. Printer-style formatters (Prettier, Biome, Mago, dprint) reprint the code from scratch, and they could not even reproduce PhpStorm's Default output (see "Can external formatters cover PhpStorm's options?", #2, and "Which building blocks exist for our own formatting engine?", #3). We use only Neovim, Neovim plugins and Lua. We ship, download, compile and call no outside program, so the parsers come from the user's Neovim setup, for example nvim-treesitter.

## Considered Options

- **External formatters** (Prettier, php-cs-fixer, Biome, dprint, …). Ruled out: they cover 11–36% of the Options exactly and change most of PhpStorm's own Default outputs.
- **A compiled helper** (Rust/Go, mlua module or helper process). It gives no gain in fidelity, because the rules for each language are hand-written in any runtime, and the Lua engine is fast enough (a toy formats the PHP Preview in about 1.2 ms). It would add a release pipeline per OS and architecture to every Language Plugin repo.
- **Parsers that we ship, download or compile.** Ruled out by the rule "nothing outside Neovim, Neovim plugins and Lua".
- **`shfmt` for Shell Script**, which PhpStorm itself calls. Ruled out by the same rule.

## Consequences

- Shell Script is formatted in Lua too, and it must match its Behaviour Records without `shfmt`.
- A Language Plugin cannot fix the version of the user's parser. Each rule names the parser nodes it needs. When a node is missing, the engine skips that rule, formats the rest, and warns the user.
- A language that has no parser in the user's setup (for example Less, Sass and Gherkin, which are not in nvim-treesitter) is not formatted.
- Code inside and around an `ERROR` or `MISSING` node keeps its text. The rest of the file is formatted.
- One format run is: Arrangement, then the Language Plugin's steps that change text, then a new parse, then the whitespace pass, then the steps after it. A Language Plugin can also replace the Core engine with its own Lua formatter.
- In mixed-language files, the Core merges the block trees of the host and the embedded language. The embedded language's own Language Plugin formats its part with that language's Code Style. When that Language Plugin is not installed, the embedded part keeps its text.
- No selection formats the whole file, and a selection formats only that part. The engine always builds blocks for the whole file. Only the changed text is written to the buffer, as one undo step.
- An LSP server is never needed by default. The "overridden" Arrangement features (off by default) need to know parent classes in other files. When the user turns one on, it requires the user's LSP server. Without the server, that feature is skipped with a warning.
