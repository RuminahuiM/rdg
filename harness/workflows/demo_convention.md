# Demo-Konvention

Regelmässige Integrations-Demos zeigen, dass das Zusammenspiel mehrerer Stories funktioniert, nicht nur einzelne Unit-Tests. Sie sind bewertungsrelevant und fangen Architekturprobleme früh ab.

## Trigger

1. **Meilenstein:** Mehrere zusammenhängende Stories schliessen einen funktionalen Block ab.
2. **Vor jedem Mentor-Termin:** Aktuellen Stand integriert zeigen.
3. **Session-Ende:** Etwas Demo-würdiges ist durchgängig lauffähig fertig geworden.

## Ablage und IDs

```
sprint_journal/sprint_<n>/
├── evidence/             # 1 Markdown pro Story
└── demos/
    ├── D-001_<thema>.md
    ├── D-001_screenshot_01.png
    └── D-002_<thema>.md
```

- `D-NNN` global fortlaufend über alle Sprints. Vor dem Anlegen alle `demos/`-Ordner scannen, höchste Nummer plus 1.
- Screenshots erstellt der User und benennt sie `D-NNN_screenshot_<seq>.png` im selben Ordner.
- Demo-Markdown aus `sprint_journal/_templates/demo_template.md`: D-ID, Datum, integrierte Stories, Kontext, Befehl, vollständiger Output, Interpretation.
- Optionales Demo-Script unter `scripts/demos/<thema>.*`, self-contained und reproduzierbar, gegen die echte Laufzeitumgebung (echte Container, echte Konfiguration).

## Hinweis

Demo-Scripts möglichst nicht ins Produktiv-Image bauen; stattdessen von aussen gegen die laufende Umgebung ausführen oder per stdin in den Container geben. Framework-Eigenheiten (z.B. Startup-Hooks, die nur beim echten Serverstart laufen) im Tech-Profil notieren.
