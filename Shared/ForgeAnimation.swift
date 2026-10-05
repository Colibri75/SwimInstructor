import SwiftUI

/// Ladeanzeige im Stil des App-Symbols: Der Hammer holt aus, schlägt auf den Gipfel und Funken sprühen.
/// Ersetzt den Spinner neben Lade- und Erstell-Texten auf iPhone und Watch. Bei "Bewegung reduzieren" steht das
/// Symbol still. Rein dekorativ, den Zustand nennt der Text daneben.
struct ForgeAnimation: View {
    var size: CGFloat = 22

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Dauer eines Schlags in Sekunden.
    private static let period: Double = 0.9

    var body: some View {
        TimelineView(.animation(minimumInterval: nil, paused: reduceMotion)) { timeline in
            let phase: Double? = reduceMotion ? nil : timeline.date.timeIntervalSinceReferenceDate
                .truncatingRemainder(dividingBy: Self.period) / Self.period
            Canvas { context, canvasSize in
                Self.draw(in: &context, size: canvasSize, phase: phase)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    // MARK: - Zeichnen (Koordinaten wie im Symbol, 1024 × 1024)

    private static let hammerColor = Color(red: 1.0, green: 159 / 255, blue: 67 / 255)
    private static let sparkColor = Color(red: 1.0, green: 209 / 255, blue: 102 / 255)
    /// Ende des Stiels, um das der Hammer schwingt.
    private static let pivot = CGPoint(x: 922.5, y: 622.5)
    private static let maxLift: Double = 32
    /// Funken: Anfang am Gipfel, Ende außen.
    private static let sparks: [(CGPoint, CGPoint)] = [
        (CGPoint(x: 415, y: 415), CGPoint(x: 355, y: 350)),
        (CGPoint(x: 395, y: 485), CGPoint(x: 305, y: 480)),
        (CGPoint(x: 455, y: 385), CGPoint(x: 445, y: 300))
    ]

    /// `phase` läuft je Schlag von 0 bis 1; `nil` zeichnet das ruhende Symbol.
    private static func draw(in context: inout GraphicsContext, size: CGSize, phase: Double?) {
        let scale = min(size.width, size.height) / 1024
        context.scaleBy(x: scale, y: scale)

        var peak = Path()
        peak.move(to: CGPoint(x: 150, y: 840))
        peak.addLine(to: CGPoint(x: 470, y: 480))
        peak.addLine(to: CGPoint(x: 790, y: 840))
        context.stroke(peak, with: .color(.primary),
                       style: StrokeStyle(lineWidth: 92, lineCap: .round, lineJoin: .round))

        let (lift, sparkProgress) = motion(phase)

        var hammer = context
        hammer.translateBy(x: pivot.x, y: pivot.y)
        hammer.rotate(by: .degrees(lift))
        hammer.translateBy(x: 630 - pivot.x, y: 330 - pivot.y)
        hammer.rotate(by: .degrees(-45))
        hammer.scaleBy(x: 1.05, y: 1.05)
        var handle = Path()
        handle.move(to: CGPoint(x: -24, y: 40))
        handle.addLine(to: CGPoint(x: 24, y: 40))
        handle.addLine(to: CGPoint(x: 24, y: 370))
        handle.addQuadCurve(to: CGPoint(x: 0, y: 394), control: CGPoint(x: 24, y: 394))
        handle.addQuadCurve(to: CGPoint(x: -24, y: 370), control: CGPoint(x: -24, y: 394))
        handle.closeSubpath()
        hammer.fill(handle, with: .color(hammerColor))
        var head = Path()
        head.move(to: CGPoint(x: -150, y: -56))
        head.addLine(to: CGPoint(x: 40, y: -56))
        head.addLine(to: CGPoint(x: 124, y: -32))
        head.addLine(to: CGPoint(x: 124, y: 32))
        head.addLine(to: CGPoint(x: 40, y: 56))
        head.addLine(to: CGPoint(x: -150, y: 56))
        head.closeSubpath()
        hammer.fill(head, with: .color(hammerColor))
        hammer.stroke(head, with: .color(hammerColor), style: StrokeStyle(lineWidth: 18, lineJoin: .round))

        guard let sparkProgress else { return }
        var spark = context
        spark.opacity = 1 - sparkProgress * sparkProgress
        let reach = phase == nil ? 1 : 0.35 + 0.65 * sparkProgress
        for (start, end) in sparks {
            var line = Path()
            line.move(to: start)
            line.addLine(to: CGPoint(x: start.x + (end.x - start.x) * reach, y: start.y + (end.y - start.y) * reach))
            spark.stroke(line, with: .color(sparkColor), style: StrokeStyle(lineWidth: 34, lineCap: .round))
        }
    }

    /// Ausholen (langsam), Schlag (schnell), dann Funken. Liefert den Hubwinkel in Grad und den Fortschritt der
    /// Funken (0 bis 1, `nil` = keine Funken). Ohne Animation ruht der Hammer auf dem Gipfel, die Funken stehen.
    private static func motion(_ phase: Double?) -> (lift: Double, sparks: Double?) {
        guard let phase else { return (0, 0) }
        switch phase {
        case ..<0.55:
            let t = phase / 0.55
            return (maxLift * (1 - (1 - t) * (1 - t)), nil)
        case ..<0.68:
            let t = (phase - 0.55) / 0.13
            return (maxLift * (1 - t * t), nil)
        default:
            return (0, (phase - 0.68) / 0.32)
        }
    }
}

#Preview {
    HStack(spacing: 12) {
        ForgeAnimation()
        Text("Dein Coach schreibt deinen Plan …")
    }
    .padding()
}
