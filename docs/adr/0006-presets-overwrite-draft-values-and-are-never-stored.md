# Presets overwrite Draft values and are never stored

A Preset is data: a name, the language whose "Set from…" list shows it, and Option values keyed by language id. The values can be for its own language, for `general`, and for other languages, so PHP "Drupal" also sets HTML, XML, JSON and `general` values, as in PhpStorm. Language Plugins declare their Presets in their contract, and the user can add Presets in `setup()`. Applying a Preset writes its values into the Draft of the Code Style that is being edited and changes nothing else. The Code Style file stores only the values, never the name of a Preset, as in PhpStorm. So a Language Plugin release that changes a Preset never changes a saved Code Style or its formatting output ("How do Presets and "Set from…" act on a Code Style?", #21). PhpStorm's "Set from… › <Language>" copy is not in v1. The operator ruled it out.

## Considered Options

- **Store the Preset as a base** (`"preset": "psr12"` plus the user's changes on top). A fix to a Preset would then reach every saved file. Rejected, because formatting output would change after a plugin update, and Preset ids would become permanent file keys.
- **Reset the language to defaults, then apply.** The result would be exactly the Preset, but the user's other edits would be lost. Rejected for PhpStorm's behaviour, which overwrites only the named fields.
- **Presets for their own language only.** A simpler contract, but Drupal and Joomla! would lose their `general` and other-language values.
- **"Copy from <Language>"** by equal key and type, with a list of common keys that the Core documents. Its design was discussed and then dropped. Under ADR-0003 no key is shared between languages, so a copy works only where Language Plugins choose the same key names.

## Consequences

- A cross-language Preset names other Language Plugins' Option keys. ADR-0003 makes those keys permanent, so they are a stable interface.
- Values for a language that has no installed Language Plugin are skipped. Unknown keys, invalid values, and the values of Options that v1 leaves out (e.g. visual guides) are skipped too. One notice lists what was skipped. Nothing unvalidated reaches the file.
- "Set from…" lists the Language Plugin's Presets first, then the user's Presets marked "(user)". A name that appears twice hides neither Preset.
- The Draft gets undo and redo (`u` and `<C-r>`), and a Preset is one step. The history lasts until save, Discard or close. This adds to the keys of ADR-0004.
- Presets set Options only, never Arrangement rules. None of PhpStorm's 22 Presets change Arrangement.
- Each first-party Preset has a golden test. Its `scheme_xml_diff` in the Research Corpus (`data/presets.json`), mapped through the Language Plugin's field → Option mapping, must equal the Preset. The fields of Options that v1 leaves out are listed as skipped.
