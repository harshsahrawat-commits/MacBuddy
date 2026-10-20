import SwiftUI
import MacBuddyCore

struct PebbleAvatar: View {
    var expression: PebbleExpression
    var responding = false
    var size: CGFloat = 44
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        Canvas { context, size in
            context.scaleBy(x: size.width / 44, y: size.height / 44)
            let ink = Color(red: 0.13, green: 0.22, blue: 0.13)
            var face = Path()
            face.move(to: CGPoint(x: 5, y: 24))
            face.addCurve(to: CGPoint(x: 23, y: 11), control1: CGPoint(x: 5, y: 14), control2: CGPoint(x: 14, y: 10))
            face.addCurve(to: CGPoint(x: 40, y: 25), control1: CGPoint(x: 36, y: 10), control2: CGPoint(x: 41, y: 15))
            face.addCurve(to: CGPoint(x: 22, y: 40), control1: CGPoint(x: 41, y: 36), control2: CGPoint(x: 34, y: 40))
            face.addCurve(to: CGPoint(x: 5, y: 24), control1: CGPoint(x: 11, y: 41), control2: CGPoint(x: 4, y: 35))
            context.fill(face, with: .linearGradient(Gradient(colors: [Color(red: 0.79, green: 0.85, blue: 0.71), Color(red: 0.68, green: 0.77, blue: 0.59)]), startPoint: .zero, endPoint: CGPoint(x: 40, y: 40)))
            // Five low swept spikes; the silhouette stays legible at strip size.
            var hair = Path()
            hair.move(to: CGPoint(x: 7, y: 19))
            for point in [CGPoint(x: 9,y: 9),CGPoint(x: 14,y: 12),CGPoint(x: 17,y: 4),CGPoint(x: 20,y: 10),CGPoint(x: 25,y: 3),CGPoint(x: 27,y: 10),CGPoint(x: 33,y: 5),CGPoint(x: 33,y: 12),CGPoint(x: 39,y: 10),CGPoint(x: 37,y: 21),CGPoint(x: 30,y: 16),CGPoint(x: 22,y: 18),CGPoint(x: 17,y: 15)] { hair.addLine(to: point) }
            hair.closeSubpath()
            context.fill(hair, with: .linearGradient(Gradient(colors: [Color(red: 0.90, green: 0.84, blue: 0.62), Color(red: 0.77, green: 0.69, blue: 0.46)]), startPoint: CGPoint(x: 8, y: 4), endPoint: CGPoint(x: 38, y: 23)))
            let focused = expression == .focused
            let relieved = expression == .relieved || expression == .recovering
            for x: CGFloat in [16, 29] {
                if relieved {
                    var eye = Path(); eye.move(to: CGPoint(x: x-2,y: 25)); eye.addQuadCurve(to: CGPoint(x: x+2,y: 25), control: CGPoint(x: x,y: 22))
                    context.stroke(eye, with: .color(ink), style: .init(lineWidth: 1.7, lineCap: .round))
                } else {
                    context.fill(Path(ellipseIn: CGRect(x: x-1.6,y: focused ? 24 : 22.5,width: 3.2,height: focused ? 2.5 : 4.5)), with: .color(ink))
                }
            }
            var brow = Path(); brow.move(to: CGPoint(x: 26,y: 20)); brow.addQuadCurve(to: CGPoint(x: 32,y: 19), control: CGPoint(x: 29,y: expression == .attention ? 16 : 18))
            context.stroke(brow, with: .color(ink.opacity(0.8)), style: .init(lineWidth: 1.3,lineCap: .round))
            var mouth = Path(); mouth.move(to: CGPoint(x: 19,y: 31))
            mouth.addQuadCurve(to: CGPoint(x: 27,y: 30), control: CGPoint(x: 23,y: focused || expression == .attention || expression == .checking ? 30 : 35))
            context.stroke(mouth, with: .color(ink), style: .init(lineWidth: 1.5,lineCap: .round))
            for x: CGFloat in [10, 13, 33, 36] { context.fill(Path(ellipseIn: CGRect(x:x,y:29,width:1.2,height:1.2)),with:.color(ink.opacity(0.35))) }
        }.frame(width: size, height: size)
            .rotationEffect(.degrees(responding && !reduceMotion ? -4 : 0))
            .offset(y: responding && !reduceMotion ? -1 : 0)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.22), value: responding)
            .accessibilityHidden(true)
    }
}

struct CompanionBadge: View {
    @ObservedObject var model: MonitorModel
    @ViewState private var showingReply = false
    var body: some View {
        Button { showingReply.toggle() } label: { PebbleAvatar(expression: model.companion.expression, responding: showingReply, size: 56) }
            .buttonStyle(.plain).help(model.companion.lines[0])
            .accessibilityLabel("Pebble’s check-in").accessibilityValue(model.companion.lines[0])
            .popover(isPresented: $showingReply) { CompanionReplyView(message: model.companion.lines[0]) }
    }
}
