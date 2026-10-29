# Can Behaviour Records run as automated golden tests?

Research for issue #6 (map: issue #1). Primary source: the Research Corpus at
`~/Projects/phpstorm-editorconfig/` (PhpStorm 2026.2.3), read on 2026-10-29. All
paths below are relative to the corpus root unless they start with `docs/research/`.
Counts come from `jq`/Python scans of the files named in each claim (scripts
reproduced in "How the counts were made").

## Answer

**Yes for the formatter, with a thin adapter. Yes for Arrangement, from the case
directories.** No PhpStorm is needed at test time.

- Each formatter Behaviour Record (`data/behavior/<language>/<key>.json`, 1,201
  records) holds the exact input text (`.inputs`), the Code Style delta for each run
  (`.results[].base_settings` plus the Option value in `.results[].value` /
  `.internal`), and the complete expected output. The output is in
  `.results[].changed_files[<file>].output`, or, for files the value did not change,
  in `.base_outputs[<base>][<file>]`. All 28,074 stored diffs can be rebuilt from
  those outputs (28,034 byte-exact, and 40 differ only by a missing
  "no newline at end of file" marker). So the outputs are complete, not excerpts.
- **Runnable formatter goldens:** 1,063 Options (1,059 `verified-effect` + 4
  `no-visible-effect` with stored inputs). They give **47,766 distinct
  (Code Style, input) → output cases** (52,886 before deduplication), 24,514 of them
  SQL. 20 cases are excluded because of the one nondeterministic construct. The table
  for each language is under "Runnable cases for each language".
- **Runnable Arrangement goldens:** 605 IDE cases in
  `tests/gui/arrangement/<lang>/<topic>/<case>/` (`input.*`, `arrangement.xml`,
  `output.*`). They are referenced by 171 `arrangement-*` records.
- **Determinism:** outputs are byte-stable except
  `ij_{javascript,typescript}_align_var_statements = 2` on three files (values: about
  35–50 % of runs flip), and 4 non-idempotent JavaScript Arrangement cases.
- **What the "must match for each Option" target still lacks** (details under "Gaps"):
  1. 108 `untestable-via-cli` Options have no golden.
  2. 30 `no-visible-effect` records store no inputs, so they can be tested only as
     "the output does not change".
  3. Records store only the inputs that some value changed. The "no effect on the other
     files" results exist only in the scratch cache `work/*/cache`.
  4. `base_settings` uses scheme-XML field names, not Option keys, so a translation
     table is needed (about 64 % map directly, about 22 % are SQL dialect choices).
  5. Coverage is thin for many Options: 755 of 1,059 `verified-effect` Options have
     exactly one value with a visible effect, and many have 1–3 inputs.
  6. Presets, the Arrangement items of A7, and Stylus were never run.
  7. Passing the goldens proves a match only on the recorded inputs. It does not prove
     a general match with PhpStorm.

## 1. Formatter record shape

Source: `data/behavior/php/ij_php_align_assignments.json` (trimmed; the field set is
the same in all 1,201 formatter records, from a key scan of `data/behavior/*/*.json`).

```jsonc
{
  "key": "ij_php_align_assignments",          // Option key (ij_* or, e.g. SQL, a field name)
  "language": "php",
  "ui_tab": "Wrapping and Braces", "ui_group": null,
  "ui_label": "Align consecutive assignments",
  "parent_option": "ij_php_assignment_wrap",
  "field": "PhpCodeStyleSettings.ALIGN_ASSIGNMENTS",
  "scheme_xml_location": ["custom", "ALIGN_ASSIGNMENTS"],
  "default": "false", "default_internal": "false",
  "test_inputs_dir": "tests/formatter/php/wrapping_and_braces",
  "description": "...", "notes": "...", "evidence": null,
  "suggested_tests": ["two consecutive '.=' / '??=' assignments ...", "..."],
  "inputs": {                                  // only files some value changed (see §6.3)
    "inline_comments.php": "<?php\n$a = 1; // first\n$bbbbb = 2; // second\n$cc = 3; // third\n\nfoo(); // call\n$longerVariable = bar(); // another\n",
    "...": "..."
  },
  "base_outputs": {                            // full output of each base scheme, per input
    "Default": { "inline_comments.php": "<?php\n$a = 1; // first\n..." },
    "ij_php_assignment_wrap = Wrap always": { "...": "..." },
    "ij_php_assignment_wrap = Chop down if long": { "...": "..." }
  },
  "results": [
    {
      "base": "Default", "base_settings": {},
      "value": "true", "ui": "checked", "internal": "true", "is_default": false,
      "effect": "Pads the target of each assignment ...",
      "changed_files": {
        "inline_comments.php": {
          "output": "<?php\n$a     = 1; // first\n$bbbbb = 2; // second\n$cc    = 3; // third\n\nfoo(); // call\n$longerVariable = bar(); // another\n",
          "diff": "--- default/inline_comments.php\n+++ changed/inline_comments.php\n@@ -1,6 +1,6 @@ ..."
        }
      }
    },
    { "base": "Default", "base_settings": {}, "value": "false", "is_default": true, "changed_files": {} },
    { "base": "ij_php_assignment_wrap = Wrap always",
      "base_settings": {"common:ASSIGNMENT_WRAP": "2"}, "value": "true", "...": "..." }
  ],
  "status": "verified-effect", "status_reason": null, "undescribed_results": []
}
```

Optional fields: `ide_verification` (46 records), `status_from_diffs` (6 records;
only Sass `keep_single_line_blocks` differs from `status`). The 2 files under
`data/behavior/_validation/` are harness checks, not records.

### How a test is built (no PhpStorm)

```
for each record (no record_type) whose status != "untestable-via-cli":
  for each r in record.results:
    code_style = NothingSet(language) ⊕ translate(r.base_settings) ⊕ {record.key: r.value}
    for (file, input) in record.inputs:
      expected = r.changed_files[file].output  if file in r.changed_files
                 else record.base_outputs[r.base][file]
      assert format(input, code_style) == expected
```

- The Option value has three spellings in each result: `value` (the `.editorconfig`
  spelling, e.g. `on_every_item`), `ui` (the Menu label, e.g. "Chop down if long"),
  and `internal` (the scheme-XML value, e.g. `5`)
  (`data/behavior/php/ij_php_assignment_wrap.json` → `.results[]`).
- The base outputs are goldens too: `NothingSet ⊕ translate(base_settings)` →
  `base_outputs[base]`. The `Default` base is the "nothing set" Code Style
  (`docs/notes/BEHAVIOR-NOTES.md` § "Catalog default versus real default").
- The diffs are against the base output (`--- default/…`, `+++ changed/…`, 2 context
  lines). A test needs only `output`.
- Checked consistency (scan of all records): `set(inputs)` equals the union of
  `changed_files` keys in every `verified-effect` record (1,059/1,059). Every
  `base_outputs[base]` covers every input. No result names a base that is missing.

### How the runs were made

Each value is written into a scheme that differs from the Default scheme only in that
field. The scheme is run through `phpstorm format -s scheme.xml files…` on all inputs
of the tab, and the result is diffed against the base run (`docs/notes/BEHAVIOR-NOTES.md`
§ "Method"; `tools/behavior/run_tab.py` lines 226–330; `tools/behavior/fmt.py`). The
scheme for the default value on a non-Default base is skipped because it is the base
itself (`run_tab.py`, "identical to the base scheme itself").

## 2. "Base" schemes (Option interactions)

Source: `docs/notes/BEHAVIOR-NOTES.md` § "Method" step 2; `tools/behavior/run_tab.py`
(plan loop: `bases = [("Default", …)]`, parent-wrap bases, `combos`,
`dialect_bases`).

- A base is a labelled Code Style that the Option is applied on top of. It is stored
  three times: the label in `.results[].base`, the delta in `.results[].base_settings`,
  and the full outputs in `.base_outputs[<label>]`.
- Kinds of base:
  - **Parent wrap.** Each sub-option of a wrap Option is also run with the parent set
    to "Wrap always" (`2`) and "Chop down if long" (`5`).
  - **Hand-picked combos.** From `tools/behavior/specs/<lang>.json` → `tabs.<tab>.combos`.
  - **SQL dialects.** From `dialect` / `dialect_bases`.
- Counts (non-`untestable` records): 1,093 records. 463 of them have only the Default
  base. There are 1,054 distinct (language, base label) pairs. 3,814 of 6,524 results
  are on a non-Default base: 2,377 SQL and 1,437 in other languages. Most bases change
  1 field (2,689 results), but some change up to 25 fields (scan of `.results[]`).
- `base_settings` keys use scheme-XML locations, not Option keys:

  | Prefix | Example (file → key) | Meaning |
  |---|---|---|
  | `common:` | `blade/HtmlCodeStyleSettings.HTML_UNIFORM_INDENT.json` → `common:INDENT.INDENT_SIZE` | `<codeStyleSettings language=…>` of this language |
  | `custom:` | `css/ij_css_align_closing_brace_with_properties.json` → `custom:BRACE_PLACEMENT` | the language's custom tag |
  | `tag:<Tag>:` | `blade/ij_continuation_indent_size.json` → `tag:HTMLCodeStyleSettings:HTML_ALIGN_ATTRIBUTES` | another settings tag |
  | `lang:<Lang>:` | `…HTML_UNIFORM_INDENT.json` → `lang:HTML:INDENT.INDENT_SIZE` | another language's common block |
  | `root:` | `general/ij_formatter_off_tag.json` → `root:FORMATTER_ON_TAG` | scheme root |
  | `ecfile:` | `general/insert_final_newline.json` → `ecfile:trim_trailing_whitespace` | a root `.editorconfig` written next to the inputs |
  | `otherindent:` | `other-file-types/ij_smart_tabs.json` → `otherindent:USE_TAB_CHARACTER` | Other File Types indent |
  | `dialect:` | `sql/CASEDIALECT_BUILT_IN.json` → `dialect:` = `SQL92` | SQL dialect of the file (not a scheme field) |

- Mapping coverage (scan): of 7,378 `base_settings` entries, 4,748 (64 %) match the
  `scheme_xml_location` of some formatter record, so they map to an Option key.
  1,620 (22 %) are SQL `dialect:`, which is a property of the buffer and not an
  Option. 1,010 (14 %) match no record. Most of these are SQL dialect-page tags
  (`tag:MSSQLCodeStyleSettings:…` and similar, 81–86 each), and the rest are
  cross-language `lang:` fields in `general`. The 14 % need a hand-made translation
  table, or scheme-level support in the test adapter.

## 3. `no-visible-effect` and `untestable-via-cli`

Statuses are defined in `docs/notes/BEHAVIOR-NOTES.md` § "Statuses". The counts are
in `data/behavior/index.json` → `.options[].status` and in the README summary.
Formatter records: 1,059 verified-effect, 34 no-visible-effect, 108
untestable-via-cli. Arrangement records: 157 verified-effect, 14 no-visible-effect.

**`no-visible-effect` (34 formatter Options).** This is a conclusion backed by a
control, by prerequisites, by the construct being present in the inputs, by a
bytecode reader, and by a real-settings run (§ "What a no-effect conclusion needs").
- 30 records store no `inputs`, and their `base_outputs[*]` are empty objects. Their
  results all have empty `changed_files` (e.g.
  `data/behavior/blade/HtmlCodeStyleSettings.HTML_UNIFORM_INDENT.json`: 5 bases,
  6 results, 0 files). The test is an **invariance test**: read the files of
  `test_inputs_dir` from disk, and check that every recorded value on every recorded
  base gives the same output as the base. On the Default base, the expected output
  can come from sibling records of the same tab. 853 of 909 tab input files have a
  Default output in at least one record. For non-Default bases there is no stored
  output, so only the invariance holds.
- 4 records have inputs and run as normal goldens.
- Sass `ij_sass_keep_single_line_blocks` is forced to `no-visible-effect` by
  `status_override`. Its stored diff is real but comes from invalid Sass
  (`docs/notes/BEHAVIOR-NOTES.md` § "Statuses"). A golden test would still check
  that diff.
- The no-effect audits refuted 2 of 30 conclusions, and both were fixed
  (`BEHAVIOR-NOEFFECT-AUDIT-1.md`, `-2.md`, as summarised in BEHAVIOR-NOTES).

**`untestable-via-cli` (108 Options).** These Options cannot be golden-tested from the
records. The reasons are in the README table "Options the command-line formatter
cannot show": editor actions/code generation (40), commenter (28), display only (12),
typing-time (10), Shell Script shfmt (9), Other File Types (5), Vue interpolation (4).
- 99 records store no inputs. 9 records (`general/autodetect_indents`, `end_of_line`,
  `ij_visual_guides`, `ij_wrap_on_typing`, and 5 in `other-file-types`) store CLI
  outputs. Those outputs show only that the CLI ignores the Option, so they must not
  be used as goldens.
- 35 of them have an `ide_verification` block with IDE output files under
  `tests/gui/` (README table "IDE-verified among the CLI-untestable";
  `docs/notes/BEHAVIOR-NOTES.md` § "GUI verification"). The two groups that matter for
  the formatter are:
  - Vue interpolation: 4 Options. `tests/gui/vue/` holds `input.vue`,
    `input_multiline.vue`, and `<tag>.vue` + `<tag>.editorconfig` for each of the
    16+ combinations.
  - Shell Script through shfmt: 7 Options, in `tests/gui/shell/`.

  Each of these is **one run per combination, not repeated**, so it is weaker than a
  Behaviour Record. The commenter and Optimize Imports checks are editor actions, not
  formatting.

## 4. Determinism

Source: `docs/notes/BEHAVIOR-DETERMINISM.md`.

- There is one nondeterministic construct, inside PhpStorm itself:
  `align_var_statements = 2` ("When grouped") in JavaScript and TypeScript. On a line
  like `var a = 1, b = 2;`, the second and later declarators are padded in about
  35–50 % of runs (36/70 and 25/70 runs over two schemes). It becomes stable with
  `-XX:hashCode=2`.
  - Affected cases: `vars.*`, `r3_wrap2.*` and `r4_ts_calls.ts` under value 2 in
    `data/behavior/{javascript,typescript}/ij_*_align_var_statements.json`. That is 20
    (result, file) cases in the scan (8 JS, 12 TS).
  - The note's advice: align the first `=`, do not pad the later ones, and do not
    test against those files.
- No other variation was found. 230 other (scheme, input set) pairs were re-run and
  were byte-identical. The pairs were a random sample of 40 across all languages
  (3 re-runs each) and 190 alignment schemes (2 re-runs each).
- Line endings: tabs without `keep_cr` read inputs with universal newlines and write
  LF (`tools/behavior/run_tab.py` `rd`, `tools/behavior/fmt.py` `write_text`). So
  `tests/formatter/php/blank_lines/keep_contexts_crlf.php` and `r2_crlf_tight.php`
  are CRLF on disk but LF in the records and in the run. The records stay
  self-consistent goldens (LF in → output), but they say nothing about CRLF input.
  Only the `general` tabs keep `\r` (`tools/behavior/specs/general.json`
  `keep_cr: true`). Test fixtures must therefore come from the record `inputs`, not
  from the disk files.
- Real default versus catalog default: there are 2 mismatches in 994 Options,
  TypeScript `force_semicolon_style` and General `trim_trailing_whitespace`
  (`docs/notes/BEHAVIOR-DEFAULTS-CHECK.md`). The test Code Style must be "nothing
  set", and `default_internal` gives the real default.

## 5. Arrangement cases as tests

Sources: `docs/notes/BEHAVIOR-ARRANGEMENT-DATA.md`, `docs/notes/BEHAVIOR-NOTES.md`
§ "Arrangement", `tests/gui/arrangement/run.py`, the case directories, and
`data/arrangement.json`.

**Case shape** (`tests/gui/arrangement/php/mods/<case>/`):

```
input.php          the file before Code > Rearrange Code
arrangement.xml    <arrangement><rules><section><rule><match><PUBLIC>true</PUBLIC></match>
                   <order>BY_NAME</order></rule></section></rules></arrangement>
output.php         IDE result
run.json           {"changed": true, "idempotent": true, "retried": false, "secs": 30.5}
output2.php        only if a second run changed the file (4 cases)
recheck.json       only for rechecked unchanged cases (54)
```

**Record shape** (`data/behavior/arrangement-php/arrangement_php_alias_modifiers.json`):
`record_type: "arrangement"`, `syntax`, `method: "IDE Rearrange Code"`,
`ide_verified: true`, `slices`, `evidence` (case dirs). In each `.results[]`, `value`
is the one-line `arrangement.xml`, `case` is the case path, `effect` is the
description, `changed_files["input.<ext>"]` holds `{output, diff}`, and `run` is a
copy of `run.json`. **The record does not store the input text**, so the case
directory is the golden source.

**Test:**

```
for case in tests/gui/arrangement/<lang>/*/*/:
  rules = case/arrangement.xml == "default"
            ? data/arrangement.json .rearrangers[<R>].default_settings_xml
            : parse(case/arrangement.xml)          # <arrangement> or a whole <codeStyleSettings language=…>
  assert arrange(read(case/input.*), rules, code_style = NothingSet) == read(case/output.*)
```

- In 113 cases `arrangement.xml` is the word `default`, so the default rules must come
  from `data/arrangement.json`. That file has `default_settings_xml`,
  `default_sections`, `default_groupings` and `rule_aliases` for 8 rearrangers
  (Angular2Html, CSS, HTML, JavaScript, PHP, TypeScript, Vue, XML).
- 22 cases use a whole `<codeStyleSettings language="…">` block. Examples: JavaScript
  rules for an HTML `<script>`
  (`html/embedded/e02_script_js_methods_by_name/arrangement.xml`), and the CSS-family
  blocks `CSS`/`SCSS`/`LESS`/`SASS`. So the adapter needs Arrangement for more than
  one language.
- Arrangement output depends on formatter Options. In PHP the gaps between moved
  entries become N blank lines, where N comes from the Code Style (for example
  `BLANK_LINES_AROUND_METHOD`). JS/TS use a refined formula. Markup and CSS never
  touch blank lines (BEHAVIOR-NOTES § "Arrangement", "Blank-line rule"). The cases
  ran with the Default Code Style, so the test must use "nothing set" too.

| Arrangement lang | cases | changed | unchanged | rechecked (settle 8) | `default` | `<codeStyleSettings>` fragment | idempotent | non-idempotent | idempotency not run |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| angular | 3 | 3 | 0 | 0 | 2 | 0 | 3 | 0 | 0 |
| css | 48 | 42 | 6 | 0 | 1 | 4 | 48 | 0 | 0 |
| html | 57 | 43 | 14 | 14 | 19 | 6 | 56 | 0 | 1 |
| javascript | 76 | 71 | 5 | 5 | 27 | 0 | 57 | 4 | 15 |
| less | 10 | 8 | 2 | 0 | 1 | 2 | 10 | 0 | 0 |
| php | 306 | 274 | 32 | 32 | 31 | 0 | 116 | 0 | 190 |
| sass | 9 | 4 | 5 | 0 | 1 | 5 | 9 | 0 | 0 |
| scss | 19 | 16 | 3 | 0 | 1 | 2 | 19 | 0 | 0 |
| typescript | 40 | 39 | 1 | 1 | 13 | 0 | 21 | 0 | 19 |
| vue | 19 | 18 | 1 | 1 | 11 | 3 | 19 | 0 | 0 |
| xml | 18 | 17 | 1 | 1 | 6 | 0 | 18 | 0 | 0 |
| **Total** | **605** | **535** | **70** | **54** | **113** | **22** | **376** | **4** | **225** |

(Scan of `tests/gui/arrangement/*/*/*/run.json`, `arrangement.xml` and `recheck.json`.)

Caveats:
- **Non-idempotent cases.** 4 JavaScript cases change again on a second run
  (`javascript/types/j16_getter_setter_mismatch`, `groups/ov_keep`,
  `ovs/ovs1_keep`, `ovs/ovs3_static_accessor_keep`; there is no model for them, per
  BEHAVIOR-NOTES "Open arrangement questions"). Test them against the first-run
  `output` and leave idempotency out.
- **Unchanged cases.** For the 70 cases where the output equals the input, a false
  negative is possible (the IDE had not loaded the scheme yet). 54 of them were
  rerun with `--settle 8`, and 0 flipped (`BEHAVIOR-ARRANGEMENT-RECHECK.md`). The 16
  CSS-family cases were rerun with settle 5 or verified with a marker.
- **No independent review.** The Arrangement records were never spot-checked. This
  matters for the descriptions, not for the raw input/output goldens.
- **Hand-written XML.** The XML for inverted atoms and for `OVERRIDDEN` as a modifier
  was written by hand and never confirmed by an IDE-written `Project.xml`.

## 6. Runnable cases for each language

Formatter goldens. Each case is (Code Style, input file) → expected output, for
`verified-effect` records and `no-visible-effect` records with inputs. Excluded:
`untestable-via-cli` and the 20 nondeterministic cases. "Distinct" removes the
Default-base outputs that are repeated across the records of a tab.

| Language | Options with goldens | cases | distinct cases | distinct Code Styles | inputs with a Default golden | cases for each Option (min/median) | no-effect results without inputs (invariance only) |
|---|---:|---:|---:|---:|---:|---:|---:|
| blade | 33 | 748 | 595 | 94 | 21 | 2/16 | 14 |
| css | 21 | 532 | 449 | 73 | 23 | 6/24 | 0 |
| editorconfig | 6 | 111 | 93 | 16 | 13 | 12/15 | 0 |
| general (multi-language) | 12 | 1,666 | 1,614 | 81 | 54 | 8/57 | 0 |
| gherkin | 4 | 86 | 82 | 17 | 5 | 10/18 | 11 |
| html | 30 | 682 | 586 | 92 | 18 | 3/17 | 0 |
| http-request | 8 | 272 | 267 | 63 | 13 | 4/10 | 0 |
| javascript | 152 | 3,274 | 2,561 | 368 | 68 | 1/12 | 3 |
| json | 18 | 1,562 | 1,492 | 141 | 31 | 5/28 | 12 |
| less | 22 | 722 | 605 | 74 | 31 | 2/25 | 0 |
| markdown | 21 | 424 | 400 | 101 | 23 | 2/16 | 6 |
| mermaid | 36 | 333 | 254 | 61 | 27 | 2/10 | 11 |
| php | 230 | 9,635 | 8,447 | 802 | 146 | 2/12 | 24 |
| sass | 18 | 122 | 106 | 46 | 10 | 2/4 | 9 |
| scss | 22 | 748 | 628 | 74 | 31 | 2/27 | 0 |
| sql | 203 | 25,718 | 24,514 | 2,608 | 127 | 2/48 | 0 |
| twig | 32 | 746 | 591 | 94 | 24 | 3/18 | 12 |
| typescript | 159 | 4,978 | 4,005 | 411 | 97 | 1/18 | 3 |
| vue-template | 8 | 133 | 125 | 31 | 5 | 3/15 | 0 |
| xml | 17 | 223 | 195 | 64 | 10 | 3/12 | 11 |
| yaml | 11 | 171 | 157 | 37 | 15 | 2/9 | 0 |
| other-file-types | 0 | 0 | 0 | 0 | 0 | – | 0 |
| shell-script | 0 | 0 | 0 | 0 | 0 | – | 0 |
| **Total** | **1,063** | **52,886** | **47,766** | **5,348** | **792** | | **116** |

Arrangement goldens: 605 cases (table in § 5). They are referenced 740 times by the
171 `arrangement-*` records (README table "Arrangement records").

Notes:
- `general` inputs are several file types: 37 `.php`, 12 `.js`, 7 `.yaml`, 6 `.md`,
  6 `.json`, 6 `.html`, 5 `.xml`, 5 `.css`, 3 `.ini`, 2 `.http`
  (`find tests/formatter/general`). Its goldens need the Language Plugins of those
  languages.
- Blade, Twig, Vue, HTML and inline-HTML PHP inputs contain embedded CSS/JS, and their
  outputs depend on HTML, CSS and JavaScript Options (BEHAVIOR-NOTES § "Findings from
  the later tabs"; `HTML_UNIFORM_INDENT` evidence). Their goldens need more than one
  Language Plugin.
- SQL cases also need the SQL dialect of the buffer. 1,620 base entries set it
  (BEHAVIOR-NOTES § "SQL").
- Option keys are not all `ij_*`. 299 non-Arrangement index entries use other keys:
  all 207 SQL field names, prefixed keys such as `html.indent_size` in Blade/Twig, and
  plain `.editorconfig` keys (`data/behavior/index.json` → `.options[].key`).

## 7. Gaps for "must match for each Option"

1. **No golden for `untestable-via-cli`.** 108 Options. Following map issue #1 ("never
   approximated"), they must be left out or flagged, or covered only by the single-run
   IDE files (Vue interpolation 4 and shfmt 7, if those are in scope).
2. **Invariance-only `no-visible-effect`.** 30 records (116 results) have no stored
   inputs or outputs. They can be tested only as "the value changes nothing", with
   inputs read from `test_inputs_dir`.
3. **Unchanged files are not stored.** A record keeps only the inputs that some value
   changed (1,059/1,059 records: `inputs` = union of `changed_files`). Summed over
   these records, their tab directories hold 20,957 input files, but only 6,764 are
   stored.
   - Every scheme was run on every input of its tab (`run_tab.py` → `fmt.run_many(todo,
     inputs, …)`), and the full outputs are cached in `work/*/cache/<sha>.json`
     (`{"scheme", "outputs"}`; 45 cache dirs, 24,602 files).
   - The cache key is `sha256(scheme_xml + sha256(inputs)[:16])[:20]`
     (`run_tab.py` lines 239, 297). So a read-only exporter could rebuild the full
     matrix and add the "no effect on this file" goldens, which guard against
     over-application of an Option.
   - The README calls `work/` scratch, and some cache entries belong to old input
     sets (BEHAVIOR-DETERMINISM § 2). An export must match the current input hash.
4. **Translation of `base_settings`.** About 14 % of the base entries do not map to any
   record's `scheme_xml_location` (§ 2). The adapter needs a scheme-field → Option
   table that covers the SQL dialect pages and the cross-language `lang:` fields, and
   it needs the dialect as a buffer property.
5. **Depth of coverage.** In `data/behavior/index.json`, `values_with_effect` has
   1 entry for 755 verified Options, 2 for 215, and 3 or more for 89. 76 Options with
   stored inputs have 1–3 cases in total (e.g. `php/ij_php_namespace_brace_style.json`: 1 input,
   2 values). Interactions cover only the recorded bases. Each record's
   `suggested_tests` lists the combinations that are left, and BEHAVIOR-NOTES
   § "Known gaps" says: "Options interact in many more ways than the bases cover".
   Passing all goldens therefore proves "matches the Behaviour Records", not "matches
   PhpStorm". New records need PhpStorm and `tools/behavior/run_tab.py` (headless, no
   licence; BEHAVIOR-NOTES § "Safety and environment"). That is a development-time
   dependency, not a test-time one.
6. **Default Code Style.** Each golden assumes all other Options are at PhpStorm's
   "nothing set" values, including those of the neighbouring languages. The values are
   in `data/default-scheme.editorconfig`, `data/defaults-by-language.json`, and in
   `default_internal` (2 mismatches with the catalog).
7. **Things never run.** Presets ("Set from…", `data/presets.json`: values known,
   effect not run). Arrangement A7 (Reformat with "Rearrange entries", Actions on Save,
   selection ranges). Stylus. SQL `ALIAS_CASE` and the name templates. CRLF input
   outside `general` (§ 4).
8. **Nondeterministic cases.** 20 cases must be skipped or relaxed (§ 4), and 4
   Arrangement cases are not idempotent (§ 5).
9. **Wording errors do not affect the goldens.** The spot-checks graded the
   descriptions (`effect`, `description`), not the outputs. Errors there matter only
   if someone implements from the prose. The raw outputs come straight from
   PhpStorm.

## How the counts were made

Python 3 over `data/behavior/*/*.json`, excluding `_validation/` and splitting by
`record_type`:
- Key, status and result counts.
- `inputs` against the union of `changed_files`.
- Base coverage.
- Diff rebuild with `difflib.unified_diff(n=2)` from `base_outputs[base][f]` to
  `changed_files[f].output`.
- `base_settings` prefixes against the set of `scheme_xml_location` values.
- Golden counts. A key is (language, base_settings + field = internal, sha1(input),
  file name). Results with `is_default` collapse to the base. The 20 cases in § 4 are
  skipped.

Arrangement counts come from `tests/gui/arrangement/*/*/*/{run.json, arrangement.xml,
recheck.json}`. Disk inputs come from `tests/formatter/<lang>/<tab>/`.

## Sources

- `README.md` § "Formatter behaviour", "Counts", "Known limits", "Spot-check and audit reports"
- `data/behavior/index.json` (`.options[].status`, `.values_with_effect`, `.key`)
- `data/behavior/<language>/<key>.json`, especially `php/ij_php_align_assignments.json`,
  `php/ij_php_assignment_wrap.json`, `blade/HtmlCodeStyleSettings.HTML_UNIFORM_INDENT.json`,
  `general/end_of_line.json`, `vue-template/ij_vue_interpolation_wrap.json`
- `data/behavior/arrangement-php/arrangement_php_alias_modifiers.json`
- `data/arrangement.json` (`.rearrangers[*].default_settings_xml`)
- `data/default-scheme.editorconfig`, `data/defaults-by-language.json`, `data/catalog.json`
- `tests/formatter/<language>/<tab>/`
- `tests/gui/arrangement/<lang>/<topic>/<case>/`, `tests/gui/arrangement/run.py`
- `tests/gui/vue/`, `tests/gui/shell/`
- `docs/notes/BEHAVIOR-NOTES.md` (Method, Statuses, Cross-cutting rules, Determinism,
  Catalog default, No-effect conclusion, GUI verification, Arrangement, Known gaps)
- `docs/notes/BEHAVIOR-DETERMINISM.md`, `docs/notes/BEHAVIOR-ARRANGEMENT-DATA.md`,
  `docs/notes/BEHAVIOR-DEFAULTS-CHECK.md`, `docs/notes/BEHAVIOR-ARRANGEMENT-RECHECK.md`
  (as summarised in BEHAVIOR-NOTES)
- `tools/behavior/run_tab.py` (lines 226–330), `tools/behavior/fmt.py` (lines 117–145),
  `tools/behavior/specs/*.json`
- `work/*/cache/*.json` (scratch run cache; only the format was inspected)

Glossary gap: "golden test" and "base scheme" are not `GLOSSARY.md` terms. This file
uses them in the corpus's sense, and they may need entries if the test strategy adopts
them.
