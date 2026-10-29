# 📘 Kapitel 1: Einführung in Scrum

---

## 1.1 Was ist Scrum?

Scrum ist ein **leichtgewichtiges Framework** für die Entwicklung, Auslieferung und Erhaltung komplexer Produkte.  
👉 Wichtig: Es ist **kein detaillierter Projektplan** und auch **keine starre Methode**, sondern ein Rahmen, innerhalb dessen Teams ihre eigene Arbeitsweise entwickeln können.  

- **Scrum ist leichtgewichtig** → wenige Regeln, die bewusst „unvollständig“ gehalten sind.  
- **Scrum ist einfach zu verstehen** → aber schwer zu meistern.  
- **Scrum ist anpassungsfähig** → es funktioniert in Softwareprojekten, Cloud-Engineering, Forschung und sogar im Marketing.  

💡 **Kurzdefinition:**  
Scrum ist ein *iteratives* und *inkrementelles* Vorgehen, das Teams ermöglicht, regelmässig **funktionierende Ergebnisse** zu liefern, Feedback einzuholen und ihre Vorgehensweise kontinuierlich zu verbessern.

---

## 1.2 Herkunft von Scrum

- Ursprünglich inspiriert vom **Rugby-Scrum** (engl. für Gedränge): Ein Team bewegt sich geschlossen vorwärts.  
- In den 1990ern durch **Ken Schwaber** und **Jeff Sutherland** als Methode für Softwareentwicklung entwickelt.  
- Heute in vielen Branchen etabliert.  
- Offiziell dokumentiert im **Scrum Guide** (kostenlos unter [scrumguides.org](https://scrumguides.org)).  

---

## 1.3 Warum Scrum?

🔍 Klassische Projektmanagement-Methoden (z. B. **Wasserfallmodell**) gehen davon aus, dass man **alle Anforderungen im Voraus** kennt.  
❌ Das ist in der Realität von IT-Projekten oft unmöglich:  
- Anforderungen ändern sich während der Entwicklung.  
- Kunden wissen oft erst nach einem Prototyp, was sie wirklich wollen.  
- Technologien entwickeln sich rasant.  

✔ Scrum bietet hier den Vorteil, dass man **in kurzen Zyklen** (Sprints) arbeitet und regelmässig Feedback einholt.  

**Vergleich: Wasserfall vs. Scrum**

| Aspekt | Wasserfall-Modell | Scrum |
|--------|------------------|-------|
| Planung | Alles im Voraus festgelegt | Iterativ: nur für den nächsten Sprint |
| Flexibilität | Gering | Sehr hoch |
| Feedback vom Kunden | Am Ende des Projekts | Nach jedem Sprint |
| Risiken | Werden spät erkannt | Frühe Risikoerkennung |
| Teamstruktur | Stark hierarchisch | Selbstorganisiert |

---

## 1.4 Iterativ und Inkrementell

- **Iterativ** = wir wiederholen den Prozess in kurzen Zyklen (Sprints).  
- **Inkrementell** = wir liefern jedes Mal ein nutzbares Stück (Increment) des Produkts.  

⚡ **Software-Entwickler Beispiel:**  
- Iterativ: Das UI-Design für die Login-Seite wird mehrfach überarbeitet, basierend auf Feedback.  
- Inkrementell: Am Ende jedes Sprints funktioniert die Login-Seite schon ein Stück besser (erst Basis-Login, dann 2FA, dann Social-Login).  

☁️ **Cloud Engineer Beispiel (AWS):**  
- Iterativ: Erst wird ein Prototyp eines S3-Buckets mit einfacher Policy erstellt, später mit feineren IAM-Rollen und Logging.  
- Inkrementell: Nach jedem Sprint gibt es eine produktionsreifere Infrastruktur (zuerst nur S3, dann CloudFront, dann WAF & Monitoring).  

---

## 1.5 Scrum in Zahlen (Stand 2025)

- 🔹 Rund **87 % aller agilen Teams** nutzen Scrum oder Teile davon.  
- 🔹 Über **2 Millionen Scrum Master Zertifizierungen** weltweit.  
- 🔹 Scrum wird in Software-Teams, Cloud-Projekten, Start-ups und sogar im **öffentlichen Sektor** eingesetzt.  

---

## 1.6 Kernidee von Scrum in einem Bild

~~~text
+---------------------+
|   Product Backlog   |  <-- Vision & Ideen
+---------------------+
          |
          v
+---------------------+       +----------------------+
|   Sprint Planning   | ----> |   Sprint Backlog     |
+---------------------+       +----------------------+
          |
          v
   +----------------+
   |     Sprint     |  <-- 1-4 Wochen
   +----------------+
          |
          v
+---------------------+       +---------------------+
|   Sprint Review     | ----> |   Increment (Done)  |
+---------------------+       +---------------------+
          |
          v
   +----------------+
   | Retrospective  |  <-- Verbesserung des Prozesses
   +----------------+
~~~

---

## 1.7 Typisches Beispiel aus der Praxis

👨‍💻 **Software-Entwickler**:  
Ein Team entwickelt eine neue **Chat-Funktion** für eine App.  
- Sprint 1: Nur einfache Textnachrichten.  
- Sprint 2: Bilder und Emojis.  
- Sprint 3: Push-Benachrichtigungen.  
👉 Der Kunde kann nach jedem Sprint die App ausprobieren und Feedback geben.  

☁️ **Cloud Engineer (Azure)**:  
Ein Team baut eine **Serverless-Architektur**.  
- Sprint 1: Erste Azure Function + Storage.  
- Sprint 2: API Gateway & Authentifizierung.  
- Sprint 3: Logging mit Application Insights.  
👉 Das System ist nach jedem Sprint nutzbar und wächst Schritt für Schritt.  

---

✅ **Takeaway Kapitel 1:**  
Scrum ist eine **flexible, empirische Arbeitsweise**, die Teams befähigt, in kurzen Zyklen Ergebnisse zu liefern, Feedback einzuholen und sich kontinuierlich zu verbessern. Es ersetzt starre Pläne durch eine **lernorientierte Kultur**.


# 📘 Kapitel 2: Scrum-Theorie und Werte

---

## 2.1 Scrum-Theorie

Scrum basiert auf zwei wesentlichen Denkansätzen:

1. **Empirismus** → Entscheidungen basieren auf **Erfahrungen, Beobachtungen und realen Ergebnissen**.  
2. **Lean Thinking** → Fokus auf das Wesentliche, Vermeidung von Verschwendung.

---

### 2.1.1 Empirismus

👉 Empirismus bedeutet, dass wir nicht alles im Voraus planen können. Stattdessen **probieren wir Dinge aus, messen das Ergebnis und passen uns an**.

Drei Säulen stützen den empirischen Prozess in Scrum:

- **Transparenz**: Alle sehen denselben Stand.  
- **Inspektion**: Wir überprüfen regelmässig, ob wir auf Kurs sind.  
- **Adaption**: Wir passen unser Vorgehen an, wenn nötig.

⚡ **Software-Entwickler Beispiel:**  
- Ein Entwickler implementiert eine neue Suchfunktion.  
- Transparenz: Der Fortschritt ist im Sprint Backlog sichtbar.  
- Inspektion: Im Sprint Review probiert der Kunde die Funktion aus.  
- Adaption: Der Kunde wünscht eine Filterfunktion → das Team passt den nächsten Sprint an.

☁️ **Cloud Engineer Beispiel (AWS):**  
- Ein Team baut ein Kubernetes-Cluster in **EKS**.  
- Transparenz: Architektur-Diagramm und Terraform-Code liegen offen in GitHub.  
- Inspektion: Im Sprint Review zeigt das Team ein funktionierendes Cluster.  
- Adaption: Der Kunde wünscht zusätzlich **Auto-Scaling Policies** → wird in den nächsten Sprint aufgenommen.

---

### 2.1.2 Lean Thinking

Lean stammt aus der **Toyota-Produktionsphilosophie**.  
Es geht darum, **Verschwendung zu vermeiden** und nur das zu tun, was **tatsächlich Wert schafft**.

Arten von Verschwendung in IT-Projekten (nach Lean):

| Verschwendung | Beispiel Software | Beispiel Cloud |
|---------------|-------------------|----------------|
| Überproduktion | Features, die niemand nutzt | Zu viele EC2-Instanzen, die brachliegen |
| Wartezeiten | Entwickler wartet auf UI-Designs | Cloud Engineer wartet auf Freigabe von IAM-Rollen |
| Überarbeitung | Mehrfaches Refactoring wegen fehlendem Feedback | Mehrfach neu konfigurierte Netzwerke wegen fehlender Architekturentscheidungen |
| Bewegungen | Unnötige Meetings, Dokumente | Ticketsysteme mit doppeltem Aufwand |
| Fehler | Bugs im Code | Fehlkonfigurierte Security Groups |

💡 Scrum hilft, Verschwendung zu vermeiden, indem es **früh Feedback** einholt und **regelmässig liefert**.

---

## 2.2 Die drei Säulen von Scrum

Scrum steht auf den drei Säulen:

1. **Transparenz** 🔍  
2. **Inspektion** 👀  
3. **Adaption** 🔄  

---

### 2.2.1 Transparenz

Alles muss **sichtbar** sein – für Entwickler, Product Owner und Stakeholder.

- **Software-Beispiel:** Code-Reviews auf GitHub sind für alle sichtbar.  
- **Cloud-Beispiel:** Terraform-Code liegt offen im Repository, Änderungen sind nachvollziehbar.  

Ohne Transparenz → falsche Entscheidungen.  
Beispiel: Ein Entwickler arbeitet zwei Wochen an einem Feature, das längst obsolet ist – weil niemand wusste, dass sich die Prioritäten geändert haben.

---

### 2.2.2 Inspektion

Regelmässige Überprüfung der Ergebnisse und des Prozesses.  
👉 Scrum bietet dafür feste Events (z. B. Sprint Review, Retrospektive).

- **Software-Beispiel:** Testumgebung zeigt, ob ein Feature funktioniert.  
- **Cloud-Beispiel:** Monitoring in Azure Application Insights zeigt, ob die neue API performant genug ist.  

---

### 2.2.3 Adaption

Wenn sich etwas als ungeeignet herausstellt → **schnell anpassen**.  
Scrum-Teams ändern ihre Planung, nicht ihre Ziele.

- **Software-Beispiel:** Kunde findet ein Feature unpraktisch → Team baut es um.  
- **Cloud-Beispiel:** Geplante Architektur ist zu teuer in AWS → Team wechselt von RDS zu DynamoDB.  

---

## 2.3 Scrum-Werte

Die **Scrum-Werte** bilden das Fundament für Zusammenarbeit im Team:  

| Wert | Bedeutung | Software-Beispiel | Cloud-Beispiel |
|------|-----------|-------------------|----------------|
| **Commitment** 🤝 | Team verpflichtet sich, Sprint-Ziele zu erreichen | Entwickler liefert ein getestetes Login-Feature | Cloud Engineer sorgt für sichere IAM-Rollen |
| **Focus** 🎯 | Konzentration auf Sprint-Ziele | Keine Ablenkung durch Side-Projekte | Keine unnötigen Ressourcen deployen |
| **Openness** 👐 | Offene Kommunikation | Entwickler meldet Blocker früh | Cloud Engineer sagt offen, dass er keine Erfahrung mit Kubernetes hat |
| **Respect** 🙏 | Respekt für Fähigkeiten & Meinungen | Jeder Beitrag im Code-Review wird ernst genommen | Architekt respektiert Vorschlag eines Juniors zur Kostenoptimierung |
| **Courage** 🦁 | Mut, Neues auszuprobieren und Probleme anzusprechen | Entwickler wagt Refactoring eines kritischen Moduls | Cloud Engineer schlägt Migration auf Infrastructure as Code vor |

---

## 2.4 Bildliche Darstellung

~~~text
   +-------------------------+
   |    Scrum-Theorie        |
   |  Empirismus + Lean      |
   +-----------+-------------+
               |
               v
   +-------------------------+
   |   Drei Säulen           |
   |  Transparenz,           |
   |  Inspektion, Adaption   |
   +-----------+-------------+
               |
               v
   +-------------------------+
   |   Scrum-Werte           |
   |  Commitment, Focus,     |
   |  Openness, Respect,     |
   |  Courage                |
   +-------------------------+
~~~

---

## 2.5 Praxis-Szenario

👨‍💻 **Software-Entwickler (Web-App mit Login-System):**  
- Transparenz: Code liegt im Repo, Sprint-Board ist öffentlich.  
- Inspektion: Kunde testet Login im Sprint Review.  
- Adaption: Feedback → „Bitte 2FA einbauen“.  

☁️ **Cloud Engineer (Azure Kubernetes Service):**  
- Transparenz: YAML-Files im Repo dokumentieren alle Deployments.  
- Inspektion: Cluster läuft, Load Tests zeigen hohe Latenz.  
- Adaption: Team entscheidet, Autoscaling-Regeln nachzujustieren.  

---

✅ **Takeaway Kapitel 2:**  
Scrum basiert auf **Erfahrung (Empirismus)** und **Effizienz (Lean)**.  
Die drei Säulen (Transparenz, Inspektion, Adaption) sorgen dafür, dass Teams jederzeit den Kurs prüfen und anpassen können.  
Die fünf Scrum-Werte (Commitment, Focus, Openness, Respect, Courage) schaffen die notwendige **Teamkultur**, damit Scrum erfolgreich funktioniert.

# 📘 Kapitel 3: Das Scrum Team

---

## 3.1 Überblick

Ein Scrum Team ist **klein, flexibel und selbstorganisiert**.  
Es besteht immer aus drei klar definierten Rollen:

1. **Entwickler** 👩‍💻  
2. **Product Owner** 🎯  
3. **Scrum Master** 🧭  

👉 Wichtig:  
- Keine Hierarchien innerhalb des Teams.  
- Keine Sub-Teams (z. B. „Frontend-Team“ vs. „Backend-Team“).  
- Ein Team arbeitet immer auf ein **gemeinsames Produktziel** hin.  

---

## 3.2 Eigenschaften des Scrum Teams

- **Klein, aber leistungsfähig**: Optimal sind **10 oder weniger Personen**.  
- **Cross-funktional**: Alle notwendigen Fähigkeiten sind im Team vorhanden.  
- **Selbstorganisiert**: Das Team entscheidet **wie** es arbeitet – nicht das Management.  
- **End-to-End-Verantwortung**: Vom Entwurf bis zur Wartung liegt die Verantwortung im Team.  

---

## 3.3 Rolle der Entwickler 👩‍💻

Entwickler im Scrum-Team sind **alle, die aktiv am Increment arbeiten**.  
👉 Das bedeutet: Nicht nur klassische Programmierer, sondern auch Cloud Engineers, Tester, UX-Designer usw.

**Hauptaufgaben der Entwickler:**
- Erstellen des **Sprint Plans** (Wie setzen wir das Ziel um?).  
- Sicherstellen der **Qualität** (Tests, Code Reviews, Definition of Done).  
- Tägliches **Anpassen des Plans** (Daily Scrum).  
- Verantwortung für das **Increment** am Ende des Sprints.  

⚡ **Software-Entwickler Beispiel:**  
Ein Entwickler im Team kümmert sich um die Implementierung einer neuen „Passwort-zurücksetzen“-Funktion.  
- Er erstellt Tasks: API-Endpunkt, UI-Formular, Unit-Tests.  
- Im Daily Scrum meldet er, dass er beim E-Mail-Versand blockiert ist.  
- Das Team hilft ihm, und am Ende des Sprints ist die Funktion **„done“**.  

☁️ **Cloud Engineer Beispiel (Azure):**  
Eine Cloud Engineerin ist zuständig für ein **Monitoring-System**.  
- Sie setzt Azure Application Insights auf.  
- Sie erstellt ein Dashboard für die CPU-Auslastung.  
- Im Sprint Review präsentiert sie das Dashboard – Stakeholder geben Feedback („Bitte zusätzlich Memory-Auslastung anzeigen“).  

---

## 3.4 Rolle des Product Owners 🎯

Der **Product Owner** (PO) ist verantwortlich für den **Wert des Produkts**.  
👉 Es ist **immer nur eine Person**, kein Komitee.

**Hauptaufgaben des PO:**
- Definieren und Kommunizieren des **Product Goals**.  
- Pflegen und Priorisieren des **Product Backlogs**.  
- Sicherstellen, dass das Backlog **transparent und verständlich** ist.  
- Zusammenarbeit mit Stakeholdern (Kunden, Management, Nutzer).  

⚡ **Software-Entwickler Sicht:**  
Der PO ordnet die Features nach Geschäftswert.  
- Beispiel: „Login mit Social Media“ bringt mehr Nutzerwachstum als „Dark Mode“.  
- Entwickler sehen im Backlog klar, was Vorrang hat.  

☁️ **Cloud Engineer Sicht (AWS):**  
Der PO entscheidet: „Wir wollen Kosten um 30 % reduzieren“.  
- Cloud Engineers priorisieren daher **Serverless Services (Lambda)** statt teurer EC2-Instanzen.  
- PO erklärt die Vision: Kostenoptimierung → höhere Gewinnmarge.  

👉 Wichtig: Der PO bestimmt **was** entwickelt wird – nicht **wie**.

---

## 3.5 Rolle des Scrum Masters 🧭

Der **Scrum Master** ist ein **Coach, Mentor und Facilitator**.  
Er sorgt dafür, dass Scrum verstanden und richtig angewendet wird.  

**Hauptaufgaben des Scrum Masters:**
- Fördert das Verständnis der Scrum-Theorie.  
- Hilft dem Team, **Hindernisse** zu beseitigen.  
- Coacht den PO bei der **Backlog-Pflege**.  
- Moderiert Scrum-Events (Daily, Planning, Review, Retrospektive).  
- Unterstützt die Organisation bei der Einführung von Scrum.  

⚡ **Software-Entwickler Sicht:**  
Ein Daily Scrum dauert viel zu lange (30+ Minuten).  
- Scrum Master greift ein: Er erinnert ans Timeboxing (15 Minuten).  
- Ergebnis: Entwickler fokussieren sich wieder auf Blocker statt Detaildiskussionen.  

☁️ **Cloud Engineer Sicht (Azure):**  
Ein Team hat Probleme, weil Security-Rollen (IAM) nicht rechtzeitig freigegeben werden.  
- Scrum Master identifiziert den Prozess-Engpass.  
- Er organisiert ein Meeting mit dem Security-Team, um einen schnelleren Workflow zu etablieren.  

---

## 3.6 Zusammenarbeit der Rollen

Die drei Rollen ergänzen sich:  

| Rolle | Fokus | Beispiel Software | Beispiel Cloud |
|-------|-------|------------------|----------------|
| Entwickler 👩‍💻 | „Wie setzen wir es um?“ | Implementieren eines Login-Systems | Aufbau eines AKS-Clusters |
| Product Owner 🎯 | „Was hat den höchsten Wert?“ | Priorisiert Login > Dark Mode | Priorisiert Kostenoptimierung > High-Availability |
| Scrum Master 🧭 | „Wird Scrum richtig gelebt?“ | Moderiert Daily, achtet auf DoD | Hilft, Security-Blocker zu beseitigen |

---

## 3.7 Bildliche Darstellung: Scrum Team

~~~text
+--------------------------------------+
|              Scrum Team              |
+-----------------+--------------------+
| Product Owner   |  Scrum Master      |
|  (Was?)         |  (Wie Scrum läuft) |
+-----------------+--------------------+
|                Entwickler             |
|     (Wie wird das Ziel erreicht?)     |
+--------------------------------------+
          -> Gemeinsames Produktziel <-
~~~

---

## 3.8 Praxis-Szenario

👨‍💻 **Software-Entwickler-Team (E-Commerce-App):**  
- Entwickler: Arbeiten an Warenkorb- und Checkout-Features.  
- Product Owner: Priorisiert „Mobile Payment“ vor „Rabatt-Codes“.  
- Scrum Master: Achtet darauf, dass das Daily nicht zum Status-Meeting wird.  

☁️ **Cloud-Engineering-Team (AWS-Infrastruktur):**  
- Entwickler (Cloud Engineers): Automatisieren VPC-Setup mit Terraform.  
- Product Owner: Priorisiert „Kosten senken durch Spot Instances“.  
- Scrum Master: Unterstützt bei Blockern durch fehlende AWS-Accounts.  

---

✅ **Takeaway Kapitel 3:**  
Das Scrum Team besteht aus **Entwicklern, Product Owner und Scrum Master**.  
- Entwickler → liefern das Increment.  
- Product Owner → maximiert den Wert.  
- Scrum Master → sorgt für die Einhaltung von Scrum.  
Nur wenn alle Rollen zusammenspielen, kann Scrum seine volle Wirkung entfalten.

# 📘 Kapitel 4: Scrum-Artefakte

---

## 4.1 Überblick

Scrum-Artefakte dienen dazu, **Arbeit sichtbar zu machen**.  
Sie sind Werkzeuge, um **Transparenz, Inspektion und Adaption** zu ermöglichen.

Die drei Artefakte sind:

1. **Product Backlog** 📋 (Vision, alles was getan werden könnte)  
   → Commitment: **Product Goal**  
2. **Sprint Backlog** ✅ (Plan für den aktuellen Sprint)  
   → Commitment: **Sprint Goal**  
3. **Increment** 🎁 (fertiges Ergebnis am Ende des Sprints)  
   → Commitment: **Definition of Done**  

---

## 4.2 Product Backlog 📋

Das **Product Backlog** ist eine **geordnete Liste** aller Dinge, die am Produkt entwickelt werden sollen.  
👉 Es ist die **einzige Quelle** für Arbeit im Scrum-Team.  

**Eigenschaften:**
- Dynamisch → wächst und verändert sich ständig.  
- Priorisiert → der PO ordnet die Items nach Wert.  
- Transparent → für alle sichtbar.  

**Beispiele für Product Backlog Items (PBI):**

⚡ **Software-Entwickler (Web-App):**
- Login-Funktion mit E-Mail
- Passwort zurücksetzen
- Social-Login (Google, Facebook)
- Dark Mode

☁️ **Cloud Engineer (AWS):**
- S3-Bucket für Daten-Uploads
- IAM-Rollen für Zugriffskontrolle
- CloudFront CDN
- Monitoring via CloudWatch

---

### 4.2.1 Product Goal 🎯

Jedes Product Backlog hat ein **übergeordnetes Ziel**.  
👉 Es beschreibt den **Zustand des Produkts in der Zukunft**.

**Beispiele:**

- Software: „Unsere App soll eine Million Nutzer unterstützen.“  
- Cloud: „Unsere Plattform läuft vollständig serverless, um Kosten zu minimieren.“  

💡 Regel: **Nur ein Product Goal gleichzeitig** → Fokus!  

---

## 4.3 Sprint Backlog ✅

Das **Sprint Backlog** ist eine **Auswahl aus dem Product Backlog**, die das Team im aktuellen Sprint umsetzt.  
Es enthält:
1. **Sprint Goal** (Warum machen wir das?)  
2. **Ausgewählte Product Backlog Items** (Was wird gemacht?)  
3. **Plan zur Umsetzung** (Wie setzen wir es um?)  

👉 Es gehört allein den **Entwicklern** – sie entscheiden, wie die Arbeit aufgeteilt wird.

⚡ **Software-Entwickler Beispiel (2-Wochen-Sprint):**
- Sprint Goal: „Benutzer können ihr Passwort zurücksetzen.“  
- PBI: Passwort-Reset-Formular, E-Mail-Token, Integration ins Backend.  
- Plan: Tasks in GitHub Issues.  

☁️ **Cloud Engineer Beispiel (Azure):**
- Sprint Goal: „Monitoring ist für alle kritischen Services aktiv.“  
- PBI: Setup von Application Insights, Alerts für CPU-Usage, Logging ins Storage.  
- Plan: Terraform-Skripte in Repo erstellen.  

---

### 4.3.1 Sprint Goal 🎯

Das Sprint Goal ist ein **kurzer Satz**, der erklärt, warum der Sprint wertvoll ist.  

**Beispiele:**
- Software: „Benutzer können ihre Accounts selbst verwalten.“  
- Cloud: „Alle Daten sind verschlüsselt gespeichert.“  

👉 Das Sprint Goal bleibt **stabil**, auch wenn sich der Plan ändert.  

---

## 4.4 Increment 🎁

Ein **Increment** ist ein **fertiges, nutzbares Ergebnis** am Ende des Sprints.  
- Muss **bereit für Release** sein.  
- Baut auf allen vorherigen Increments auf.  
- Kann mehrere PBI enthalten.  

⚡ **Software-Entwickler Beispiel:**  
- Increment = Funktionierendes Passwort-Reset inkl. E-Mail-Token.  
- Release wäre sofort möglich.  

☁️ **Cloud Engineer Beispiel (AWS):**  
- Increment = Neuer S3-Bucket mit Lifecycle Policies + Monitoring.  
- Kunde kann den Bucket sofort nutzen.  

---

### 4.4.1 Definition of Done ✅

Die **Definition of Done (DoD)** ist ein **gemeinsames Qualitätsversprechen**.  
👉 Sie definiert, wann Arbeit wirklich **fertig** ist.

**Typische Punkte in der DoD:**
- Code geschrieben, getestet & reviewed  
- Dokumentation aktualisiert  
- Deployment automatisiert  
- Keine offenen kritischen Bugs  

**Beispiele:**

- Software-Team DoD: „Feature ist getestet (Unit + Integration), im Repo gemergt und deploybar.“  
- Cloud-Team DoD: „Infrastruktur via Terraform codiert, in Staging getestet, Security-Checks bestanden.“  

---

## 4.5 Bildliche Darstellung

~~~text
   +-------------------------+
   |      Product Backlog    |  <-- Alles, was getan werden könnte
   |   Commitment: Goal 🎯   |
   +-----------+-------------+
               |
               v
   +-------------------------+
   |      Sprint Backlog     |  <-- Auswahl für aktuellen Sprint
   |   Commitment: Goal 🎯   |
   +-----------+-------------+
               |
               v
   +-------------------------+
   |       Increment 🎁      |  <-- Fertiges Ergebnis
   | Commitment: DoD ✅      |
   +-------------------------+
~~~

---

## 4.6 Praxis-Szenario

👨‍💻 **Software-Entwickler (Mobile-App):**  
- Product Backlog: Login, Push-Nachrichten, Dark Mode.  
- Sprint Backlog (Sprint 1): Login-Basis.  
- Increment: Login mit E-Mail funktioniert.  
- DoD: Getestet, dokumentiert, deploybar.  

☁️ **Cloud Engineer (Azure):**  
- Product Backlog: Storage Accounts, Key Vault, App Gateway.  
- Sprint Backlog (Sprint 1): Key Vault für Secrets.  
- Increment: Key Vault einsatzbereit, Secrets verschlüsselt gespeichert.  
- DoD: ARM-Template im Repo, Security Review bestanden.  

---

✅ **Takeaway Kapitel 4:**  
Die Scrum-Artefakte sorgen für **Transparenz und Klarheit**:  
- Product Backlog = Vision & alles, was möglich ist.  
- Sprint Backlog = Plan für den aktuellen Sprint.  
- Increment = Fertiges, nutzbares Ergebnis.  
Mit den Commitments (Goal & DoD) wird sichergestellt, dass das Team **fokussiert und qualitätsbewusst** arbeitet.

# 📘 Kapitel 5: Scrum-Events

---

## 5.1 Überblick

Scrum-Events strukturieren die Arbeit.  
Sie schaffen **Transparenz, Inspektion und Adaption** – und reduzieren den Bedarf an unnötigen Meetings.

Die 5 offiziellen Scrum-Events sind:

1. **Der Sprint** ⏳ (Rahmen für alle Events)  
2. **Sprint Planning** 📝  
3. **Daily Scrum** ☀️  
4. **Sprint Review** 👥  
5. **Sprint Retrospektive** 🔄  

---

## 5.2 Der Sprint ⏳

- **Dauer:** 1–4 Wochen (meist 2 Wochen).  
- Enthält alle anderen Events.  
- Ziel: Lieferung eines **fertigen Increments**.  

👉 Nur der **Product Owner** darf einen Sprint abbrechen – und nur, wenn das Sprint Goal obsolet wird.

⚡ **Software Beispiel:**  
- Sprint 1: Passwort-Reset entwickeln.  
- Sprint 2: Login mit Social Media.  

☁️ **Cloud Beispiel (AWS):**  
- Sprint 1: S3-Bucket + IAM.  
- Sprint 2: Monitoring mit CloudWatch.  

---

## 5.3 Sprint Planning 📝

**Frage 1: Warum ist der Sprint wertvoll?**  
→ Sprint Goal wird gemeinsam festgelegt.  

**Frage 2: Was kann im Sprint fertiggestellt werden?**  
→ Team wählt PBIs.  

**Frage 3: Wie wird die Arbeit erledigt?**  
→ Entwickler planen Tasks.  

⚡ **Software Beispiel:**  
- Sprint Goal: „Nutzer können Passwort zurücksetzen.“  
- PBIs: Reset-Formular, Token-Logik, Mail-Versand.  

☁️ **Cloud Beispiel (Azure):**  
- Sprint Goal: „Monitoring eingerichtet.“  
- PBIs: App Insights, Alerts, Logs.  

---

## 5.4 Daily Scrum ☀️

- **Dauer:** max. 15 Minuten.  
- Jeden Tag zur gleichen Zeit.  
- Nur Entwickler sprechen – Fokus auf **Fortschritt zum Sprint Goal**.  

Fragen (klassisch, aber optional):  
1. Was habe ich seit gestern erreicht?  
2. Was mache ich heute?  
3. Was blockiert mich?  

⚡ **Software Beispiel:**  
„Ich habe Reset-Formular fertiggestellt, heute baue ich Token-Logik, ich brauche Hilfe beim Mailserver.“  

☁️ **Cloud Beispiel (AWS):**  
„Gestern Terraform-Module für IAM erstellt, heute S3-Bucket Lifecycle Rules, ich hänge bei Policy-Rechten.“  

---

## 5.5 Sprint Review 👥

- Präsentation des **Increments** an Stakeholder.  
- Fokus: **Feedback & Zusammenarbeit**.  
- Kein PowerPoint, sondern **echte Ergebnisse**.  

⚡ **Software Beispiel:**  
- Nutzer testet Passwort-Reset.  
- Feedback: „Bitte auch SMS-Option.“  

☁️ **Cloud Beispiel (Azure):**  
- Dashboard gezeigt.  
- Feedback: „Bitte zusätzlich Error-Rates der API anzeigen.“  

---

## 5.6 Sprint Retrospektive 🔄

- Reflexion: Wie lief der Sprint?  
- Themen: Zusammenarbeit, Prozesse, Tools.  
- Ziel: **Verbesserung ab nächstem Sprint**.  

⚡ **Software Beispiel:**  
- Problem: Daily Scrum zu lang.  
- Maßnahme: Timebox strikt einhalten.  

☁️ **Cloud Beispiel (AWS):**  
- Problem: Zugriffsrechte bei Security-Team dauern zu lange.  
- Maßnahme: Frühere Einbindung.  

---

## 5.7 Übersicht

~~~text
+------------------+
|      Sprint      |  <-- 1-4 Wochen
+------------------+
        |
   +------------+
   |  Planning  |
   +------------+
        |
   +------------+
   |   Daily    |
   +------------+
        |
   +------------+
   |   Review   |
   +------------+
        |
   +----------------+
   | Retrospektive  |
   +----------------+
~~~

---

✅ **Takeaway Kapitel 5:**  
Scrum-Events geben Struktur und stellen sicher, dass Teams **fokussiert, transparent und adaptiv** arbeiten.

# 📘 Kapitel 6: Praktische Umsetzung – Software-Entwickler

---

## 6.1 Typisches Szenario

Ein Team entwickelt eine **Web-App** mit folgenden Features:  
- Login & Registrierung  
- Passwort zurücksetzen  
- Rollenverwaltung  
- Dashboard  

👉 Das Team setzt Scrum ein, um Schritt für Schritt ein nutzbares Produkt zu liefern.

---

## 6.2 Product Backlog Beispiel

| Priorität | PBI |
|-----------|-----|
| Hoch | Login mit E-Mail |
| Mittel | Passwort zurücksetzen |
| Niedrig | Dark Mode |

---

## 6.3 Sprint 1 – Beispiel

- Sprint Goal: „Nutzer können sich einloggen.“  
- PBIs: Login-Formular, Authentifizierung, Session-Handling.  
- Increment: Login mit E-Mail funktioniert.  

---

## 6.4 Sprint 2 – Beispiel

- Sprint Goal: „Nutzer können ihr Passwort zurücksetzen.“  
- PBIs: Reset-Formular, E-Mail-Token.  
- Increment: Passwort-Reset nutzbar.  

---

## 6.5 Tools für Entwickler

- **GitHub Projects / Jira** für Backlog & Sprint Board  
- **CI/CD** (GitHub Actions, GitLab CI)  
- **Testing** (Jest, Selenium, Postman)  

---

✅ **Takeaway Kapitel 6:**  
Für Software-Entwickler bedeutet Scrum, regelmäßig **fertige Features** zu liefern, Feedback zu holen und Qualität hochzuhalten.


# 📘 Kapitel 7: Praktische Umsetzung – Cloud Engineers

---

## 7.1 Typisches Szenario

Ein Cloud-Team baut eine Infrastruktur in **AWS oder Azure**.  
Ziel: Bereitstellung einer sicheren, skalierbaren Plattform.

---

## 7.2 Product Backlog Beispiel

| Priorität | PBI |
|-----------|-----|
| Hoch | S3-Bucket für Daten |
| Hoch | IAM-Rollen konfigurieren |
| Mittel | Monitoring mit CloudWatch |
| Niedrig | CDN über CloudFront |

---

## 7.3 Sprint 1 – Beispiel (AWS)

- Sprint Goal: „Basis-Speicher vorhanden.“  
- PBIs: S3-Bucket, IAM-Policy.  
- Increment: Daten können hochgeladen werden.  

---

## 7.4 Sprint 2 – Beispiel (Azure)

- Sprint Goal: „Monitoring aktiv.“  
- PBIs: App Insights, Alerts, Logging.  
- Increment: Dashboard mit CPU-Usage sichtbar.  

---

## 7.5 Tools für Cloud Engineers

- **Terraform / Bicep** für Infrastructure as Code  
- **AWS CloudWatch / Azure Monitor**  
- **CI/CD** via GitHub Actions oder Azure DevOps  
- **Security Scans** (z. B. Checkov, Azure Policy)  

---

✅ **Takeaway Kapitel 7:**  
Scrum hilft Cloud-Teams, **komplexe Infrastrukturen iterativ und inkrementell** bereitzustellen.

# 📘 Kapitel 8: Typische Herausforderungen in Scrum

---

## 8.1 „ScrumBut“

👉 „Wir machen Scrum, aber …“  
Beispiele:
- Daily nur 1x pro Woche  
- Kein Review, nur Demos  
- Product Owner ist ein Komitee  

💡 Folge: Verlust von Transparenz & Feedback.

---

## 8.2 Skalierung

Mehrere Teams arbeiten am gleichen Produkt.  
👉 Lösung: **Ein Product Owner, ein Product Backlog**.  

Frameworks: SAFe, LeSS, Nexus.

---

## 8.3 Remote Scrum

Herausforderungen:
- Weniger spontane Kommunikation  
- Tools statt Whiteboards  
- Gefahr: Meetings werden zu „Monologen“  

👉 Lösung:  
- Kameras an, aktive Moderation  
- Tools wie Miro, MURAL, MS Teams, Slack  

---

✅ **Takeaway Kapitel 8:**  
Scrum scheitert oft nicht an der Theorie, sondern an der **konsequenten Anwendung**.


# 📘 Kapitel 9: Tools & Best Practices

---

## 9.1 Tools für Scrum

- **Jira**: Klassisches Enterprise-Tool  
- **Azure DevOps**: Gut für Cloud-Projekte  
- **GitHub Projects**: Ideal für Dev-Teams  
- **Trello**: Einfacher Einstieg  

---

## 9.2 Nützliche Metriken

- **Velocity**: Wie viele Story Points pro Sprint?  
- **Burndown Chart**: Arbeit im Sprint noch offen.  
- **Cumulative Flow**: Bottlenecks sichtbar machen.  

---

## 9.3 Definition of Ready (DoR)

👉 Nicht offiziell im Scrum Guide, aber oft hilfreich:  
- PBI ist klar beschrieben.  
- Akzeptanzkriterien vorhanden.  
- Abhängigkeiten geklärt.  

---

✅ **Takeaway Kapitel 9:**  
Die richtigen Tools & Metriken machen Scrum **sichtbar und messbar**.

# 📘 Kapitel 10: Fazit & Takeaways

---

## 10.1 Scrum in Kürze

- **Framework, kein Prozess**.  
- **Iterativ & inkrementell**.  
- **Rollen**: Entwickler, Product Owner, Scrum Master.  
- **Artefakte**: Product Backlog, Sprint Backlog, Increment.  
- **Events**: Sprint, Planning, Daily, Review, Retrospektive.  

---

## 10.2 Vorteile von Scrum

- Frühes Feedback von Kunden.  
- Höhere Flexibilität.  
- Transparente Zusammenarbeit.  
- Bessere Qualität durch „Definition of Done“.  

---

## 10.3 Fazit für Studierende

Scrum ist nicht nur ein Projektmanagement-Ansatz – es ist eine **Kultur der Zusammenarbeit, Transparenz und Verbesserung**.  
👉 Egal ob **Software-Entwickler** oder **Cloud Engineer**: Scrum hilft, in unsicheren, komplexen Umgebungen **wertvolle Produkte Schritt für Schritt** zu liefern.  

---

✅ **Takeaway Kapitel 10:**  
Scrum ist einfach zu verstehen, aber schwer zu meistern – die wahre Stärke liegt in der **konsequenten Anwendung** und der **gelebten Teamkultur**.

