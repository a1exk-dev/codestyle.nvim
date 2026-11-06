"""The four schemes: name -> {language id: INDENT_SIZE}."""
SCHEMES = {
    "default": {},
    "js8_css2": {"JavaScript": 8, "CSS": 2},
    "html2_vue4_blade2": {"HTML": 2, "Vue": 4, "Blade": 2},
    "php8": {"PHP": 8},
}


def scheme_body(langs):
    out = ""
    for lid, n in langs.items():
        out += (f'    <codeStyleSettings language="{lid}">\n      <indentOptions>\n'
                f'        <option name="INDENT_SIZE" value="{n}" />\n      </indentOptions>\n    </codeStyleSettings>\n')
    return out


def project_xml(langs):
    return ('<component name="ProjectCodeStyleConfiguration">\n  <code_scheme name="Project" version="173">\n'
            + scheme_body(langs) + "  </code_scheme>\n</component>\n")


def plain_scheme(langs):
    return '<code_scheme name="behavior" version="173">\n' + scheme_body(langs) + "</code_scheme>\n"
