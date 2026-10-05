import SwiftUI

/// Ladeanzeige im Stil des App-Symbols: Der Hammer holt aus, schlägt auf den Gipfel, der Berg ruckt und Funken sprühen.
/// Ersetzt den Spinner neben Lade- und Erstell-Texten auf iPhone und Watch. Bei "Bewegung reduzieren" steht das
/// Symbol still (Hammer auf dem Gipfel, Funken stehen). Rein dekorativ, den Zustand nennt der Text daneben.
///
/// Der Takt kommt aus einer eigenen Schleife, die `@State` setzt: Das zeichnet zuverlässig neu, auch in Listenzeilen
/// und Button-Beschriftungen, wo ein `TimelineView` stehen bleiben kann.
struct ForgeAnimation: View {
    var size: CGFloat = 30

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: Double?

    var body: some View {
        Canvas { context, canvasSize in
            ForgeDrawing.draw(in: &context, size: canvasSize, phase: reduceMotion ? nil : phase)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
        .task(id: reduceMotion) {
            guard !reduceMotion else {
                phase = nil
                return
            }
            let start = Date()
            while !Task.isCancelled {
                phase = Date().timeIntervalSince(start).truncatingRemainder(dividingBy: ForgeDrawing.period) / ForgeDrawing.period
                try? await Task.sleep(nanoseconds: 16_000_000)
            }
        }
    }
}

/// Zeichnung und Bewegung, Koordinaten wie im Symbol (1024 × 1024).
enum ForgeDrawing {
    /// Dauer eines Schlags in Sekunden.
    static let period: Double = 1.15

    private static let hammerColor = Color(red: 1.0, green: 159 / 255, blue: 67 / 255)
    private static let sparkColor = Color(red: 1.0, green: 209 / 255, blue: 102 / 255)
    /// Ende des Stiels, um das der Hammer schwingt.
    private static let pivot = CGPoint(x: 922.5, y: 622.5)
    /// So weit holt der Hammer aus (Grad); mehr schwingt ihn rechts aus dem Bild.
    private static let maxLift: Double = 38
    /// Wo der Hammer den Gipfel trifft.
    private static let impact = CGPoint(x: 470, y: 450)

    /// Funken: Richtung in Grad (0 = rechts, -90 = oben), Geschwindigkeit und Dicke.
    private static let sparks: [(angle: Double, speed: Double, width: Double)] = [
        (-170, 620, 30), (-150, 740, 34), (-128, 660, 28), (-110, 780, 32),
        (-92, 600, 26), (-72, 700, 30), (-52, 540, 24), (-195, 500, 24)
    ]
    /// Schwerkraft der Funken (Einheiten pro Sekunde²).
    private static let gravity: Double = 900
    /// Aufprall: Ab hier bis zum Ende des Schlags fliegen die Funken.
    private static let strikeEnd: Double = 0.6

    /// `phase` läuft je Schlag von 0 bis 1; `nil` zeichnet das ruhende Symbol.
    static func draw(in context: inout GraphicsContext, size: CGSize, phase: Double?) {
        let scale = min(size.width, size.height) / 1024
        context.scaleBy(x: scale, y: scale)

        let motion = motion(phase)

        // Berg: ruckt beim Aufprall kurz nach unten.
        var mountain = context
        mountain.translateBy(x: 0, y: 26 * motion.shake)
        var peak = Path()
        peak.move(to: CGPoint(x: 150, y: 840))
        peak.addLine(to: CGPoint(x: 470, y: 480))
        peak.addLine(to: CGPoint(x: 790, y: 840))
        mountain.stroke(peak, with: .color(.primary),
                        style: StrokeStyle(lineWidth: 92, lineCap: .round, lineJoin: .round))

        // Aufprall: heller Blitz am Gipfel.
        if motion.flash > 0 {
            var glow = context
            glow.opacity = motion.flash
            let radius = 60 + 110 * (1 - motion.flash)
            glow.fill(Path(ellipseIn: CGRect(x: impact.x - radius, y: impact.y - radius, width: radius * 2, height: radius * 2)),
                      with: .color(sparkColor.opacity(0.7)))
        }

        drawHammer(in: context, lift: motion.lift)

        guard let progress = motion.sparks else { return }
        drawSparks(in: context, progress: progress, frozen: phase == nil)
    }

    private static func drawHammer(in context: GraphicsContext, lift: Double) {
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
    }

    /// Funken fliegen im Bogen vom Gipfel weg, ziehen einen kurzen Schweif und verglühen.
    private static func drawSparks(in context: GraphicsContext, progress: Double, frozen: Bool) {
        var spark = context
        spark.opacity = frozen ? 1 : 1 - progress * progress
        let flight = (1 - strikeEnd) * period
        let time = (frozen ? 0.45 : progress) * flight
        let tail = min(time, 0.06)
        for (index, item) in sparks.enumerated() {
            // Im Ruhebild nur drei Funken, wie im Symbol.
            if frozen && index % 3 != 1 { continue }
            let radians = item.angle * .pi / 180
            func position(_ t: Double) -> CGPoint {
                CGPoint(x: impact.x + cos(radians) * item.speed * t,
                        y: impact.y + sin(radians) * item.speed * t + 0.5 * gravity * t * t)
            }
            var line = Path()
            line.move(to: position(time - tail))
            line.addLine(to: position(time))
            let width = item.width * (frozen ? 1.1 : 1 - 0.5 * progress)
            spark.stroke(line, with: .color(sparkColor), style: StrokeStyle(lineWidth: width, lineCap: .round))
        }
    }

    /// Ausholen (langsam), kurz oben halten, Schlag (schnell), dann Aufprall mit Blitz, Ruck und Funken.
    /// Ohne Animation ruht der Hammer auf dem Gipfel, die Funken stehen.
    private static func motion(_ phase: Double?) -> (lift: Double, sparks: Double?, flash: Double, shake: Double) {
        guard let phase else { return (0, 0, 0, 0) }
        switch phase {
        case ..<0.42:
            let t = phase / 0.42
            return (maxLift * (1 - (1 - t) * (1 - t)), nil, 0, 0)
        case ..<0.5:
            return (maxLift, nil, 0, 0)
        case ..<strikeEnd:
            let t = (phase - 0.5) / (strikeEnd - 0.5)
            return (maxLift * (1 - t * t * t), nil, 0, 0)
        default:
            let t = (phase - strikeEnd) / (1 - strikeEnd)
            let flash = max(0, 1 - t / 0.35)
            let shake = t < 0.2 ? sin(t / 0.2 * .pi) : 0
            return (0, t, flash, shake)
        }
    }
}

#Preview {
    VStack(spacing: 24) {
        HStack(spacing: 12) {
            ForgeAnimation()
            Text("Dein Coach schreibt deinen Plan …")
        }
        ForgeAnimation(size: 120)
    }
    .padding()
}
