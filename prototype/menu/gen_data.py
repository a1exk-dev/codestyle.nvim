#!/usr/bin/env python3
"""PROTOTYPE (throwaway): turn Research Corpus data into lua/codestyle_proto/data.lua.

Usage: python3 prototype/menu/gen_data.py [~/Projects/phpstorm-editorconfig]
"""
import json
import os
import re
import sys

CORPUS = os.path.expanduser(sys.argv[1] if len(sys.argv) > 1 else "~/Projects/phpstorm-editorconfig")
OUT = os.path.join(os.path.dirname(__file__), "lua", "codestyle_proto", "data.lua")

ui = json.load(open(f"{CORPUS}/data/ui-structure.json"))["pages"]
cat = json.load(open(f"{CORPUS}/data/catalog.json"))["languages"]
presets = json.load(open(f"{CORPUS}/data/presets.json"))

# Options that Reformat never applies are out of scope for v1 (ADR-0003 / map "Out of scope").
DROP_KEYS = {"ij_wrap_on_typing", "ij_visual_guides"}
DROP_TABS = {"Code Generation", "Imports"}

SAMPLE_FILES = {
    "Tabs and Indents": "INDENT_SETTINGS",
    "Spaces": "SPACING_SETTINGS",
    "Wrapping and Braces": "WRAPPING_AND_BRACES_SETTINGS",
    "Blank Lines": "BLANK_LINES_SETTINGS",
    "Arrangement": "LANGUAGE_SPECIFIC",
}
CUSTOM_SAMPLES = {
    ("PHP", "PHPDoc"): "PhpDocCodeStylePanel__PHPDoc.txt",
    ("PHP", "Code Conversion"): "PhpConversionCodeStylePanel__Code_Conversion.txt",
    ("TypeScript", "Punctuation"): "TypeScriptCodeStyleMainPanel$1__Punctuation.txt",
    ("Shell Script", "General"): "ShCodeStylePanel__Other.txt",
}


def short_key(ec, lang_prefix):
    if ec == "indent_style":
        return "use_tab_character"
    for p in (f"ij_{lang_prefix}_", "ij_"):
        if ec.startswith(p):
            return ec[len(p):]
    return ec


def slug(label):
    return re.sub(r"[^a-z0-9]+", "_", label.lower()).strip("_")


class Lang:
    def __init__(self, lid, name, page, catalog_id, prefix, ts, syntax, sample_dir):
        self.id, self.name, self.page, self.prefix = lid, name, page, prefix
        self.ts, self.syntax, self.sample_dir = ts, syntax, sample_dir
        self.cat = {o["key"]: o for o in cat[catalog_id]["options"]}
        self.catalog_id = catalog_id

    def opt_from_node(self, ec, label, kind, node):
        if ec in DROP_KEYS or not ec:
            return None
        c = self.cat.get(ec, {})
        key = short_key(ec, self.prefix)
        o = {"t": "option", "key": key, "label": label.rstrip(":").strip()}
        if kind in ("checkbox", "JCheckBox"):
            o["type"] = "boolean"
            d = c.get("default", "false")
            o["default"] = d in ("true", "tab")
        elif kind in ("int_field", "IntegerField"):
            o["type"] = "integer"
            rng = c.get("range", {})
            o["min"] = node.get("min", rng.get("min", 0))
            o["max"] = node.get("max", rng.get("max", 999))
            try:
                o["default"] = int(c.get("default", node.get("text", "0")))
            except ValueError:
                o["default"] = 0
            if ec == "max_line_length" and self.id != "general":
                o["inherit"] = "general.max_line_length"
                o["default"] = None
        elif kind in ("combo", "wrap_combo"):
            o["type"] = "choice"
            vals = c.get("values") or []
            by_int = {v.get("int"): v for v in vals}
            choices = []
            for ch in node.get("choices", []):
                if isinstance(ch, str):
                    choices.append({"id": slug(ch), "label": ch})
                    continue
                v = by_int.get(ch.get("int"))
                choices.append({"id": v["value"] if v else slug(ch["ui"]), "label": ch["ui"]})
            if not choices:
                choices = [{"id": v["value"], "label": v["ui"]} for v in vals]
            o["choices"] = choices
            o["default"] = c.get("default", choices[0]["id"] if choices else "")
            if o["default"] not in [x["id"] for x in choices] and choices:
                o["default"] = choices[0]["id"]
        elif kind == "text_field":
            o["type"] = "string"
            o["default"] = c.get("default", "")
        else:
            return None
        return o

    def tree(self, nodes):
        rows = []
        for n in nodes:
            k = n.get("kind")
            if k == "group":
                rows.append({"t": "group", "label": n["label"], "children": self.tree(n.get("children", []))})
            elif k == "wrap_combo":
                g = {"t": "group", "label": n["label"], "children": self.tree(n.get("children", []))}
                g["option"] = self.opt_from_node(n.get("editorconfig_name"), n["label"], k, n)
                rows.append(g)
            else:
                o = self.opt_from_node(n.get("editorconfig_name"), n.get("label", ""), k, n)
                if o:
                    rows.append(o)
        return rows

    def indent_editor(self, tab):
        rows = []
        for c in tab["controls_in_order"]:
            cls = c["class"]
            if cls == "JLabel":
                continue
            label = c.get("label") or c.get("text")
            o = self.opt_from_node(c.get("editorconfig_name"), label, cls, c)
            if o:
                rows.append(o)
        for o in rows:
            if o["key"] == "smart_tabs":
                o["dep"] = {"key": "use_tab_character", "is": True}
        return rows

    def blank_lines(self, tab):
        return [{"t": "group", "label": g["group"],
                 "children": [o for o in (self.opt_from_node(x["editorconfig_name"], x["label"], x["kind"], x)
                                          for x in g["options"]) if o]}
                for g in tab["groups"]]

    def custom(self, tabname, tab):
        rows, groups = [], {}
        prev_bool = None
        for c in tab["controls_in_order"]:
            if "stores" in c and "no ij key" in c["stores"] or "application setting" in c.get("stores", ""):
                continue
            ec = c.get("editorconfig_name")
            o = OVERRIDES.get(ec)
            if o == "skip":
                continue
            if o is not None:
                o = dict(o, t="option", key=short_key(ec, self.prefix))
            elif c["kind"] == "list_field" and c.get("editorconfig_names"):
                members = ["@" + short_key(e, self.prefix)[:-len("_weight")] for e in c["editorconfig_names"]]
                o = {"t": "option", "key": "phpdoc_tag_order", "label": "PHPDoc tag order", "type": "order",
                     "default": members}
            elif c["kind"] == "radio" and prev_bool:
                cv = self.cat.get(ec, {})
                o = {"t": "option", "key": short_key(ec, self.prefix), "label": "Style", "type": "choice",
                     "choices": [{"id": v["value"], "label": v["ui"]} for v in cv.get("values", [])],
                     "default": cv.get("default"), "dep": {"key": prev_bool, "is": True}, "indent": 1}
            else:
                o = self.opt_from_node(ec, c["label"], c["kind"], c)
            if not o:
                continue
            if o["type"] == "boolean":
                prev_bool = o["key"]
            g = c.get("group")
            if g:
                if g not in groups:
                    groups[g] = {"t": "group", "label": g, "children": []}
                    rows.append(groups[g])
                groups[g]["children"].append(o)
            else:
                rows.append(o)
        return rows

    def sample(self, tabname):
        f = CUSTOM_SAMPLES.get((self.page, tabname))
        path = (f"{CORPUS}/data/code-samples/_custom_panels/{f}" if f else
                f"{CORPUS}/data/code-samples/{self.sample_dir}/{SAMPLE_FILES.get(tabname, 'LANGUAGE_SPECIFIC')}.txt")
        if not self.sample_dir or not os.path.exists(path):
            return None
        return open(path).read()

    def build(self):
        tabs = []
        for tn, t in ui[self.page]["tabs"].items():
            if tn in DROP_TABS:
                continue
            k = t["kind"]
            if k == "option_tree":
                rows = self.tree(t["tree"])
            elif k == "indent_options_editor":
                rows = self.indent_editor(t)
            elif k == "blank_lines_form":
                rows = self.blank_lines(t)
            elif k == "custom_panel":
                rows = self.custom(tn, t)
            elif k == "arrangement":
                rows = [{"t": "note", "label": "Arrangement rule editor: not part of this prototype"},
                        {"t": "note", "label": "(it is still in the fog of the map, see \"Not yet specified\")"}]
            else:
                continue
            tabs.append({"name": tn, "rows": rows, "sample": self.sample(tn)})
        out = {"id": self.id, "name": self.name, "tabs": tabs}
        if self.ts:
            out["ts"], out["syntax"] = self.ts, self.syntax
        out["presets"] = sorted(p["name"] for p in presets["presets"].values() if p.get("language") == self.page)
        return out


def ch(*pairs):
    return [{"id": a, "label": b} for a, b in pairs]


OVERRIDES = {
    # PhpStorm stores these as two booleans; the Option is one choice (ADR-0003).
    "ij_php_lower_case_boolean_const": {"label": "Convert True/False constants to", "type": "choice",
                                        "choices": ch(("as_is", "Don't convert"), ("lower", "Lower case"), ("upper", "Upper case")),
                                        "default": "as_is"},
    "ij_php_upper_case_boolean_const": "skip",
    "ij_php_lower_case_null_const": {"label": "Convert Null constant to", "type": "choice",
                                     "choices": ch(("as_is", "Don't convert"), ("lower", "Lower case"), ("upper", "Upper case")),
                                     "default": "as_is"},
    "ij_php_upper_case_null_const": "skip",
    "ij_php_else_if_style": {"label": "Convert else if/elseif to", "type": "choice",
                             "choices": ch(("as_is", "Don't convert"), ("separate", "else if"), ("combine", "elseif")),
                             "default": "as_is"},
    "ij_php_import_sorting": {"label": "Sort 'use' statements", "type": "choice",
                              "choices": ch(("dont_sort", "Don't sort"), ("alphabetic", "Alphabetically"), ("by_length", "By length")),
                              "default": "alphabetic"},
    "ij_php_null_type_position": {"label": "Place 'null' in types", "type": "choice",
                                  "choices": ch(("dont_force", "Don't force"), ("in_the_beginning", "In the beginning"), ("in_the_end", "In the end")),
                                  "default": "in_the_end"},
    "ij_php_reformat_null_type_position": {"label": "Reorder 'null' in types on reformatting", "type": "choice",
                                           "choices": ch(("dont_force", "Don't reorder"), ("in_the_beginning", "In the beginning"), ("in_the_end", "In the end")),
                                           "default": "dont_force"},
    "ij_typescript_use_semicolon_after_statement": {"label": "Semicolon after statement", "type": "choice",
                                                    "choices": ch(("use", "Use"), ("dont_use", "Don't use")), "default": "use"},
    "ij_typescript_force_semicolon_style": {"label": "Semicolon rule applies", "type": "choice",
                                            "choices": ch(("generated", "In code generated by IDE"), ("always", "Always")),
                                            "default": "always", "indent": 1},
    "ij_typescript_use_double_quotes": {"label": "Quotes", "type": "choice",
                                        "choices": ch(("double", "Double"), ("single", "Single")), "default": "double"},
    "ij_typescript_force_quote_style": {"label": "Quote rule applies", "type": "choice",
                                        "choices": ch(("generated", "In code generated by IDE"), ("always", "Always")),
                                        "default": "generated", "indent": 1},
}


def general():
    rows = [
        {"t": "option", "key": "line_separator", "label": "Line separator", "type": "choice",
         "choices": ch(("system", "System-Dependent"), ("lf", "Unix and macOS (\\n)"), ("crlf", "Windows (\\r\\n)"), ("cr", "Classic Mac OS (\\r)")),
         "default": "system"},
        {"t": "option", "key": "max_line_length", "label": "Hard wrap at", "type": "integer", "min": 1, "max": 1000, "default": 120},
        {"t": "option", "key": "insert_final_newline", "label": "Ensure every saved file ends with a line break", "type": "boolean", "default": False},
        {"t": "group", "label": "Formatter control", "children": [
            {"t": "option", "key": "formatter_tags_enabled", "label": "Turn formatter on/off with markers in code comments", "type": "boolean", "default": False},
            {"t": "option", "key": "formatter_off_tag", "label": "Formatter off", "type": "string", "default": "@formatter:off", "dep": {"key": "formatter_tags_enabled", "is": True}},
            {"t": "option", "key": "formatter_on_tag", "label": "Formatter on", "type": "string", "default": "@formatter:on", "dep": {"key": "formatter_tags_enabled", "is": True}},
        ]},
    ]
    return {"id": "general", "name": "General", "tabs": [{"name": "General", "rows": rows, "sample": None}], "presets": []}


def lua(v, ind=0):
    pad = "  " * ind
    if v is None:
        return "nil"
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, (int, float)):
        return str(v)
    if isinstance(v, str):
        return json.dumps(v, ensure_ascii=False)
    if isinstance(v, list):
        if not v:
            return "{}"
        return "{\n" + "".join(f"{pad}  {lua(x, ind + 1)},\n" for x in v) + pad + "}"
    if isinstance(v, dict):
        items = [(k, x) for k, x in v.items() if x is not None]
        return "{\n" + "".join(f"{pad}  [{json.dumps(k)}] = {lua(x, ind + 1)},\n" for k, x in items) + pad + "}"
    raise TypeError(v)


langs = [
    general(),
    Lang("php", "PHP", "PHP", "php", "php", "php", "php", "PHP").build(),
    Lang("typescript", "TypeScript", "TypeScript", "typescript", "typescript", "typescript", "typescript", "TypeScript").build(),
    Lang("shell", "Shell Script", "Shell Script", "shell-script", "shell", "bash", "sh", "Shell_Script").build(),
    Lang("json", "JSON", "JSON", "json", "json", "json", "json", "JSON").build(),
]
data = {"languages": langs, "kept": [{"id": "yaml", "count": 3}]}
os.makedirs(os.path.dirname(OUT), exist_ok=True)
with open(OUT, "w") as f:
    f.write("-- PROTOTYPE (throwaway). Generated by prototype/menu/gen_data.py from the Research Corpus. Do not edit.\n")
    f.write("return " + lua(data) + "\n")
print("wrote", OUT)
