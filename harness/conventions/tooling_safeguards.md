# Tooling-Schutzmassnahmen

## Truncation bei Edit/Write

In der Cowork-Umgebung wurden grosse Dateien (ab ca. 150 Zeilen, jede Sprache inkl. Markdown) durch Edit/Write-Aufrufe mehrfach stillschweigend abgeschnitten, besonders bei mehreren Edits hintereinander oder grossen Einfügungen (z.B. Mermaid-Blöcke). Die Tool-Antwort meldet trotzdem Erfolg.

Pflicht:

1. Vor und nach jedem Edit an Dateien über 150 Zeilen `wc -l` vergleichen und das Dateiende ansehen (`tail`).
2. Code zusätzlich syntaktisch prüfen (Befehle im Tech-Profil, Abschnitt 2: PowerShell-Parser, `tsc --noEmit`, `tofu fmt -check`/`tofu validate`).
3. Komplette Rewrites und grosse Einfügungen per Script: Bash-Heredoc mit `<< 'EOF'` oder Python-Read-Modify-Write mit `assert text.count(anchor) == 1`.
4. Edit-Tool nur für kleine, gezielte Änderungen.
5. Bei entdeckter Truncation: File aus Git wiederherstellen (`git show HEAD:<file> > <file>`), Änderungen per Script neu anwenden. Nicht mit weiteren Edits "drüberpatchen".
6. Nach jedem Code-Block die volle Test-Suite, nicht nur die Story-Tests (Truncations in fremden Files werden sonst übersehen; Test-Caches können sie verdecken).

## Sonstiges

- Keine Shell-Workarounds, die Zustand zerstören können (siehe Git-Verbote).
- Session-Summaries inline im Chat, nie als Datei im Repo.
- OneDrive (ergänzt 21.10.2026): Dateien im verbundenen Ordner können nur online verfügbar sein und lassen sich dann in der Shell nicht lesen ("Invalid argument"). Abhilfe: Ordner in OneDrive auf "Immer auf diesem Gerät behalten" stellen oder Datei einmal stagen. Warum: beim Einlesen von RDG_Base aufgetreten.
