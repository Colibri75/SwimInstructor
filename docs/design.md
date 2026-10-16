# Design

Farben, Schrift und Formen kommen aus dem Logo (`docs/logo/peaksmith-icon.svg`): der Gipfel ist das Ziel, der Hammer
das Training. Entwürfe: Artifact "PeakSmith Design-Entwürfe". Im Code stehen die Werte in `Shared/Theme.swift`.

| Name | Wert | Rolle |
|---|---|---|
| Nacht | `#22335C` | Logo, App-Icon, Widget-Grund, Karten und Tageskarte ("Dämmerung", vorher `#14213D`); Grund im Dunkeln `#18264A` |
| Glut | `#FF9F43` | nur Aktionen: Hauptknöpfe, aktiver Tab, Fortschritt, aktueller Schritt auf der Watch |
| Funke | `#FFD166` | nur Erfolge: erledigt, Bestwerte, Pausen auf der Watch, Fahne auf dem Gipfel |
| Gipfel | `#FFFFFF` | Text und Linien auf Nacht |

- Orange ist auf Weiß als Schrift nicht lesbar (etwa 2:1). Im hellen Modus ist der Akzent `#A8540A` (5,1:1), Glut
  erscheint nur als Fläche mit Navy-Schrift (`EmberButtonStyle`).
- Sportarten haben eigene Farben aus ihrem Modul (`SportModule.colorRGB`), nie Orange: Schwimmen Türkis, Rad Grün,
  Laufen Violett; im hellen Modus auf 60 % abgedunkelt.
- Schrift: SF Rounded (`fontDesign(.rounded)`), Zahlen und Titel kräftig.
- Motiv: der Gipfel-Winkel mit runden Enden (`PeakShape`, `SparkPeak`), der Gesamtplan als Berg
  (`MacroSummitProfile`: Höhe = bis dahin geplantes Training, Gipfel = Ziel).
- Listen: `themedList()` für den Grund, `cardRows()` für die Zeilen.
- Heller Modus "Morgennebel": Grund `#DCE2EC` (gedämpftes Blaugrau), Karten `#EFF2F7`, heute/diese Woche `#F2E0D0`,
  leere Spur `#C9D2E0`. Kein reines Weiß, damit die App nicht grell wirkt.
- Hell oder dunkel wählt man unter Einstellungen › Erscheinungsbild (Wie iPhone, Hell, Dunkel; `App/Appearance.swift`).
  Die Watch und die Widgets bleiben dabei, wie sie sind.
- Darunter schaltet "Farben für Grün-Schwäche" (`Theme.greenWeakKey`) die Statusfarben von Grün/Orange/Rot auf
  Nacht-Blau/Glut/Grau (`Theme.done/caution/missed(greenWeak:)`) und Laufen von Violett auf Beere. Nur iPhone-App.


## Barrierefreiheit (VoiceOver)

iPhone-App, Watch-App und Widgets müssen sich mit VoiceOver bedienen lassen. Für neue Ansichten gilt:

- **Knöpfe nur mit Symbol** (Zahnrad, Pfeile, Plus, Minus, Abspielen, Info …) bekommen `.accessibilityLabel("…")`
  mit einem deutschen Literal, das sagt, was der Knopf tut ("Vorige Woche", "Beenden"). Steht der Text sichtbar
  daneben, bekommt der Knopf das Label und der Text `.accessibilityHidden(true)`.
- **Symbole neben Text** sind Schmuck: `.accessibilityHidden(true)`. Das Symbol einer Sportart ist nur dann
  bedeutsam, wenn kein Text sie nennt; dann trägt das Element den Namen aus der Registry
  (`registry.displayName(for:)`). In `Label("…", systemImage:)` liest VoiceOver nur den Titel, da ist nichts zu tun.
- **Zusammengesetzte Zeilen und Karten** (Tageszeile, Kachel, Kopf einer Einheit, Schritt, Widget-Inhalt) werden mit
  `.accessibilityElement(children: .combine)` ein Element. Nicht kombinieren, wenn darin eigene Knöpfe stecken.
  Braucht die Zeile einen anderen Text als die Summe ihrer Teile: `children: .ignore` plus eigenes Label.
- **Diagramme** (Swift Charts) bekommen `.accessibilityLabel("…")` (was gezeigt wird) und `.accessibilityValue(…)`
  (eine kurze Zusammenfassung, z. B. Summen oder Ø/min/max). Steht dieselbe Information schon als Liste daneben,
  oder ist es nur ein Mini-Verlauf in einer Kachel, ist das Diagramm `.accessibilityHidden(true)`.
- **Die Schmiede** (`ForgeAnimation`) ist für VoiceOver stumm. Der Text daneben sagt, was passiert ("Dein Coach
  schreibt deinen Plan …"); Schmiede und Text stehen in einem Container mit `.accessibilityElement(children: .combine)`
  (in einem `Button`-Label passiert das von selbst).
- **Tippen ohne `Button`**: lieber einen `Button` (mit `.buttonStyle(.plain)`) nehmen. Wo es ein `onTapGesture` bleiben
  muss: `.accessibilityAddTraits(.isButton)` und `.accessibilityAction { … }`.
- **Auswahl** mit Häkchen: das Häkchen versteckt, die Zeile `.accessibilityAddTraits(isSelected ? .isSelected : [])`.
- **Werte, die man dreht oder schiebt** (Crown, Slider, Plus/Minus): Label nennt die Größe ("Anstrengung"), Value den
  Wert in Worten ("7 von 10, hart"); bei Crown-Eingaben zusätzlich `.accessibilityAdjustableAction`, damit Wischen
  nach oben/unten den Wert ändert.
- Alle Labels, Hints und Values sind Übersetzungsschlüssel wie jeder andere Text: Literal statt `String`-Variable,
  Eintrag in allen zehn Sprachdateien (siehe `docs/uebersetzungen.md`).
- Prüfen: Xcode › Accessibility Inspector oder auf dem Gerät VoiceOver an und einmal durch jeden Bildschirm wischen.
