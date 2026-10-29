# Can external formatters cover PhpStorm's Code Style Options?

Research for ticket [#2](https://github.com/a1exk-dev/codestyle.nvim/issues/2) (map: [#1](https://github.com/a1exk-dev/codestyle.nvim/issues/1)). Date: 2026-10-30. Reference: the Research Corpus (PhpStorm 2026.2.3, `~/Projects/phpstorm-editorconfig/`).

## Answer

**No.** No external formatter, and no combination of them, can be the formatting engine under the fidelity rule ("for each supported Option, the output must match its Behaviour Records"). There is one exception: Shell Script. PhpStorm itself formats Shell Script by running `shfmt`.

- **Option coverage is low.** Of the Options with a recorded effect (`verified-effect`), the best tool for each Option has a setting for the same construct and every value ("exact" mapping) for only **26 of 230 PHP Options (11%)** and **55 of 152 JavaScript / 55 of 159 TypeScript Options (35–36%)**. Another 157 PHP and 68–71 JS/TS Options map only partially: one setting covers several Options, only some values exist (for example 0 or 1 blank lines instead of 0–10, or "true only"), or the tool uses a different algorithm. No tool has a setting at all for 47 PHP and 29–33 JS/TS Options. Most of those are on Wrapping and Braces: the Wrap modes, "Align when multiline", "New line after '('", and "Keep … in one line".
- **The tools cannot even reproduce PhpStorm's Default output.** When given PhpStorm's own Default-scheme outputs from the Behaviour Records, the tools leave only a small share of them unchanged: prettier + plugin-php 15%, mago 29%, phpcbf (PSR12) 34%, and the best php-cs-fixer rule set 77% of 146 PHP files. For JavaScript the shares are prettier 7%, biome 7%, dprint 10%, clang-format 6%, ESLint + @stylistic 65%, and the TypeScript language service formatter 76% of 68 files. TypeScript is similar. If the Default base already differs, no Option value can match its Behaviour Record.
- **Mapped Options mostly do not produce PhpStorm's edit.** In 132 runs (one Option value, one tool, and that Option's Behaviour Record inputs), the tool made the same edit as PhpStorm on 51% of the PHP files and 31% of the JS/TS files that PhpStorm changed. A tool matched PhpStorm's edit on every input in only 12 of 58 PHP runs and 7 of 74 JS/TS runs. Every one of those 19 runs was a simple spacing, brace, blank-line or single line-break Option.
- **The cause is the engine model, not a missing setting.** The IntelliJ formatter adjusts only the whitespace between blocks and keeps the author's line breaks. It wraps only where a Wrap Option tells it to. Prettier, biome, dprint and mago reprint the code from the syntax tree and break lines wherever a line is longer than the print width ([Prettier: "reprints it from scratch"](https://prettier.io/docs/)). With PhpStorm's Default ("Do not wrap"), `max_line_length = 80` changed 1 of 22 PHP files. The same width in mago and prettier changed 9–10 other files. Fixers (php-cs-fixer, phpcbf, ESLint + @stylistic) and the TypeScript formatter keep the layout and come closest. But they have no wrapping or alignment engine, and one fixer rule usually controls several Options.
- **Speed and installation are not the problem.** Native command-line tools take 3–36 ms per call (mago 3, dprint 7, clang-format 22, biome 36). Node tools take about 1–13 ms in a running process, but 90–430 ms with a cold start. PHP tools take 165–180 ms. A live Preview could use any of them (through a long-running process for the Node tools). Fidelity is what rules them out.
- **For #8 (engine):** do not build the engine on external formatters. The one exception is Shell Script: the Research Corpus shows that PhpStorm adds `shfmt` flags (`-i`, `-bn`, `-ci`, `-sr`, `-kp`, `-mn`) for its Shell Script Options, so a Language Plugin that runs `shfmt` gets the same behaviour. The good fixers are still useful as design references, because they keep the layout and are organised into one rule per construct. Examples are php-cs-fixer's rules, ESLint + @stylistic's rules, the TypeScript `FormatCodeSettings`, and dprint's per-node options.

## 1. Scope and method

### 1.1 Tools and versions (all run locally)

| Language | Tool | Version | Kind |
|---|---|---|---|
| PHP | php-cs-fixer | 3.95.27 (PHP 8.4.14 static binary) | fixer: token rules, keeps the layout |
| PHP | PHP_CodeSniffer `phpcbf` | 4.0.4 | fixer: sniffs with properties |
| PHP | mago `fmt` | 1.59.0 | printer (reprints from the syntax tree) |
| PHP | prettier + @prettier/plugin-php | 3.9.10 + 0.26.0 | printer |
| JS/TS | dprint + dprint-plugin-typescript | 0.64.3 + 0.96.1 | printer with many "maintain" options |
| JS/TS | ESLint + @stylistic/eslint-plugin (+ typescript-eslint parser) | 10.13.0 + 5.10.0 (+ 8.72.1) | fixer: lint rules with auto-fix |
| JS/TS | TypeScript language service formatter (`FormatCodeSettings`) | typescript 6.0.3 | whitespace formatter, keeps the layout |
| JS/TS | prettier | 3.9.10 | printer |
| JS/TS | biome | 2.6.4 | printer |
| JS/TS | clang-format (`Language: JavaScript`) | 23.1.3 | printer |

### 1.2 Inputs from the Research Corpus

- **Options:** `data/behavior/index.json`. The coverage counts use only the Options with status `verified-effect`, because only these have output that a formatter must reproduce: PHP 230, JavaScript 152, TypeScript 159. The other statuses (`no-visible-effect`, `untestable-via-cli`) are not formatter behaviour.
- **Behaviour Records:** `data/behavior/<language>/<key>.json`. Each record has the `inputs`, the Default output (`base_outputs.Default`), and the changed output for each value (`results[].changed_files`). A PhpStorm "expected output" for a value is the changed output, or the Default output if the file did not change.
- **Corpus of unique inputs:** every input file of all records of a language, with its Default output: PHP 146 files, JavaScript 68, TypeScript 97. 104, 44 and 68 of them are changed by PhpStorm's Default scheme. The rest are already in the Default format.

### 1.3 Three measurements

1. **Option mapping (desk study).** For each `verified-effect` Option, I looked up the best setting in each tool's own option reference (sources at the end). Grades:
   - **E (exact candidate):** a setting for the same construct that can represent every value of the Option.
   - **P (partial):** a setting exists, but it covers a wider or narrower construct (one setting for several Options), supports only some values, or uses a different algorithm (for example "fits or breaks at the print width" instead of a Wrap mode).
   - **N (none).**

   "E" does not mean that the output matches. Measurements 2 and 3 test that.
2. **Default fidelity.** Each tool, with the configuration closest to PhpStorm's Default scheme (4 spaces, width 120, no trailing commas, quotes and blank lines kept where possible), formats (a) the corpus inputs and (b) PhpStorm's Default outputs. I count the files whose result is byte-identical to PhpStorm's Default output. Test (b) is a necessary condition: a tool that changes PhpStorm's own Default output cannot match any record.
3. **Option effect fidelity.** For 32 PHP and 26 JS/TS Option values (132 tool runs), I gave the tool the mapped setting. I then ran it on that Option's record inputs twice: with the tool's Default-like configuration and with the mapped setting. Then I compared the tool's edit (the lines that the setting changed) with PhpStorm's edit (Default output to value output). Results per run:
   - "PhpStorm changed": the number of files that PhpStorm's edit changes.
   - "Same edit": the number of those files where the tool changed exactly the same lines in the same way.
   - "Tool-only edits": the number of files that the tool changed but PhpStorm did not.
   - "Output identical": the number of files whose output is byte-identical to PhpStorm's.

   The method gives a tool every advantage: it isolates the Option's effect from the differences in the Default output.

The configurations and scripts were scratch files (in `/tmp/opencode/fmt`), not part of the repo. The essential settings are listed in §7.

## 2. Why the engine model decides the result

| Model | Tools | What it does to layout | Consequence for the Behaviour Records |
|---|---|---|---|
| IntelliJ formatting model | PhpStorm | Builds a block tree and computes "the sequence of whitespace characters (spaces, tabs, and/or line breaks)" between blocks ([IntelliJ SDK: Code Formatter](https://plugins.jetbrains.com/docs/intellij/code-formatting.html)). It keeps line breaks (`keep_line_breaks = true`), wraps only where a Wrap Option is not "Do not wrap", and aligns only where an Align Option is on. | This is the reference. |
| Printer (Wadler style) | prettier, plugin-php, biome, dprint, mago, clang-format | "removes all original styling … reprints it from scratch by taking the line length into account" ([Prettier docs](https://prettier.io/docs/)). The layout comes from the print width, and the input decides it only through a few "preserve" or "maintain" switches. | It wraps lines that PhpStorm keeps. It joins lines that PhpStorm keeps. It adds or removes parentheses (`(a && b) \|\| c`), changes quotes, and collapses `{}`. The Default output differs on most files (§3.2, §4.2). |
| Fixer (rule list) | php-cs-fixer, phpcbf, ESLint + @stylistic | Applies separate token-level rules and keeps everything else. | The Default output can be close (php-cs-fixer 77% fixed point). But there is no wrap engine, and the rules have their own scope (for example "align `=`" in php-cs-fixer uses different run boundaries than PhpStorm's "Align consecutive assignments"). |
| Whitespace formatter | TypeScript language service | Rule-based spacing and indentation on the syntax tree. Keeps line breaks. | Closest Default output for JS/TS (76% / 69% fixed point). But it has only 20 settings, and several of them cover all parentheses, brackets or braces at once. |

An example of a printer on PhpStorm's own Default output (`wrapping_and_braces/binary.js`; prettier with `printWidth 120`, `tabWidth 4`):

```diff
-    const logic = conditionNumberOne && conditionNumberTwo || conditionNumberThree && conditionNumberFour || conditionFive || six;
+    const logic =
+        (conditionNumberOne && conditionNumberTwo) ||
+        (conditionNumberThree && conditionNumberFour) ||
+        conditionFive ||
+        six;
-    const multi = first +
-        second;
+    const multi = first + second;
```

An example of a fixer whose mapped setting has different semantics. PhpStorm's `align_assignments = true` compared with php-cs-fixer's `binary_operator_spaces` set to `=` → `align_single_space_minimal` (`r3_align_assignments_compound.php`). PhpStorm aligns compound operators and ends a run at a multi-line statement. php-cs-fixer, configured for `=` only, does neither, and it aligns across a destructuring assignment:

```diff
--- phpstorm
+++ php-cs-fixer
-$a    .= 1;
+$a .= 1;
 $bbbb .= 2;
 ...
 [$x, $y] = $p;
-$long = 1;
+$long    = 1;
```

## 3. PHP

### 3.1 Option coverage (230 `verified-effect` Options)

| Tool | E | P | N | Notes |
|---|---:|---:|---:|---|
| php-cs-fixer | 19 | 146 | 65 | Best PHP coverage. Many Options map to one rule (`binary_operator_spaces`, `braces_position`, `spaces_inside_parentheses`, `class_attributes_separation`, `phpdoc_align`). Blank-line rules support only 0 or 1. It has no wrap engine; the only wrap rule is `method_argument_space.on_multiline`. The 28 PHPDoc tag weights map to one ordered list (`phpdoc_order.order`). |
| PHP_CodeSniffer `phpcbf` | 13 | 66 | 151 | Its sniff properties (for example `Squiz.WhiteSpace.FunctionSpacing.spacing`, `MemberVarSpacing.spacing`) are the only way that any tool supports N blank lines. Most sniffs enforce one fixed style. `Generic.Files.LineLength` only reports. |
| mago `fmt` | 10 | 61 | 159 | About 95 settings, mostly switches for PER-CS variants. One setting, `align-assignment-like`, covers assignments, properties, constants, `=>` and enum cases. "Blank line after X" settings are true or false. It wraps at `print-width`. |
| prettier + plugin-php | 2 | 10 | 218 | 4 PHP settings (`phpVersion`, `trailingCommaPHP`, `braceStyle`, `singleQuote`) plus the core `printWidth`, `tabWidth` and `useTabs`. |
| **Best of all four** | **26** | **157** | **47** | |

Best-of-all coverage per Tab:

| Tab | E | P | N |
|---|---:|---:|---:|
| Tabs and Indents | 2 | 2 | 2 |
| Spaces | 13 | 51 | 9 |
| Wrapping and Braces | 2 | 44 | 32 |
| Blank Lines | 3 | 16 | 1 |
| PHPDoc | 1 | 35 | 1 |
| Code Conversion | 5 | 9 | 1 |
| Code Generation (reformat-time only) | 0 | 0 | 1 |

The mapping for each Option is in Appendix A.1.

### 3.2 Default fidelity (146 inputs; 104 of them are changed by PhpStorm)

| Tool and configuration | Inputs → identical to PhpStorm Default | Of the 104 changed | PhpStorm Default output left unchanged (fixed point) | Lines matching |
|---|---:|---:|---:|---:|
| no formatting (input as is) | 42 (29%) | 0 | – | 80% |
| php-cs-fixer, rules chosen to match the Default scheme | 54 (37%) | 16 | **113 (77%)** | 92% / 98% |
| php-cs-fixer `@PSR12` | 21 (14%) | 15 | 42 (29%) | 89% / 94% |
| php-cs-fixer `@PER-CS` | 9 (6%) | 4 | – | 79% |
| phpcbf `--standard=PSR12` | 24 (16%) | 16 | 49 (34%) | 89% / 93% |
| mago (settings closest to Default) | 25 (17%) | 12 | 43 (29%) | 82% / 86% |
| prettier + plugin-php | 13 (9%) | 5 | 22 (15%) | 68% / 71% |

"Lines matching": the share of PhpStorm's output lines that appear in the tool output in the same order, for the input run / the fixed-point run.

Even the best fixer configuration formats only 16 of the 104 changed inputs exactly as PhpStorm does. The fixer configuration keeps 77% of PhpStorm's output unchanged because it does almost nothing that PhpStorm would not do. It does not do most of what PhpStorm does: for example the continuation indent, the alignment of multiline parameters (`align_multiline_parameters = true` by default), and blank-line normalisation with up to 2 kept lines.

### 3.3 Option effect fidelity (58 PHP runs)

Over all PHP runs, PhpStorm changed 404 input files. The tool made the same edit on 206 of them (51%) and produced byte-identical output on 50 of 485 files run. The full edit matched on all inputs in 12 runs. These are spacing and brace Options:

- php-cs-fixer: `class_brace_style`, `concat_spaces`, `space_before_short_closure_left_parenthesis`, `space_after_unary_not`, `spaces_around_assignment_in_declare`, `multiline_chained_calls_semicolon_on_new_line`, `new_line_after_php_opening_tag`.
- mago: `concat_spaces`, `space_before_short_closure_left_parenthesis`, `spaces_around_assignment_in_declare`, `blank_lines_before_return_statement = 1`, `new_line_after_php_opening_tag`.

The runs failed on:

- Alignment (`align_assignments`, `align_key_value_pairs`, `align_class_constants`): 0–3 of 11 files.
- Wrap modes (`method_parameters_wrap = split_into_lines`): 0 of 8 for php-cs-fixer and mago.
- Blank lines for N > 1, and blank lines in general (`blank_lines_around_method = 0`: php-cs-fixer 0 of 10, plus 6 tool-only edits).
- `keep_blank_lines_in_code = 1` (0 of 12).
- Trailing commas (`comma_after_last_parameter`: 0 of 3).
- The keyword-case and constant-case conversions (0–1 of 4).
- `max_line_length` (PhpStorm changed 1 file; mago and prettier changed 9–10 other files).

All runs are listed in Appendix B.1.

### 3.4 Tool notes (PHP)

- **php-cs-fixer** ([rules index](https://cs.symfony.com/doc/rules/index.html)): 300 rules in 3.95 (`list-rules`). It is the best PHP option source, but:
  - many rules are "true only" (for example `no_spaces_after_function_name`, `object_operator_without_whitespace`, `trim_array_spaces`), so the opposite value of the Option is not possible;
  - `binary_operator_spaces` controls all operator spacing and alignment;
  - `control_structure_continuation_position` moves `else`, `catch`, `finally` and `while` together, while PhpStorm has 4 Options;
  - with `-` it reads stdin, but it prints only a report (or a diff with `--diff`), not the fixed code, so an editor must use a temp file;
  - a parse error stops it on the whole file: 2 of 146 corpus files were skipped ("not fixed due to errors reported during linting").
- **phpcbf** ([customisable sniff properties](https://github.com/PHPCSStandards/PHP_CodeSniffer/wiki/Customisable-Sniff-Properties)): 338 sniffs in Generic, Squiz, PSR1, PSR2, PSR12, PEAR and Zend. It reads stdin (`-`) and writes the result to stdout. The sniffs are designed to enforce one standard, so few of them have a property for the opposite value.
- **mago** (option schema from `mago config --show formatter --schema`): 95 formatter settings, with `--stdin-input` and `--stdin-filepath`. It is the fastest tool (3 ms). It always wraps at `print-width` and normalises quotes (`single-quote` true or false, never "keep"), so the Default output differs.
- **prettier + plugin-php** ([options.mjs](https://github.com/prettier/plugin-php/blob/main/src/options.mjs)): it has almost no options, so it is not a candidate.

## 4. JavaScript and TypeScript

### 4.1 Option coverage

JavaScript has 152 `verified-effect` Options and TypeScript 159. TypeScript adds `blank_lines_around_*_in_interface`, `enum_constants_wrap` and the TS-only tests. The tools map the same way for both languages.

| Tool | JS E / P / N | TS E / P / N | Notes |
|---|---|---|---|
| ESLint + @stylistic | 34 / 75 / 43 | 34 / 75 / 50 | 97 rules ([eslint.style](https://eslint.style/rules)). Exact for many spacing Options (`keyword-spacing.overrides`, `key-spacing`, `comma-spacing`, `semi-spacing`, `generator-star-spacing`, `template-curly-spacing`, `comma-dangle`, `quotes`, `semi`, `dot-location`, `no-multiple-empty-lines.max`). `space-in-parens` and `object-curly-spacing` each cover many Options. There is no wrap engine. |
| dprint-plugin-typescript | 25 / 34 / 93 | 25 / 37 / 97 | 185 settings ([schema](https://plugins.dprint.dev/dprint/dprint-plugin-typescript/0.96.1/schema.json)). It has spacing settings per node (`ifStatement.spaceAround`, `parameters.spaceAround`, `typeAnnotation.spaceBeforeColon`…) and brace and "next control flow" positions per node, with a `maintain` value. It still reprints at `lineWidth`. |
| TypeScript LS formatter | 10 / 33 / 109 | 10 / 33 / 116 | 20 `FormatCodeSettings` plus `indentSize`/`tabSize`/`convertTabsToSpaces` ([types.ts](https://github.com/microsoft/TypeScript/blob/main/src/services/types.ts)). One setting for all non-empty parentheses, one for all brackets, one for all braces. |
| clang-format (`Language: JavaScript`) | 8 / 29 / 115 | 8 / 29 / 122 | It has C++-oriented style options ([reference](https://clang.llvm.org/docs/ClangFormatStyleOptions.html)). `JavaScriptQuotes` and `MaxEmptyLinesToKeep` are exact. |
| prettier | 3 / 18 / 131 | 3 / 18 / 138 | 27 documented options in total, including parser, pragma and range options. Few options by design ([option philosophy](https://prettier.io/docs/option-philosophy)). |
| biome | 3 / 20 / 129 | 3 / 20 / 136 | 18 JavaScript formatter settings (`configuration_schema.json`). |
| **Best of all** | **55 / 68 / 29** | **55 / 71 / 33** | |

Best-of-all coverage per Tab (JavaScript; TypeScript is the same within ±2):

| Tab | E | P | N |
|---|---:|---:|---:|
| Tabs and Indents | 4 | 2 | 2 |
| Spaces | 38 | 21 | 6 |
| Wrapping and Braces | 6 | 40 | 18 |
| Blank Lines | 1 | 5 | 0 |
| Punctuation | 6 | 0 | 0 |
| Code Generation (reformat-time only) | 0 | 0 | 3 |

The E counts look higher than for PHP because JavaScript has a dense spacing Tab and ESLint + @stylistic has one rule per construct. A combination would need ESLint + @stylistic for spacing, dprint for braces, and still nothing for Wrap and Align. No combination can produce one coherent Default output.

### 4.2 Default fidelity

| Tool | JS: identical from input (of 44 changed) | JS: fixed point (of 68) | TS: identical from input (of 68 changed) | TS: fixed point (of 97) | PhpStorm outputs the tool refused (JS / TS) |
|---|---:|---:|---:|---:|---:|
| no formatting | 0 | – | 0 | – | – |
| TypeScript LS formatter | 2 | **52 (76%)** | 2 | **67 (69%)** | 0 / 0 |
| ESLint + @stylistic | 2 | 44 (65%) | 2 | 70 (72%) | 16 / 3 |
| dprint | 0 | 7 (10%) | 1 | 10 (10%) | 4 / 1 |
| prettier | 1 | 5 (7%) | 1 | 6 (6%) | 8 / 3 |
| biome | 1 | 5 (7%) | 1 | 6 (6%) | 17 / 13 |
| clang-format | 0 | 4 (6%) | 0 | 5 (5%) | 0 / 0 |

- No tool formats more than 2 of the inputs that PhpStorm changes exactly as PhpStorm does.
- The printers leave 5–10% of PhpStorm's own Default output unchanged.
- "Refused" means that the tool rejected the file. The corpus has intentionally odd inputs: Flow annotations, JSX in `.js`, duplicate `export default`, `-x ** 2`. PhpStorm formats all of them. biome rejects semantic errors as well as syntax errors (for example "Illegal duplicate default export declarations"). For a real buffer in the middle of an edit, this means that the printers refuse more often than PhpStorm.

### 4.3 Option effect fidelity (74 JS/TS runs + 5 clang-format reruns)

PhpStorm changed 505 files. The tool made the same edit on 158 (31%) and produced byte-identical output on 59 of 569 files run. The full edit matched on all inputs in 7 runs:

- TS LS: `space_before_function_left_parenth = false`.
- ESLint: `space_before_method_parentheses = true`, `space_before_function_left_parenth = false`, `spaces_around_arrow_function_operator = false`, `space_after_unary_not = true`, `spaces_within_brackets = true`, `keep_blank_lines_in_code = 1`.

These ESLint runs covered only the inputs that its parser accepted. The printers (prettier, biome, dprint) matched 0 edits even for pure spacing Options such as `spaces_within_object_literal_braces = true`. Their line layout differs from PhpStorm's on the affected lines, so the changed lines are never the same text. `max_line_length = 80` again caused tool-only edits in 11–19 files, while PhpStorm changed 5–6. All runs are listed in Appendix B.2.

### 4.4 Tool notes (JS/TS)

- **TypeScript LS formatter**: the closest model to PhpStorm (keeps line breaks; `getFormattingEditsForRange` gives range formatting). But it has 20 settings, and several of them cover groups of Options. A Neovim plugin can reach it only through a TS server (for example `ts_ls` or `vtsls` with LSP `textDocument/formatting`).
- **ESLint + @stylistic**: the finest option grain for Spaces and Punctuation. A cold start takes 430 ms; a running process takes 13 ms per file. It fixes in several passes (`verifyAndFix` runs until stable). It cannot format a file that does not parse.
- **dprint**: the richest printer (185 settings, `maintain` values, `--stdin`, `--lines` for ranges, 7 ms per call). It is still a printer: 10% fixed point.
- **prettier / biome**: too few options, and no "keep" for quotes, semicolons or trailing commas.
- **clang-format**: `--lines` and `--offset` for ranges and 22 ms per call, but it is C++-oriented and has 6% fixed point.

## 5. Live Preview: stdin, range, speed, install cost

Measured on PhpStorm's own Wrapping and Braces preview sample (`data/code-samples/{PHP,TypeScript,JavaScript}/WRAPPING_AND_BRACES_SETTINGS.txt`, 106–138 lines). The time is the median of 6 runs of the whole command on this Linux machine.

| Tool | Buffer from stdin | Range formatting | Time per call | Install cost (measured on disk) |
|---|---|---|---:|---|
| mago | yes (`--stdin-input`, `--stdin-filepath`) | no (not in `mago fmt --help`) | 3 ms | one static binary, 25 MB |
| dprint + TS plugin | yes (`--stdin <ext>`) | yes (`--lines`) | 7 ms | 27 MB binary + 21 MB plugin cache (WASM, downloaded at first run) |
| clang-format | yes | yes (`--lines`, `--offset`/`--length`) | 22 ms | distro package (LLVM) |
| biome | yes (`--stdin-file-path`) | not in the CLI (`biome format --help`) | 36 ms | 85 MB native binary (npm or standalone) |
| prettier (+ plugin-php) | yes (`--stdin-filepath`) | yes (`--range-start`/`--range-end`, widened to whole statements) | 88–92 ms cold; 1–3 ms in a running process | Node.js + 9.7 MB (+0.4 MB plugin) |
| ESLint + @stylistic | yes (`--stdin`, with `--fix-dry-run`) | no (whole file) | about 430 ms cold; 13 ms in a running process | Node.js + about 12 MB (eslint, @stylistic, typescript-eslint) + a config file |
| TypeScript LS formatter | through the language service / LSP | yes (`getFormattingEditsForRange`) | 1–4 ms in a running process | Node.js + 24 MB (`typescript`) + an LSP server |
| phpcbf | yes (`-`) | no | 165 ms | PHP runtime (a static binary is 9.8 MB) + 1.4 MB phar |
| php-cs-fixer | stdin gives only a report or diff; needs a temp file | no | 179 ms | PHP runtime + 3.6 MB phar |

Every tool is fast enough for a debounced Preview. A 30–50 ms budget excludes only cold Node and PHP processes. Those need a daemon (prettierd or eslint_d style) or a long-running process. The cost to the user is one more runtime per language (Node.js or PHP) and the tool installation. This is the kind of external dependency that conform.nvim users already manage.

## 6. The other Research Corpus languages (short)

Counts are the `verified-effect` Options from the Research Corpus README. "Fixed point" is the share of PhpStorm's Default outputs that the tool leaves unchanged (measured only for CSS, SCSS and Less).

| Language (verified-effect Options) | Best candidate(s) | Fit |
|---|---|---|
| Shell Script (0 via the CLI; 7 verified in the IDE) | `shfmt` | **Exact by construction.** PhpStorm has no own Shell formatter. It runs `shfmt` and maps its Options to the flags `-i`, `-bn`, `-ci`, `-sr`, `-kp`, `-mn` (Research Corpus `docs/languages/shell-script.md`; [shfmt(1)](https://github.com/mvdan/sh/blob/master/cmd/shfmt/shfmt.1.scd)). The PhpStorm 2026.2 IDE check used shfmt 3.14.1. |
| CSS 21, SCSS 22, Less 22, Sass 17 | malva (dprint plugin; 39 settings incl. `hex_case`, `hex_color_length`, `quotes`, `declaration_order`, [config.rs](https://github.com/g-plane/malva/blob/main/malva/src/config.rs)); prettier; biome (CSS only); stylelint + @stylistic/stylelint-plugin | Partial. All are printers. Fixed point of PhpStorm's Default output: CSS: prettier 2/23, malva 3/23, biome 2/23. SCSS: prettier 4/31, malva 6/31. Less: prettier 4/31, malva 5/31. prettier does not support indented Sass; malva does ([README](https://github.com/g-plane/malva)). |
| HTML 30, Vue 8, Angular, Twig 32, Blade 33 | markup_fmt (47 settings; HTML, Vue, Angular, Jinja, Twig, XML…, [config.rs](https://github.com/g-plane/markup_fmt/blob/main/markup_fmt/src/config.rs)); prettier (`htmlWhitespaceSensitivity`, `singleAttributePerLine`, `vueIndentScriptAndStyle`, `bracketSameLine`) | Printers. They have none of PhpStorm's tag lists (keep whitespace inside, do not indent children of, inline elements…). Not measured. |
| XML 17 | @prettier/plugin-xml (4 settings: `xmlQuoteAttributes`, `xmlSelfClosingSpace`, `xmlSortAttributesByKey`, `xmlWhitespaceSensitivity`, [README](https://github.com/prettier/plugin-xml)); markup_fmt | Low. |
| JSON 18 | dprint-plugin-json, prettier, biome | Low to partial. Few options (indent, line width, trailing commas). |
| YAML 11 | yamlfmt basic formatter (about 20 settings incl. `indent`, `retain_line_breaks`, `indentless_arrays`, `pad_line_comments`, [config docs](https://github.com/google/yamlfmt/blob/main/docs/config-file.md)); prettier | Partial. Not measured. |
| Markdown 21 | prettier (`proseWrap`), dprint-plugin-markdown | Low. |
| SQL 203 (210 fields, 11 dialects) | sql-formatter (14 settings: `keywordCase`, `dataTypeCase`, `functionCase`, `identifierCase`, `logicalOperatorNewline`, `expressionWidth`, `linesBetweenQueries`, `denseOperators`, `newlineBeforeSemicolon`…, [README](https://github.com/sql-formatter-org/sql-formatter)); SQLFluff (rule-based linter and fixer, [rules](https://docs.sqlfluff.com/en/stable/reference/rules.html)) | Very low compared with 210 fields. |
| HTTP Request 7 | kulala-fmt ("an opinionated .http and .rest files linter and formatter", [README](https://github.com/mistweaverco/kulala-fmt)) | Opinionated: almost no options. |
| Mermaid 36, Gherkin 4, EditorConfig 6, General 10 | None found that has a comparable option set. | – |

## 7. Implications for codestyle.nvim

- **#8 (engine runtime):** external formatters cannot meet the fidelity rule. The engine has to be our own: a whitespace-adjusting formatter that follows the IntelliJ model (blocks, spacing, wrap, alignment, keep line breaks). Whether it is pure Lua with Tree-sitter or a compiled helper stays open for #8. The one exception is a Shell Script Language Plugin that runs `shfmt`, as PhpStorm does.
- **Flagging, not approximating:** an Option that an external tool covers only "partially" cannot be offered as supported. Under the standing decision, an external backend would therefore support almost none of the Options.
- **Useful material:** the rule lists of php-cs-fixer and ESLint + @stylistic, the TypeScript `FormatCodeSettings`, and dprint's per-node options. They show how other tools split spacing and brace rules into one rule per construct. The test harness of this research is a cheap model for golden tests: run the formatter on the record inputs, then compare the result with the Default output and with the value output.

Essential tool configurations used for "closest to Default":

- **mago:** `print-width 120`, `tab-width 4`, `single-quote true`, `trailing-comma false`, `remove-trailing-close-tag false`, `classlike/function/method-brace-style next_line`, `control/closure-brace-style same_line`, every `inline-empty-*-braces false`, every `preserve-breaking-* true`, `sort-uses none`, `expand-use-groups false`, `space-after-cast-unary-prefix-operators false`, every `empty-line-after-* false`, `separate-class-like-members false`.
- **php-cs-fixer:** a curated list of 36 rules. The main ones: `braces_position` (classes and functions on the next line unless the signature ends with a newline; control structures and anonymous functions and classes on the same line), `binary_operator_spaces` single_space, `concat_space` one, `cast_spaces` none, `function_declaration` (closure one, fn none), `method_argument_space` ignore, `no_extra_blank_lines` with no tokens, `control_structure_braces` off.
- **prettier JS/TS:** `printWidth 120`, `tabWidth 4`, `trailingComma none`, `bracketSpacing false`, `arrowParens always`, `quoteProps preserve`. prettier PHP: `braceStyle per-cs`, `trailingCommaPHP false`, `singleQuote true`. biome: the same values.
- **dprint TS:** `lineWidth 120`, `indentWidth 4`, `quoteStyle preferDouble`, `trailingCommas never`, and `maintain` for `operatorPosition`, `bracePosition`, `singleBodyPosition`, `nextControlFlowPosition`, `arrowFunction.useParentheses` and sorting. `spaceSurroundingProperties false` for objects, imports and exports.
- **TS LS:** `indentSize 4`, `insertSpaceAfterFunctionKeywordForAnonymousFunctions true`, non-empty braces without spaces, `semicolons ignore`.
- **ESLint + @stylistic:** 29 rules, among them `indent 4` with `SwitchCase 1`, `space-before-function-paren` (anonymous always, named never), `object-curly-spacing never`, `brace-style 1tbs`, `no-multiple-empty-lines max 2`.
- **clang-format:** `BasedOnStyle LLVM`, `ColumnLimit 120`, `IndentWidth 4`, `JavaScriptQuotes Leave`, every `AllowShort*` off, `MaxEmptyLinesToKeep 2`.

### Limits of this research

- The mapping grades are my reading of each tool's option reference. "E" was tested for a sample only (§3.3, §4.3).
- The tool configurations are my best effort at "closest to Default". A better configuration could add a few fixed-point files, but it cannot change the printer model or add missing settings.
- The other languages (§6) are a desk study, except for the CSS/SCSS/Less fixed-point run.
- Arrangement, Presets and the reformat-time Options (`untestable-via-cli`) are out of scope.

## Appendix A: Option mapping

A grade marks the best setting of each tool for that Option: **E** = the same construct and every value can be expressed; **P** = partial (the scope or the value set differs, or the algorithm differs); **–** = none. "Best" is the best grade over the tools in the row. The Options are the `verified-effect` Options of `data/behavior/index.json`.

### A.1 PHP (230 Options)

<details><summary>Show the PHP table</summary>

| Option (`ij_php_` omitted) | Tab | Best | php-cs-fixer | mago | prettier + plugin-php | phpcbf |
|---|---|---|---|---|---|---|
| `blank_lines_after_class_header` | Blank Lines | P | **P** no_blank_lines_after_class_opening (0 only) | **P** empty-line-after-class-like-open (0/1) | – | **P** Squiz.WhiteSpace.MemberVarSpacing.spacingBeforeFirst / PSR12.Classes.OpeningBraceSpace |
| `blank_lines_after_function` | Blank Lines | P | – | **P** empty-line-after-symbols (0/1) | – | – |
| `blank_lines_after_imports` | Blank Lines | P | **P** single_line_after_imports (1 only) | **P** empty-line-after-use (0/1) | – | **P** PSR2.Namespaces.UseDeclaration (1 only) |
| `blank_lines_after_opening_tag` | Blank Lines | P | **P** blank_line_after_opening_tag (1 only) | **P** empty-line-after-opening-tag (0/1) | – | – |
| `blank_lines_after_package` | Blank Lines | P | **P** blank_line_after_namespace (1 only) | **P** empty-line-after-namespace (0/1) | – | **P** PSR2.Namespaces.NamespaceDeclaration (1 only) |
| `blank_lines_around_class` | Blank Lines | P | **P** class_attributes_separation? no; no_extra_blank_lines | **P** empty-line-after-symbols (0/1) | – | – |
| `blank_lines_around_constants` | Blank Lines | P | **P** class_attributes_separation.elements.const (none\|one) | **P** empty-line-after-class-like-constant (0/1) | – | – |
| `blank_lines_around_enum_cases` | Blank Lines | P | **P** class_attributes_separation.elements.case (none\|one) | **P** empty-line-after-enum-case (0/1) | – | – |
| `blank_lines_around_field` | Blank Lines | E | **P** class_attributes_separation.elements.property (none\|one) | **P** empty-line-after-property (0/1) | – | **E** Squiz.WhiteSpace.MemberVarSpacing.spacing |
| `blank_lines_around_method` | Blank Lines | E | **P** class_attributes_separation.elements.method (none\|one) | **P** empty-line-after-method (0/1) | – | **E** Squiz.WhiteSpace.FunctionSpacing.spacing |
| `blank_lines_before_class_end` | Blank Lines | P | – | **P** empty-line-before-class-like-close (0/1) | – | – |
| `blank_lines_before_imports` | Blank Lines | P | – | **P** empty-line-after-namespace (0/1) | – | – |
| `blank_lines_before_method_body` | Blank Lines | N | – | – | – | – |
| `blank_lines_before_package` | Blank Lines | E | **E** blank_lines_before_namespace.min_line_breaks/max_line_breaks | – | – | **P** PSR2.Namespaces.NamespaceDeclaration |
| `blank_lines_before_return_statement` | Blank Lines | P | **P** blank_line_before_statement[return] (1 only) | **P** empty-line-before-return (0/1) | – | – |
| `blank_lines_between_imports` | Blank Lines | P | **P** blank_line_between_import_groups (0/1) | **P** separate-use-types (0/1) | – | – |
| `keep_blank_lines_after_lbrace` | Blank Lines | P | **P** no_blank_lines_after_class_opening / no_extra_blank_lines[curly_brace_block] (0 only) | **P** fixed | – | – |
| `keep_blank_lines_before_right_brace` | Blank Lines | P | **P** no_extra_blank_lines[curly_brace_block] (0 only) | – | – | **P** Squiz.WhiteSpace.FunctionClosingBraceSpace (0 only) |
| `keep_blank_lines_in_code` | Blank Lines | P | **P** no_extra_blank_lines (max 1 only) | **P** fixed: keeps at most 1 | **P** fixed: keeps at most 1 | **P** Squiz.WhiteSpace.SuperfluousWhitespace (max 1) |
| `keep_blank_lines_in_declarations` | Blank Lines | P | **P** no_extra_blank_lines (max 1 only) | **P** fixed 1 | **P** fixed 1 | – |
| `comma_after_last_argument` | Code Conversion | E | **E** trailing_comma_in_multiline.elements[arguments] | **P** trailing-comma | **P** trailingCommaPHP | – |
| `comma_after_last_argument_style` | Code Conversion | P | **P** trailing_comma_in_multiline (multiline only) + no_trailing_comma_in_singleline | – | – | – |
| `comma_after_last_array_element` | Code Conversion | E | **E** trailing_comma_in_multiline.elements[arrays] | **P** trailing-comma (all lists at once) | **P** trailingCommaPHP (all lists) | **P** Squiz.Arrays.ArrayDeclaration |
| `comma_after_last_closure_use_var` | Code Conversion | P | **P** trailing_comma_in_multiline (no closure-use element) | **P** trailing-comma | – | – |
| `comma_after_last_closure_use_var_style` | Code Conversion | N | – | – | – | – |
| `comma_after_last_match_arm` | Code Conversion | E | **E** trailing_comma_in_multiline.elements[match] | **P** trailing-comma | – | – |
| `comma_after_last_parameter` | Code Conversion | E | **E** trailing_comma_in_multiline.elements[parameters] | **P** trailing-comma | **P** trailingCommaPHP | – |
| `comma_after_last_parameter_style` | Code Conversion | P | **P** trailing_comma_in_multiline (multiline only) | – | – | – |
| `else_if_style` | Code Conversion | P | **P** elseif (combine only) | – | – | **P** PSR2.ControlStructures.ElseIfDeclaration (combine only) |
| `force_short_declaration_array_style` | Code Conversion | E | **E** array_syntax.syntax + list_syntax | – | – | **E** Generic.Arrays.DisallowLongArraySyntax |
| `lower_case_boolean_const` | Code Conversion | P | **P** constant_case (true, false, null together) | **P** uppercase-literal-keyword (always rewrites) | – | **P** Generic.PHP.LowerCaseConstant |
| `lower_case_keywords` | Code Conversion | P | **P** lowercase_keywords (true only) | – | – | **P** Generic.PHP.LowerCaseKeyword (true only) |
| `lower_case_null_const` | Code Conversion | P | **P** constant_case (shared) | **P** uppercase-literal-keyword | – | **P** Generic.PHP.LowerCaseConstant |
| `upper_case_boolean_const` | Code Conversion | P | **P** constant_case (shared) | **P** uppercase-literal-keyword | – | **P** Generic.PHP.UpperCaseConstant |
| `upper_case_null_const` | Code Conversion | P | **P** constant_case (shared) | **P** uppercase-literal-keyword | – | **P** Generic.PHP.UpperCaseConstant |
| `line_comment_add_space_on_reformat` | Code Generation | N | – | – | – | – |
| `align_phpdoc_comments` | PHPDoc | P | **P** phpdoc_align.align=vertical (shared) | – | – | – |
| `align_phpdoc_param_names` | PHPDoc | P | **P** phpdoc_align.align=vertical (aligns type, name and description together) | – | – | – |
| `api_weight` | PHPDoc | P | **P** phpdoc_order.order (tag list order) | – | – | – |
| `author_weight` | PHPDoc | P | **P** phpdoc_order.order (tag list order) | – | – | – |
| `category_weight` | PHPDoc | P | **P** phpdoc_order.order (tag list order) | – | – | – |
| `copyright_weight` | PHPDoc | P | **P** phpdoc_order.order (tag list order) | – | – | – |
| `deprecated_weight` | PHPDoc | P | **P** phpdoc_order.order (tag list order) | – | – | – |
| `example_weight` | PHPDoc | P | **P** phpdoc_order.order (tag list order) | – | – | – |
| `filesource_weight` | PHPDoc | P | **P** phpdoc_order.order (tag list order) | – | – | – |
| `global_weight` | PHPDoc | P | **P** phpdoc_order.order (tag list order) | – | – | – |
| `ignore_weight` | PHPDoc | P | **P** phpdoc_order.order (tag list order) | – | – | – |
| `internal_weight` | PHPDoc | P | **P** phpdoc_order.order (tag list order) | – | – | – |
| `license_weight` | PHPDoc | P | **P** phpdoc_order.order (tag list order) | – | – | – |
| `link_weight` | PHPDoc | P | **P** phpdoc_order.order (tag list order) | – | – | – |
| `package_weight` | PHPDoc | P | **P** phpdoc_order.order (tag list order) | – | – | – |
| `param_weight` | PHPDoc | P | **P** phpdoc_order.order (tag list order) | – | – | – |
| `phpdoc_blank_line_before_tags` | PHPDoc | P | **P** phpdoc_separation / phpdoc_summary | – | – | – |
| `phpdoc_blank_lines_around_parameters` | PHPDoc | P | **P** phpdoc_separation.groups | – | – | – |
| `phpdoc_keep_blank_lines` | PHPDoc | P | **P** phpdoc_trim_consecutive_blank_line_separation (false only) | – | – | – |
| `phpdoc_param_spaces_between_name_and_description` | PHPDoc | P | **P** phpdoc_align.spacing | – | – | – |
| `phpdoc_param_spaces_between_tag_and_type` | PHPDoc | P | **P** phpdoc_align.spacing (single or per-tag; 1 for left alignment) | – | – | – |
| `phpdoc_param_spaces_between_type_and_name` | PHPDoc | P | **P** phpdoc_align.spacing | – | – | – |
| `phpdoc_wrap_long_lines` | PHPDoc | N | – | – | – | – |
| `property_read_weight` | PHPDoc | P | **P** phpdoc_order.order (tag list order) | – | – | – |
| `property_weight` | PHPDoc | P | **P** phpdoc_order.order (tag list order) | – | – | – |
| `property_write_weight` | PHPDoc | P | **P** phpdoc_order.order (tag list order) | – | – | – |
| `reformat_null_type_position` | PHPDoc | E | **E** phpdoc_types_order.null_adjustment (always_first\|always_last\|none) | – | – | – |
| `return_weight` | PHPDoc | P | **P** phpdoc_order.order (tag list order) | – | – | – |
| `see_weight` | PHPDoc | P | **P** phpdoc_order.order (tag list order) | – | – | – |
| `since_weight` | PHPDoc | P | **P** phpdoc_order.order (tag list order) | – | – | – |
| `sort_phpdoc_elements` | PHPDoc | P | **P** phpdoc_order | – | – | – |
| `subpackage_weight` | PHPDoc | P | **P** phpdoc_order.order (tag list order) | – | – | – |
| `throws_weight` | PHPDoc | P | **P** phpdoc_order.order (tag list order) | – | – | – |
| `todo_weight` | PHPDoc | P | **P** phpdoc_order.order (tag list order) | – | – | – |
| `uses_weight` | PHPDoc | P | **P** phpdoc_order.order (tag list order) | – | – | – |
| `var_weight` | PHPDoc | P | **P** phpdoc_order.order (tag list order) | – | – | – |
| `version_weight` | PHPDoc | P | **P** phpdoc_order.order (tag list order) | – | – | – |
| `collapse_line_break_after_type_cast` | Spaces | N | – | – | – | – |
| `concat_spaces` | Spaces | E | **E** concat_space.spacing | **E** space-around-concatenation-binary-operator | – | **E** Squiz.Strings.ConcatenationSpacing.spacing |
| `normalize_cast_paren_spacing` | Spaces | P | **P** short_scalar_cast/lowercase_cast (also renames) | – | – | **P** Squiz.WhiteSpace.CastSpacing (true only) |
| `space_after_colon` | Spaces | P | **P** ternary_operator_spaces (true only) | – | – | – |
| `space_after_colon_in_enum_backed_type` | Spaces | N | – | – | – | – |
| `space_after_colon_in_named_argument` | Spaces | N | – | – | – | – |
| `space_after_colon_in_return_type` | Spaces | P | **P** return_type_declaration (true only) | – | – | **P** ReturnTypeDeclaration (true only) |
| `space_after_comma` | Spaces | P | **P** method_argument_space / whitespace_after_comma_in_array (true only) | – | – | **P** FunctionCallArgumentSpacing (true only) |
| `space_after_for_semicolon` | Spaces | P | **P** space_after_semicolon (true only) | – | – | **P** ForLoopDeclaration (true only) |
| `space_after_quest` | Spaces | P | **P** ternary_operator_spaces (true only) | – | – | – |
| `space_after_type_cast` | Spaces | E | **E** cast_spaces.space | **E** space-after-cast-unary-prefix-operators | – | **E** Generic.Formatting.SpaceAfterCast.spacing |
| `space_after_unary_not` | Spaces | E | **E** not_operator_with_successor_space | **E** space-after-logical-not-unary-prefix-operator | – | **E** Generic.Formatting.SpaceAfterNot.spacing |
| `space_before_array_initializer_left_brace` | Spaces | N | – | – | – | – |
| `space_before_catch_keyword` | Spaces | P | **P** control_structure_continuation_position (true only) | – | – | **P** ControlSignature (true only) |
| `space_before_catch_left_brace` | Spaces | P | **P** braces_position (true only) | – | – | **P** ControlSignature (true only) |
| `space_before_catch_parentheses` | Spaces | P | **P** single_space_around_construct (true only) | – | – | **P** ControlSignature (true only) |
| `space_before_class_left_brace` | Spaces | P | **P** braces_position (true only) | – | – | **P** PSR2.Classes.ClassDeclaration (true only) |
| `space_before_closure_left_parenthesis` | Spaces | E | **E** function_declaration.closure_function_spacing | **E** space-before-closure-parameter-list-parenthesis | – | – |
| `space_before_colon` | Spaces | P | **P** ternary_operator_spaces (true only) | – | – | – |
| `space_before_colon_in_enum_backed_type` | Spaces | N | – | – | – | – |
| `space_before_colon_in_named_argument` | Spaces | N | – | – | – | – |
| `space_before_colon_in_return_type` | Spaces | E | **E** return_type_declaration.space_before | – | – | **P** PSR12.Functions.ReturnTypeDeclaration (false only) |
| `space_before_comma` | Spaces | P | **P** method_argument_space / no_whitespace_before_comma_in_array (false only) | – | – | **P** Generic.Functions.FunctionCallArgumentSpacing (false only) |
| `space_before_do_left_brace` | Spaces | P | **P** braces_position (true only) | – | – | **P** ControlSignature (true only) |
| `space_before_else_keyword` | Spaces | P | **P** control_structure_continuation_position (true only) | – | – | **P** ControlSignature (true only) |
| `space_before_else_left_brace` | Spaces | P | **P** braces_position (true only) | – | – | **P** ControlSignature (true only) |
| `space_before_finally_keyword` | Spaces | P | **P** control_structure_continuation_position (true only) | – | – | **P** ControlSignature (true only) |
| `space_before_finally_left_brace` | Spaces | P | **P** braces_position (true only) | – | – | **P** ControlSignature (true only) |
| `space_before_for_left_brace` | Spaces | P | **P** braces_position (true only) | – | – | **P** ControlSignature (true only) |
| `space_before_for_parentheses` | Spaces | P | **P** single_space_around_construct (true only) | – | – | **P** ControlSignature (true only) |
| `space_before_for_semicolon` | Spaces | E | **P** no_singleline_whitespace_before_semicolons (false only) | – | – | **E** Squiz.ControlStructures.ForLoopDeclaration |
| `space_before_if_left_brace` | Spaces | P | **P** control_structure_braces/braces_position (true only) | – | – | **P** ControlSignature (true only) |
| `space_before_if_parentheses` | Spaces | P | **P** single_space_around_construct (true only) | – | – | **P** Squiz.ControlStructures.ControlSignature (true only) |
| `space_before_method_call_parentheses` | Spaces | P | **P** no_spaces_after_function_name (false only) | – | – | **P** PSR2.Methods.FunctionCallSignature (false only) |
| `space_before_method_left_brace` | Spaces | P | **P** braces_position (true only) | – | – | – |
| `space_before_method_parentheses` | Spaces | P | **P** no_spaces_after_function_name (false only) | – | – | **P** Squiz.Functions.FunctionDeclaration (false only) |
| `space_before_quest` | Spaces | P | **P** ternary_operator_spaces (true only) | – | – | – |
| `space_before_short_closure_left_parenthesis` | Spaces | E | **E** function_declaration.closure_fn_spacing | **E** space-before-arrow-function-parameter-list-parenthesis | – | – |
| `space_before_switch_left_brace` | Spaces | P | **P** braces_position (true only) | – | – | **P** ControlSignature (true only) |
| `space_before_switch_parentheses` | Spaces | P | **P** single_space_around_construct (true only) | – | – | **P** ControlSignature (true only) |
| `space_before_try_left_brace` | Spaces | P | **P** braces_position (true only) | – | – | **P** ControlSignature (true only) |
| `space_before_unary_not` | Spaces | P | **P** not_operator_with_space (both sides) | – | – | – |
| `space_before_while_keyword` | Spaces | P | **P** control_structure_continuation_position (true only) | – | – | **P** ControlSignature (true only) |
| `space_before_while_left_brace` | Spaces | P | **P** braces_position (true only) | – | – | **P** ControlSignature (true only) |
| `space_before_while_parentheses` | Spaces | P | **P** single_space_around_construct (true only) | – | – | **P** ControlSignature (true only) |
| `space_between_ternary_quest_and_colon` | Spaces | P | **P** ternary_operator_spaces (false only) | – | – | – |
| `spaces_around_additive_operators` | Spaces | P | **P** binary_operator_spaces.operators[+,-] | – | – | **P** OperatorSpacing (true only) |
| `spaces_around_ampersand_in_intersection_type` | Spaces | P | **P** types_spaces.space (shared with \|) | – | – | – |
| `spaces_around_arrow` | Spaces | P | **P** object_operator_without_whitespace (false only) | – | – | **P** Squiz.WhiteSpace.ObjectOperatorSpacing (false only) |
| `spaces_around_assignment_in_declare` | Spaces | E | **E** declare_equal_normalize.space | **E** space-around-assignment-in-declare | – | **P** PSR12.Files.DeclareStatement (false only) |
| `spaces_around_assignment_operators` | Spaces | P | **P** binary_operator_spaces.operators[=] (single_space\|no_space) | – | – | **P** Squiz.WhiteSpace.OperatorSpacing (true only) |
| `spaces_around_bitwise_operators` | Spaces | P | **P** binary_operator_spaces.operators[&,\|,^] | – | – | **P** OperatorSpacing (true only) |
| `spaces_around_equality_operators` | Spaces | P | **P** binary_operator_spaces.operators[==,!=,===,!==] | – | – | **P** OperatorSpacing (true only) |
| `spaces_around_logical_operators` | Spaces | P | **P** binary_operator_spaces.operators[&&,\|\|,and,or,xor] | – | – | **P** Squiz.WhiteSpace.LogicalOperatorSpacing (true only) |
| `spaces_around_multiplicative_operators` | Spaces | P | **P** binary_operator_spaces.operators[*,/,%,**] | – | – | **P** OperatorSpacing (true only) |
| `spaces_around_null_coalesce_operator` | Spaces | P | **P** binary_operator_spaces.operators[??] | – | – | **P** OperatorSpacing (true only) |
| `spaces_around_pipe_in_union_type` | Spaces | E | **E** types_spaces.space | – | – | – |
| `spaces_around_relational_operators` | Spaces | P | **P** binary_operator_spaces.operators[<,>,<=,>=,<=>] | – | – | **P** OperatorSpacing (true only) |
| `spaces_around_shift_operators` | Spaces | P | **P** binary_operator_spaces.operators[<<,>>] | – | – | **P** OperatorSpacing (true only) |
| `spaces_around_unary_operator` | Spaces | P | **P** unary_operator_spaces (false only) | **P** space-after-additive/increment/decrement-unary-prefix-operator (prefix only) | – | **P** Generic.WhiteSpace.IncrementDecrementSpacing (false only) |
| `spaces_around_var_within_brackets` | Spaces | N | – | – | – | – |
| `spaces_within_array_initializer_braces` | Spaces | P | **P** trim_array_spaces (false only) | – | – | **P** Squiz.Arrays.ArrayDeclaration (false only) |
| `spaces_within_brackets` | Spaces | P | **P** no_spaces_around_offset (false only) | – | – | – |
| `spaces_within_catch_parentheses` | Spaces | P | **P** spaces_inside_parentheses (all parentheses) | – | – | – |
| `spaces_within_compound_type_parens` | Spaces | N | – | – | – | – |
| `spaces_within_for_parentheses` | Spaces | E | **P** spaces_inside_parentheses (all parentheses) | – | – | **E** Squiz.ControlStructures.ForLoopDeclaration.requiredSpacesAfterOpen |
| `spaces_within_if_parentheses` | Spaces | P | **P** spaces_inside_parentheses (all parentheses) | – | – | **P** Squiz.ControlStructures.ControlSignature (false only) |
| `spaces_within_method_call_parentheses` | Spaces | E | **P** spaces_inside_parentheses (all parentheses) | – | – | **E** PSR2.Methods.FunctionCallSignature.requiredSpacesAfterOpen/BeforeClose |
| `spaces_within_method_parentheses` | Spaces | E | **P** spaces_inside_parentheses (all parentheses) | – | – | **E** Squiz.Functions.FunctionDeclarationArgumentSpacing.requiredSpacesAfterOpen/BeforeClose |
| `spaces_within_parentheses` | Spaces | E | **P** spaces_inside_parentheses (all parentheses at once) | **E** space-within-grouping-parenthesis | – | **E** Generic.WhiteSpace.ArbitraryParenthesesSpacing.spacing |
| `spaces_within_short_echo_tags` | Spaces | N | – | – | – | – |
| `spaces_within_switch_parentheses` | Spaces | P | **P** spaces_inside_parentheses (all parentheses) | – | – | – |
| `spaces_within_while_parentheses` | Spaces | P | **P** spaces_inside_parentheses (all parentheses) | – | – | – |
| `ij_continuation_indent_size` | Tabs and Indents | N | – | – | – | – |
| `indent_code_in_php_tags` | Tabs and Indents | N | – | – | – | – |
| `keep_indents_on_empty_lines` | Tabs and Indents | P | **P** no_whitespace_in_blank_line (false only) | – | – | **P** Squiz.WhiteSpace.SuperfluousWhitespace (false only) |
| `indent_size` | Tabs and Indents | E | **E** Config::setIndent | **E** tab-width | **E** tabWidth | **E** Generic.WhiteSpace.ScopeIndent.indent |
| `indent_style` | Tabs and Indents | E | **E** setIndent("\t")+indentation_type | **E** use-tabs | **E** useTabs | **E** ScopeIndent.tabIndent / Generic.WhiteSpace.DisallowTabIndent |
| `tab_width` | Tabs and Indents | P | **P** setIndent (tab = indent) | **P** tab-width | **P** tabWidth | **P** ScopeIndent.indent |
| `align_assignments` | Wrapping and Braces | P | **P** binary_operator_spaces.operators[=] align_single_space_minimal (different run rules) | **P** align-assignment-like (also aligns properties, constants, => and enum cases) | – | **P** Generic.Formatting.MultipleStatementAlignment |
| `align_class_constants` | Wrapping and Braces | P | **P** binary_operator_spaces[=] (all = at once) | **P** align-assignment-like (shared) | – | – |
| `align_enum_cases` | Wrapping and Braces | P | – | **P** align-assignment-like (shared) | – | – |
| `align_group_field_declarations` | Wrapping and Braces | P | – | **P** align-assignment-like (shared) | – | – |
| `align_inline_comments` | Wrapping and Braces | N | – | – | – | – |
| `align_key_value_pairs` | Wrapping and Braces | P | **P** binary_operator_spaces.operators[=>] align_single_space_minimal | **P** align-assignment-like (shared) | – | **P** Squiz.Arrays.ArrayDeclaration (also forces layout) |
| `align_match_arm_bodies` | Wrapping and Braces | N | – | – | – | – |
| `align_multiline_array_initializer_expression` | Wrapping and Braces | N | – | – | – | – |
| `align_multiline_binary_operation` | Wrapping and Braces | N | – | – | – | – |
| `align_multiline_chained_methods` | Wrapping and Braces | N | – | – | – | – |
| `align_multiline_extends_list` | Wrapping and Braces | N | – | – | – | – |
| `align_multiline_for` | Wrapping and Braces | N | – | – | – | – |
| `align_multiline_parameters` | Wrapping and Braces | P | – | **P** align-parameters (column of variable, not of first parameter) | – | – |
| `align_multiline_parameters_in_calls` | Wrapping and Braces | N | – | – | – | – |
| `align_named_arguments` | Wrapping and Braces | P | – | **P** align-named-arguments | – | – |
| `anonymous_brace_style` | Wrapping and Braces | P | **P** braces_position.anonymous_classes_opening_brace | – | – | – |
| `array_initializer_new_line_after_left_brace` | Wrapping and Braces | N | – | – | – | – |
| `array_initializer_right_brace_on_new_line` | Wrapping and Braces | N | – | – | – | – |
| `array_initializer_wrap` | Wrapping and Braces | P | **P** array_indentation / trailing_comma_in_multiline | **P** preserve-breaking-array-like | – | – |
| `assignment_wrap` | Wrapping and Braces | N | – | – | – | – |
| `attributes_wrap` | Wrapping and Braces | P | – | **P** separate-attributes | – | – |
| `binary_operation_sign_on_next_line` | Wrapping and Braces | P | **P** operator_linebreak.position (all operators incl. ternary) | **P** line-before-binary-operator | – | – |
| `binary_operation_wrap` | Wrapping and Braces | P | – | **P** preserve-breaking-binary-expression | – | – |
| `block_brace_style` | Wrapping and Braces | P | **P** braces_position.control_structures_opening_brace | **P** control-brace-style | – | – |
| `call_parameters_new_line_after_left_paren` | Wrapping and Braces | P | **P** method_argument_space ensure_fully_multiline (true only) | – | – | – |
| `call_parameters_right_paren_on_new_line` | Wrapping and Braces | P | **P** method_argument_space ensure_fully_multiline (true only) | – | – | – |
| `call_parameters_wrap` | Wrapping and Braces | P | **P** method_argument_space.on_multiline | **P** preserve-breaking-argument-list | – | – |
| `catch_on_new_line` | Wrapping and Braces | P | **P** control_structure_continuation_position (shared) | **P** following-clause-on-newline (shared) | – | – |
| `class_brace_style` | Wrapping and Braces | P | **P** braces_position.classes_opening_brace (same_line\|next_line_unless_newline_at_signature_end) | **P** classlike-brace-style (same_line\|next_line\|always_next_line) | **P** braceStyle per-cs\|1tbs (classes and functions together) | **P** PSR2.Classes.ClassDeclaration (next_line only) |
| `collapse_abstract_property_hooks` | Wrapping and Braces | P | – | **P** inline-abstract-property-hooks | – | – |
| `do_while_brace_force` | Wrapping and Braces | P | **P** control_structure_braces (always only) | – | – | **P** InlineControlStructure (always only) |
| `else_on_new_line` | Wrapping and Braces | P | **P** control_structure_continuation_position (else, catch, finally, while together) | **P** following-clause-on-newline (else/elseif/catch/finally together) | – | – |
| `extends_keyword_wrap` | Wrapping and Braces | N | – | – | – | – |
| `extends_list_wrap` | Wrapping and Braces | N | – | – | – | – |
| `finally_on_new_line` | Wrapping and Braces | P | **P** control_structure_continuation_position (shared) | **P** following-clause-on-newline (shared) | – | – |
| `for_brace_force` | Wrapping and Braces | P | **P** control_structure_braces (always only) | – | – | **P** InlineControlStructure (always only) |
| `for_statement_new_line_after_left_paren` | Wrapping and Braces | N | – | – | – | – |
| `for_statement_right_paren_on_new_line` | Wrapping and Braces | N | – | – | – | – |
| `for_statement_wrap` | Wrapping and Braces | N | – | – | – | – |
| `force_empty_classes_in_one_line` | Wrapping and Braces | P | **P** single_line_empty_body (shared) | **P** inline-empty-classlike-braces | – | – |
| `force_empty_methods_in_one_line` | Wrapping and Braces | P | **P** single_line_empty_body (functions and classes together) | **P** inline-empty-function-braces + inline-empty-method-braces + inline-empty-constructor-braces | **P** fixed: always {} | – |
| `group_use_wrap` | Wrapping and Braces | P | **P** group_import / single_import_per_statement | **P** expand-use-groups | – | – |
| `heredoc_on_same_line` | Wrapping and Braces | N | – | – | – | – |
| `if_brace_force` | Wrapping and Braces | P | **P** control_structure_braces (always only) | – | – | **P** Generic.ControlStructures.InlineControlStructure (always only) |
| `if_lparen_on_next_line` | Wrapping and Braces | N | – | – | – | – |
| `if_rparen_on_next_line` | Wrapping and Braces | N | – | – | – | – |
| `indent_break_from_case` | Wrapping and Braces | N | – | – | – | – |
| `indent_case_from_switch` | Wrapping and Braces | P | – | – | – | **P** PSR2.ControlStructures.SwitchDeclaration.indent |
| `keep_control_statement_in_one_line` | Wrapping and Braces | N | – | – | – | – |
| `keep_first_column_comment` | Wrapping and Braces | N | – | – | – | – |
| `keep_line_breaks` | Wrapping and Braces | P | – | **P** preserve-breaking-* (per construct) | – | – |
| `keep_rparen_and_lbrace_on_one_line` | Wrapping and Braces | N | – | – | – | – |
| `keep_simple_classes_in_one_line` | Wrapping and Braces | N | – | – | – | – |
| `keep_simple_methods_in_one_line` | Wrapping and Braces | N | – | – | – | – |
| `lambda_brace_style` | Wrapping and Braces | P | **P** braces_position.anonymous_functions_opening_brace | **P** closure-brace-style | – | – |
| `method_brace_style` | Wrapping and Braces | P | **P** braces_position.functions_opening_brace | **P** function-brace-style + method-brace-style | **P** braceStyle | **P** Generic.Functions.OpeningFunctionBraceBsdAllman / OpeningFunctionBraceKernighanRitchie |
| `method_call_chain_wrap` | Wrapping and Braces | P | – | **P** method-chain-breaking-style + preserve-breaking-member-access-chain | – | – |
| `method_parameters_new_line_after_left_paren` | Wrapping and Braces | P | **P** method_argument_space ensure_fully_multiline (true only) | – | – | – |
| `method_parameters_right_paren_on_new_line` | Wrapping and Braces | P | **P** method_argument_space ensure_fully_multiline (true only) | – | – | – |
| `method_parameters_wrap` | Wrapping and Braces | P | **P** method_argument_space.on_multiline (ensure_fully_multiline\|ensure_single_line\|ignore) | **P** preserve-breaking-parameter-list (fits-or-breaks algorithm) | – | – |
| `modifier_list_wrap` | Wrapping and Braces | N | – | – | – | – |
| `multiline_chained_calls_first_call_on_new_line` | Wrapping and Braces | P | – | **P** first-method-chain-on-new-line | – | – |
| `multiline_chained_calls_semicolon_on_new_line` | Wrapping and Braces | E | **E** multiline_whitespace_before_semicolons.strategy | **E** method-chain-semicolon-on-next-line | – | – |
| `multiline_closure_lambda_on_new_line` | Wrapping and Braces | N | – | – | – | – |
| `namespace_brace_style` | Wrapping and Braces | N | – | – | – | – |
| `new_line_after_php_opening_tag` | Wrapping and Braces | P | **P** linebreak_after_opening_tag (true only) | **P** opening-tag-on-own-line | – | – |
| `parameters_attributes_wrap` | Wrapping and Braces | P | – | **P** parameter-attribute-on-new-line | – | – |
| `place_assignment_sign_on_next_line` | Wrapping and Braces | N | – | – | – | – |
| `place_parens_for_constructor` | Wrapping and Braces | E | **E** new_with_parentheses.named_class/anonymous_class | **P** parentheses-in-new-expression | – | – |
| `return_type_on_new_line` | Wrapping and Braces | N | – | – | – | – |
| `special_else_if_treatment` | Wrapping and Braces | N | – | – | – | – |
| `ternary_operation_signs_on_next_line` | Wrapping and Braces | P | **P** operator_linebreak (shared with binary) | – | – | – |
| `ternary_operation_wrap` | Wrapping and Braces | P | – | **P** preserve-breaking-conditional-expression | – | – |
| `treat_multiline_arrays_and_lambdas_multiline` | Wrapping and Braces | P | – | **P** inline-single-breaking-value-argument | – | – |
| `union_type_wrap` | Wrapping and Braces | N | – | – | – | – |
| `while_brace_force` | Wrapping and Braces | P | **P** control_structure_braces (always only) | – | – | **P** InlineControlStructure (always only) |
| `while_on_new_line` | Wrapping and Braces | P | **P** control_structure_continuation_position (shared) | – | – | – |
| `max_line_length` | Wrapping and Braces | P | – | **P** print-width (always wraps; PhpStorm wraps only where a wrap Option is on) | **P** printWidth (same) | **P** Generic.Files.LineLength (reports only, no fix) |
</details>

### A.2 JavaScript and TypeScript (one row per Option name; "In" says which language has it as `verified-effect`)

<details><summary>Show the JavaScript / TypeScript table</summary>

| Option (`ij_javascript_` / `ij_typescript_` omitted) | In | Tab | Best | dprint-plugin-typescript | ESLint + @stylistic | TypeScript LS formatter | prettier | biome | clang-format |
|---|---|---|---|---|---|---|---|---|---|
| `blank_lines_after_imports` | JS, TS | Blank Lines | P | – | **P** import-x/newline-after-import (other plugin) | – | – | – | – |
| `blank_lines_around_class` | JS, TS | Blank Lines | P | – | **P** padding-line-between-statements (0/1) | – | – | – | – |
| `blank_lines_around_field` | JS, TS | Blank Lines | P | – | **P** lines-between-class-members (0/1) | – | – | – | – |
| `blank_lines_around_field_in_interface` | TS | Blank Lines | N | – | – | – | – | – | – |
| `blank_lines_around_function` | JS, TS | Blank Lines | P | – | **P** padding-line-between-statements (0/1) | – | – | – | – |
| `blank_lines_around_method` | JS, TS | Blank Lines | P | – | **P** lines-between-class-members (0/1) | – | – | – | **P** SeparateDefinitionBlocks |
| `blank_lines_around_method_in_interface` | TS | Blank Lines | N | – | – | – | – | – | – |
| `keep_blank_lines_in_code` | JS, TS | Blank Lines | E | **P** fixed max 1 | **E** no-multiple-empty-lines.max | – | **P** fixed max 1 | **P** fixed max 1 | **E** MaxEmptyLinesToKeep |
| `field_prefix` | JS, TS | Code Generation | N | – | – | – | – | – | – |
| `line_comment_add_space_on_reformat` | JS, TS | Code Generation | N | – | – | – | – | – | – |
| `property_prefix` | JS, TS | Code Generation | N | – | – | – | – | – | – |
| `comma_on_new_line` | JS, TS | Punctuation | E | – | **E** comma-style | – | – | – | – |
| `enforce_trailing_comma` | JS, TS | Punctuation | E | **E** trailingCommas (never\|always\|onlyMultiLine\|maintain) | **E** comma-dangle (never\|always\|always-multiline\|ignore) | – | **P** trailingComma (no keep) | **P** trailingCommas (no keep) | – |
| `force_quote_style` | JS, TS | Punctuation | E | **P** quoteStyle prefer* vs always* | **P** quotes.avoidEscape | – | **P** none (always forces) | **P** none (always forces) | **E** JavaScriptQuotes=Leave |
| `force_semicolon_style` | JS, TS | Punctuation | E | **P** semiColons=prefer is "keep" | **P** semi (always forces) | **E** semicolons=ignore | **P** none (always forces) | **P** none (always forces) | – |
| `use_double_quotes` | JS, TS | Punctuation | E | **E** quoteStyle | **E** quotes | – | **E** singleQuote | **E** quoteStyle | **E** JavaScriptQuotes |
| `use_semicolon_after_statement` | JS, TS | Punctuation | E | **P** semiColons (always\|prefer\|asi) | **E** semi | **E** semicolons (insert\|remove\|ignore) | **P** semi (always rewrites) | **P** semicolons (always rewrites) | – |
| `space_after_colon` | JS, TS | Spaces | N | – | – | – | – | – | – |
| `space_after_comma` | JS, TS | Spaces | E | – | **E** comma-spacing.after | **E** insertSpaceAfterCommaDelimiter | – | – | – |
| `space_after_dots_in_rest_parameter` | JS, TS | Spaces | E | – | **E** rest-spread-spacing | – | – | – | – |
| `space_after_generator_mult` | JS, TS | Spaces | E | – | **E** generator-star-spacing.after | – | – | – | – |
| `space_after_property_colon` | JS, TS | Spaces | E | – | **E** key-spacing.afterColon | – | – | – | – |
| `space_after_quest` | JS, TS | Spaces | N | – | – | – | – | – | – |
| `space_after_type_colon` | JS, TS | Spaces | E | – | **E** type-annotation-spacing.after | – | – | – | – |
| `space_after_unary_not` | JS, TS | Spaces | E | – | **E** space-unary-ops.overrides["!"] | – | – | – | – |
| `space_before_async_arrow_lparen` | JS, TS | Spaces | E | – | **E** space-before-function-paren.asyncArrow | – | – | – | – |
| `space_before_catch_keyword` | JS, TS | Spaces | E | – | **E** keyword-spacing.overrides.catch.before | – | – | – | – |
| `space_before_catch_left_brace` | JS, TS | Spaces | P | – | **P** space-before-blocks.keywords | – | – | – | – |
| `space_before_catch_parentheses` | JS, TS | Spaces | P | – | **P** keyword-spacing | **P** insertSpaceAfterKeywordsInControlFlowStatements | – | – | – |
| `space_before_class_lbrace` | JS, TS | Spaces | P | – | **P** space-before-blocks.classes | – | – | – | – |
| `space_before_colon` | JS, TS | Spaces | N | – | – | – | – | – | – |
| `space_before_comma` | JS, TS | Spaces | E | – | **E** comma-spacing.before | – | – | – | **P** fixed |
| `space_before_do_left_brace` | JS, TS | Spaces | P | – | **P** space-before-blocks.keywords | – | – | – | – |
| `space_before_else_keyword` | JS, TS | Spaces | E | – | **E** keyword-spacing.overrides.else.before | – | – | – | – |
| `space_before_else_left_brace` | JS, TS | Spaces | P | – | **P** space-before-blocks.keywords | – | – | – | – |
| `space_before_finally_keyword` | JS, TS | Spaces | E | – | **E** keyword-spacing.overrides.finally.before | – | – | – | – |
| `space_before_finally_left_brace` | JS, TS | Spaces | P | – | **P** space-before-blocks.keywords | – | – | – | – |
| `space_before_for_left_brace` | JS, TS | Spaces | P | – | **P** space-before-blocks.keywords | – | – | – | – |
| `space_before_for_parentheses` | JS, TS | Spaces | E | **E** forStatement/forIn/forOf.spaceAfterForKeyword | **P** keyword-spacing | **P** insertSpaceAfterKeywordsInControlFlowStatements | – | – | – |
| `space_before_for_semicolon` | JS, TS | Spaces | E | – | **E** semi-spacing.before | – | – | – | – |
| `space_before_function_left_parenth` | JS, TS | Spaces | E | **E** functionExpression.spaceAfterFunctionKeyword | **E** space-before-function-paren.anonymous | **E** insertSpaceAfterFunctionKeywordForAnonymousFunctions | – | – | – |
| `space_before_generator_mult` | JS, TS | Spaces | E | – | **E** generator-star-spacing.before | – | – | – | – |
| `space_before_if_left_brace` | JS, TS | Spaces | P | – | **P** space-before-blocks.keywords (all control blocks) | – | – | – | – |
| `space_before_if_parentheses` | JS, TS | Spaces | E | **E** ifStatement.spaceAfterIfKeyword | **P** keyword-spacing (all keywords) | **P** insertSpaceAfterKeywordsInControlFlowStatements (all) | – | – | **P** SpaceBeforeParens ControlStatements |
| `space_before_method_call_parentheses` | JS, TS | Spaces | E | – | **E** function-call-spacing | – | – | – | **P** SpaceBeforeParens |
| `space_before_method_left_brace` | JS, TS | Spaces | P | – | **P** space-before-blocks.functions | – | – | – | – |
| `space_before_method_parentheses` | JS, TS | Spaces | E | **E** functionDeclaration.spaceBeforeParentheses + method.spaceBeforeParentheses | **E** space-before-function-paren.named | **P** insertSpaceBeforeFunctionParenthesis (decl only) | – | – | **P** SpaceBeforeParens (also calls) |
| `space_before_property_colon` | JS, TS | Spaces | E | – | **E** key-spacing.beforeColon | – | – | – | – |
| `space_before_quest` | JS, TS | Spaces | N | – | – | – | – | – | – |
| `space_before_switch_left_brace` | JS, TS | Spaces | P | – | **P** space-before-blocks.keywords | – | – | – | – |
| `space_before_switch_parentheses` | JS, TS | Spaces | P | – | **P** keyword-spacing | **P** insertSpaceAfterKeywordsInControlFlowStatements | – | – | – |
| `space_before_try_left_brace` | JS, TS | Spaces | P | – | **P** space-before-blocks.keywords | – | – | – | – |
| `space_before_type_colon` | JS, TS | Spaces | E | **E** typeAnnotation.spaceBeforeColon | **E** type-annotation-spacing.before | **E** insertSpaceBeforeTypeAnnotation | – | – | – |
| `space_before_unary_not` | JS, TS | Spaces | N | – | – | – | – | – | – |
| `space_before_while_keyword` | JS, TS | Spaces | E | – | **E** keyword-spacing.overrides.while.before | – | – | – | – |
| `space_before_while_left_brace` | JS, TS | Spaces | P | – | **P** space-before-blocks.keywords | – | – | – | – |
| `space_before_while_parentheses` | JS, TS | Spaces | E | **E** whileStatement.spaceAfterWhileKeyword | **P** keyword-spacing | **P** insertSpaceAfterKeywordsInControlFlowStatements | – | – | – |
| `spaces_around_additive_operators` | JS, TS | Spaces | P | **P** binaryExpression.spaceSurroundingBitwiseAndArithmeticOperator | **P** space-infix-ops (true only) | **P** insertSpaceBeforeAndAfterBinaryOperators (all) | – | – | – |
| `spaces_around_arrow_function_operator` | JS, TS | Spaces | E | – | **E** arrow-spacing | – | – | – | – |
| `spaces_around_assignment_operators` | JS, TS | Spaces | P | – | **P** space-infix-ops (true only) | **P** insertSpaceBeforeAndAfterBinaryOperators (all binary) | – | – | – |
| `spaces_around_bitwise_operators` | JS, TS | Spaces | P | **P** binaryExpression.spaceSurroundingBitwiseAndArithmeticOperator (with arithmetic) | **P** space-infix-ops (true only) | **P** insertSpaceBeforeAndAfterBinaryOperators (all) | – | – | – |
| `spaces_around_equality_operators` | JS, TS | Spaces | P | – | **P** space-infix-ops (true only) | **P** insertSpaceBeforeAndAfterBinaryOperators (all) | – | – | – |
| `spaces_around_logical_operators` | JS, TS | Spaces | P | – | **P** space-infix-ops (true only) | **P** insertSpaceBeforeAndAfterBinaryOperators (all) | – | – | – |
| `spaces_around_multiplicative_operators` | JS, TS | Spaces | P | **P** binaryExpression.spaceSurroundingBitwiseAndArithmeticOperator | **P** space-infix-ops (true only) | **P** insertSpaceBeforeAndAfterBinaryOperators (all) | – | – | – |
| `spaces_around_relational_operators` | JS, TS | Spaces | P | – | **P** space-infix-ops (true only) | **P** insertSpaceBeforeAndAfterBinaryOperators (all) | – | – | – |
| `spaces_around_shift_operators` | JS, TS | Spaces | P | **P** binaryExpression.spaceSurroundingBitwiseAndArithmeticOperator | **P** space-infix-ops (true only) | **P** insertSpaceBeforeAndAfterBinaryOperators (all) | – | – | – |
| `spaces_around_unary_operator` | JS, TS | Spaces | E | – | **E** space-unary-ops.nonwords | – | – | – | – |
| `spaces_within_array_initializer_brackets` | JS, TS | Spaces | E | **E** arrayExpression.spaceAround (+arrayPattern) | **E** array-bracket-spacing | **P** ...NonemptyBrackets (also index access) | – | – | **P** SpacesInContainerLiterals |
| `spaces_within_brackets` | JS, TS | Spaces | E | – | **E** computed-property-spacing | **P** insertSpaceAfterOpeningAndBeforeClosingNonemptyBrackets (also arrays) | – | – | – |
| `spaces_within_catch_parentheses` | JS, TS | Spaces | E | **E** catchClause.spaceAround | **P** space-in-parens (all) | **P** ...NonemptyParenthesis (all) | – | – | – |
| `spaces_within_for_parentheses` | JS, TS | Spaces | E | **E** forStatement/forIn/forOf.spaceAround | **P** space-in-parens (all) | **P** ...NonemptyParenthesis (all) | – | – | – |
| `spaces_within_if_parentheses` | JS, TS | Spaces | E | **E** ifStatement.spaceAround | **P** space-in-parens (all) | **P** ...NonemptyParenthesis (all) | – | – | – |
| `spaces_within_imports` | JS, TS | Spaces | E | **E** importDeclaration.spaceSurroundingNamedImports + exportDeclaration.spaceSurroundingNamedExports | **P** object-curly-spacing (shared) | **P** ...NonemptyBraces (shared) | **P** bracketSpacing (shared) | **P** bracketSpacing (shared) | – |
| `spaces_within_interpolation_expressions` | JS, TS | Spaces | E | – | **E** template-curly-spacing | **E** insertSpaceAfterOpeningAndBeforeClosingTemplateStringBraces | – | – | – |
| `spaces_within_method_call_parentheses` | JS, TS | Spaces | E | **E** arguments.spaceAround | **P** space-in-parens (all) | **P** ...NonemptyParenthesis (all) | – | – | – |
| `spaces_within_method_parentheses` | JS, TS | Spaces | E | **E** parameters.spaceAround | **P** space-in-parens (all) | **P** ...NonemptyParenthesis (all) | – | – | – |
| `spaces_within_object_literal_braces` | JS, TS | Spaces | E | **E** objectExpression.spaceSurroundingProperties (+objectPattern) | **P** object-curly-spacing (also imports, types) | **P** insertSpaceAfterOpeningAndBeforeClosingNonemptyBraces (all braces) | **P** bracketSpacing (all braces) | **P** bracketSpacing (all braces) | **P** Cpp11BracedListStyle |
| `spaces_within_object_type_braces` | JS, TS | Spaces | E | **E** typeLiteral.spaceSurroundingProperties | **P** object-curly-spacing (shared) | **P** ...NonemptyBraces (shared) | **P** bracketSpacing (shared) | **P** bracketSpacing (shared) | – |
| `spaces_within_parentheses` | JS, TS | Spaces | E | **E** parenExpression.spaceAround | **P** space-in-parens (all) | **P** insertSpaceAfterOpeningAndBeforeClosingNonemptyParenthesis (all) | – | – | **P** SpacesInParens |
| `spaces_within_switch_parentheses` | JS, TS | Spaces | E | **E** switchStatement.spaceAround | **P** space-in-parens (all) | **P** ...NonemptyParenthesis (all) | – | – | – |
| `spaces_within_type_assertion` | TS | Spaces | N | – | – | – | – | – | – |
| `spaces_within_union_types` | JS, TS | Spaces | N | – | – | – | – | – | – |
| `spaces_within_while_parentheses` | JS, TS | Spaces | E | **E** whileStatement/doWhileStatement.spaceAround | **P** space-in-parens (all) | **P** ...NonemptyParenthesis (all) | – | – | – |
| `ij_continuation_indent_size` | JS, TS | Tabs and Indents | E | – | – | – | – | – | **E** ContinuationIndentWidth |
| `ij_smart_tabs` | JS, TS | Tabs and Indents | N | – | – | – | – | – | – |
| `indent_chained_calls` | JS, TS | Tabs and Indents | P | – | **P** indent.MemberExpression | – | – | – | – |
| `indent_size` | JS, TS | Tabs and Indents | E | **E** indentWidth | **E** indent | **E** indentSize | **E** tabWidth | **E** indentWidth | **E** IndentWidth |
| `indent_style` | JS, TS | Tabs and Indents | E | **E** useTabs | **E** indent "tab" | **E** convertTabsToSpaces | **E** useTabs | **E** indentStyle | **E** UseTab |
| `keep_indents_on_empty_lines` | JS, TS | Tabs and Indents | P | – | **P** no-trailing-spaces (false only) | **P** trimTrailingWhitespace | – | – | – |
| `tab_width` | JS, TS | Tabs and Indents | E | **P** indentWidth | – | **E** tabSize | **P** tabWidth | **P** indentWidth | **E** TabWidth |
| `use_chained_calls_group_indents` | JS, TS | Tabs and Indents | N | – | – | – | – | – | – |
| `align_imports` | JS, TS | Wrapping and Braces | N | – | – | – | – | – | – |
| `align_multiline_array_initializer_expression` | JS, TS | Wrapping and Braces | N | – | – | – | – | – | – |
| `align_multiline_binary_operation` | JS, TS | Wrapping and Braces | P | – | – | – | – | – | **P** AlignOperands |
| `align_multiline_chained_methods` | JS, TS | Wrapping and Braces | N | – | – | – | – | – | – |
| `align_multiline_extends_list` | JS, TS | Wrapping and Braces | N | – | – | – | – | – | – |
| `align_multiline_for` | JS, TS | Wrapping and Braces | N | – | – | – | – | – | – |
| `align_multiline_parameters` | JS, TS | Wrapping and Braces | P | – | – | – | – | – | **P** AlignAfterOpenBracket |
| `align_multiline_parameters_in_calls` | JS, TS | Wrapping and Braces | P | – | – | – | – | – | **P** AlignAfterOpenBracket |
| `align_multiline_ternary_operation` | JS, TS | Wrapping and Braces | N | – | – | – | – | – | – |
| `align_object_properties` | JS, TS | Wrapping and Braces | E | – | **E** key-spacing.align ("colon"\|"value") | – | – | – | **P** AlignConsecutiveAssignments |
| `align_union_types` | TS | Wrapping and Braces | N | – | – | – | – | – | – |
| `align_var_statements` | JS, TS | Wrapping and Braces | P | – | – | – | – | – | **P** AlignConsecutiveAssignments/Declarations |
| `array_initializer_new_line_after_left_brace` | JS, TS | Wrapping and Braces | P | – | **P** array-bracket-newline | – | – | – | – |
| `array_initializer_right_brace_on_new_line` | JS, TS | Wrapping and Braces | P | – | **P** array-bracket-newline | – | – | – | – |
| `array_initializer_wrap` | JS, TS | Wrapping and Braces | P | **P** arrayExpression.preferSingleLine/preferHanging | **P** array-bracket-newline + array-element-newline | – | **P** fits-or-breaks at lineWidth | **P** expand | – |
| `assignment_wrap` | JS, TS | Wrapping and Braces | P | – | – | – | **P** fits-or-breaks at lineWidth | **P** fits-or-breaks at lineWidth | – |
| `binary_operation_sign_on_next_line` | JS, TS | Wrapping and Braces | E | **E** binaryExpression.operatorPosition (nextLine\|sameLine\|maintain) | **P** operator-linebreak | – | – | **P** operatorLinebreak | **P** BreakBeforeBinaryOperators |
| `binary_operation_wrap` | JS, TS | Wrapping and Braces | P | **P** binaryExpression.linePerExpression | – | – | **P** fits-or-breaks at lineWidth | **P** fits-or-breaks at lineWidth | **P** ColumnLimit |
| `block_brace_style` | JS, TS | Wrapping and Braces | P | **P** if/for/while/try/switch.bracePosition | **P** brace-style (all braces) | **P** placeOpenBraceOnNewLineForControlBlocks | – | – | **P** BraceWrapping.AfterControlStatement |
| `call_parameters_new_line_after_left_paren` | JS, TS | Wrapping and Braces | P | – | **P** function-paren-newline | – | – | – | **P** AlignAfterOpenBracket BlockIndent |
| `call_parameters_right_paren_on_new_line` | JS, TS | Wrapping and Braces | P | – | **P** function-paren-newline | – | – | – | **P** AlignAfterOpenBracket BlockIndent |
| `call_parameters_wrap` | JS, TS | Wrapping and Braces | P | **P** fits-or-breaks at lineWidth + arguments.preferHanging/preferSingleLine | **P** function-call-argument-newline | – | **P** fits-or-breaks at lineWidth | **P** fits-or-breaks at lineWidth | **P** BinPackArguments |
| `catch_on_new_line` | JS, TS | Wrapping and Braces | P | **P** tryStatement.nextControlFlowPosition (catch+finally) | **P** brace-style stroustrup (shared) | – | – | – | **P** BraceWrapping.BeforeCatch |
| `chained_call_dot_on_new_line` | JS, TS | Wrapping and Braces | E | – | **E** dot-location | – | – | – | – |
| `class_brace_style` | JS, TS | Wrapping and Braces | P | **P** classDeclaration.bracePosition (maintain\|sameLine\|nextLine\|sameLineUnlessHanging) | **P** brace-style (all braces) | **P** placeOpenBraceOnNewLineForFunctions (shared) | – | – | **P** BraceWrapping.AfterClass |
| `class_decorator_wrap` | JS, TS | Wrapping and Braces | P | **P** decorators.preferSingleLine | – | – | – | – | – |
| `class_field_decorator_wrap` | JS, TS | Wrapping and Braces | N | – | – | – | – | – | – |
| `class_method_decorator_wrap` | JS, TS | Wrapping and Braces | N | – | – | – | – | – | – |
| `do_while_brace_force` | JS, TS | Wrapping and Braces | P | – | **P** curly | – | – | – | – |
| `else_on_new_line` | JS, TS | Wrapping and Braces | P | **P** ifStatement.nextControlFlowPosition | **P** brace-style stroustrup (else, catch, finally together) | – | – | – | **P** BraceWrapping.BeforeElse |
| `enum_constants_wrap` | TS | Wrapping and Braces | P | **P** enumDeclaration.memberSpacing | – | – | – | – | – |
| `extends_keyword_wrap` | JS, TS | Wrapping and Braces | P | **P** extendsClause.preferHanging | – | – | – | – | – |
| `extends_list_wrap` | JS, TS | Wrapping and Braces | P | **P** implementsClause.preferHanging | – | – | – | – | – |
| `finally_on_new_line` | JS, TS | Wrapping and Braces | P | **P** tryStatement.nextControlFlowPosition (shared) | **P** brace-style stroustrup (shared) | – | – | – | – |
| `for_brace_force` | JS, TS | Wrapping and Braces | P | **P** forStatement.useBraces | **P** curly | – | – | – | – |
| `for_statement_new_line_after_left_paren` | JS, TS | Wrapping and Braces | N | – | – | – | – | – | – |
| `for_statement_right_paren_on_new_line` | JS, TS | Wrapping and Braces | N | – | – | – | – | – | – |
| `for_statement_wrap` | JS, TS | Wrapping and Braces | P | **P** forStatement.preferSingleLine/preferHanging | – | – | – | – | – |
| `function_expression_brace_style` | JS, TS | Wrapping and Braces | P | **P** functionExpression.bracePosition | – | **P** placeOpenBraceOnNewLineForFunctions (shared) | – | – | – |
| `function_parameter_decorator_wrap` | JS, TS | Wrapping and Braces | N | – | – | – | – | – | – |
| `if_brace_force` | JS, TS | Wrapping and Braces | P | **P** ifStatement.useBraces (maintain\|whenNotSingleLine\|always\|preferNone) | **P** curly (core ESLint rule, not stylistic) | – | – | – | – |
| `imports_wrap` | JS, TS | Wrapping and Braces | P | **P** importDeclaration.forceSingleLine/forceMultiLine/preferSingleLine | **P** object-curly-newline.ImportDeclaration | – | – | – | – |
| `indent_case_from_switch` | JS, TS | Wrapping and Braces | E | – | **E** indent.SwitchCase | **E** indentSwitchCase | – | – | **E** IndentCaseLabels |
| `keep_first_column_comment` | JS, TS | Wrapping and Braces | N | – | – | – | – | – | – |
| `keep_line_breaks` | JS, TS | Wrapping and Braces | P | **P** preferSingleLine=false + "maintain" options | **P** (rule-based fixer keeps breaks) | **P** (whitespace formatter keeps breaks) | – | – | – |
| `keep_simple_blocks_in_one_line` | JS, TS | Wrapping and Braces | P | – | **P** brace-style.allowSingleLine | – | – | – | **P** AllowShortBlocksOnASingleLine |
| `keep_simple_methods_in_one_line` | JS, TS | Wrapping and Braces | P | – | **P** brace-style.allowSingleLine | – | – | – | **P** AllowShortFunctionsOnASingleLine |
| `max_line_length` | JS, TS | Wrapping and Braces | P | **P** lineWidth (always wraps) | **P** max-len (reports only) | – | **P** printWidth (always wraps) | **P** lineWidth (always wraps) | **P** ColumnLimit (always wraps) |
| `method_brace_style` | JS, TS | Wrapping and Braces | P | **P** functionDeclaration/method/constructor.bracePosition (no shifted styles) | **P** brace-style (all braces) | **P** placeOpenBraceOnNewLineForFunctions (end_of_line\|next_line) | – | – | **P** BraceWrapping.AfterFunction |
| `method_call_chain_wrap` | JS, TS | Wrapping and Braces | P | **P** memberExpression.linePerExpression | **P** newline-per-chained-call | – | **P** fits-or-breaks at lineWidth | **P** fits-or-breaks at lineWidth | – |
| `method_parameters_new_line_after_left_paren` | JS, TS | Wrapping and Braces | P | – | **P** function-paren-newline | – | – | – | – |
| `method_parameters_right_paren_on_new_line` | JS, TS | Wrapping and Braces | P | – | **P** function-paren-newline | – | – | – | – |
| `method_parameters_wrap` | JS, TS | Wrapping and Braces | P | **P** fits-or-breaks at lineWidth + parameters.preferHanging/preferSingleLine | **P** function-paren-newline | – | **P** fits-or-breaks at lineWidth | **P** fits-or-breaks at lineWidth | **P** BinPackParameters |
| `object_literal_wrap` | JS, TS | Wrapping and Braces | P | **P** objectExpression.preferSingleLine/preferHanging | **P** object-curly-newline + object-property-newline | – | **P** objectWrap (preserve\|collapse) | **P** expand (auto\|always\|never) | – |
| `object_types_wrap` | TS | Wrapping and Braces | P | **P** typeLiteral.preferSingleLine | – | – | – | – | – |
| `parentheses_expression_new_line_after_left_paren` | JS, TS | Wrapping and Braces | N | – | – | – | – | – | – |
| `parentheses_expression_right_paren_on_new_line` | JS, TS | Wrapping and Braces | N | – | – | – | – | – | – |
| `place_assignment_sign_on_next_line` | JS, TS | Wrapping and Braces | P | – | **P** operator-linebreak.overrides = | – | – | **P** operatorLinebreak | – |
| `prefer_parameters_wrap` | JS, TS | Wrapping and Braces | N | – | – | – | – | – | – |
| `reformat_c_style_comments` | JS, TS | Wrapping and Braces | N | – | – | – | – | – | – |
| `special_else_if_treatment` | JS, TS | Wrapping and Braces | N | – | – | – | – | – | – |
| `ternary_operation_signs_on_next_line` | JS, TS | Wrapping and Braces | E | **E** conditionalExpression.operatorPosition | **P** operator-linebreak.overrides ?/: | – | – | – | **P** BreakBeforeTernaryOperators |
| `ternary_operation_wrap` | JS, TS | Wrapping and Braces | P | **P** conditionalExpression.preferSingleLine | **P** multiline-ternary | – | **P** fits-or-breaks at lineWidth | **P** fits-or-breaks at lineWidth | – |
| `union_types_wrap` | TS | Wrapping and Braces | P | **P** unionAndIntersectionType.preferSingleLine/preferHanging | – | – | – | – | – |
| `var_declaration_wrap` | JS, TS | Wrapping and Braces | P | **P** variableStatement.preferHanging/preferSingleLine | **P** one-var-declaration-per-line | – | – | – | – |
| `while_brace_force` | JS, TS | Wrapping and Braces | P | **P** whileStatement.useBraces | **P** curly | – | – | – | – |
| `while_on_new_line` | JS, TS | Wrapping and Braces | E | **E** doWhileStatement.nextControlFlowPosition | – | – | – | – | **P** BraceWrapping.BeforeWhile |
| `wrap_comments` | JS, TS | Wrapping and Braces | N | – | – | – | – | – | – |
</details>

## Appendix B: Option effect runs

Columns:

- "Inputs run": the record inputs that the tool formatted, out of all of the record's inputs.
- "PhpStorm changed": the inputs whose PhpStorm output for this value differs from the Default output.
- "Same edit": of those inputs, the ones where the tool's change (tool Default configuration → mapped setting) has exactly the same added and removed lines.
- "Tool-only edits": the inputs that the tool changed but PhpStorm did not.
- "Output identical": the tool output is byte-identical to PhpStorm's output for this value.

Base: Default, except JS `use_semicolon_after_statement = false`, which runs on the record's base `force_semicolon_style = true`.

### B.1 PHP

<details><summary>Show the PHP runs</summary>

| Option = value | Tool | Inputs run | PhpStorm changed | Same edit (delta match) | Tool-only edits | Output identical |
|---|---|---|---|---|---|---|
| `class_brace_style` = `end_of_line` | php-cs-fixer | 20/20 | 20 | 20 | 0 | 2 |
| `class_brace_style` = `end_of_line` | mago | 20/20 | 20 | 15 | 0 | 2 |
| `class_brace_style` = `end_of_line` | prettier | 20/20 | 20 | 9 | 0 | 0 |
| `method_brace_style` = `end_of_line` | php-cs-fixer | 23/23 | 23 | 18 | 0 | 8 |
| `method_brace_style` = `end_of_line` | mago | 23/23 | 23 | 17 | 0 | 3 |
| `align_assignments` = `true` | php-cs-fixer | 11/11 | 11 | 3 | 0 | 3 |
| `align_assignments` = `true` | mago | 11/11 | 11 | 2 | 0 | 0 |
| `align_key_value_pairs` = `true` | php-cs-fixer | 1/1 | 1 | 0 | 0 | 0 |
| `align_key_value_pairs` = `true` | mago | 1/1 | 1 | 0 | 0 | 0 |
| `align_class_constants` = `true` | php-cs-fixer | 1/1 | 1 | 0 | 0 | 0 |
| `align_class_constants` = `true` | mago | 1/1 | 1 | 0 | 0 | 0 |
| `concat_spaces` = `false` | php-cs-fixer | 4/4 | 4 | 4 | 0 | 1 |
| `concat_spaces` = `false` | mago | 4/4 | 4 | 4 | 0 | 0 |
| `space_after_type_cast` = `true` | php-cs-fixer | 4/4 | 4 | 2 | 0 | 0 |
| `space_after_type_cast` = `true` | mago | 4/4 | 4 | 2 | 0 | 0 |
| `space_before_closure_left_parenthesis` = `false` | php-cs-fixer | 7/7 | 7 | 6 | 0 | 3 |
| `space_before_closure_left_parenthesis` = `false` | mago | 7/7 | 7 | 6 | 0 | 1 |
| `space_before_short_closure_left_parenthesis` = `true` | php-cs-fixer | 7/7 | 7 | 7 | 0 | 3 |
| `space_before_short_closure_left_parenthesis` = `true` | mago | 7/7 | 7 | 7 | 0 | 0 |
| `space_after_unary_not` = `true` | php-cs-fixer | 5/5 | 5 | 5 | 0 | 1 |
| `space_after_unary_not` = `true` | mago | 5/5 | 5 | 3 | 0 | 0 |
| `spaces_within_parentheses` = `true` | php-cs-fixer | 8/8 | 8 | 1 | 0 | 1 |
| `spaces_within_parentheses` = `true` | mago | 8/8 | 8 | 1 | 0 | 0 |
| `spaces_around_pipe_in_union_type` = `true` | php-cs-fixer | 4/4 | 4 | 1 | 0 | 1 |
| `space_before_colon_in_return_type` = `true` | php-cs-fixer | 4/4 | 4 | 1 | 0 | 1 |
| `spaces_around_assignment_in_declare` = `true` | php-cs-fixer | 4/4 | 4 | 4 | 0 | 2 |
| `spaces_around_assignment_in_declare` = `true` | mago | 4/4 | 4 | 4 | 0 | 0 |
| `blank_lines_before_return_statement` = `1` | php-cs-fixer | 6/6 | 4 | 3 | 0 | 0 |
| `blank_lines_before_return_statement` = `1` | mago | 6/6 | 4 | 4 | 0 | 0 |
| `blank_lines_around_field` = `1` | php-cs-fixer | 17/17 | 6 | 3 | 6 | 1 |
| `blank_lines_around_field` = `1` | mago | 17/17 | 6 | 3 | 4 | 0 |
| `blank_lines_around_method` = `0` | php-cs-fixer | 17/17 | 10 | 0 | 6 | 0 |
| `blank_lines_after_class_header` = `1` | mago | 28/28 | 23 | 11 | 5 | 0 |
| `keep_blank_lines_in_code` = `1` | php-cs-fixer | 13/13 | 12 | 0 | 0 | 1 |
| `else_on_new_line` = `true` | php-cs-fixer | 3/3 | 3 | 1 | 0 | 1 |
| `else_on_new_line` = `true` | mago | 3/3 | 3 | 1 | 0 | 0 |
| `comma_after_last_array_element` = `true` | php-cs-fixer | 4/4 | 4 | 3 | 0 | 0 |
| `comma_after_last_array_element` = `true` | mago | 4/4 | 4 | 1 | 0 | 0 |
| `comma_after_last_array_element` = `true` | prettier | 4/4 | 4 | 0 | 0 | 0 |
| `comma_after_last_parameter` = `true` | php-cs-fixer | 3/3 | 3 | 0 | 0 | 0 |
| `upper_case_boolean_const` = `true` | php-cs-fixer | 4/4 | 4 | 1 | 0 | 0 |
| `upper_case_boolean_const` = `true` | mago | 3/4 | 3 | 0 | 0 | 0 |
| `force_short_declaration_array_style` = `true` | php-cs-fixer | 5/5 | 5 | 1 | 0 | 0 |
| `else_if_style` = `combine` | php-cs-fixer | 2/2 | 2 | 1 | 0 | 1 |
| `method_parameters_wrap` = `split_into_lines` | php-cs-fixer | 8/8 | 8 | 0 | 0 | 0 |
| `method_parameters_wrap` = `split_into_lines` | mago | 8/8 | 8 | 0 | 0 | 0 |
| `align_phpdoc_param_names` = `true` | php-cs-fixer | 7/7 | 7 | 1 | 0 | 1 |
| `reformat_null_type_position` = `in_the_beginning` | php-cs-fixer | 3/3 | 3 | 2 | 0 | 1 |
| `indent_size` = `2` | mago | 11/11 | 11 | 1 | 0 | 1 |
| `indent_size` = `2` | prettier | 11/11 | 11 | 1 | 0 | 1 |
| `max_line_length` = `80` | mago | 22/22 | 1 | 0 | 9 | 0 |
| `max_line_length` = `80` | prettier | 22/22 | 1 | 0 | 10 | 0 |
| `multiline_chained_calls_semicolon_on_new_line` = `true` | php-cs-fixer | 2/2 | 2 | 2 | 0 | 2 |
| `multiline_chained_calls_semicolon_on_new_line` = `true` | mago | 2/2 | 2 | 1 | 0 | 0 |
| `new_line_after_php_opening_tag` = `true` | php-cs-fixer | 1/1 | 1 | 1 | 0 | 1 |
| `new_line_after_php_opening_tag` = `true` | mago | 1/1 | 1 | 1 | 0 | 1 |
| `force_empty_methods_in_one_line` = `true` | php-cs-fixer | 15/15 | 15 | 10 | 0 | 3 |
| `force_empty_methods_in_one_line` = `true` | mago | 15/15 | 15 | 11 | 0 | 3 |
</details>

### B.2 JavaScript / TypeScript

<details><summary>Show the JS/TS runs</summary>

| Option = value | Tool | Inputs run | PhpStorm changed | Same edit (delta match) | Tool-only edits | Output identical |
|---|---|---|---|---|---|---|
| `spaces_within_object_literal_braces` = `true` | prettier | 3/6 | 3 | 0 | 0 | 0 |
| `spaces_within_object_literal_braces` = `true` | biome | 2/6 | 2 | 0 | 0 | 0 |
| `spaces_within_object_literal_braces` = `true` | dprint | 5/6 | 5 | 0 | 0 | 0 |
| `spaces_within_object_literal_braces` = `true` | TS LS | 6/6 | 6 | 4 | 0 | 1 |
| `spaces_within_object_literal_braces` = `true` | ESLint+@stylistic | 2/6 | 2 | 1 | 0 | 1 |
| `spaces_within_object_literal_braces` = `true` | clang-format | 6/6 | 6 | 0 | 0 | 0 |
| `space_before_function_left_parenth` = `false` | TS LS | 3/3 | 3 | 3 | 0 | 1 |
| `space_before_function_left_parenth` = `false` | ESLint+@stylistic | 1/3 | 1 | 1 | 0 | 1 |
| `space_before_function_left_parenth` = `false` | dprint | 2/3 | 2 | 0 | 0 | 1 |
| `space_before_method_parentheses` = `true` | TS LS | 8/8 | 8 | 5 | 0 | 3 |
| `space_before_method_parentheses` = `true` | ESLint+@stylistic | 4/8 | 4 | 4 | 0 | 3 |
| `space_before_method_parentheses` = `true` | dprint | 7/8 | 7 | 2 | 0 | 1 |
| `method_brace_style` = `next_line` | TS LS | 25/25 | 25 | 12 | 0 | 7 |
| `method_brace_style` = `next_line` | dprint | 24/25 | 24 | 16 | 0 | 1 |
| `method_brace_style` = `next_line` | clang-format | 25/25 | 25 | 14 | 0 | 0 |
| `method_brace_style` = `next_line` | ESLint+@stylistic | 22/25 | 22 | 7 | 0 | 5 |
| `block_brace_style` = `next_line` | TS LS | 14/14 | 12 | 6 | 0 | 2 |
| `block_brace_style` = `next_line` | dprint | 13/14 | 11 | 0 | 1 | 0 |
| `block_brace_style` = `next_line` | ESLint+@stylistic | 12/14 | 10 | 0 | 2 | 0 |
| `use_semicolon_after_statement` = `false` | prettier | 6/7 | 6 | 0 | 0 | 0 |
| `use_semicolon_after_statement` = `false` | biome | 4/7 | 4 | 0 | 0 | 0 |
| `use_semicolon_after_statement` = `false` | dprint | 7/7 | 7 | 0 | 0 | 0 |
| `use_semicolon_after_statement` = `false` | TS LS | 7/7 | 7 | 1 | 0 | 0 |
| `use_semicolon_after_statement` = `false` | ESLint+@stylistic | 5/7 | 5 | 2 | 0 | 0 |
| `force_quote_style` = `true` | prettier | 6/7 | 6 | 0 | 0 | 0 |
| `force_quote_style` = `true` | biome | 4/7 | 4 | 0 | 0 | 0 |
| `force_quote_style` = `true` | dprint | 7/7 | 7 | 0 | 0 | 0 |
| `force_quote_style` = `true` | ESLint+@stylistic | 5/7 | 5 | 3 | 0 | 0 |
| `enforce_trailing_comma` = `whenmultiline` | prettier | 5/6 | 5 | 0 | 0 | 0 |
| `enforce_trailing_comma` = `whenmultiline` | biome | 3/6 | 3 | 0 | 0 | 0 |
| `enforce_trailing_comma` = `whenmultiline` | dprint | 6/6 | 6 | 0 | 0 | 0 |
| `enforce_trailing_comma` = `whenmultiline` | ESLint+@stylistic | 4/6 | 4 | 2 | 0 | 0 |
| `enforce_trailing_comma` = `remove` | dprint | 6/6 | 4 | 0 | 0 | 0 |
| `enforce_trailing_comma` = `remove` | ESLint+@stylistic | 4/6 | 3 | 1 | 0 | 0 |
| `spaces_within_if_parentheses` = `true` | TS LS | 8/8 | 8 | 0 | 0 | 0 |
| `spaces_within_if_parentheses` = `true` | ESLint+@stylistic | 5/8 | 5 | 0 | 0 | 0 |
| `spaces_within_if_parentheses` = `true` | dprint | 7/8 | 7 | 6 | 0 | 2 |
| `spaces_within_brackets` = `true` | TS LS | 4/4 | 4 | 0 | 0 | 0 |
| `spaces_within_brackets` = `true` | ESLint+@stylistic | 1/4 | 1 | 1 | 0 | 0 |
| `spaces_within_imports` = `true` | dprint | 2/2 | 2 | 0 | 0 | 0 |
| `spaces_within_imports` = `true` | prettier | 1/2 | 1 | 0 | 0 | 0 |
| `indent_size` = `2` | prettier | 9/10 | 9 | 1 | 0 | 1 |
| `indent_size` = `2` | biome | 8/10 | 8 | 1 | 0 | 1 |
| `indent_size` = `2` | dprint | 9/10 | 9 | 2 | 0 | 1 |
| `indent_size` = `2` | TS LS | 10/10 | 10 | 4 | 0 | 3 |
| `indent_size` = `2` | ESLint+@stylistic | 9/10 | 9 | 3 | 0 | 3 |
| `indent_case_from_switch` = `false` | TS LS | 3/3 | 3 | 2 | 0 | 0 |
| `indent_case_from_switch` = `false` | ESLint+@stylistic | 3/3 | 3 | 2 | 0 | 1 |
| `indent_case_from_switch` = `false` | clang-format | 3/3 | 3 | 0 | 0 | 1 |
| `keep_blank_lines_in_code` = `1` | ESLint+@stylistic | 2/4 | 2 | 2 | 0 | 0 |
| `keep_blank_lines_in_code` = `0` | ESLint+@stylistic | 2/4 | 2 | 1 | 0 | 0 |
| `spaces_around_arrow_function_operator` = `false` | ESLint+@stylistic | 3/6 | 3 | 3 | 0 | 3 |
| `spaces_within_interpolation_expressions` = `true` | TS LS | 4/4 | 4 | 2 | 0 | 0 |
| `spaces_within_interpolation_expressions` = `true` | ESLint+@stylistic | 2/4 | 2 | 1 | 0 | 0 |
| `else_on_new_line` = `true` | dprint | 3/3 | 3 | 0 | 0 | 0 |
| `else_on_new_line` = `true` | ESLint+@stylistic | 2/3 | 2 | 1 | 0 | 0 |
| `else_on_new_line` = `true` | clang-format | 3/3 | 3 | 1 | 0 | 0 |
| `align_object_properties` = `1` | ESLint+@stylistic | 7/8 | 6 | 0 | 0 | 1 |
| `space_after_unary_not` = `true` | ESLint+@stylistic | 1/2 | 1 | 1 | 0 | 1 |
| `max_line_length` = `80` | prettier | 23/25 | 5 | 0 | 12 | 0 |
| `max_line_length` = `80` | biome | 22/25 | 5 | 0 | 11 | 0 |
| `max_line_length` = `80` | dprint | 24/25 | 5 | 0 | 13 | 0 |
| TS `space_before_type_colon` = `true` | TS LS | 5/5 | 5 | 1 | 0 | 1 |
| TS `space_before_type_colon` = `true` | ESLint+@stylistic | 4/5 | 4 | 1 | 0 | 1 |
| TS `space_before_type_colon` = `true` | dprint | 5/5 | 5 | 1 | 0 | 1 |
| TS `spaces_within_object_type_braces` = `false` | dprint | 4/4 | 4 | 1 | 0 | 0 |
| TS `spaces_within_object_type_braces` = `false` | ESLint+@stylistic | 3/4 | 3 | 0 | 0 | 0 |
| TS `spaces_within_object_literal_braces` = `true` | prettier | 7/9 | 7 | 0 | 0 | 0 |
| TS `spaces_within_object_literal_braces` = `true` | biome | 4/9 | 4 | 0 | 0 | 0 |
| TS `spaces_within_object_literal_braces` = `true` | dprint | 8/9 | 8 | 0 | 0 | 0 |
| TS `spaces_within_object_literal_braces` = `true` | TS LS | 9/9 | 9 | 4 | 0 | 1 |
| TS `spaces_within_object_literal_braces` = `true` | ESLint+@stylistic | 7/9 | 7 | 2 | 0 | 1 |
| TS `method_brace_style` = `next_line` | TS LS | 35/35 | 35 | 13 | 0 | 8 |
| TS `method_brace_style` = `next_line` | dprint | 35/35 | 35 | 17 | 0 | 1 |
| `force_quote_style` = `true` | clang-format | 7/7 | 7 | 1 | 0 | 0 |
| `indent_size` = `2` | clang-format | 10/10 | 10 | 3 | 0 | 1 |
| `keep_blank_lines_in_code` = `1` | clang-format | 4/4 | 2 | 1 | 0 | 0 |
| `keep_blank_lines_in_code` = `0` | clang-format | 4/4 | 4 | 2 | 0 | 0 |
| `max_line_length` = `80` | clang-format | 25/25 | 6 | 1 | 19 | 0 |
</details>

## Sources

Research Corpus (read-only, `~/Projects/phpstorm-editorconfig/`):

- `README.md`: the per-language counts of `verified-effect` Options, the Shell Script / shfmt note, and the record format.
- `data/behavior/index.json` and `data/behavior/{php,javascript,typescript}/*.json`: the Behaviour Records used as the expected output.
- `docs/notes/BEHAVIOR-NOTES.md`: the method of the records (PhpStorm's command-line formatter, one setting per scheme).
- `docs/languages/shell-script.md`: PhpStorm's Shell Script formatter is the external `shfmt`; the Options map to the flags `-i`, `-bn`, `-ci`, `-sr`, `-kp`, `-mn`.
- `data/code-samples/*/WRAPPING_AND_BRACES_SETTINGS.txt`: the timing inputs.

Formatter references (primary):

- IntelliJ Platform SDK, Code Formatter (the formatting model computes the whitespace between blocks): https://plugins.jetbrains.com/docs/intellij/code-formatting.html
- Prettier, What is Prettier ("removes all original styling", "reprints it from scratch"): https://prettier.io/docs/ and source https://github.com/prettier/prettier/blob/main/docs/index.md
- Prettier options and option philosophy: https://prettier.io/docs/options, https://prettier.io/docs/option-philosophy; `prettier --help` 3.9.10 (`--range-start`, `--range-end`)
- @prettier/plugin-php options: https://github.com/prettier/plugin-php/blob/main/src/options.mjs (0.26.0, from the npm package)
- @prettier/plugin-xml options: https://github.com/prettier/plugin-xml/blob/main/README.md
- php-cs-fixer rules: https://cs.symfony.com/doc/rules/index.html; `php-cs-fixer list-rules` and `fix --help` (3.95.27)
- PHP_CodeSniffer sniffs and properties: https://github.com/PHPCSStandards/PHP_CodeSniffer/wiki/Customisable-Sniff-Properties; `phpcs -i` and `phpcs -e` (4.0.4)
- mago formatter settings: `mago config --show formatter --schema` and `--default`, and `mago fmt --help` (1.59.0); https://github.com/carthage-software/mago
- biome configuration: `configuration_schema.json` in `@biomejs/biome` 2.6.4; https://biomejs.dev/reference/configuration/; `biome format --help`
- dprint-plugin-typescript configuration schema: https://plugins.dprint.dev/dprint/dprint-plugin-typescript/0.96.1/schema.json; docs https://dprint.dev/plugins/typescript/config/; `dprint fmt --help` 0.64.3 (`--stdin`, `--lines`)
- ESLint Stylistic rules: https://eslint.style/rules (rule list from `@stylistic/eslint-plugin` 5.10.0 `dist/rules`)
- TypeScript `FormatCodeSettings` and `getFormattingEditsForRange`: https://github.com/microsoft/TypeScript/blob/main/src/services/types.ts and `lib/typescript.d.ts` (6.0.3)
- clang-format style options: https://clang.llvm.org/docs/ClangFormatStyleOptions.html; `clang-format --help` 23.1.3 (`--lines`, `--offset`)
- malva configuration: https://github.com/g-plane/malva/blob/main/malva/src/config.rs; README https://github.com/g-plane/malva
- markup_fmt configuration: https://github.com/g-plane/markup_fmt/blob/main/markup_fmt/src/config.rs; README https://github.com/g-plane/markup_fmt
- shfmt manual: https://github.com/mvdan/sh/blob/master/cmd/shfmt/shfmt.1.scd
- sql-formatter options: https://github.com/sql-formatter-org/sql-formatter/blob/master/README.md
- SQLFluff rules: https://docs.sqlfluff.com/en/stable/reference/rules.html
- yamlfmt configuration: https://github.com/google/yamlfmt/blob/main/docs/config-file.md
- dprint-plugin-json: https://github.com/dprint/dprint-plugin-json
- kulala-fmt: https://github.com/mistweaverco/kulala-fmt
