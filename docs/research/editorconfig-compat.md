# How complex is PhpStorm-compatible `.editorconfig` read/write?

Research for issue #4 (map: issue #1). Reference: PhpStorm 2026.2.3 (build 262.10968.76) and the Research Corpus
in `~/Projects/phpstorm-editorconfig/`. Terms follow `GLOSSARY.md`. A **Section** is an `.editorconfig` glob block
such as `[*.php]`. Source numbers such as [S3] point to the list at the end.

## Answer

The file syntax is easy. The cost is in the semantics.

- **`.editorconfig` cannot hold a full Code Style.** SQL (210 fields, 12 pages), Arrangement, HTML and Vue
  `uniform_indent`, and "Enable regular expressions in formatter markers" have no key. A few distinctions are also
  lost: an Option set to "Default" versus an explicit value equal to `[*]`, and wrap int 4 versus 5. So **every
  strategy needs our own format** for those Options. Read+write therefore means two stores that must stay in sync.
- **PhpStorm itself never round-trips the file.** It keeps the Code Style in its scheme XML. It reads
  `.editorconfig` as an overlay for each file, and writes one only with "Export" or "Generate", which build the
  text from scratch and never merge it into an existing file [S1][S2][S5].
- **PhpStorm reads `.editorconfig` per file, not per language.** For one file path it merges every matching Section.
  Then it applies each key to the language that the key prefix names, whatever Section the key came from.
  Unprefixed keys (`indent_size`, `ij_continuation_indent_size`, …) apply to every language in that file [S1][S3].
  The Behaviour Records were made with scheme XML [C9], which works per language. So an `.editorconfig`-driven
  result can differ from the Behaviour Records for embedded languages and for overlapping Sections.
  PhpStorm's own export causes such a difference: a `.blade.php` file gets PHP's `ij_continuation_indent_size = 4`
  (details in §3).
- **Hand edits and comments can survive a rewrite**, but only if our writer edits one line at a time. Comments are
  whole lines only, so this is easy. Semantic edits are hard: the writer must find the line that is in effect for the
  file, which can be in a custom glob or in a subdirectory file.
- **Neovim's built-in editorconfig cannot be reused to read `ij_*` keys.** It lowercases every value, applies and
  stores only keys that have a handler, keeps its parser private, and its glob matching breaks several spec rules
  [S8]. So every strategy that reads `.editorconfig` needs its own parser and glob matcher.

Complexity estimates. Lua lines of code without tests. These are my estimates, not measurements.

| Strategy | What it is | Estimate | Main risk |
|---|---|---|---|
| **Own format** (C) | Store the full Code Style in our own file. Optional: a write-once "Export to `.editorconfig`", the same as PhpStorm's. | **Small.** 200–400 LOC for the store. Export adds 300–500 LOC and can be checked byte for byte against `data/default-scheme.editorconfig`. | None specific. C is needed in all three strategies, because of SQL and Arrangement. |
| **Read-only** (B) | Import `.editorconfig` into our format, or use it at format time as an overlay for each buffer, the way PhpStorm does. | **Medium.** C plus 600–1000 LOC: a spec-compliant glob matcher, the parent-directory search, a decoder for 976 keys, PhpStorm's reader rules, and a mapping from file paths to languages. | Per-file meaning against per-language Behaviour Records. |
| **Read+write** (A) | `.editorconfig` is a primary store that the Menu edits in place. | **Large.** C + B plus 700–1100 LOC: a line-preserving editor, the writer rules, a rule for which Section and file to edit, and a side store kept in sync. In total about 1500–2500 LOC and 3–5 weeks. | Many policy choices (which line or file to edit, how to treat Default values, overlapping Sections). Silent loss when PhpStorm re-exports. Two stores. |

For comparison, PhpStorm itself uses C + B + a write-once export.

## Details

### 1. How PhpStorm stores, reads and writes

- **Store.** The Code Style lives in the scheme XML. SQL lives there too, in `<SqlCodeStyleSettings version="7">`
  plus one element per dialect [C5][C6]. Arrangement also lives there [C1 `data/arrangement.json`].
- **Read.** `EditorConfigCodeStyleSettingsModifier` changes a temporary copy of the scheme for each file. Keys that
  the file does not set keep the scheme value [S1]. A `.editorconfig` is therefore a diff over the user's scheme, not
  a full Code Style. If we read it, keys that are missing fall back to our own stored values. They match PhpStorm
  only if the PhpStorm user has the same scheme.
- **Write.** `EditorConfigSettingsWriter` writes a full file to an output stream [S2]. It is used by
  Export [S2], by "Create .editorconfig", and by "Generate language properties". The last one inserts the text of
  one language at the caret in the editor (`insertString`) [S5]. None of them merges into an existing file.

### 2. Writer rules (complete list)

| # | Rule | Source |
|---|---|---|
| W1 | **Layout.** An optional `root = true` comes first, then `[*]`, then one Section per language. Sections are sorted by the glob string. Keys are sorted by kind (standard keys, then generic `ij_*`, then `ij_<lang>_*`) and then by name. Each pair is written as `key = value`, with no comments. The Corpus export follows this: all 21 Sections are sorted, and the keys in every Section are in this order (checked with a script on `data/default-scheme.editorconfig`). | [S2] L86–125, L167–184 |
| W2 | **Section glob** = the file-type associations of the language, sorted and joined with `,`, wrapped in `{…}` if there is more than one. So it depends on the user's file-type setup (the export has `phpunit.xml.dist` and `composer.lock`, for example). A language with no file type (Angular2Html) or an empty pattern (Makefile) gets no Section. Languages with the same pattern share one header. | [S4] `buildPattern` L183–190; [S2] L92–112; [C2] `writer_rules.section_glob` |
| W3 | **Inheritance from `[*]`.** A language value is not written if `[*]` has the same key with the same value (`matchesGeneral`). This is why `indent_size`, `tab_width`, `ij_continuation_indent_size`, … appear in only some Sections. In total 976 keys can appear in Sections, and 837 are in the default export. | [S2] L146–161; [C2] `skip_if_equals_general`, `keys_per_section` |
| W4 | **Null values are skipped.** An accessor that returns null is not written: integers below 0 (`IntegerAccessor.isEmpty` is `value < 0`, so a language `RIGHT_MARGIN = -1` writes no `max_line_length`), and `WRAP_ON_TYPING = -1`. | [S6] `IntegerAccessor` L40–42, `CodeStyleFieldAccessor.get` L36–47; [C2] `skip_null` |
| W5 | **Per-language "Default" values.** "Wrap on typing" Default → nothing. "Hard wrap at" -1 → nothing, any other value → `max_line_length = N` in the language Section. Visual guides `[]` → empty, skipped when equal to `[*]`. **Correction to the Corpus README:** because of W3, "No" (`ij_wrap_on_typing = false`) is *also* not written when `[*]` has `false`, which is the default. So Default and No look the same in the file. This follows from the writer code and was not seen in a real export. | [C2] `per_language_inherit_values`; [S2] L153, L160–161 |
| W6 | **Names.** Inside a language Section, indent Options use the standard names `indent_size`, `tab_width`, `indent_style`, or generic names `ij_continuation_indent_size`, `ij_smart_tabs`. `wrap_on_typing`, `visual_guides` and `max_line_length` use the generic names too. `keep_indents_on_empty_lines` has the language prefix. Language ids can contain `-` (`ij_http-request_*`, `ij_angular-html_*`). | [C2] `writer_rules.names`; [S3] `toEditorConfigNames` L21–38 |
| W7 | **Value encoding.** Booleans `true`/`false`. Integers in decimal. Wrap: `off`/`normal`/`on_every_item`/`split_into_lines`, where ints 4 and 5 both write `on_every_item`. Brace style: `end_of_line`/`next_line_if_wrapped`/`next_line`/`whitesmiths`/`gnu`. Force braces: `never`/`if_multiline`/`always`. CSS brace placement and value alignment are names, but **Less/Sass/SCSS write raw ints** (`ij_less_brace_placement = 0`). So do JS/TS `align_object_properties`/`align_var_statements` and PHP `namespace_brace_style`/`place_parens_for_constructor`. Enum spelling = the enum's `toString()` lowercased with spaces → `_`, so JS writes `whenmultiline` and HTML/PHP write `when_multiline`. Comma lists are trimmed and may be empty. Strings may be empty (`ij_javascript_property_prefix = `). The Corpus maps all 156 enum, list and string keys (0 unmapped). | [C3] `value_sets`, `keys`, `stats`; [S6] `WrappingAccessor` L11–25, `EnumPropertyAccessor` L34–36; [S2] L186–193 |
| W8 | **Cross-page keys.** HTML › Other "Add for JSX attributes" writes `ij_javascript_jsx_attribute_value`. `ij_typescript_jsx_attribute_value` has no control in the UI. "Set from… › Language" is a copy action and writes no key. So the key of an Option is not tied to the Tab that shows it. | [C4] `cross_page_options` |
| W9 | **Not exported, scheme XML only.** `uniform_indent` of HTML ("Use HTML indents within style/script") and Vue ("Same in the whole file / Specific to the language"). `formatter_tags_accept_regexp` ("Enable regular expressions in formatter markers"). `OverrideLanguageOptions`, which is internal and has no UI. `ij_formatter_enabled` is a valid key but is not in the default export. "Other File Types" edits `OTHER_INDENT_OPTIONS`, which is written as the indent keys of `[*]`. | [C2] `not_exported_properties`, `keys_per_section.all`, `languages_without_editorconfig`; [S3] `isIgnored` L64–67 |
| W10 | **SQL has no keys at all.** `supportsExternalFormats() = false` for General and the 11 dialects. It needs `<SqlCodeStyleSettings version="7">` and one tag per dialect. A dialect page is read only when its `USE_GENERAL_STYLE` is false. | [C2] `languages_without_editorconfig.SQL`; [C5] `xml_tag_note`, `per_dialect`; [C1] README "SQL" |
| W11 | **Arrangement** is not an `ij_*` Option. It lives in the scheme XML (`<arrangement>`). | [C1] README "Formatter behaviour"; `data/arrangement.json` |
| W12 | **Standard keys come from IDE-level options, not from the scheme.** `charset` comes from the project encoding, `end_of_line` from the line separator, `insert_final_newline` from "Ensure every saved file ends with a line break". `trim_trailing_whitespace` is written only when it is not null. Its unset state ("strip modified lines") is a third value. | [S2] L43–61; [C7] `trim_trailing_whitespace` |
| W13 | **The export default can differ from the formatter default.** TypeScript `force_semicolon_style` exports `true`, but with no value set the formatter behaves as `false`. A writer that leaves out "default" values must therefore know which default it means. | [C7]; [C1] README "Catalog default is not always the real default" |

### 3. Reader rules (what PhpStorm does with a file)

| # | Rule | Source |
|---|---|---|
| R1 | **Parser = ec4j.** Keys are lowercased. Values keep their case (`prop.sourceValue`); ec4j lowercases values only for its known standard property types. `:` is accepted as well as `=`. **ec4j still treats ` #` or ` ;` after whitespace as the start of an inline comment** in values and globs. Spec 0.15 and later says they are part of the value. | [S7] `AbstractValidatingHandler` L62–90, `PropertyType.LowerCasingPropertyType` L180–196, `EditorConfigParser` L173–176, L308–319, L340; [S1b] L157 |
| R2 | **Merge for each file.** The search walks up from the file's directory and stops at `root = true`, at a project base directory (registry default), or at a `.editorconfig` that fails to parse. Inside a file, a later Section wins; a closer file wins over a farther one. ec4j passes 189/189 editorconfig-core-tests on Linux. | [S1b] L48–60, L64–77, L84–112, L144–169; [S7] README |
| R3 | **Languages are chosen by key prefix, not by Section.** The mappers used are: the file's base language, every language whose `ij_<id>_` prefix appears, and *all* languages if any indent key is present (`indent_size`, `indent_style`, `tab_width`, `continuation_indent_size`). `[*]` normally has one, so in practice all languages are used. | [S1] L294–330; [S3] L44–62 |
| R4 | **Two passes per language.** First the unprefixed names are applied, with `ij_` and then `any_` removed (so `ij_any_<common option>` and even a bare `else_on_new_line` reach every language). Then `ij_<lang>_*` is applied, so it wins over `ij_any_*`. A hand-written file can use `ij_any_*`; the writer never writes it. | [S1] L175–208, L252–271, L332–359; [S3] L40–42; [S3b] `PROPERTY_KIND_MAP` L25–43 |
| R5 | **`indent_size` also sets `continuation_indent_size`** when the file does not give `ij_continuation_indent_size`. So a plain `indent_size = 2` gives a continuation indent of 2, not the scheme's 8. | [S1] L210–219 |
| R6 | **Value preprocessing.** `indent_size = tab` → `tab_width`, or the scheme's tab size. `indent_style = tab` with a `tab_width` → `indent_size` is replaced by `tab_width`. `max_line_length = off` → 1000. | [S1] L221–250 |
| R7 | **Value parsing.** Booleans: `"true".equalsIgnoreCase(v)`, so *any other string is false*. Integers: `parseInt`, and an invalid value is ignored. Magic ints and enums: a lookup that is case-sensitive, and an unknown value is ignored. Wrap `on_every_item` reads back as **4**, not as the UI's 5. | [S6] `BooleanAccessor` L20–22, `IntegerAccessor` L15–22, `MagicIntegerConstAccessor` L33–37, `EnumPropertyAccessor` L43–46; [C3] `wrap.note` |
| R8 | **`unset` is not handled for `ij_*` keys.** `none`/`unset` are mapped only for the standard keys (`configValueForKey`). By R7, `ij_x = unset` on a boolean Option sets it to false. This was read from the source and not tested in the IDE. | [S4] L48–63; [S1] L175–208 |

**The per-file meaning in practice.** In PhpStorm's own Default export, `[*.blade.php]` comes before the PHP
Section `[{…,*.php,…}]`, and the PHP Section has `ij_continuation_indent_size = 4`. A `.blade.php` file matches both
Sections. By R2, R3 and R4, PhpStorm reading its own export gives every language in that file a continuation indent
of 4, while the scheme had 8 for Blade (Blade writes no value because it equals `[*]`) [C8] [S1]. In the same way,
`ij_html_*` keys in the PHP Section change the HTML inside PHP files. So "read the export back" is not even lossless
inside PhpStorm.

### 4. Neovim's built-in support and the editorconfig-core libraries

| | Keys | Values | Unknown keys (`ij_*`) | Inline `#`/`;` | Glob |
|---|---|---|---|---|---|
| Spec 0.17.2 [S9] | lowercased | not defined (only standard values are case-insensitive) | cores "shall accept and report"; plugins ignore | part of the value | `*`, `**`, `?`, `[seq]`, `[!seq]`, nested `{a,b}`, `{n1..n2}`, `\` escape, `{s1}` literal |
| Neovim 0.12.6 [S8] | lowercased | **all lowercased** (`val:lower()`, L266) | parsed, but applied and stored in `b:editorconfig` only if `properties[key]` exists (L337–352) | part of the value | `vim.fn.glob2regpat` plus a fix for `*` (L236–246), with bugs, see below |
| ec4j (PhpStorm) [S7] | lowercased | case kept, except standard types | kept | **inline comment** | 189/189 core tests |
| editorconfig-core-c [S10] | lowercased | lowercased only for 6 standard keys (L83–90) | kept | part of the value | reference core |
| editorconfig-core-js [S11] | lowercased | lowercased only for standard keys (L120–128, L280–285) | kept | part of the value | minimatch |

Neovim glob checks (the function was extracted from `runtime/lua/editorconfig.lua` v0.12.6 and run in
`nvim --headless`):

| Glob | Path | Spec says | Neovim |
|---|---|---|---|
| `{*.ctp,…,*.php,…}`, `*.blade.php`, `{*.ant,…,phpunit.xml.dist}`, `.editorconfig`, `{a,{b,c}}` | matching paths | match | match (OK) |
| `file{1..10}.txt` | `file10.txt` / `file5.txt` | match / match | **no / no** (turned into `[1-10]`) |
| `{single}.txt` | `{single}.txt` | literal match | **no**; it matches `single.txt` instead |
| `[!a]bc` | `xbc` | match | **no** (`!` is not turned into a negation) |
| `a\*b` | `a*b` | match | **no** |

What this means for the plugin:

- We cannot read `ij_*` values through Neovim. They lose their case (`ij_javascript_blacklist_imports = rxjs/Rx`
  becomes `rxjs/rx`). They are dropped unless we register a handler for each of the 976 keys. `parse()` is a local
  function. So we need our own parser and glob matcher (the Lua core `editorconfig-core-lua` is a binding to the C
  library, not pure Lua [S12]). Both PhpStorm-export patterns and hand-written globs must work.
- Neovim keeps applying the standard keys from the same file. `max_line_length` sets `'textwidth'`, which wraps
  text while you type. PhpStorm has `ij_wrap_on_typing = false` and does not do this. `indent_*` set `'shiftwidth'`,
  `'tabstop'` and `'expandtab'`. Neovim applies the file only on `BufNewFile`, `BufRead` and `BufFilePost`
  [S8 plugin L2–13]. So after the Menu writes the file, open buffers keep old values unless we call
  `require('editorconfig').config(buf)` for each of them.
- If we write a value that contains ` #` or ` ;`, PhpStorm (ec4j) and Neovim/core-c read different values. A writer
  must refuse such values or warn about them.

### 5. Can a user's hand edits and comments survive a rewrite?

**Syntax: yes, with an editor that changes one line at a time.** The format is line-based, and comments are whole
lines [S9]. Keep every line as it is. Change only the value part of the one pair line that we own, and keep the
original spelling of the key and the separator (`=` or `:`). Insert new pairs at the end of the target Section,
before its trailing blank and comment lines. When an Option goes back to its inherited value, delete the line or
leave it, depending on our policy. Small edge cases:

- **Duplicate keys** in one Section: the last one is in effect, so edit that one.
- **A deleted pair** leaves the comment above it with nothing to describe.
- **Inline-comment ambiguity** (R1): when we change the value of `k = v # note`, PhpStorm reads `# note` as a
  comment and the spec reads it as part of the value. Neither choice is correct in both readers.
- **PhpStorm's own Export replaces the whole file**, including our edits and the user's comments (§1). A team that
  goes back and forth between PhpStorm and Neovim can lose data in either direction.

**Semantics: this is the hard part.** A value that the Menu shows for language L must be the value that is in effect
for L's files. Hand-written files break the "one Section per language" model in these ways:

- Custom globs (`[*.{php,phtml}]`, `[src/legacy/**.php]`).
- Overlapping Sections (§3).
- Subdirectory `.editorconfig` files.
- `ij_any_*` keys (R4).
- `unset` (R8).

So the writer must compute where a value takes effect (§6) and edit *that* line. Otherwise the change has no visible
effect, or it changes other files too. Example: a generic key in `[*]` reaches every language.

### 6. A workable model for reading and writing

- **Read for each buffer** (gives fidelity with PhpStorm when a real buffer is formatted): parse the files up to
  `root`, merge the matching Sections for the buffer's path, then apply R3–R8 to the Code Style of each language
  in that file.
- **Read for the Menu** (the Menu edits one language at a time): use a *probe path* for each language, such as
  `<root>/__probe__.php` built from the language's file-type pattern, and resolve it like a buffer. This works with
  any glob. A value that a deeper Section or subdirectory overrides needs a marker in the UI.
- **Write** (strategy A only): for language L and key K, find the last pair that sets K and matches L's probe path.
  If one exists, edit it. If none exists, add the pair to L's canonical Section (W2), and create that Section if it
  is missing. Then apply W3–W7, and refuse values that W9–W11 cannot express.

### 7. Losses that a perfect implementation still has

1. SQL, Arrangement, the two `uniform_indent` Options, and `formatter_tags_accept_regexp` (W9–W11).
2. "Default" against an explicit value equal to `[*]`, for indent, `max_line_length`, `wrap_on_typing` and visual
   guides (W3–W5). The behaviour is the same until `[*]` changes. After that the language follows `[*]`, while in a
   PhpStorm scheme it would keep its own value.
3. Wrap int 5 (the UI's "Chop down if long") reads back as 4 (W7, R7). In the Behaviour Records 5 is the value that
   was measured [C10].
4. The meaning of generic keys across overlapping Sections (§3).

### 8. Breakdown of the estimates

Lua LOC without tests, my estimates. A = read+write, B = read-only, C = own format.

| Component | A | B | C | Notes |
|---|---|---|---|---|
| Own store (full Code Style incl. SQL, Arrangement, a schema version) | ✔ | ✔ | ✔ | 200–400 |
| Key table and codec, generated from `extra-ij-keys.json` + `enum-values.json` | ✔ (both directions) | ✔ (decode) | export only | 200–350; the data is complete in the Corpus |
| Parser (simple) | — | ✔ | — | 80–120 |
| Parser that keeps lines + editor | ✔ | — | — | 250–400 |
| Spec glob matcher + core-test glob cases | ✔ | ✔ | — | 150–250; Neovim's cannot be reused (§4) |
| Parent-directory search, `root`, precedence, cache, invalidation | ✔ | ✔ | — | 80–150 |
| Reader rules R3–R8, probe paths | ✔ | ✔ | — | 100–200 |
| Writer rules W1–W7, choice of target Section and file, policy for Default values | ✔ | — | export: W1–W7 only | A: 300–500; export: 150–250, golden test against `data/default-scheme.editorconfig` |
| Sync of the side store and conflict UI (values that a deeper Section overrides, values that cannot be written) | ✔ | small | — | 150–300 |
| Refresh of Neovim's built-in options after a write | ✔ | — | — | ~20 |
| **Total** | **≈1500–2500** | **≈800–1400** | **≈200–400 (+300–500 export)** | |

### 9. Open points

- Not checked in a running PhpStorm: R8 (`unset` on `ij_*` booleans), how out-of-range integers from
  `.editorconfig` are treated, and whether "No" for wrap on typing is really left out (W5). All three are read from
  the source only.
- The source is cited from the `262` branch of intellij-community. Its writer rules match the writer rules that the
  Corpus mined from the 2026.2.3 jars [C2]. The `262` tag of PhpStorm itself was not compared.
- No language pair in the Default export shares a glob (W2). That case was found only in the code.

## Sources

Primary sources, pinned to a commit.

- [S1] JetBrains/intellij-community `262` @ `2af5a497`, `plugins/editorconfig/backend/src/configmanagement/extended/EditorConfigCodeStyleSettingsModifier.kt` — https://github.com/JetBrains/intellij-community/blob/2af5a497999d4025d06801967ea5f864f216ceaf/plugins/editorconfig/backend/src/configmanagement/extended/EditorConfigCodeStyleSettingsModifier.kt
- [S1b] same commit, `plugins/editorconfig/backend/src/plugincomponents/EditorConfigPropertiesService.kt` — https://github.com/JetBrains/intellij-community/blob/2af5a497999d4025d06801967ea5f864f216ceaf/plugins/editorconfig/backend/src/plugincomponents/EditorConfigPropertiesService.kt
- [S2] same commit, `plugins/editorconfig/backend/src/configmanagement/export/EditorConfigSettingsWriter.kt` (and `EditorConfigExporter.java`, `create/CreateEditorConfigAction.java` in the same plugin) — https://github.com/JetBrains/intellij-community/blob/2af5a497999d4025d06801967ea5f864f216ceaf/plugins/editorconfig/backend/src/configmanagement/export/EditorConfigSettingsWriter.kt
- [S3] same commit, `plugins/editorconfig/backend/src/configmanagement/extended/EditorConfigIntellijNameUtil.java` — https://github.com/JetBrains/intellij-community/blob/2af5a497999d4025d06801967ea5f864f216ceaf/plugins/editorconfig/backend/src/configmanagement/extended/EditorConfigIntellijNameUtil.java
- [S3b] same commit, `plugins/editorconfig/backend/src/configmanagement/extended/IntellijPropertyKindMap.java` — https://github.com/JetBrains/intellij-community/blob/2af5a497999d4025d06801967ea5f864f216ceaf/plugins/editorconfig/backend/src/configmanagement/extended/IntellijPropertyKindMap.java
- [S4] same commit, `plugins/editorconfig/backend/src/Utils.kt` — https://github.com/JetBrains/intellij-community/blob/2af5a497999d4025d06801967ea5f864f216ceaf/plugins/editorconfig/backend/src/Utils.kt
- [S5] same commit, `plugins/editorconfig/backend/src/configmanagement/generate/EditorConfigGenerateLanguagePropertiesAction.java` — https://github.com/JetBrains/intellij-community/blob/2af5a497999d4025d06801967ea5f864f216ceaf/plugins/editorconfig/backend/src/configmanagement/generate/EditorConfigGenerateLanguagePropertiesAction.java
- [S6] same commit, `platform/lang-api/src/com/intellij/application/options/codeStyle/properties/` (`WrappingAccessor.java`, `MagicIntegerConstAccessor.java`, `BooleanAccessor.java`, `IntegerAccessor.java`, `EnumPropertyAccessor.java`, `CodeStyleFieldAccessor.java`) — https://github.com/JetBrains/intellij-community/tree/2af5a497999d4025d06801967ea5f864f216ceaf/platform/lang-api/src/com/intellij/application/options/codeStyle/properties
- [S7] ec4j/ec4j `main` @ `64a1f1a0`: `core/src/main/java/org/ec4j/core/parser/EditorConfigParser.java`, `parser/AbstractValidatingHandler.java`, `model/PropertyType.java`, `README.adoc` — https://github.com/ec4j/ec4j/tree/64a1f1a0ef1ac78d4f849de34a1c596e3fc87f91
- [S8] neovim/neovim `v0.12.6`: `runtime/lua/editorconfig.lua`, `runtime/plugin/editorconfig.lua`, `runtime/doc/plugins.txt` (`editorconfig-custom-properties`). The local `/usr/share/nvim/runtime` is identical to the tag. `master` @ `9290926c` still has `val:lower()` and the same glob code. — https://github.com/neovim/neovim/blob/v0.12.6/runtime/lua/editorconfig.lua
- [S9] EditorConfig Specification 0.17.2 — https://spec.editorconfig.org/
- [S10] editorconfig/editorconfig-core-c @ `7a42c650`, `src/lib/editorconfig.c` — https://github.com/editorconfig/editorconfig-core-c/blob/7a42c65078121bb3578a19941b6b50713e42f6bf/src/lib/editorconfig.c
- [S11] editorconfig/editorconfig-core-js @ `71d4a0a5`, `src/index.ts` — https://github.com/editorconfig/editorconfig-core-js/blob/71d4a0a5ee9b3ee3e07c82c456965697395fbbc0/src/index.ts
- [S12] editorconfig/editorconfig-core-lua `README.md` — https://github.com/editorconfig/editorconfig-core-lua

Research Corpus (`~/Projects/phpstorm-editorconfig/`, read-only):

- [C1] `README.md`, "Things a re-implementation must get right", "Formatter behaviour", "Known limits"
- [C2] `data/extra-ij-keys.json`: `writer_rules`, `per_language_inherit_values`, `keys_per_section` (976 entries, 23 domains), `not_exported_properties`, `languages_without_editorconfig`
- [C3] `data/enum-values.json`: `value_sets` (35), `keys` (156 mapped, 0 unmapped)
- [C4] `data/ui-structure.json`: `cross_page_options`
- [C5] `data/sql-options.json`: `per_dialect`, `dialect_pages`, `xml_tag_note`
- [C6] `data/default-scheme.editorconfig` (raw export) and `data/defaults-by-language.json`
- [C7] `docs/notes/BEHAVIOR-DEFAULTS-CHECK.md` (TypeScript `force_semicolon_style`, `trim_trailing_whitespace`)
- [C8] `data/default-scheme.editorconfig` lines 17–18 (`[*.blade.php]`) and 518–519 (PHP Section, `ij_continuation_indent_size = 4`)
- [C9] `docs/notes/BEHAVIOR-NOTES.md` "Method" (scheme XML per option, `phpstorm format -s scheme.xml`), "GUI verification"
- [C10] `docs/notes/BEHAVIOR-SPOT-CHECK-markup.md` and `-small-languages.md` (wrap values `0, 1, 5, 2` measured)
