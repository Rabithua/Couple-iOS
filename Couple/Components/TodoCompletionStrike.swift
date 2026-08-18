import SwiftUI

struct TodoCompletionStrike: Shape {
    func path(in rect: CGRect) -> Path {
        let verticalPositions: [CGFloat] = [
            0.52, 0.34, 0.62, 0.43, 0.58, 0.29, 0.54,
            0.40, 0.67, 0.37, 0.57, 0.31, 0.52
        ]
        let horizontalStep = rect.width / CGFloat(verticalPositions.count - 1)

        var path = Path()
        for (index, verticalPosition) in verticalPositions.enumerated() {
            let point = CGPoint(
                x: CGFloat(index) * horizontalStep,
                y: rect.height * verticalPosition
            )
            if index == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }
        return path
    }
}

struct TodoCompletionTitle: View {
    let title: String
    let isCompleted: Bool
    var font: Font? = nil
    var lineLimit: Int? = nil

    var body: some View {
        Text(title)
            .font(font)
            .lineLimit(lineLimit)
            .foregroundStyle(isCompleted ? AppTheme.muted : Color.primary)
            .overlay {
                TodoCompletionStrike()
                    .trim(from: 0, to: isCompleted ? 1 : 0)
                    .stroke(
                        isCompleted ? AppTheme.muted : Color.primary,
                        style: StrokeStyle(
                            lineWidth: AppTheme.todoCompletionStrikeWidth,
                            lineCap: .round,
                            lineJoin: .round
                        )
                    )
                    .frame(height: AppTheme.todoCompletionStrikeHeight)
                    .accessibilityHidden(true)
            }
    }
}
