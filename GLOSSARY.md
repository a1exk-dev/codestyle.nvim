# codestyle.nvim

A Neovim plugin that edits PhpStorm-style code style settings in a menu with a live preview, and formats real buffers with them.

## Language

**Code Style**:
The complete set of option values that decides how code is formatted.
_Avoid_: Settings, config, scheme

**Global Code Style**:
The user's own Code Style, used for every buffer that has no Project Code Style.
_Avoid_: Default scheme, IDE scheme

**Project Code Style**:
The Code Style committed at the root of one repository and shared by everyone who works in it. It replaces the Global Code Style completely.
_Avoid_: Project scheme, local config

**Option**:
One configurable item of a Code Style with a value, such as "Wrap if long" for method parameters.
_Avoid_: Setting

**Tab**:
One page of a language's options in the Menu, such as Tabs and Indents, Spaces, or Wrapping and Braces.
_Avoid_: Section (reserved for an `.editorconfig` glob block such as `[*.php]`)

**Menu**:
The Code Style editor inside Neovim: the language list, each language's Tabs, and the Preview.
_Avoid_: Settings window, dialog

**Preview**:
The sample code in the Menu that is reformatted at once when an option changes.

**Core**:
The codestyle.nvim plugin itself: the Menu, the Code Style storage, the formatting engine, and the contract that Language Plugins implement.

**Language Plugin**:
A separate Neovim plugin that supplies one language's Tabs, Options, Preview samples, and formatting rules to the Core.
_Avoid_: Language module, provider

**Preset**:
A named set of option values ("Set from…", such as PSR-12) that is applied over a language's Code Style in one step.

**Arrangement**:
The reordering of code elements (class members, attributes, CSS properties) by matching rules, separate from formatting options.
_Avoid_: Rearrange, sorting

## Reference

**Research Corpus**:
The PhpStorm 2026.2.3 Code Style reference in `~/Projects/phpstorm-editorconfig/`: every option, its UI place, values, defaults, and observed behaviour.

**Behaviour Record**:
A Research Corpus entry with PhpStorm's formatter output for one option and value on targeted inputs. Our formatter's output must match it.

**Scheme XML**:
PhpStorm's own file format for a Code Style, such as `.idea/codeStyles/Project.xml`. It is the only PhpStorm format we import.
