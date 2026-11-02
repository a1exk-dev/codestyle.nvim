# The Menu edits Arrangement as rows with a rule float

The Arrangement Tab draws the stored shape of ADR-0011 as rows in the Options pane, with the same look and keys as Option rows. A rule is edited in a small float, and the CSS family gets PhpStorm's simpler sort panel as a second view of the same Slot shape. The ADR-0003 editors cover Options only, so the Core adds these editors for its reserved `arrangement` key. The operator chose each part in "How does the Menu edit Arrangement rules?" (#29). Only a language whose spec has `arrangement` data gets the Tab.

## The rows

- **Rearrange when formatting** (`enabled`) is a checkbox row. Each Keep-Together Rule that the spec allows is a checkbox row with its order choice.
- **Slots:** one row per rule, with a readable summary (`method  !static  name /get.*/  by name`). The first rule of a Slot shows the Slot number, and later rules of the same Slot show `│`. `o` adds a rule in a new Slot below, and `a` adds a rule to the Slot under the cursor. `J`/`K` move a rule, and past the Slot's edge it joins the next Slot. `gJ`/`gK` move the whole Slot. `dd` deletes a rule, and `<CR>` opens the rule float.
- **Aliases** are a folded Group, one row per alias. `o` adds one (its name must be unique), `r` renames it and updates every rule that uses it, and `dd` is refused while a rule uses it, with a message that names those Slots. `<CR>` opens a float with the alias's rules as rows and the same keys.

## The rule float

Six rows: Is, Is not, Name, Namespace, Alias and Order. It shows only the parts that the spec allows, and an alias's rules have no Alias or Order. `<CR>` on Is or Is not opens a `snacks.picker` multi-select of the spec's vocabulary, with the current tokens marked. Each picker leaves out the tokens that the other one holds. A set with tokens that the spec marks as mutually exclusive is refused, and the picker opens again with that set. Name and Namespace are `vim.ui.input` fields that `vim.regex` checks, and a bad regex is refused with its error.

## Draft, Preview and reset

- Every confirmed edit (a picker, an input, a move, a delete, a toggle) writes the Draft at once as one undo step, and the Preview reformats, as for an Option (ADR-0006). `o` and `a` open the rule float at once. A new rule that is closed with no condition is dropped and leaves no undo step, because an empty rule matches every entry.
- The Preview shows the spec's Arrangement sample, rearranged and then formatted. The engine also returns the Slot and rule that each Arrangement Entry matched. Each entry gets its Slot number as dim virtual text, or `–` when no rule matched it. When the cursor is on a Slot or rule row, the entries it took are highlighted.
- `x` resets "Rearrange when formatting" or one Keep-Together Rule. A Slot or alias row has no default of its own, so there `x` only says so. `X` resets the whole Arrangement as one undo step. While the Arrangement differs from the default, the Tab and the language's `•N` count show it as one changed item.
- An **invalid stored Arrangement** (ADR-0011) shows a warning row that names the bad part, and the rows below show the default that formatting uses. The first edit or `X` replaces the stored value in the Draft. Until then, a save keeps the stored value.
- `f` (ADR-0004) finds the fixed labels only. Slot and alias rows are user data, and `/` finds them as buffer text.

## The CSS sort panel

A spec can choose the `sort` panel (CSS, SCSS). PhpStorm has no rule matcher for CSS, only "Sort CSS properties: by name / custom order" over `ij_css_properties_order`. The panel shows "Rearrange when formatting", "Sort properties", an order choice, and the custom-order list. It reads and writes only the Slot shape. Off is no Slots. "By name" is one Slot with one by-name rule that matches every declaration. "Custom order" is one Slot per property, with a name regex anchored to that property. It starts from PhpStorm's default list. `<CR>` on the list opens a list float (`J`/`K` move, `o` add, `dd` delete). A stored shape that the panel cannot express (for example, a hand-edited file) shows the generic Slot rows instead, with a note.

## Considered Options

- **An editable text buffer** with the shape as Lua or a small language, checked on `:w`. Rejected: it is unlike every other control of the Menu.
- **A second, larger dialog** with PhpStorm's two columns (Slot list, rule form). Rejected: a second layer with its own keys.
- **Tri-state token rows** (off / is / is not) in the rule float, like PhpStorm's bulbs. The operator chose the shorter float with pickers.
- **One row per Slot that folds into its rules**, or **only single-rule Slots**. Rejected: the first hides the rule order, and the second cannot produce shapes that the model stores.
- **The rule float as one undo step**, with `<Esc>` to cancel it. Rejected: it is unlike the rest of the Draft.
- **Delete a used alias and clear it from its rules.** Rejected: a quiet loss of rules.
- **The generic editor for CSS too.** Rejected: a custom order of 98 properties becomes 98 Slot rows.

## Consequences

- The Menu calls `snacks.picker` directly for multi-select, because `vim.ui.select` picks one item. Single choices still go through `vim.ui.select` (ADR-0004).
- `J`/`K` move items in every list of the Menu, including the float of the Core's `order` Option type, which the Menu prototype bound to `<C-j>`/`<C-k>`.
- The spec's `arrangement` data (ADR-0011) also names its panel (`rules` or `sort`), the labels of its tokens, and which tokens are mutually exclusive. It needs an Arrangement Preview sample.
- The engine returns the matched Slot and rule of each entry next to its edits, for the Preview only.
