# Skills del proyecto

Instrucciones empaquetadas que Claude Code carga cuando la tarea lo amerita.
Cada carpeta es una skill: un `SKILL.md` con frontmatter (`name`, `description`)
y, opcionalmente, archivos de apoyo.

## Por qué viven aquí y no en `.claude/skills/`

`.claude/` está en `.gitignore` porque mezcla configuración local de cada
máquina. Las skills sí son del proyecto, así que se versionan en `.agents/skills/`
y se exponen a Claude Code con symlinks:

```
.agents/skills/marp-slide/      <- versionado, fuente de verdad
.claude/skills/marp-slide  ->   <- symlink local, lo que Claude Code lee
```

Después de clonar, o al agregar una skill nueva:

```bash
./scripts/link-skills.sh
```

## Cómo se usan

Se activan solas cuando la tarea coincide con su `description`, o se invocan a
mano con `/nombre-de-la-skill`.

## Origen

Portadas desde el repo ToBlame. Se dejaron fuera las que dependen de un stack o
de herramientas que este proyecto no usa: React/MUI/TypeScript, Datadog, Jira, y
las que requieren CLIs externos (`codex`, `gemini`, `perplexity`).
