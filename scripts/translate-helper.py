#!/usr/bin/env python3
"""
translate-helper.py – Ferramenta de apoio à tradução do Doctum RPA (fork n8n).

Comandos:
  status         Progresso da tradução por locale
  diff           Chaves presentes em en que faltam no locale alvo
  missing        Lista todas as chaves não traduzidas
  export-missing Exporta chaves faltantes para JSON (para tradução em lote)
  validate       Verifica problemas: variáveis de interpolação, plurais, valores vazios

Uso:
  python3 scripts/translate-helper.py <comando> [--locale pt] [--layer main|design|mcp]
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
from pathlib import Path

# ── Paths ────────────────────────────────────────────────────────────────────

REPO_ROOT = Path(__file__).resolve().parent.parent

LAYERS = {
    "main": {
        "label": "Main UI (i18n)",
        "en": REPO_ROOT / "packages/frontend/@n8n/i18n/src/locales/en.json",
        "pattern": "packages/frontend/@n8n/i18n/src/locales/{locale}.json",
        "type": "json",
    },
    "design": {
        "label": "Design System",
        "en": REPO_ROOT / "packages/frontend/@n8n/design-system/src/locale/lang/en.ts",
        "pattern": "packages/frontend/@n8n/design-system/src/locale/lang/{locale}.ts",
        "type": "ts",
    },
    "mcp": {
        "label": "MCP Apps",
        "en": REPO_ROOT / "packages/@n8n/mcp-apps/src/locales/en.json",
        "pattern": "packages/@n8n/mcp-apps/src/locales/{locale}.json",
        "type": "json",
    },
}

# ── Key extraction ───────────────────────────────────────────────────────────

def load_json_keys(path: Path) -> dict[str, str]:
    """Load a flat JSON locale file and return {key: value}."""
    if not path.exists():
        return {}
    with open(path, encoding="utf-8") as f:
        return json.load(f)


def extract_ts_keys(path: Path) -> dict[str, str]:
    """Extract string-valued keys from the design-system .ts locale file.

    Keys whose values are arrow functions are stored with value '<function>'
    so they still count for coverage but aren't compared for interpolation.
    """
    if not path.exists():
        return {}

    text = path.read_text(encoding="utf-8")
    keys: dict[str, str] = {}

    # Match 'key.name': 'string value' (possibly multiline continuation)
    # and   'key.name': (args) => ... (function values)
    pattern = re.compile(
        r"'([a-zA-Z][a-zA-Z0-9_.]+)':\s*"
        r"(?:"
        r"'((?:[^'\\]|\\.)*)'"         # single-quoted string value
        r"|\"((?:[^\"\\\n]|\\.)*)\""    # double-quoted string value
        r"|\(.*?\)\s*=>"               # arrow function
        r"|`((?:[^`\\]|\\.)*)`"        # template literal (no interpolation)
        r")"
    )

    for m in pattern.finditer(text):
        key = m.group(1)
        if m.group(2) is not None:
            keys[key] = m.group(2)
        elif m.group(3) is not None:
            keys[key] = m.group(3)
        elif m.group(4) is not None:
            keys[key] = m.group(4)
        else:
            keys[key] = "<function>"

    return keys


def load_keys(layer: dict, locale: str | None = None) -> dict[str, str]:
    """Load keys for a layer, optionally for a specific locale (default: en)."""
    if locale is None or locale == "en":
        path = layer["en"]
    else:
        path = REPO_ROOT / layer["pattern"].format(locale=locale)

    if layer["type"] == "json":
        return load_json_keys(path)
    else:
        return extract_ts_keys(path)


def locale_path(layer: dict, locale: str) -> Path:
    return REPO_ROOT / layer["pattern"].format(locale=locale)


def find_locales(layer: dict) -> list[str]:
    """Discover existing locale files for a layer (excluding 'en')."""
    en_path = layer["en"]
    parent = en_path.parent
    ext = en_path.suffix
    locales = []
    for p in sorted(parent.glob(f"*{ext}")):
        name = p.stem
        if name != "en":
            locales.append(name)
    return locales


# ── Interpolation helpers ────────────────────────────────────────────────────

_INTERP_RE = re.compile(r"\{(\w+)\}")


def extract_interpolation_vars(value: str) -> set[str]:
    """Return the set of {variable} names in a translation string."""
    return set(_INTERP_RE.findall(value))


def count_pipe_segments(value: str) -> int:
    """Count pipe-separated plural segments (vue-i18n uses 'one | many')."""
    return len(value.split("|"))


# ── Commands ─────────────────────────────────────────────────────────────────

def cmd_status(args: argparse.Namespace) -> None:
    """Show translation progress per locale."""
    layers = [args.layer] if args.layer else list(LAYERS)

    for layer_name in layers:
        layer = LAYERS[layer_name]
        en_keys = load_keys(layer)
        total = len(en_keys)
        locales = find_locales(layer)

        if args.locale != "all":
            locales = [args.locale] if locale_path(layer, args.locale).exists() else []

        print(f"\n{'─' * 60}")
        print(f"  {layer['label']}  ({total} chaves em en)")
        print(f"  {layer['en']}")
        print(f"{'─' * 60}")

        if not locales:
            print(f"  Nenhum locale encontrado" + (f" para '{args.locale}'" if args.locale != "all" else ""))
            continue

        for loc in locales:
            loc_keys = load_keys(layer, loc)
            translated = len(set(en_keys) & set(loc_keys))
            # Exclude empty values from translated count
            empty = sum(1 for k in loc_keys if k in en_keys and isinstance(loc_keys[k], str) and loc_keys[k].strip() == "")
            effective = translated - empty
            pct = (effective / total * 100) if total else 0
            bar_len = 30
            filled = int(bar_len * pct / 100)
            bar = "█" * filled + "░" * (bar_len - filled)
            print(f"  {loc:>5}  {bar}  {effective:>5}/{total}  ({pct:.1f}%)")
            if empty:
                print(f"         ⚠  {empty} chave(s) com valor vazio")


def cmd_diff(args: argparse.Namespace) -> None:
    """Show keys in en that don't exist in the target locale."""
    layers = [args.layer] if args.layer else list(LAYERS)

    for layer_name in layers:
        layer = LAYERS[layer_name]
        en_keys = load_keys(layer)
        loc_keys = load_keys(layer, args.locale)

        missing = sorted(set(en_keys) - set(loc_keys))

        print(f"\n{'─' * 60}")
        print(f"  {layer['label']}  –  diff en → {args.locale}")
        print(f"  {len(missing)} chave(s) faltando de {len(en_keys)} total")
        print(f"{'─' * 60}")

        for key in missing:
            en_val = en_keys[key]
            if len(en_val) > 80:
                en_val = en_val[:77] + "..."
            print(f"  + {key}")
            print(f"    en: {en_val}")


def cmd_missing(args: argparse.Namespace) -> None:
    """List all untranslated/missing keys for a locale."""
    layers = [args.layer] if args.layer else list(LAYERS)
    total_missing = 0

    for layer_name in layers:
        layer = LAYERS[layer_name]
        en_keys = load_keys(layer)
        loc_keys = load_keys(layer, args.locale)

        missing = sorted(set(en_keys) - set(loc_keys))
        empty = sorted(k for k in loc_keys if k in en_keys and isinstance(loc_keys[k], str) and loc_keys[k].strip() == "")

        all_missing = sorted(set(missing) | set(empty))
        total_missing += len(all_missing)

        print(f"\n{'─' * 60}")
        print(f"  {layer['label']}  –  {args.locale}")
        print(f"  {len(missing)} ausente(s), {len(empty)} vazio(s)")
        print(f"{'─' * 60}")

        for key in all_missing:
            tag = "[vazio]" if key in empty else "[ausente]"
            print(f"  {tag:>10}  {key}")

    print(f"\n  Total: {total_missing} chave(s) não traduzida(s)")


def cmd_export_missing(args: argparse.Namespace) -> None:
    """Export missing keys to a JSON file for batch translation."""
    layers = [args.layer] if args.layer else list(LAYERS)

    for layer_name in layers:
        layer = LAYERS[layer_name]

        if layer["type"] != "json":
            print(f"\n  ⚠  {layer['label']}: export não suportado para arquivos .ts")
            print(f"     Edite manualmente: {layer['en']}")
            continue

        en_keys = load_keys(layer)
        loc_keys = load_keys(layer, args.locale)

        missing_keys = sorted(set(en_keys) - set(loc_keys))
        empty_keys = sorted(k for k in loc_keys if k in en_keys and isinstance(loc_keys[k], str) and loc_keys[k].strip() == "")
        all_keys = sorted(set(missing_keys) | set(empty_keys))

        if not all_keys:
            print(f"\n  ✓ {layer['label']}: nenhuma chave faltante para {args.locale}")
            continue

        export: dict[str, str] = {}
        for key in all_keys:
            export[key] = en_keys[key]

        out_dir = REPO_ROOT / "scripts"
        out_file = out_dir / f"missing-{layer_name}-{args.locale}.json"
        out_dir.mkdir(parents=True, exist_ok=True)

        with open(out_file, "w", encoding="utf-8") as f:
            json.dump(export, f, ensure_ascii=False, indent="\t")
            f.write("\n")

        print(f"\n  ✓ {layer['label']}: {len(all_keys)} chave(s) exportada(s)")
        print(f"    → {out_file}")
        print(f"    Traduza os valores e use merge-missing para incorporar.")


def cmd_validate(args: argparse.Namespace) -> None:
    """Check for formatting issues in a locale file."""
    layers = [args.layer] if args.layer else list(LAYERS)
    issues_total = 0

    for layer_name in layers:
        layer = LAYERS[layer_name]
        en_keys = load_keys(layer)
        loc_keys = load_keys(layer, args.locale)

        issues: list[str] = []

        common_keys = set(en_keys) & set(loc_keys)

        for key in sorted(common_keys):
            en_val = en_keys[key]
            loc_val = loc_keys[key]

            # Skip function values
            if en_val == "<function>" or loc_val == "<function>":
                continue

            # 1. Empty value
            if isinstance(loc_val, str) and loc_val.strip() == "":
                issues.append(f"  VAZIO       {key}")
                continue

            # 2. Missing interpolation variables
            en_vars = extract_interpolation_vars(en_val)
            loc_vars = extract_interpolation_vars(loc_val)

            missing_vars = en_vars - loc_vars
            extra_vars = loc_vars - en_vars

            if missing_vars:
                issues.append(
                    f"  VAR_FALTA   {key}\n"
                    f"              en:  {en_val}\n"
                    f"              {args.locale}:  {loc_val}\n"
                    f"              Faltando: {', '.join(sorted(missing_vars))}"
                )
            if extra_vars:
                issues.append(
                    f"  VAR_EXTRA   {key}\n"
                    f"              en:  {en_val}\n"
                    f"              {args.locale}:  {loc_val}\n"
                    f"              Extra: {', '.join(sorted(extra_vars))}"
                )

            # 3. Mismatched pipe plurals
            en_pipes = count_pipe_segments(en_val)
            loc_pipes = count_pipe_segments(loc_val)

            if en_pipes > 1 and en_pipes != loc_pipes:
                issues.append(
                    f"  PLURAL      {key}\n"
                    f"              en ({en_pipes} segmentos):  {en_val}\n"
                    f"              {args.locale} ({loc_pipes} segmentos):  {loc_val}"
                )

            # 4. Value identical to English (potential untranslated)
            # Only flag for strings longer than 3 chars to avoid false positives
            # on things like "OK", "ID", etc.
            # Commented out — too noisy for keys like brand names, URLs, etc.
            # if len(en_val) > 3 and en_val == loc_val:
            #     issues.append(f"  IGUAL_EN    {key}: {en_val}")

        # 5. Keys in locale that don't exist in en (orphaned)
        orphaned = sorted(set(loc_keys) - set(en_keys))
        for key in orphaned:
            issues.append(f"  ÓRFÃ        {key}  (existe em {args.locale} mas não em en)")

        issues_total += len(issues)

        print(f"\n{'─' * 60}")
        print(f"  {layer['label']}  –  validate {args.locale}")
        lp = locale_path(layer, args.locale)
        if not lp.exists():
            print(f"  ⚠  Arquivo não encontrado: {lp}")
            continue
        print(f"  {len(issues)} problema(s) encontrado(s)")
        print(f"{'─' * 60}")

        for issue in issues:
            print(issue)

    print(f"\n  Total: {issues_total} problema(s)")
    sys.exit(1 if issues_total > 0 else 0)


# ── CLI ──────────────────────────────────────────────────────────────────────

def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="translate-helper",
        description="Ferramenta de apoio à tradução do Doctum RPA (fork n8n).",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Exemplos:
  %(prog)s status                           # progresso de todos os locales
  %(prog)s status --locale pt               # progresso apenas do pt
  %(prog)s diff --locale pt --layer main    # chaves faltando em main/pt
  %(prog)s missing --locale pt              # todas as chaves não traduzidas
  %(prog)s export-missing --locale pt       # exportar faltantes para JSON
  %(prog)s validate --locale pt             # verificar problemas de formatação

Camadas (--layer):
  main    → packages/frontend/@n8n/i18n/src/locales/
  design  → packages/frontend/@n8n/design-system/src/locale/lang/
  mcp     → packages/@n8n/mcp-apps/src/locales/
""",
    )

    parser.add_argument(
        "command",
        choices=["status", "diff", "missing", "export-missing", "validate"],
        help="Comando a executar",
    )
    parser.add_argument(
        "--locale",
        default="pt",
        help="Código do locale alvo (padrão: pt). Use 'all' com status para ver todos.",
    )
    parser.add_argument(
        "--layer",
        choices=["main", "design", "mcp"],
        default=None,
        help="Camada de tradução (padrão: todas)",
    )

    return parser


def main() -> None:
    parser = build_parser()
    args = parser.parse_args()

    commands = {
        "status": cmd_status,
        "diff": cmd_diff,
        "missing": cmd_missing,
        "export-missing": cmd_export_missing,
        "validate": cmd_validate,
    }

    commands[args.command](args)


if __name__ == "__main__":
    main()
