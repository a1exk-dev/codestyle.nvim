# Option data in the Research Corpus

Ticket: [#5](https://github.com/a1exk-dev/codestyle.nvim/issues/5), "What option data does the Research Corpus provide for a Language Plugin?" (map [#1](https://github.com/a1exk-dev/codestyle.nvim/issues/1)).

Source: the Research Corpus at `~/Projects/phpstorm-editorconfig/` (PhpStorm 2026.2.3, build 262.10968.76, Default scheme). All paths below are relative to that directory. Each JSON path is written as `file.json › path`. The counts were computed with `jq` and `python3` on the files as they were on 2026-10-29.

## Answer

The corpus has enough data to generate the Tabs, Options, value sets, defaults, limits, Presets, and Arrangement metadata of every language except SQL. No single file does it all, though. A generator must join three layers:

1. **Option facts** (key, type, default, values, range, label, Tab, group) are in `data/catalog.json › languages.<slug>.options[]`. It has 837 Options in 25 languages. **It is not complete per language**: it lists only the keys that the IDE's export writes into that language's section. Keys whose value equals `[*]` (indent size, tab size, Hard wrap at, Wrap on typing, Visual guides, …) are in `other_possible_keys` instead.
2. **UI layout** (Tab order, groups, control order, control kind, enable dependencies) is in `data/ui-structure.json › pages.<Page>.tabs.<Tab>` (91 Tabs). `catalog.json › languages.<slug>.ui_layout` is an identical copy. It comes in **five Tab shapes** (`option_tree`, `indent_options_editor`, `blank_lines_form`, `custom_panel`, `arrangement`), and each shape has its own node format.
3. **Side tables**: value sets (`data/enum-values.json`, 35 sets, also copied as `catalog.json › value_sets`), integer limits (`data/int-constraints.json`, 74 keys), labels for hand-built Tabs (`data/labels-supplement.json`), Presets (`data/presets.json`, 23), Arrangement (`data/arrangement.json`, 8 rearrangers), and Preview text (`data/code-samples/`, 294 files).

The data is accurate: every Tab is `screenshot_verified: true`, and 835 of 837 Options have a label. It is **not uniform**, though. Five things are free text only and need hand modelling: enable dependencies, the choices of boolean combos, the mapping from a Tab to its Preview sample, the Arrangement rule aliases (only PHP has them), and the "Set from… › Language" semantics. Also, the Preview samples are missing or useless for SQL (the file says `-- something goes wrong`), Shell Script, and XML. And one UI control can map to two keys, or 28 keys, or none. A general Option model therefore needs: a **control** that is separate from the **key(s)** it stores; a typed value with the `.editorconfig` spelling, UI label, and internal int; an "inherit" state (`-1`, `Default`, `global`, or unset); and dependencies as data that a Language Plugin writes by hand.

SQL is a separate case. It has no `.editorconfig` keys, so `catalog.json › languages.sql.options` is empty. Its 210 fields are in `data/sql-options.json` (not covered in detail here).

## Inventory

### Language identifiers differ per file

There is no single language ID. A generator needs this mapping (from `catalog.json › languages.<slug>.ui_layout` = `ui-structure.json › pages.<Page>`, `.domain`, and the `preview_samples` paths):

| catalog slug | ui-structure page | EditorConfig domain | code-samples dir | Options in catalog |
|---|---|---|---|---:|
| general | (root) Code Style | `[*]` | – | 14 |
| php | PHP | php | PHP | 239 |
| angular-html-template | Angular2Html | angular-html | Angular2Html | 0 |
| blade | Blade | blade | Blade | 1 |
| editorconfig | EditorConfig | editorconfig | EditorConfig | 6 |
| gherkin | Gherkin | gherkin | Gherkin | 2 |
| html | HTML | html | HTML | 26 |
| http-request | HTTP Request | http-request | HTTP_Request | 5 |
| javascript | JavaScript | javascript | JavaScript | 172 |
| json | JSON | json | JSON | 15 |
| makefile | Makefile | makefile | Makefile | 0 |
| markdown | Markdown | markdown | Markdown | 16 |
| mermaid | Mermaid | mermaid | Mermaid | 33 |
| shell-script | Shell Script | shell | Shell_Script | 8 |
| sql | – (SQL page has option trees, see `sql-options.json`) | – | SQL + `sql/<dialect>/` | 0 |
| css | CSS | css | CSS | 18 |
| less | LESS | less | LESS | 21 |
| sass | SASS | sass | SASS | 20 |
| scss | SCSS | scss | SCSS | 21 |
| twig | Twig | twig | Twig | 4 |
| typescript | TypeScript | typescript | TypeScript | 176 |
| vue-template | Vue | vue | Vue | 9 |
| xml | XML | xml | XML | 17 |
| yaml | yaml | yaml | yaml | 14 |
| other-file-types | Other File Types | `[*]` | – | 0 |

Presets name the language by display name (`"language": "PHP"`). Arrangement keys look like `"PHP (PhpRearranger)"`. The Behaviour Records use the catalog slug (`data/behavior/<slug>/`, `data/behavior/arrangement-<x>/`).

### `data/catalog.json`

Top level: `product`, `scheme`, `value_sets` (equal to `enum-values.json › value_sets`), `languages` (25 slugs).

Each language has these keys: `title`, `settings_page`, `globs`, `options`, `other_possible_keys`, `ui_layout`, `ui_labels`, `preview_samples`, `screenshots`, and where they apply, `presets` (php 12, javascript 3, css 1, sql 7) and `arrangement` (php, angular-html-template, html, javascript, css, typescript, vue-template, xml). `general` and `other-file-types` have no `preview_samples`. `sql` has no `ui_layout` or `other_possible_keys`.

**`options[]`** is sorted by key, not by UI order. Fields and how often they occur (of 837):

| Field | Count | Meaning |
|---|---:|---|
| `key` | 837 | EditorConfig name, for example `ij_php_align_assignments`, `indent_size` |
| `default` | 837 | Default value as an export string (`"false"`, `"4"`, `"end_of_line"`) |
| `type` | 837 | `boolean` 562, `enum` 136, `integer` 116, `comma_separated_list` 13, `string` 9, `visual_guides` 1 |
| `ui_kind` | 837 | `checkbox` 521, `int_field` 86, `combo` 67, `wrap_combo` 56, `list_field` 38, `none` 35, `checkbox+radio` 20, `text_field` 7, `radio` 7 |
| `label_source` | 837 | `ui-structure (exact field join)` 769, `labels-supplement (screenshot-verified)` 56, `labels-supplement` 10, `no control on this page (exported only)` 2 |
| `ui_label` | 835 | Label text |
| `ui_tab` | 802 | Tab name |
| `ui_group` | 514 | Group heading inside the Tab |
| `value_set`, `field` | 156 | Value-set name; IntelliJ field (`PhpCodeStyleSettings.NULL_TYPE_POSITION`) |
| `values` | 136 | `[{value, ui, int?}]` for enums, in UI order |
| `range` | 86 | `{min, max}` |

Example, `catalog.json › languages.php.options[0]`:

```json
{"key": "ij_continuation_indent_size", "default": "4", "type": "integer",
 "ui_label": "Continuation indent:", "ui_tab": "Tabs and Indents",
 "ui_kind": "int_field", "label_source": "ui-structure (exact field join)",
 "range": {"min": 0, "max": 32}}
```

**`other_possible_keys`** is a map from property to `{editorconfig_name, default, field, accessor, in_default_export}`. It lists keys that the section *can* contain. These are mostly the indent and margin keys that the language inherits from `[*]` when they are equal. For example, `languages.php.other_possible_keys` has `indent_size` (default `"4"`), `tab_width`, `indent_style`, `ij_smart_tabs`, `max_line_length` (default `null`), `ij_wrap_on_typing` (default `null`), `ij_visual_guides`, and `ij_php_OverrideLanguageOptions`. They have no label, kind, or Tab. Those come from `ui_layout`.

**`ui_labels`** is the flat label list of the page's search index (285 strings for PHP, including noise such as `"Default"` and `"Project"`). It is not useful for a model.

### `data/ui-structure.json`

Top level: `_about`, `pages` (25), `cross_page_options` (7), `dependencies_custom` (9), `set_from_language_menu`.

`pages.<Page>` = `{domain, screenshots, tabs, tabs_from_screenshots}`. `tabs` is an ordered object, and its key order is PhpStorm's Tab order (for example, Markdown starts with "Wrapping and Braces"). There are 91 Tabs, all `screenshot_verified: true`. By kind: `custom_panel` 28, `option_tree` 27, `indent_options_editor` 19, `blank_lines_form` 10, `arrangement` 7.

The five Tab shapes:

- **`option_tree`** (Spaces, Wrapping and Braces, the SQL tabs, and others): `tree[]` of nodes `{label, kind, field, option, editorconfig_name, choices?, min?, max?, special_default?, anchor?, anchor_option?, custom?}`. The node kinds over all trees are `checkbox` 481, `group` 106, `combo` 106, `wrap_combo` 57, `text_field` 13, `int_field` 8. The nesting is at most two levels. A top-level `group` or `wrap_combo` has `children`. The order is final: the `_about` says the IDE ordering code was run headless, so `anchor: BEFORE/AFTER` (16 nodes) and the `custom: true` options (75) are already in place. SQL nodes add `xml_option`, `visible_in[]`, and once, `choices_per_page`.
- **`indent_options_editor`** (Tabs and Indents): `controls_in_order[]` of Swing controls `{class: JCheckBox|JLabel|IntegerField|JRadioButton|ExpandableTextField, text, enabled, editorconfig_name, field?, label?}` and `dependencies[]`. A number field is two entries, a `JLabel` "Tab size:" and then an `IntegerField` with `text: "4"`.
- **`blank_lines_form`** (Blank Lines): `groups[]` of `{group, options[{field, label, kind: int_field, min: 0, max: 10, editorconfig_name, anchor, anchor_option}]}`.
- **`custom_panel`** (PHPDoc, Code Conversion, Code Generation, Punctuation, Imports, HTML/XML/CSS "Other", Shell "General", PostCSS, …): `controls_in_order[]` of `{label, group, kind, editorconfig_name | editorconfig_names | stores, source, note?, min?, max?, depends_on?, choices?}`. These were transcribed from forms and bytecode traces, not generated by the IDE's ordering code. Kinds: `checkbox` 112, `combo` 37, `checkbox+radio` 20, `int_field` 14, `radio` 12, `text_field` 12, `list_field` 11.
- **`arrangement`**: points to `arrangement.json`.

### `data/enum-values.json`

`value_sets` (35), `keys` (156 keys → `{section, default, value_set, field, evidence}`), `integer_ranges`, `stats` (`unmapped: 0`). Each set has `kind` (`magic_int`, `enum`, `raw_int`, `string`, `string_list`, `int_list`) and `values[{value, int?, alt_ints?, ui}]` in UI order, plus a `note`. Examples:

- `wrap` (59 keys): `off`/0 "Do not wrap", `normal`/1 "Wrap if long", `on_every_item`/5 (`alt_ints: [4]`) "Chop down if long", `split_into_lines`/2 "Wrap always".
- `wrap_singleton` (2 keys): the same accessor, but the UI offers only three values.
- `brace_style` (13), `force_braces` (12), and the language-specific sets such as `enum:PhpCodeStyleSettings.ImportSorting` (`alphabetic`, `by_length`, `dont_sort`).
- `css_brace_placement_raw_int` (3 keys: Less, Sass, SCSS): written as `"0"`/`"1"`, while CSS writes `end_of_line`/`next_line`.

`docs/value-sets.md` is the readable copy.

### `data/int-constraints.json`

`keys.<editorconfig_name>.<domain>` = `{min, max, special?, source, ui?}` for 74 keys, plus `notes`. Example: `keys.max_line_length.php` = `{min: 0, max: 1000, special: {"-1": "inherit general value (shown as \"Default: <general>\")"}}`. `[*]` has `max_line_length` with `min: null, max: 1000`. `notes` also gives the rules: Blank Lines 0..10, PHPDoc `@param` spaces 1..8, `php_*_weight` = "position in the PHPDoc tag order list", and HTML/XML keep-blank-lines and HTML `do_not_align_children_of_min_lines` are "undetermined" (`min: null, max: null`).

The catalog copies these as `range`. Of the 116 integer Options, 86 have a `range`. The others are the 28 PHPDoc weights (`list_field`) and the two `indent_package_children` keys (JS/TS, no UI).

`enum-values.json › integer_ranges` is an older, coarser copy: it gives `blank_lines.max: null`, while `int-constraints.json` and `ui-structure.json` give 10. Use `int-constraints.json`.

### `data/labels-supplement.json`

`labels.<key>[@<section>]` = `{ui_label, ui_tab, ui_group, ui_kind, source, note?, verified, page}` for 341 keys (`stats`: 330 verified, 33 with no UI). These are the labels for keys that the field join could not label, which are mostly on hand-built Tabs. Example: `labels.end_of_line` → "Line separator:", combo, General, with the choices in `note`. The catalog has already merged it (`label_source: labels-supplement…`), so a generator does not need to read it separately.

### `data/presets.json`

`presets.<class>` = `{class, name, language, ij_changes, persisted_options, scheme_xml_diff}`. There are 23 Presets: PHP 12 (Drupal, Joomla!, PEAR, Zend, Symfony2, PSR1/PSR2, CodeIgniter, Laravel, PER-CS 2.0.0, PER-CS 3.0.0, PSR12, WordPress), JavaScript 3 (Drupal, Standard, Google), CSS 1 (Drupal), SQL 7. `ij_changes` maps `"[<section> section] <key>"` (or `"[*] <key>"`) to `{default, preset}` in export spelling, for example `"[php section] ij_php_array_initializer_wrap": {"default": "off", "preset": "on_every_item"}`. `persisted_options` is the list of scheme-XML field/value pairs, and `scheme_xml_diff` is the full XML. The catalog copies the Presets per language (`languages.php.presets`, 12).

`ui-structure.json › set_from_language_menu` lists the targets of "Set from… › <Language>" for each page. For most pages it is the string "all languages that have a code style page … minus this one". SQL and its dialects list the other dialects, and HTTP Request has `[]`.

### `data/arrangement.json`

`rearrangers.<"Lang (Class)">` = `{rearranger, language, grouping_rules, matching_tokens, mutually_exclusive_tokens, default_groupings, default_sections, rule_aliases, default_settings_xml}` for 8 rearrangers: XML, HTML, Angular2Html, CSS, TypeScript, JavaScript, PHP, Vue. Tokens are `{id, representation, type (ENTRY_TYPE|MODIFIER|REG_EXP|ORDER|GROUPING|ALIAS|GENERAL), uiRole (CHECKBOX|COMBO_BOX|BULB|LABEL|TEXT_FIELD)}`, nested with `children`. For example, PHP `grouping_rules` = GETTERS_AND_SETTERS, OVERRIDDEN_METHODS (order by name / keep order), DEPENDENT_METHODS (breadth-first / depth-first). Default rules are structured as `default_sections[][]{matcher_toString, condition, orderType}` (PHP has 7 sections, TypeScript 19, Vue 11) and as XML.

### `data/code-samples/`

`INDEX.json › files.<IDE language id>.<SettingsType>` → path. There are 36 entries and 294 files. Each language has six `getCodeSample` types: `INDENT_SETTINGS`, `SPACING_SETTINGS`, `WRAPPING_AND_BRACES_SETTINGS`, `BLANK_LINES_SETTINGS`, `LANGUAGE_SPECIFIC`, and `COMMENTER_SETTINGS`. There are also 12 `_custom_panels/<Panel>__<Tab>.txt` (`getPreviewText()` of custom Tabs) and `sql/<dialect>/preview-{case,queries,ddl,code,expressions,indent,wrapping}.sql` (11 dialects × 7). `catalog.json › languages.<slug>.preview_samples` lists only the six `getCodeSample` files.

## Control kinds

| Control (catalog `ui_kind`) | Value types seen | Where | Example |
|---|---|---|---|
| `checkbox` | boolean 512, enum 8, string 1 | everywhere | `ij_php_align_assignments` |
| `combo` | enum 55, boolean 11, string 1 | trees and panels | `ij_php_namespace_brace_style` (End of line / Next line) |
| `wrap_combo` | enum 56 | Wrapping and Braces | `ij_php_extends_list_wrap`; it may also be a group header with child checkboxes |
| `int_field` | integer 85 (+1 wrong, see below) | Tabs and Indents, Blank Lines, Hard wrap at, PHPDoc spaces | `ij_php_keep_blank_lines_in_code` 0..10 |
| `text_field` | string 6, visual_guides 1 | Formatter markers, Visual guides | `ij_visual_guides` (`"80,120"`) |
| `list_field` | integer 28, comma_separated_list 10 | PHPDoc tag order, CSS/SCSS property order, JS/TS imports, … | `ij_css_properties_order` |
| `radio` | enum 7 | PHP Code Generation, trailing-comma style | `ij_php_variable_naming_style` (Mixed / camelCase / snake_case) |
| `checkbox+radio` | boolean 16, enum 4 | PHP Code Conversion and PHPDoc, CSS hex colours | see the irregular cases below |
| three-way Default/No/Yes | (combo with ints −1/0/1) | "Wrap on typing" on the language pages that show it (Wrapping tree or HTML/XML/Twig "Other") | `ui-structure.json › pages.PHP.tabs["Wrapping and Braces"].tree[1]` |
| `none` | 35 keys | exported keys with no control on that page | `ij_sass_brace_placement`, `ij_typescript_jsx_attribute_value` |

## Groups and order inside a Tab

- `option_tree`: order = array order. Groups are top-level `group` nodes or `wrap_combo` nodes with `children` (37 such wrap combos, for example "Extends/implements/permits list" › "Align when multiline"). Ungrouped options sit at the top level, for example "Hard wrap at:", "Wrap on typing", and "Visual guides" at the top of PHP Wrapping and Braces.
- `blank_lines_form`: `groups[].group` ("Keep maximum blank lines", "Minimum blank lines") and `groups[].options[]` in order.
- `custom_panel`: a flat `controls_in_order[]` with a `group` string per control (or `null`).
- `indent_options_editor`: a flat list of controls with no groups.
- Catalog `ui_group` repeats the group name, but `options[]` is in key order. **UI order is only in `ui_layout`/`ui-structure.json`.**
- Known simplifications (`README.md`, "Two layout simplifications"): the right-hand "Spaces" column of HTML › Other is listed after the left column, and label and field are separate entries in Tabs and Indents.

## Enable and visibility dependencies

Every dependency is free text. None of them can be evaluated as data.

- **Per Tab**: `ui-structure.json › pages.<P>.tabs.<T>.dependencies[]` = `{control, property, depends_on, rule, derived_from}`. Only two rules occur. The first is "Smart tabs" in every indent editor: `enabled = pageEnabled && useTab && (indent % tabSize == 0)`. It is a **computed** rule over three values, not just one checkbox. The second is JS/TS "Indent all chained calls in a group" ⇐ "Indent chained methods". The Vue rule (indent fields enabled only with "Same in the whole file") is marked "inferred".
- **Per control**: `depends_on` in 5 `custom_panel` controls (CSS/SCSS Arrangement radios ⇐ "Sort CSS properties"; Other File Types "Smart tabs").
- **Cross-Tab, free text**: `ui-structure.json › dependencies_custom[]` (9): the PHP Code Conversion checkbox enables its radios; the PHPDoc null-position radios and the tag-order list; the CSS hex-colour radios; Comments: "Add a space at line comment start" enabled only when "Line comment at first column" is unchecked, and YAML "Enforce on reformat" only when "Add a space…" is checked; Vue uniform indent; Formatter markers ⇐ "Turn formatter on/off…"; CSS Arrangement; and SQL dialect pages, which are all disabled while "Inherit General SQL Style" is checked. `docs/notes/gui-verification.md` "UI dependencies observed" confirms them from screenshots. It also adds that the quote-mark combos (CSS, HTML) have a dependent "Enforce on format" checkbox.
- **No dependencies are recorded inside `option_tree` Tabs.**
- **Visibility**: the visibility filters of the option trees are already applied (`_about`), so hidden options are not listed. The only explicit visibility data is SQL `visible_in[]` per dialect page and `choices_per_page` (`pages.SQL.tabs.Case` › `QUOTE_TYPE`). Visibility also differs between languages: JS and TS have different sets (TS has "Use type modifier in imports"), and Sass hides 13 keys that it still exports (`ui_kind: none`, "not shown on the Sass page").

## Cross-page Options and inheritance from General/`[*]`

`ui-structure.json › cross_page_options[]` (7):

- HTML › Other "Add for JSX attributes:" stores `ij_javascript_jsx_attribute_value`. It is a control on one language's page that writes another language's key (`ij_typescript_jsx_attribute_value` has no UI).
- "Set from… › <Language>" copies the Common and indent settings of another language. JS-derived pages and SQL also copy their custom settings.
- Not exported, scheme XML only: Vue "Same in the whole file / Specific to the language in the block" (`UNIFORM_INDENT`), HTML "Use HTML indents within <style> and <script> tags", CSS › PostCSS "Line comment style", root "Enable EditorConfig support".
- Blade, Twig, and Angular pages edit their own Common/indent settings, not the HTML keys.

Inheritance (`data/extra-ij-keys.json › writer_rules`, `per_language_inherit_values`):

- `skip_if_equals_general`: a language value equal to `[*]` is not written. This is why `indent_size`, `tab_width`, `indent_style`, `ij_continuation_indent_size`, `ij_smart_tabs`, and `ij_visual_guides` appear in only some catalog languages. For example, `ij_continuation_indent_size` is in `languages.php.options` (default `"4"` against `[*]` `"8"`), and YAML has `indent_size` (`"2"`).
- `skip_null`: per-language `max_line_length` at −1 ("Default: 120") and `ij_wrap_on_typing` at −1 ("Default") are not written.
- Names: per-language Hard wrap at, Wrap on typing, and Visual guides use the general names (`max_line_length`, `ij_wrap_on_typing`, `ij_visual_guides`) inside the language section. `keep_indents_on_empty_lines` is language-prefixed.
- General `ij_wrap_on_typing` is a boolean **checkbox** (`languages.general.options`), while each language's Wrap on typing is a three-way **combo** (Default/No/Yes).
- Other File Types edits the `[*]` indent keys (`OTHER_INDENT_OPTIONS`).

So, for each language, the full Option list of a Tab = the `ui_layout` controls, with facts from `options[]`, or from `other_possible_keys` (default = the `[*]` value, or `null` = inherit) when the key is not in `options[]`. I computed this per language: the UI names that are only in `other_possible_keys` are, for PHP, `ij_smart_tabs`, `ij_visual_guides`, `ij_wrap_on_typing`, `indent_size`, `indent_style`, `max_line_length`, and `tab_width`. HTML additionally has `ij_continuation_indent_size`.

## Value sets

35 sets (`enum-values.json › value_sets`). Each enum Option carries its values in `catalog.json › options[].values` (136 of 136 enums). The three spellings are kept apart: `.editorconfig` value, UI label, and internal int. A model must keep all three:

- The UI order is not the int order. `yaml_align_values` lists Do not align/0, On colon/2, On value/1, while `json_property_alignment` lists Do not align/0, On value/1, On colon/2.
- `wrap`: two ints (4 and 5) map to one value.
- Raw-int keys are written as numbers: `raw_int:PhpCodeStyleSettings.PLACE_PARENS_FOR_CONSTRUCTOR` (`"0"` As is / `"1"` Always / `"2"` Never), JS/TS `ALIGN_OBJECT_PROPERTIES` and `ALIGN_VAR_STATEMENTS`, and Less/Sass/SCSS brace placement and value alignment.
- Enum spelling comes from display text: JS trailing comma `whenmultiline`, HTML `when_multiline` (`README.md`, "Enum spelling").
- Some sets contain an "off" value that the UI shows as an unchecked checkbox: `ImportSorting.dont_sort`, `ElseIfStyle.as_is`, `PhpDocNullPosition.dont_force`, and `xml_text_wrap` `off`/`normal`.
- `BooleanWithGlobalOption` (`global`/`true`/`false`, 6 keys) is shown as a plain checkbox. The default `global` ("follows the IDE-level setting") cannot be displayed.

## Integer limits and special values

- Indent and continuation indent 0..32. Tab size 1..16. Blank lines 0..10. Hard wrap at 0..1000 with −1 = "Default: <general>" (language pages; `special` in `int-constraints.json`, `special_default: -1` in tree nodes). PHPDoc `@param` spaces 1..8.
- Undetermined: HTML/XML keep blank lines, HTML "tag size" (`min/max: null`), and SQL numeric fields.
- The GUI validates only on Apply. The value stored for an out-of-range number was not tested (`README.md`, "Not determined").

## Preview samples for each Tab

- No file records which sample a Tab shows. By IntelliJ convention and the Tab `kind`: `indent_options_editor` → `INDENT_SETTINGS`, Spaces tree → `SPACING_SETTINGS`, Wrapping tree → `WRAPPING_AND_BRACES_SETTINGS`, `blank_lines_form` → `BLANK_LINES_SETTINGS`, and `custom_panel` → `_custom_panels/<Panel>__<Tab>.txt` if one exists (`code-samples/INDEX.json › _about`). This mapping is an inference. Confirm it before a generator depends on it.
- **Many languages use one text for all six types** (same MD5): Angular2Html, Blade, CSS, EditorConfig, Gherkin, HTML, JSON, LESS, Makefile, SASS, SCSS, Twig, Vue, and yaml. Only PHP, JavaScript, TypeScript, Markdown, Mermaid, and HTTP Request have different texts for each Tab.
- **Broken or empty**: all SQL and dialect `getCodeSample` files are the one line `-- something goes wrong`, and `catalog.json › languages.sql.preview_samples` points to them. The real SQL previews are `sql/<dialect>/preview-*.sql`, seven per dialect for General's "Preview dialect". `Shell_Script/*` are empty (0 lines), and the Shell preview is `_custom_panels/ShCodeStylePanel__Other.txt`. XML is empty except `INDENT_SETTINGS` (34 lines), and XML › Other uses `_custom_panels/CodeStyleXmlPanel__Other.txt`. The Code Generation custom panels of PHP, JS, and TS are empty (no Preview).
- General and Other File Types have no Preview.

## Presets

- The values are complete, in export spelling. Their effect on formatting was not run (`README.md`, "Open items").
- **A Preset can change more than its own language.** PHP "Drupal" changes the `html`, `xml`, and `json` sections (3 each) and `[*]` (5: indent 2, continuation 2, tab 2, `max_line_length` 80, `ij_visual_guides` `80,120`). PHP "Joomla!" sets `[*] indent_style = tab`.
- Some Preset changes have no `.editorconfig` key. Drupal has 71 `persisted_options` but 70 `ij_changes` (`AUTODETECT_INDENTS = false`), and all 7 SQL Presets have `ij_changes: {}` (scheme XML only).
- Presets set PHPDoc weights as integers (`THROWS_WEIGHT=3`). In the UI those are positions in a list editor.

## Irregular cases a general Option model must handle

1. **One control, two boolean keys**: PHP "Convert True/False constants to: [Lower|Upper] case" is one checkbox with two radios that write `ij_php_lower_case_boolean_const` and `ij_php_upper_case_boolean_const`. The checkbox is checked when one of them is true. The same holds for the null constants and the CSS hex colour case and format (`checkbox+radio`, 16 boolean keys).
2. **One control, one enum with an "off" member**: "Sort 'use' statements:" (checkbox + radios) writes `ij_php_import_sorting` = `dont_sort`, `alphabetic`, or `by_length`. Others are "Place 'null' in types:" and "Convert else if/elseif to:".
3. **One control, many keys**: the PHPDoc tag-order list editor writes 28 `ij_php_*_weight` integers (`editorconfig_names[]` in `pages.PHP.tabs.PHPDoc`). The value is a position, not a number the user types.
4. **One row, two combos**: JS/TS Punctuation "[Use|Don't use] semicolon [in code generated by IDE|always]" writes `use_semicolon_after_statement` and `force_semicolon_style`, and the same holds for quotes. **The choice labels of these boolean combos are only in `note` text.** The same is true for `end_of_line` and `ij_css_use_double_quotes` (Double/Single).
5. **Checkbox that writes a non-boolean**: `indent_style` (`space`/`tab`), `ij_html_text_wrap` and `ij_xml_text_wrap` (`off`/`normal`), and `BooleanWithGlobalOption` (`global`/`true`/`false`).
6. **Inherit states**: −1 for Hard wrap at, the "Default" choice for Wrap on typing (int −1), `global`, empty Visual guides, and keys not written when equal to `[*]`. Each language has its own "default" sentinel.
7. **Control on one language's page, key of another**: HTML › Other → `ij_javascript_jsx_attribute_value`.
8. **Controls with no key** (scheme XML only): Vue uniform indent, HTML uniform indent, PostCSS comment style, the CSS "Sort CSS properties" checkbox and its radios (only the list is `ij_css_properties_order`), and "Enable regular expressions in formatter markers".
9. **Keys with no control**: 35 keys with `ui_kind: none`. Examples: 13 Sass keys, `ij_less_properties_order` and `ij_sass_properties_order` (no Arrangement Tab on those pages), and `ij_{javascript,typescript}_space_before_class_left_brace` (the GUI's "Class left brace" writes `…_space_before_class_lbrace`).
10. **Languages with a UI but no export**: Angular2Html (Spaces and Wrapping trees with `ij_angular-html_*` names, catalog `options: []`) and Makefile (indent editor, empty file pattern) (`extra-ij-keys.json › languages_without_editorconfig`).
11. **Group header with a value**: a `wrap_combo` with `children` is both an Option and a group.
12. **Computed enable rule**: Smart tabs depends on `indent % tabSize == 0`, not just on a checkbox.
13. **Number field kinds**: Tabs and Indents splits label and field (`JLabel` + `IntegerField`). Vue "Indent children of top-level tag" is an `ExpandableTextField` with a `comma_separated_list` value, but `catalog.json` gives it `ui_kind: int_field`. **That is a corpus error.**
14. **Different defaults in similar languages**: TS `force_semicolon_style = true`, JS `false`. Two catalog defaults do not match the formatter's real default (TS `force_semicolon_style`, General `trim_trailing_whitespace`; `README.md`, "Catalog default is not always the real default").
15. **Arrangement rule aliases** are mined only for PHP (`modifiers`, `visibility`). For the other 7 rearrangers, `rule_aliases` holds `"ERR java.lang.NoSuchMethodException …"`. SCSS, Less, and Sass have no own rearranger in `arrangement.json`. SCSS's Arrangement Tab is the CSS property sort.
16. **SQL** needs its own model: 210 fields in `sql-options.json`, per-dialect pages with `visible_in`, inherit-General per dialect, choices per page, no EditorConfig names, and 7 Presets with XML-only changes.

## Completeness summary

| File | Structure | Completeness | Varies by language |
|---|---|---|---|
| `catalog.json` | per language: options, layout copy, presets, arrangement, previews | 837 keys, 835 labelled; misses inherited keys (they are in `other_possible_keys`) | Option count 0–239; SQL empty |
| `ui-structure.json` | 25 pages, 91 Tabs, 5 Tab shapes | all Tabs screenshot-verified; dependencies are free text | Tab set and order per language |
| `enum-values.json` | 35 value sets, 156 keys | 0 unmapped | language-specific sets for PHP, JS/TS, CSS family, XML/HTML, JSON, YAML |
| `int-constraints.json` | key → domain → bounds | 74 keys; HTML/XML blank lines, tag size, and SQL undetermined | per domain |
| `labels-supplement.json` | key[@section] → label | 341 keys, 330 verified; already merged into the catalog | hand-built Tabs |
| `presets.json` | 23 Presets with export and XML diffs | values complete; effect not tested | PHP 12, JS 3, CSS 1, SQL 7; none elsewhere |
| `arrangement.json` | 8 rearrangers: tokens, groupings, defaults | aliases only for PHP | PHP/JS/TS rich; HTML-family tag/attribute; CSS sort only |
| `code-samples/` | 294 texts | broken for SQL (use `sql/<dialect>/`), empty for Shell and most of XML | 14 languages share one text for all Tabs |

## Sources

- `README.md` (sections "Start here", "All files", "Languages", "Things a re-implementation must get right", "Coverage and known gaps", "Known limits", "Open items")
- `data/catalog.json` › `languages.<slug>.{options, other_possible_keys, ui_layout, ui_labels, preview_samples, presets, arrangement}`, `value_sets`
- `data/ui-structure.json` › `_about`, `pages.<Page>.tabs.<Tab>.{kind, tree, controls_in_order, groups, dependencies}`, `cross_page_options`, `dependencies_custom`, `set_from_language_menu`
- `data/enum-values.json` › `value_sets`, `keys`, `integer_ranges`, `stats`
- `data/int-constraints.json` › `keys`, `notes`
- `data/labels-supplement.json` › `labels`, `stats`
- `data/presets.json` › `presets.<class>.{name, language, ij_changes, persisted_options, scheme_xml_diff}`
- `data/arrangement.json` › `rearrangers.<name>.{grouping_rules, matching_tokens, default_groupings, default_sections, rule_aliases}`
- `data/code-samples/INDEX.json`, `data/code-samples/<Lang>/*.txt`, `data/code-samples/_custom_panels/`, `data/code-samples/sql/<dialect>/`
- `data/extra-ij-keys.json` › `writer_rules`, `per_language_inherit_values`, `languages_without_editorconfig`
- `data/sql-options.json` › `_about`, `stats`, `fields[]` (structure only)
- `docs/value-sets.md`, `docs/languages/php.md` ("UI layout", "Dependencies", "Other keys this section can contain"), `docs/notes/gui-verification.md` ("UI dependencies observed"), `docs/notes/MINING-NOTES.md` (code-samples provenance)
