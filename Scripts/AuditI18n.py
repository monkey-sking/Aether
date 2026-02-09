#!/usr/bin/env python3
import os
import re
import sys


def parse_strings_file(filepath: str) -> dict[str, str]:
    entries: dict[str, str] = {}
    if not os.path.exists(filepath):
        return entries

    # .strings files are often UTF-16. Fall back to UTF-8.
    content = None
    for enc in ("utf-16", "utf-8"):
        try:
            with open(filepath, "r", encoding=enc) as f:
                content = f.read()
            if content:
                break
        except Exception:
            continue

    if not content:
        return entries

    pattern = re.compile(r'"([^"]+)"\s*=\s*"([^"]*)"\s*;')
    for match in pattern.finditer(content):
        entries[match.group(1)] = match.group(2)
    return entries


def audit_i18n(resources_path: str, reference_lang: str = "en") -> bool:
    lproj_dirs = [d for d in os.listdir(resources_path) if d.endswith(".lproj")]
    all_data: dict[str, dict[str, str]] = {}

    print(f"🔍 Auditing {len(lproj_dirs)} languages in {resources_path}...")

    for lproj in sorted(lproj_dirs):
        lang = lproj.replace(".lproj", "")
        strings_path = os.path.join(resources_path, lproj, "Localizable.strings")
        all_data[lang] = parse_strings_file(strings_path)
        print(f"  ✅ Loaded {lang}: {len(all_data[lang])} keys")

    if reference_lang not in all_data:
        print(f"❌ Error: '{reference_lang}.lproj' not found. It's required as the reference.")
        return False

    reference = all_data[reference_lang]
    reference_keys = set(reference.keys())

    has_errors = False
    for lang, entries in sorted(all_data.items()):
        if lang == reference_lang:
            continue

        current_keys = set(entries.keys())
        missing = reference_keys - current_keys
        if missing:
            has_errors = True
            print(f"\n🚩 [{lang}] Missing {len(missing)} keys:")
            for key in sorted(missing):
                print(f"    - {key}")

        empty_values = [k for k, v in entries.items() if k in reference_keys and v.strip() == ""]
        if empty_values:
            has_errors = True
            print(f"\n🚩 [{lang}] Empty translations {len(empty_values)} keys:")
            for key in sorted(empty_values):
                print(f"    - {key}")

    if has_errors:
        print("\n⚠️ i18n audit failed.")
        return False

    print("\n✨ i18n audit passed.")
    return True


def main() -> int:
    script_dir = os.path.dirname(os.path.realpath(__file__))
    workspace_root = os.path.dirname(script_dir)
    resources_path = os.path.join(workspace_root, "Apps", "AetherCore", "Resources")

    if not os.path.exists(resources_path):
        print(f"❌ Path not found: {resources_path}")
        return 1

    ok = audit_i18n(resources_path)
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())

