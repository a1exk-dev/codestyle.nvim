---@meta
-- LuaCATS annotations of the Language Plugin contract, `api` 1 (ADR-0007).
-- Plugin repos check their spec and formatter against them with LuaLS
-- (ADR-0013). Within one `api`, fields are only added, and only as optional.

---@alias codestyle.OptionType 'boolean'|'integer'|'choice'|'string'|'list'|'order'

--- One choice of a `choice` Option. The file stores its `id` (ADR-0003).
---@class codestyle.OptionChoice
---@field id string
---@field label string

--- One Option of a language (ADR-0003).
---@class codestyle.OptionSpec
---@field key string the stored path, nested by topic with dots, such as `spaces.around_assignment`
---@field type codestyle.OptionType
---@field default? any the value when none is stored; for `order`, every member in the default order; not used with `inherit`
---@field label string
---@field min? integer the least value of an `integer`, or of each item of a `list` of integers
---@field max? integer the greatest value of an `integer`, or of each item of a `list` of integers
---@field choices? codestyle.OptionChoice[] the choices of a `choice` Option
---@field item? 'integer'|'string' the type of each item of a `list`
---@field inherit? string a `general` key, such as `hard_wrap_at`, whose value the Option takes when it has none stored (ADR-0018)

--- One rename that a Language Plugin ships when it renames a key or a
--- choice id (ADR-0007). The Core applies them in order on read.
---@class codestyle.Migration
---@field key string the old key; for a choice rename, the key of the `choice` Option
---@field to string the new key, or the new choice id
---@field choice? string for a choice rename, the old choice id

--- The spec module `lua/codestyle/languages/<id>.lua` of a Language Plugin (ADR-0007).
---@class codestyle.Spec
---@field api integer the contract version, `require('codestyle').api`
---@field id string the language id, the key under `languages` in a Code Style file (ADR-0003)
---@field name string the display name
---@field filetypes string[] the Neovim filetypes that the plugin claims (ADR-0015)
---@field match? fun(buf: integer): boolean claims a buffer whose filetype no spec lists, or that has none; build it with `require('codestyle').match_globs` (ADR-0015)
---@field parsers table<string, string[]> filetype → parser names, first installed wins; `default` is required (ADR-0015)
---@field uses? table<string, integer> language id → the export version this plugin needs from that plugin (ADR-0007)
---@field exports? codestyle.Exports what this plugin offers to plugins that use it (ADR-0007)
---@field options codestyle.OptionSpec[]
---@field migrations? codestyle.Migration[] renames of keys and choice ids, in the order they were made
--- The key of the boolean Option that is PhpStorm's "Keep indents on empty lines", if the
--- language has one. `:checkhealth codestyle` warns when editorconfig's trim would strip those indents.
---@field keep_indents_on_empty_lines? string
---@field formatter string the module path of the `codestyle.Formatter`, required on first format

--- What a Language Plugin offers to the plugins that `uses` it (ADR-0007).
--- Within one version, only optional fields are added.
---@class codestyle.Exports
---@field version integer

--- The resolved Option values of one language, nested like the stored keys,
--- with the `general` values under `general`.
---@alias codestyle.Values table<string, any>

--- What the Core passes to a plugin's functions. Plugin functions read only
--- `ctx` and their arguments (ADR-0016).
---@class codestyle.FormatContext
---@field language string the language id
---@field parser string the name of the parser of `root`
---@field root TSNode the root of the parse tree of `source`
---@field source string the text being formatted, lines joined by `\n`
---@field values codestyle.Values
---@field range? codestyle.Range the lines to format, nil for the whole text; the Core drops a step's edit outside it

--- Whole lines of the text: rows 0-based, both ends included.
---@class codestyle.Range
---@field start_row integer
---@field end_row integer

--- One rule that the engine calls on a parent Block (ADR-0007). A rule names
--- the parser nodes and fields it needs; when the grammar lacks one, the Core
--- skips the rule with a warning (ADR-0002).
---@class codestyle.Rule
---@field nodes? string[] node types, named (`assignment_statement`) or anonymous (`=`)
---@field fields? string[] field names
--- The Spacing of the Gap between two adjacent children of `parent`, or nil to
--- leave the Gap to the next rule. The first rule that gives a Spacing wins.
---@field spacing? fun(parent: codestyle.Block, left: codestyle.Block, right: codestyle.Block, values: codestyle.Values): codestyle.Spacing?

--- A step that changes text, such as forced braces or letter case. The Core
--- parses the text again after each step.
---@alias codestyle.Step fun(ctx: codestyle.FormatContext): codestyle.Edit[]

--- The `formatter` module of a Language Plugin (ADR-0007). It gives `build`
--- and `rules` for the Core engine, or `format` to replace the engine.
---@class codestyle.Formatter
---@field build? fun(ctx: codestyle.FormatContext): codestyle.Block
---@field rules? codestyle.Rule[] in order of priority
---@field before? codestyle.Step[] run in order before the engine
---@field after? codestyle.Step[] run in order after the engine
--- Replaces the Core engine for the language: the edits for the whole text, or
--- for the lines of `ctx.range`. Such a language has no Blocks.
---@field format? fun(ctx: codestyle.FormatContext): codestyle.Edit[]

--- One text change: replace the text from the start to the end position
--- (rows 0-based, byte columns, end exclusive) with `text`.
---@class codestyle.Edit
---@field start_row integer
---@field start_col integer
---@field end_row integer
---@field end_col integer
---@field text string
