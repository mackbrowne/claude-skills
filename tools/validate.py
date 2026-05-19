#!/usr/bin/env python3
"""Validate every skills/*/SKILL.md.

Checks: YAML frontmatter present, `name` present, `description` present and
<= 1024 chars (the limit the skill triggering description must satisfy).

Requires PyYAML (`pip install pyyaml`). CI installs it.
"""
import pathlib
import sys

import yaml  # type: ignore

MAX_DESC = 1024


def validate(skill_md: pathlib.Path) -> list[str]:
    text = skill_md.read_text()
    if not text.lstrip().startswith("---"):
        return [f"{skill_md}: missing YAML frontmatter"]
    parts = text.split("---", 2)
    if len(parts) < 3:
        return [f"{skill_md}: malformed frontmatter"]
    try:
        data = yaml.safe_load(parts[1]) or {}
    except yaml.YAMLError as exc:  # pragma: no cover
        return [f"{skill_md}: invalid YAML ({exc})"]

    errs: list[str] = []
    if not data.get("name"):
        errs.append(f"{skill_md}: missing 'name'")
    desc = data.get("description")
    if not desc:
        errs.append(f"{skill_md}: missing 'description'")
    elif len(desc) > MAX_DESC:
        errs.append(
            f"{skill_md}: description is {len(desc)} chars (max {MAX_DESC})"
        )
    return errs


def main() -> None:
    root = pathlib.Path(__file__).resolve().parent.parent
    skills = sorted((root / "skills").glob("*/SKILL.md"))
    if not skills:
        print("No skills found.", file=sys.stderr)
        sys.exit(1)

    errors: list[str] = []
    for md in skills:
        errors.extend(validate(md))

    if errors:
        print("\n".join(errors), file=sys.stderr)
        sys.exit(1)
    print(f"All {len(skills)} skill(s) valid.")


if __name__ == "__main__":
    main()
