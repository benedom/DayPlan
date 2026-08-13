import SwiftUI

// MARK: - Time of day

/// Five slices of the day. Everything visual about the arc (sky, clouds,
/// stars, the colour of the travelling body) is derived from this, so the
/// header looks like the time it actually is.
enum DayPhase: CaseIterable {
    case dawn, morning, day, dusk, night

    static func current(at date: Date = Date(), calendar: Calendar = .current) -> DayPhase {
        switch calendar.component(.hour, from: date) {
        case 5..<8: return .dawn
        case 8..<11: return .morning
        case 11..<17: return .day
        case 17..<20: return .dusk
        default: return .night
        }
    }

    /// Top of the sky gradient, always the darker end.
    var skyTop: Color {
        switch self {
        case .dawn: return Color(red: 0.24, green: 0.24, blue: 0.48)
        case .morning: return Color(red: 0.20, green: 0.47, blue: 0.84)
        case .day: return Color(red: 0.12, green: 0.42, blue: 0.83)
        case .dusk: return Color(red: 0.20, green: 0.16, blue: 0.40)
        case .night: return Color(red: 0.04, green: 0.05, blue: 0.14)
        }
    }

    /// Horizon end of the gradient.
    var skyBottom: Color {
        switch self {
        case .dawn: return Color(red: 0.95, green: 0.58, blue: 0.44)
        case .morning: return Color(red: 0.55, green: 0.78, blue: 0.96)
        case .day: return Color(red: 0.46, green: 0.74, blue: 0.96)
        case .dusk: return Color(red: 0.94, green: 0.47, blue: 0.30)
        case .night: return Color(red: 0.11, green: 0.14, blue: 0.30)
        }
    }

    /// Sun for daylight, moon once it is dark.
    var travellerSymbol: String { self == .night ? "moon.fill" : "sun.max.fill" }

    var travellerColor: Color {
        switch self {
        case .dawn: return Color(red: 1.00, green: 0.86, blue: 0.62)
        case .morning, .day: return Color(red: 1.00, green: 0.89, blue: 0.38)
        case .dusk: return Color(red: 1.00, green: 0.76, blue: 0.40)
        case .night: return Color(red: 0.93, green: 0.95, blue: 1.00)
        }
    }

    /// Clouds read as clutter against a night sky; stars read as clutter at noon.
    var showsClouds: Bool { self != .night }
    var showsStars: Bool { self == .night || self == .dusk || self == .dawn }
}

// MARK: - Motivation

/// One line under the arc, picked from how far the day has got and how much of
/// the list is gone. Deliberately short, since it sits in a header, not a banner.
enum DayMessage {
    static func line(done: Int, total: Int, phase: DayPhase) -> String {
        guard total > 0 else { return "Nothing planned yet." }
        let left = total - done

        if left == 0 {
            switch phase {
            case .dawn, .morning: return "All clear before noon. Show-off."
            case .day: return "List’s empty. The day isn’t."
            case .dusk: return "Day closed out. Nicely done."
            case .night: return "Day cleared. Rest earned."
            }
        }

        if done == 0 {
            switch phase {
            case .dawn: return "Fresh page. Pick one thing."
            case .morning: return "Nothing checked yet. Start small."
            case .day: return "Half the day gone, list untouched."
            case .dusk: return "Evening’s still long enough for one."
            case .night: return "Late. One thing, then stop."
            }
        }

        if left == 1 {
            switch phase {
            case .night: return "One left. Then the day is yours."
            default: return "One left. Finish it."
            }
        }

        let fraction = Double(done) / Double(total)
        if fraction < 0.5 {
            switch phase {
            case .dawn, .morning: return "Good start. Keep the streak."
            case .day: return "Warmed up. Keep rolling."
            case .dusk: return "\(left) left before the day closes."
            case .night: return "\(left) left. Pick the easy one."
            }
        }

        switch phase {
        case .dawn, .morning: return "Ahead of the clock already."
        case .day: return "Downhill from here."
        case .dusk: return "Almost. \(left) to go."
        case .night: return "So close. One push."
        }
    }
}

// MARK: - Arc

/// The Today header: a sun (or moon) riding a half-circle from horizon to
/// horizon, where the distance travelled is the share of today’s todos that
/// are done. The sky behind it tracks the real clock, not the progress.
struct DayArcView: View {
    let done: Int
    let total: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var phase = DayPhase.current()
    /// Bumped each time the list goes from unfinished to fully done, so the
    /// celebration fires once per completion rather than on every redraw.
    @State private var celebrations = 0
    @State private var burst = false

    private let phaseTicker = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    private var fraction: Double {
        guard total > 0 else { return 0 }
        return min(1, Double(done) / Double(total))
    }

    private var message: String {
        DayMessage.line(done: done, total: total, phase: phase)
    }

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            // The arc sits on a horizon line at 70% height; text lives below it.
            let center = CGPoint(x: size.width / 2, y: size.height * 0.70)
            let radius = min(size.width * 0.30, size.height * 0.42)

            ZStack {
                sky
                ambience(size: size)
                horizon(at: center.y, width: size.width)
                arc(center: center, radius: radius)
                traveller(center: center, radius: radius)
                labels(size: size)
            }
        }
        .frame(height: 142)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(.white.opacity(0.14), lineWidth: 1)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
        .onReceive(phaseTicker) { _ in
            let now = DayPhase.current()
            if now != phase {
                withAnimation(.easeInOut(duration: 1.4)) { phase = now }
            }
        }
        .onChange(of: fraction) { _, new in
            guard new >= 1 else { return }
            celebrations += 1
            burst = true
            withAnimation(.easeOut(duration: 0.9)) { burst = false }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Today’s progress")
        .accessibilityValue("\(done) of \(total) done. \(message)")
    }

    // MARK: Sky

    private var sky: some View {
        // Keyed on the phase so a change cross-fades, because gradients don’t
        // interpolate their colours on their own.
        LinearGradient(
            colors: [phase.skyTop, phase.skyBottom],
            startPoint: .top,
            endPoint: .bottom
        )
        .id(phase)
        .transition(.opacity)
        .overlay(alignment: .bottom) {
            // Keeps the caption readable over the bright end of a daytime sky.
            LinearGradient(
                colors: [.clear, .black.opacity(0.28)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 56)
        }
    }

    /// Drifting clouds and twinkling stars. One `Canvas` for both so the whole
    /// weather layer is a single redraw per frame.
    private func ambience(size: CGSize) -> some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            Canvas { context, canvasSize in
                if phase.showsStars {
                    drawStars(in: &context, size: canvasSize, time: t)
                }
                if phase.showsClouds {
                    drawClouds(in: &context, size: canvasSize, time: t)
                }
            }
        }
        .frame(width: size.width, height: size.height)
        .allowsHitTesting(false)
    }

    private func drawStars(in context: inout GraphicsContext, size: CGSize, time: Double) {
        // Stars only make sense in the upper sky, and never over the horizon band.
        let ceiling = size.height * 0.62
        for star in Self.stars {
            let twinkle = 0.35 + 0.45 * (0.5 + 0.5 * sin(time * 1.6 + star.seed))
            let dot = Path(ellipseIn: CGRect(
                x: star.x * size.width - star.radius,
                y: star.y * ceiling - star.radius,
                width: star.radius * 2,
                height: star.radius * 2
            ))
            // Dawn and dusk keep only the brightest few.
            let fade = phase == .night ? 1.0 : 0.45
            context.fill(dot, with: .color(.white.opacity(twinkle * fade)))
        }
    }

    private func drawClouds(in context: inout GraphicsContext, size: CGSize, time: Double) {
        for cloud in Self.clouds {
            // Wrap around with a margin either side so nothing pops in mid-sky.
            let span = size.width + 160
            let x = (cloud.offset * span + time * cloud.speed).truncatingRemainder(dividingBy: span) - 80
            let y = cloud.y * size.height
            let s = cloud.scale
            var blob = Path()
            blob.addEllipse(in: CGRect(x: x, y: y, width: 46 * s, height: 17 * s))
            blob.addEllipse(in: CGRect(x: x + 11 * s, y: y - 9 * s, width: 26 * s, height: 24 * s))
            blob.addEllipse(in: CGRect(x: x + 26 * s, y: y - 5 * s, width: 20 * s, height: 18 * s))
            context.fill(blob, with: .color(.white.opacity(cloud.opacity)))
        }
    }

    // MARK: Arc

    private func horizon(at y: CGFloat, width: CGFloat) -> some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [.white.opacity(0), .white.opacity(0.30), .white.opacity(0)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .frame(width: width, height: 1)
            .position(x: width / 2, y: y)
    }

    /// Track plus the travelled portion. `trim` from 0.5 to 1 is the upper half
    /// of a circle: left horizon, over the top, to the right horizon.
    private func arc(center: CGPoint, radius: CGFloat) -> some View {
        ZStack {
            Circle()
                .trim(from: 0.5, to: 1)
                .stroke(.white.opacity(0.22), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))

            Circle()
                .trim(from: 0.5, to: 0.5 + 0.5 * fraction)
                .stroke(
                    LinearGradient(
                        colors: [phase.travellerColor.opacity(0.55), phase.travellerColor],
                        startPoint: .leading,
                        endPoint: .trailing
                    ),
                    style: StrokeStyle(lineWidth: 3.5, lineCap: .round)
                )
                .shadow(color: phase.travellerColor.opacity(0.6), radius: 4)
                .animation(Motion.arc, value: fraction)
        }
        .frame(width: radius * 2, height: radius * 2)
        .position(center)
    }

    private func traveller(center: CGPoint, radius: CGFloat) -> some View {
        // Angle 0 is the left horizon, π the right one, matching the trim above.
        let angle = Double.pi * fraction
        let point = CGPoint(
            x: center.x - radius * cos(angle),
            y: center.y - radius * sin(angle)
        )

        return ZStack {
            Circle()
                .fill(phase.travellerColor.opacity(0.35))
                .frame(width: 34, height: 34)
                .blur(radius: 9)

            Image(systemName: phase.travellerSymbol)
                .font(.system(size: 17))
                .foregroundStyle(phase.travellerColor)
                .contentTransition(.symbolEffect(.replace))
                .symbolEffect(.bounce, value: celebrations)

            // One-shot ring on hitting the last todo.
            Circle()
                .stroke(phase.travellerColor, lineWidth: 2)
                .frame(width: 26, height: 26)
                .scaleEffect(burst ? 2.6 : 0.6)
                .opacity(burst ? 0.7 : 0)
        }
        .position(point)
        .animation(Motion.arc, value: fraction)
    }

    // MARK: Text

    private func labels(size: CGSize) -> some View {
        VStack(spacing: 3) {
            HStack(spacing: 4) {
                Text("\(done)")
                    .contentTransition(.numericText(value: Double(done)))
                Text("of \(total) done")
            }
            .font(.system(.title3, design: .rounded).weight(.semibold))
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.35), radius: 3, y: 1)
            .animation(Motion.snap, value: done)

            Text(message)
                .font(.caption.weight(.medium))
                .foregroundStyle(.white.opacity(0.88))
                .shadow(color: .black.opacity(0.35), radius: 3, y: 1)
                .id(message)
                .transition(.blurReplace.combined(with: .offset(y: 3)))
                .animation(Motion.reveal, value: message)
        }
        .multilineTextAlignment(.center)
        // Both lines sit in the band between the horizon and the card edge.
        .position(x: size.width / 2, y: size.height - 22)
    }

    // MARK: Ambience data

    private struct Star {
        let x: Double
        let y: Double
        let radius: Double
        let seed: Double
    }

    private struct Cloud {
        let offset: Double
        let y: Double
        let scale: CGFloat
        let speed: Double
        let opacity: Double
    }

    /// Fixed field rather than random per launch. A star that jumps position
    /// between redraws reads as a glitch.
    private static let stars: [Star] = {
        var state: UInt64 = 0x9E37_79B9_7F4A_7C15
        func next() -> Double {
            state ^= state << 13
            state ^= state >> 7
            state ^= state << 17
            return Double(state % 10_000) / 10_000
        }
        return (0..<26).map { _ in
            Star(x: next(), y: 0.08 + next() * 0.9, radius: 0.6 + next() * 1.1, seed: next() * 6.28)
        }
    }()

    private static let clouds: [Cloud] = [
        Cloud(offset: 0.05, y: 0.14, scale: 1.0, speed: 5.5, opacity: 0.22),
        Cloud(offset: 0.45, y: 0.30, scale: 0.7, speed: 8.0, opacity: 0.16),
        Cloud(offset: 0.78, y: 0.08, scale: 1.3, speed: 3.5, opacity: 0.13),
    ]
}
