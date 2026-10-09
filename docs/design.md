# Design

Farben, Schrift und Formen kommen aus dem Logo (`docs/logo/peaksmith-icon.svg`): der Gipfel ist das Ziel, der Hammer
das Training. Entwürfe: Artifact "Peaksmith Design-Entwürfe". Im Code stehen die Werte in `Shared/Theme.swift`.

| Name | Wert | Rolle |
|---|---|---|
| Nacht | `#14213D` | Grund im Dunkeln (`#0D1629`), Karten, die Tageskarte auf Aktuell (auch hell) |
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
