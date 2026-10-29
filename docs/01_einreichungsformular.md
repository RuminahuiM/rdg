# Einreichungsformular: eingereichter Stand

> Stand 21.10.2026, Version für die Einreichung im Teams-Kanal (Word-Datei `ITCNE25_Semesterarbeit 4 Einreichungsformular_Dodoe.docx`). Text unten ist ein Export davon. Nicht mehr ändern; Abweichungen im Projektverlauf als ADR oder im Steckbrief festhalten.
>
> Nach der Einreichung geklärt: Kubernetes-Vorgabe entfällt ausnahmsweise (Lehrer, 21.10.2026). Test-Tenant = eigener Tenant mit Azure Pay-as-you-go. Tracking-Tool noch offen (wahrscheinlich GitHub).

---

# Semesterarbeit Einreichungsformular /  Klasse ITCNE25 – 4. Semesterarbeit

Im Folgenden beschreibt der Studierende das geplante Thema seiner
Zertifikatsarbeit. Der Studierende orientiert sich dabei an dem
Bewertungsraster. Der begleitende Dozent entscheidet, ob es sich dabei
um ein geeignetes Thema handelt und fügt seine Kommentare und
Überlegungen hinzu.

Bitte die *kursiven Textteile* durch die konkreten Angaben ersetzen.

## Name und Vorname des Studierenden 

Mannale Dodoe

## Titel der Semesterarbeit

RDG als DevOps-Projekt mit KI-Wartung: Eine Pipeline, die GitHub-Issues
selbst löst

## Zu behandelnde Themenfelder / Module (bitte ankreuzen) 

<table>
<colgroup>
<col style="width: 14%" />
<col style="width: 71%" />
<col style="width: 14%" />
</colgroup>
<thead>
<tr class="header">
<th><strong>Pkt.</strong></th>
<th><strong>Themenfeld / Modul</strong></th>
<th></th>
</tr>
</thead>
<tbody>
<tr class="odd">
<td><ol type="1">
<li></li>
</ol></td>
<td>Projektmanagement (Corrado)</td>
<td>Pflicht</td>
</tr>
<tr class="even">
<td><ol start="2" type="1">
<li></li>
</ol></td>
<td>DevOps* (Armin, Thanam, Patrick)</td>
<td>☒</td>
</tr>
<tr class="odd">
<td><ol start="3" type="1">
<li></li>
</ol></td>
<td>CNC - Cloud-native Core* (Philip S.)</td>
<td>☐</td>
</tr>
<tr class="even">
<td><ol start="4" type="1">
<li></li>
</ol></td>
<td>SECM - Cyber Security Specialist</td>
<td>☐</td>
</tr>
<tr class="odd">
<td></td>
<td><strong><br />
Themen aus dem 3. Semester<br />
</strong></td>
<td></td>
</tr>
<tr class="even">
<td><ol start="5" type="1">
<li></li>
</ol></td>
<td>Relationale Datenbanken (Yves)</td>
<td>☐</td>
</tr>
<tr class="odd">
<td><ol start="6" type="1">
<li></li>
</ol></td>
<td>NoSQL, Key/Value, Time Series (Yves)</td>
<td>☐</td>
</tr>
<tr class="even">
<td><ol start="7" type="1">
<li></li>
</ol></td>
<td>Microservices mit Python (Boris)</td>
<td>☐</td>
</tr>
<tr class="odd">
<td><ol start="8" type="1">
<li></li>
</ol></td>
<td>Netzwerk (Raphael)</td>
<td>☐</td>
</tr>
</tbody>
</table>

\* Als Infrastruktur wird Kubernetes mit mindestens einer CI/CD Pipeline
erwartet.

**Kurzbeschreibung des Zertifikatsarbeit Themas  
(1 bis max. 2 Seiten)**

### Problemstellung / Ausgangslage / Potential der Semesterarbeit

**Hintergrund:** In Microsoft 365 gibt es dynamische Gruppen, die ihre
Mitglieder automatisch nach Regeln füllen (z. B. alle Benutzer einer
Abteilung). In der Praxis reichen sie oft nicht: Viele Funktionen
akzeptieren keine dynamischen Gruppen (z. B. mail-aktivierte Gruppen,
Verteilerlisten oder gewisse Defender- und Exchange-Richtlinien), man
kann Regel und manuelle Ausnahmen nicht mischen und die
Regel-Möglichkeiten sind begrenzt. Darum habe ich bei meiner Arbeit
(HEKS) das Tool RDG (Real Dynamic Groups) gebaut. RDG wertet die Regeln
selbst aus und schreibt das Resultat als normale Mitgliederliste in die
Gruppe. So funktionieren die Gruppen auch dort, wo Microsoft dynamische
Gruppen ablehnt.

**Ausgangslage:** RDG ist bisher ein MVP. Es läuft in Azure (PowerShell,
kleine Web-App, Infrastruktur mit OpenTofu) und wird bei HEKS getestet.
Das Projekt liegt aber nur in einem Ordner. Es wurde halb von Hand
eingerichtet, die Pipelines sind zwar angelegt, aber nie richtig
getestet worden, und das Deployment mache ich von Hand von meinem PC
aus. Dazu kommt: Ich werde die Firma voraussichtlich bald verlassen, und
danach gibt es niemanden, der RDG weiterpflegt. Ohne Wartung kann die
Firma das Tool wahrscheinlich nicht weiter einsetzen, was schade wäre.

**Problemstellung:** Ich möchte RDG darum als Open-Source-Projekt
veröffentlichen, das sich so weit wie möglich selbst wartet. Zuerst
setze ich es sauber als DevOps-Projekt auf. Danach soll eine KI die
Wartung übernehmen: Wenn auf GitHub ein Issue erfasst wird (z. B. ein
Bug oder eine kleine Erweiterung), soll eine Pipeline mit einem
KI-Agenten (Claude) den Code ändern, Tests schreiben, alles testen und
in eine Testumgebung deployen. Ein Mensch testet am Schluss nur noch die
fertige Version und gibt das Release frei.

**Potential:** Wenn das klappt, kann RDG auch ohne mich weiterleben und
von HEKS und anderen Firmen genutzt werden. Weil RDG ein kleines und
klar abgegrenztes Tool ist, eignet es sich gut, um auszuprobieren, wie
weit KI-gestützte Wartung heute geht. Gleichzeitig wende ich die Inhalte
aus dem DevOps-Unterricht (Git, CI/CD, Tests, Deployment, Monitoring) an
einem echten Projekt an.

### Zielsetzung der Semesterarbeit

**Z1 – Sauberes DevOps-Projekt:** RDG liegt in einem GitHub-Repository
mit dokumentierter Branching-Strategie, einem Kanban-Board mit User
Stories und Versionen nach SemVer. Auf main kann nur per Pull Request
gemergt werden, und nur wenn die CI-Pipeline grün ist. Nachweis: Ein
absichtlich fehlerhafter Pull Request wird blockiert.

**Z2 – Automatisches Deployment:** Jeder Merge auf main baut automatisch
ein Release-Paket und deployt es ohne Handarbeit in eine Testumgebung,
inklusive Smoke-Test. Ich deploye nicht mehr von meinem PC aus.
Nachweis: mindestens 5 erfolgreiche automatische Deployments in die
Testumgebung.

**Z3 – KI-Wartung (Hauptziel):** Wenn ich ein Issue mit dem Label „ai“
erfasse, startet eine Pipeline. Ein KI-Agent erstellt selbständig einen
Branch, ändert den Code, ergänzt Tests und eröffnet einen Pull Request.
Danach laufen CI und Deployment in die Testumgebung wie in Z1 und Z2.
Messbar: Von 10 vorbereiteten Test-Issues (Bugs und kleine
Erweiterungen) werden mindestens 6 gelöst, ohne dass ich selbst Code
schreibe. Pro Issue dauert es bis zur Testumgebung weniger als 1 Stunde.

**Z4 – Der Mensch entscheidet, die KI bleibt eingeschränkt:** Ein
Release gibt es nur, wenn ich die Version in der Testumgebung getestet
und von Hand freigegeben habe. Der KI-Agent kann nicht direkt auf main
pushen, hat keinen Zugriff auf die produktive Umgebung und reagiert nur
auf Issues von mir. Nachweis: Ein Test-Issue mit einer versteckten
falschen Anweisung (Prompt Injection) führt zu keiner unerlaubten
Aktion.

### Terminplan mit den wesentlichen Arbeitsschritten

**Sprint 1 (26.10. – 16.11.2026):** Planung, Backlog und Kanban-Board,
Repository sauber aufsetzen, Branch-Schutz, bestehende CI-Pipeline
reparieren und testen (Z1). Besprechung 1.

**Sprint 2 (17.11. – 14.12.2026):** Automatisches Deployment in die
Testumgebung und Release mit Freigabe (Z2, Teil von Z4). Erste einfache
Version der KI-Pipeline. Besprechung 2.

**Sprint 3 (15.12.2026 – 22.01.2027):** KI-Pipeline fertig bauen,
Sicherheitsregeln, die 10 Test-Issues durchspielen und auswerten (Z3,
Z4). Besprechung 3.

**23.01. – 27.01.2027:** Dokumentation, Reflexion, Schlusspräsentation
und Abgabe.

### Sachmittel / Rahmenbedingungen

Mein Laptop (Windows) und meine Arbeitszeit ausserhalb des Unterrichts.

GitHub: Repository und GitHub Actions (Pipelines).

Für das Projektmanagement Jira oder GitHub Projects (Entscheid in Sprint
1).

Ein Azure-Abo für die Testumgebung von RDG (Kosten ca. 27 USD pro Monat)
und ein Test-Tenant für Microsoft 365, damit keine produktiven Daten
angefasst werden.

Zugang zu Claude (Modell Opus) für den KI-Agenten, mit einem
Kostenlimit.

### Vorgaben, Methoden und Werkzeuge

**Vorgehen:** agil in 3 Sprints, Kanban-Board mit User Stories (in Jira
oder GitHub Projects), Besprechungen mit den Experten nach jedem Sprint.

**Git:** GitHub Flow, Conventional Commits, Versionen nach SemVer.

**Werkzeuge:** GitHub Actions (CI/CD), OpenTofu (Infrastruktur), Pester
und PSScriptAnalyzer (PowerShell-Tests), Vitest und ESLint (Tests und
Code-Prüfung der Web-App), Trivy (Sicherheits-Scan), Claude Code in
GitHub Actions (KI-Agent).

**Vorgaben:** Keine Passwörter oder echten Firmendaten im Repository.
Die KI arbeitet nur über Pull Requests. Ein Release gibt es nur nach
meinem Test und meiner Freigabe.

### Risiken

**KI macht falsche Änderungen (hoch):** Alle Änderungen laufen durch
Tests und die Pipeline, ich prüfe jeden Pull Request, und ein Release
gibt es nur nach meinem Test.

**Zu wenig Zeit, der KI-Teil ist schwieriger als gedacht (mittel):**
Zuerst Z1 und Z2 fertig machen, dann die KI-Pipeline Schritt für Schritt
aufbauen und mit einfachen Issues beginnen.

**Missbrauch über Issue-Texte oder zu viele Rechte (mittel):** Die
Pipeline reagiert nur auf meine Issues, der Agent bekommt nur die
nötigsten Rechte und hat keinen Zugriff auf die produktive Umgebung.

**Kosten für die KI steigen (niedrig):** Limit pro Durchlauf festlegen
und die Kosten pro Issue aufschreiben.

**Testumgebung oder Test-Tenant nicht verfügbar (mittel):** Das kläre
ich in Sprint 1. Notfalls laufen die Tests nur mit den vorhandenen
Mocks.

**Entscheid des begleitenden Dozenten**

Bitte ankreuzen

- Genehmigt ☐

- Zu verbessern ☐

- Abgelehnt ☐

**Begleitender Dozent**

Ort und Datum:
\_\_\_\_\_\_\_\_\_\_\_\_\_\_\_\_\_\_\_\_\_\_\_\_\_\_\_\_\_\_\_\_\_\_\_\_\_\_\_\_\_\_\_\_\_\_\_\_

Name & Unterschrift:
\_\_\_\_\_\_\_\_\_\_\_\_\_\_\_\_\_\_\_\_\_\_\_\_\_\_\_\_\_\_\_\_\_\_\_\_\_\_\_\_\_\_\_\_\_\_\_\_\_

**Beurteilung des Antrages**

| **Kriterium**                                                     | **Kommentare** | **Erfüllt** |
|-------------------------------------------------------------------|----------------|-------------|
| **Anforderungen an die Form (Strukturierung) der Semesterarbeit** |                |             |
| Problemstellung                                                   |                | ☐           |
| Ziele (mindestens drei!)                                          |                | ☐           |
| Risiken bezogen auf Zertifikatsarbeit                             |                | ☐           |
| Themenfelder (mindestens zwei!)                                   |                | ☐           |
| **Anforderungen an Qualität der Semesterarbeit**                  |                |             |
| Machbar                                                           |                | ☐           |
| Praxisnah                                                         |                | ☐           |
| Herausfordernd                                                    |                | ☐           |
| Lehrgangsbezug                                                    |                | ☐           |

Damit die Semesterarbeit angenommen wird, müssen alle Kriterien erfüllt
sein.

Die Kommunikation wird über den jeweiligen Teams-Kanal geführt.
