# Git-Konventionen

Gilt für die Arbeit im RDG-Repo. Der Harness selbst liegt nur lokal und ist kein Teil des Repos.

Angepasst am 21.10.2026. Warum: Branching-Strategie, Merge-Strategie, Commit-Konvention und Branch-Schutz sind Teil des eigentlichen Projekts (DevOps-Aufnahme von RDG) und werden dort festgelegt und in `CONTRIBUTING.md` des Repos dokumentiert. Der Harness legt nur die Sicherheitsregeln für Claude fest. Sobald die Projekt-Konvention steht, hier darauf verweisen.

## Projekt-Konvention

| Thema | Festgelegt in | Stand |
|---|---|---|
| Branching-Strategie | RDG `CONTRIBUTING.md` | offen (Projekt, Sprint 1) |
| Merge-Strategie | RDG `CONTRIBUTING.md` | offen |
| Commit-Messages | RDG `CONTRIBUTING.md` | offen |
| Branch-Schutz / Required Checks | GitHub-Einstellungen, dokumentiert im Repo | offen |

## Sicherheitsregeln für Claude (gelten immer)

- **Goldene Regel:** Nur Files committen, die Claude in dieser Story tatsächlich angefasst hat. Bei Unsicherheit nicht stagen. Hat der User bereits selbst committet (siehe `git log`), keinen Duplikat-Commit.
- Ablauf: `git status`, nur Story-relevante Files einzeln stagen, `git diff --cached --stat` prüfen, committen, Hash und Message im Chat melden.
- Kein `git push`, kein `--force`, kein Rewriting der History ohne explizite Anweisung. Push und Merge macht der User.
- Nie `.git/index` löschen oder per `git read-tree` neu bauen. Das hat in der Vergangenheit Commits erzeugt, die das ganze Repo als gelöscht markiert haben.
- Bei Index-Problemen: `git reset --mixed HEAD`. Einzelne Files: `git checkout HEAD -- <file>` oder `git show HEAD:<file> > <file>`.
- Vor jedem Commit `git diff --cached --stat`. Mehr als 10 Deletions, die nicht geplant sind: STOPP, nicht committen, User informieren.

## Was nie ins RDG-Repo gehört

- Harness-Inhalte (Sprint Journal, Evidence, Mentor-Protokolle, Bericht, Präsentation, Steckbrief, Risk Register, TBZ-Unterlagen)
- `docs/internal/` und alles mit echten HEKS- oder Tenant-Daten
- `.env`, `*.tfvars` mit echten Werten, Zertifikate und andere Secrets, Build-Artefakte, Bundles

## Privates Semester-Repo

Die Semester-Doku für die Experten liegt in einem eigenen, privaten Repo (entschieden 21.10.2026). Was genau dort versioniert wird und was nur lokal bleibt (z.B. Harness-Regeln, TBZ-Unterlagen), wird im Kickoff (Block E) festgelegt. Die Sicherheitsregeln oben gelten auch dort.

## Ablageort der Repos

Die Repos nicht in OneDrive führen (Lock-Probleme, Dateien teils nur online verfügbar). Ort wird im Kickoff (Block E) festgelegt, Vorschlag `C:\rdg\src`.
