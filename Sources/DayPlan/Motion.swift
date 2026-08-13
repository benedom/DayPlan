import SwiftUI

// MARK: - Timing

/// One place for every animation curve in the app, so a row in the menu bar and
/// the same row in the main window move at the same speed.
enum Motion {
    /// Small, immediate state flips: checkboxes, chevrons, badges.
    static let snap = Animation.snappy(duration: 0.22, extraBounce: 0.12)
    /// Something the eye should follow: rows entering or leaving a list.
    static let list = Animation.spring(response: 0.34, dampingFraction: 0.82)
    /// Pointer feedback, fast enough to feel attached to the cursor.
    static let hover = Animation.easeOut(duration: 0.13)
    /// Layout that grows or collapses: disclosure sections, revealed fields.
    static let reveal = Animation.smooth(duration: 0.26)
    /// Content appearing for the first time (popover, empty states).
    static let appear = Animation.smooth(duration: 0.32)
    /// The sun sliding along the day arc. Slower and looser than a row flip,
    /// so a completed todo reads as the sun *travelling* rather than jumping.
    static let arc = Animation.spring(response: 0.75, dampingFraction: 0.7)

    /// Rows animate in bottom-up, out to the leading edge. Insertions read as
    /// "added", removals as "filed away" rather than as a jump cut.
    static var rowTransition: AnyTransition {
        .asymmetric(
            insertion: .move(edge: .top).combined(with: .opacity),
            removal: .move(edge: .leading).combined(with: .opacity)
        )
    }
}

// MARK: - Button feel

/// Plain button that dips slightly while held. Used for every icon-sized control.
struct PressableStyle: ButtonStyle {
    var scale: CGFloat = 0.86

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .animation(Motion.snap, value: configuration.isPressed)
    }
}

extension View {
    /// Grows a touch while hovered. Cheap affordance for borderless icon buttons.
    func hoverLift(_ amount: CGFloat = 1.12) -> some View {
        modifier(HoverLift(amount: amount))
    }
}

private struct HoverLift: ViewModifier {
    let amount: CGFloat
    @State private var hovering = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(hovering ? amount : 1)
            .animation(Motion.hover, value: hovering)
            .onHover { hovering = $0 }
    }
}

// MARK: - Completion toggle

/// The check circle, shared by the main list and the menu bar popover.
/// Toggling fires a symbol replace, a bounce, and a one-shot ring that expands
/// out of the circle, the only celebratory moment in the app.
struct CompletionToggle: View {
    @Bindable var todo: Todo
    var size: CGFloat = 15

    /// Bumped on every completion so `symbolEffect` re-fires; also drives the ring.
    @State private var completions = 0
    @State private var ring = false

    var body: some View {
        Button {
            withAnimation(Motion.snap) { todo.toggleDone() }
            if todo.isDone {
                completions += 1
                ring = true
                withAnimation(.easeOut(duration: 0.45)) { ring = false }
            }
        } label: {
            Image(systemName: todo.isDone ? "largecircle.fill.circle" : "circle")
                .font(.system(size: size))
                .foregroundStyle(todo.isDone ? Color.accentColor : Color.secondary)
                .contentTransition(.symbolEffect(.replace.downUp))
                .symbolEffect(.bounce, value: completions)
                .overlay {
                    Circle()
                        .stroke(Color.accentColor, lineWidth: 2)
                        .scaleEffect(ring ? 1.9 : 0.7)
                        .opacity(ring ? 0.55 : 0)
                        .frame(width: size, height: size)
                        .allowsHitTesting(false)
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
    }
}

// MARK: - Title

/// Title text whose strikethrough and dimming ease in instead of snapping.
struct TodoTitleText: View {
    let title: String
    let isDone: Bool
    var lineLimit: Int = 2

    var body: some View {
        Text(title)
            .strikethrough(isDone, color: .secondary)
            .foregroundStyle(isDone ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
            .opacity(isDone ? 0.75 : 1)
            .lineLimit(lineLimit)
            .animation(Motion.snap, value: isDone)
    }
}
