import SwiftUI
import SwimInstructorCore
#if canImport(UIKit)
import UIKit
#endif

/// Farben, Schrift und Formen aus dem Logo (docs/logo): Nacht (Navy) als Grund, Glut (Orange) nur für Aktionen, Funke
/// (Gelb) nur für Erfolge, Gipfel (Weiß) für Text und Linien. Orange ist auf Weiß als Schrift nicht lesbar (etwa 2:1):
/// Im hellen Modus ist der Akzent deshalb dunkler, und Glut erscheint nur als Fläche mit Navy-Schrift.
enum Theme {
    static let night = Color(rgb: 0x14213D)
    static let ember = Color(rgb: 0xFF9F43)
    static let spark = Color(rgb: 0xFFD166)
    /// Schrift auf Glut- und Funke-Flächen.
    static let onBright = Color(rgb: 0x14213D)

    /// Akzent für Knöpfe, Links und aktive Tabs: Glut im Dunkeln, hell ein dunkleres Orange (5,1:1 auf den hellen Karten).
    static let accent = Color.dynamic(light: 0xA8540A, dark: 0xFF9F43)
    /// Grund hinter Listen: hell gedämpftes Blaugrau ("Morgennebel"), nicht grell.
    static let background = Color.dynamic(light: 0xDCE2EC, dark: 0x0D1629)
    /// Karten und Listenzeilen: hell nicht ganz weiß.
    static let card = Color.dynamic(light: 0xEFF2F7, dark: 0x14213D)
    /// Karte für "heute" und "diese Woche": Karte mit einem Hauch Glut.
    static let highlightedCard = Color.dynamic(light: 0xF2E0D0, dark: 0x30303E)
    /// Leere Spur von Balken und Ringen.
    static let track = Color.dynamic(light: 0xC9D2E0, dark: 0x26375F)

    // MARK: Grün-Schwäche

    /// Schlüssel in den UserDefaults: Farben für Grün-Schwäche (Einstellungen › Erscheinungsbild).
    static let greenWeakKey = "greenWeakColors"

    /// Status erfüllt: Grün, bei Grün-Schwäche Nacht-Blau (Blau gegen Orange trennen fast alle Farbschwächen).
    static func done(greenWeak: Bool) -> Color {
        greenWeak ? .dynamic(light: 0x2E4372, dark: 0x6FA8FF) : .green
    }

    /// Status abweichend und Hinweise: Orange, bei Grün-Schwäche Glut.
    static func caution(greenWeak: Bool) -> Color {
        greenWeak ? accent : .orange
    }

    /// Status verpasst: Rot, bei Grün-Schwäche Grau (Rot und Grün sähen gleich aus).
    static func missed(greenWeak: Bool) -> Color {
        greenWeak ? .dynamic(light: 0x868E9F, dark: 0x8C95A8) : .red
    }

    /// Text und Linien auf der Nacht-Karte (immer dunkel, auch im hellen Modus).
    static let nightSecondary = Color(rgb: 0xA9B4CC)

    /// Die Farbe einer Sportart: so, wie das Modul sie nennt, im hellen Modus dunkler, damit Symbole auf Weiß lesbar bleiben.
    /// Bei Grün-Schwäche wird Laufen Beere statt Violett, sonst sähe es aus wie Schwimmen.
    static func sport(_ id: SportID, greenWeak: Bool = false, registry: SportRegistry = .standard) -> Color {
        if greenWeak, id == .run {
            return .dynamic(light: 0xB5487F, dark: 0xF28AC0)
        }
        let rgb = registry.colorRGB(for: id)
        return .dynamic(light: darkened(rgb), dark: rgb)
    }

    /// Farbe einer Phase im Bergprofil: Grundlage Nacht, dann zunehmend Glut, Ziel Funke.
    static func phase(_ phase: MacroPhase) -> Color {
        switch phase {
        case .base: return Color.dynamic(light: 0x8C9BBE, dark: 0x2E4372)
        case .specific: return Color(rgb: 0xC27A3E)
        case .taper: return ember
        case .goalWeek: return spark
        case .maintain: return Color.dynamic(light: 0xC5CCDB, dark: 0x4A5878)
        }
    }

    /// Dunkelt eine Farbe auf 60 % ab (für hellen Grund).
    private static func darkened(_ rgb: UInt32) -> UInt32 {
        let r = UInt32(Double((rgb >> 16) & 0xFF) * 0.6)
        let g = UInt32(Double((rgb >> 8) & 0xFF) * 0.6)
        let b = UInt32(Double(rgb & 0xFF) * 0.6)
        return (r << 16) | (g << 8) | b
    }
}

extension Color {
    /// Eine Farbe aus `0xRRGGBB`.
    init(rgb: UInt32) {
        self.init(
            .sRGB,
            red: Double((rgb >> 16) & 0xFF) / 255,
            green: Double((rgb >> 8) & 0xFF) / 255,
            blue: Double(rgb & 0xFF) / 255,
            opacity: 1
        )
    }

    /// Hell und dunkel verschieden. Die Watch ist immer dunkel.
    static func dynamic(light: UInt32, dark: UInt32) -> Color {
        #if os(iOS)
        return Color(UIColor { traits in
            UIColor(Color(rgb: traits.userInterfaceStyle == .dark ? dark : light))
        })
        #else
        return Color(rgb: dark)
        #endif
    }
}

/// Der Gipfel aus dem Logo: ein Winkel mit runden Enden, als Wasserzeichen, Symbol und Fortschrittszeichen.
struct PeakShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        return path
    }
}

/// Der Gipfel mit drei Funken darüber, wie im Logo: für "erledigt" und Bestwerte.
struct SparkPeak: View {
    var size: CGFloat = 44
    var peakColor: Color = .white

    var body: some View {
        let line = size * 0.11
        ZStack {
            PeakShape()
                .stroke(peakColor, style: StrokeStyle(lineWidth: line, lineCap: .round, lineJoin: .round))
                .frame(width: size * 0.7, height: size * 0.42)
                .offset(y: size * 0.24)
            Path { path in
                let center = CGPoint(x: size / 2, y: size * 0.32)
                for angle in [-135.0, -90.0, -45.0] {
                    let radians = angle * .pi / 180
                    let inner = size * 0.2, outer = size * 0.36
                    path.move(to: CGPoint(x: center.x + cos(radians) * inner, y: center.y + sin(radians) * inner))
                    path.addLine(to: CGPoint(x: center.x + cos(radians) * outer, y: center.y + sin(radians) * outer))
                }
            }
            .stroke(Theme.spark, style: StrokeStyle(lineWidth: line * 0.6, lineCap: .round))
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
