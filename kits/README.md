# Kits

A kit is the specialist layer between global rules and a project. One kit per archetype: bot (now), api, front (later).

Each kit repo / template carries:
- `AGENTS.md` — archetype conventions, verification strategy, archetype risks. Max one page. Never repeats global hard rules.
- `.agents/skills/` — archetype-specific skills (override global ones with the same name).
- `.pi/agents/` — optional agent overrides (tintinweb gives project agents priority over global ones).
- `issues/TEMPLATE.md` and `repo-template/AGENTS.md` sections, so every new project starts factory-ready.

Merge `kits/bot/AGENTS.additions.md` into your existing bot AGENTS.md.
