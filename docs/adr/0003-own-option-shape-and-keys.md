# Options have their own shape and keys, not PhpStorm's fields

An Option is one item that the user sets, with one typed value. It is not one PhpStorm field. PhpStorm often stores one control as several fields: two booleans for the upper and lower case of constants, a checkbox plus an enum with an "off" member for import sorting, and 28 integer weights for the PHPDoc tag order. Because our own JSON is the only store (ADR-0001), we model what the user sees, so states that the UI cannot produce cannot be stored. Each Language Plugin maps PhpStorm fields to its Options for the Scheme XML import and for the Behaviour Record golden tests.

The file is `{"version": 1, "languages": {"<language id>": {...}}}`. A language id is a short id that we choose (`php`, `typescript`, `shell`), not a Neovim filetype or a Research Corpus slug. The Core reserves `general`, and it refuses a second Language Plugin with an id that is already used. Inside a language, the Option key is the Language Plugin's own path, nested by topic (`wrap.call_arguments`) and never by Tab, so a Tab can move without touching stored values. A choice is stored as its own string id, never as PhpStorm's int.

Every Option has one of six Core types: `boolean`, `integer` (with `min` and `max`), `choice`, `string`, `list` (of integers or strings), and `order` (a permutation of fixed members). A Language Plugin cannot add a type, so the Core owns every Menu editor and all validation.

## Considered Options

- **One Option per PhpStorm field, keyed by the `.editorconfig` name.** Import and tests need no mapping. But the Menu then needs composite controls that write several Options, and invalid combinations can be stored.
- **Keys derived from PhpStorm `.editorconfig` names** (`ij_php_align_assignments` → `align_assignments`). Rejected in favour of each Language Plugin's own names.
- **Keys nested by Tab**, as in the Menu. Rejected, because moving an Option to another Tab would lose every saved value.
- **Types that a Language Plugin adds**, with its own editor. Rejected, because the Menu would run plugin UI code. All 837 Research Corpus Options and all 210 SQL fields fit the six types.

## Consequences

- Keys are permanent. Renaming a key needs a migration that the Language Plugin ships (see "What is the Language Plugin contract?", #12).
- When a Language Plugin adds an `order` member, a stored order that lacks it gets the member where the default order puts it. A stored member that the plugin no longer knows is kept in the file and ignored.
- An invalid stored value (wrong type, out of range, unknown choice) gives one warning per file. Formatting uses that Option's default, and the raw value stays in the file until the user sets that Option in the Menu.
