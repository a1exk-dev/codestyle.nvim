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
One item of a Code Style that the user sets, with one typed value, such as how method parameters wrap. One Option can stand for several PhpStorm fields, for example one choice of upper or lower case for the two PhpStorm case flags.
_Avoid_: Setting, field (reserved for PhpStorm's stored items)

**Tab**:
One page of a language's options in the Menu, such as Tabs and Indents, Spaces, or Wrapping and Braces.
_Avoid_: Section (reserved for an `.editorconfig` glob block such as `[*.php]`)

**Group**:
A labelled set of Options inside a Tab, such as "Keep maximum blank lines". A Group can have an Option of its own, such as a wrap choice whose children are its alignment Options.
_Avoid_: Section, category

**Menu**:
The Code Style editor inside Neovim: the language list, each language's Tabs, and the Preview.
_Avoid_: Settings window, dialog

**Preview**:
The sample code in the Menu that is reformatted at once when an option changes.

**Draft**:
The changes made in the Menu that are not saved yet. The Preview shows them at once, but no file or real buffer gets them until the user saves.
_Avoid_: Pending changes, unsaved settings

**Core**:
The codestyle.nvim plugin itself: the Menu, the Code Style storage, the formatting engine, and the contract that Language Plugins implement.

**Language Plugin**:
A separate Neovim plugin that supplies one language's Tabs, Options, Preview samples, and formatting rules to the Core.
_Avoid_: Language module, provider

**Preset**:
A named set of option values ("Set from…", such as PSR-12) that is applied over a language's Code Style in one step.

**Block**:
A part of a file that the formatter places as one unit. Formatting changes only the Gaps between Blocks.
_Avoid_: Node (reserved for an item of a Tree-sitter parse tree)

**Gap**:
The whitespace between two adjacent Blocks. The lowest Block that holds both of them owns the Gap.
_Avoid_: Whitespace token

**Host Language**:
The language of a file that also contains code of another language, such as PHP or Twig around HTML.
_Avoid_: Outer language, template language

**Embedded Language**:
The language of code inside a file of a Host Language, such as the HTML in a PHP or Twig file.
_Avoid_: Injected language, inner language, template data language

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
