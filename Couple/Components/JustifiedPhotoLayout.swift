import SwiftUI

struct JustifiedPhotoLayout: Layout {
    let idealRowHeight: CGFloat
    let spacing: CGFloat

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        let aspectRatios = subviews.map { subview in
            subview[PhotoAspectRatioLayoutKey.self]
        }
        let width = proposal.width ?? naturalWidth(for: aspectRatios)
        let rows = Self.rows(
            containerWidth: width,
            spacing: spacing,
            idealRowHeight: idealRowHeight,
            aspectRatios: aspectRatios
        )
        let height = rows.reduce(0) { $0 + $1.height }
            + spacing * CGFloat(max(rows.count - 1, 0))

        return CGSize(width: width, height: height)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        let aspectRatios = subviews.map { subview in
            Self.displayedAspectRatio(subview[PhotoAspectRatioLayoutKey.self])
        }
        let rows = Self.rows(
            containerWidth: bounds.width,
            spacing: spacing,
            idealRowHeight: idealRowHeight,
            aspectRatios: aspectRatios
        )
        var y = bounds.minY

        for row in rows {
            var x = bounds.minX
            for index in row.range {
                let isLastItem = index == row.range.last
                let width = isLastItem
                    ? bounds.maxX - x
                    : row.height * aspectRatios[index]
                subviews[index].place(
                    at: CGPoint(x: x, y: y),
                    anchor: .topLeading,
                    proposal: ProposedViewSize(width: width, height: row.height)
                )
                x += width + spacing
            }
            y += row.height + spacing
        }
    }

    static func rows(
        containerWidth: CGFloat,
        spacing: CGFloat,
        idealRowHeight: CGFloat,
        aspectRatios: [CGFloat]
    ) -> [(range: Range<Int>, height: CGFloat)] {
        guard containerWidth > 0, aspectRatios.isEmpty == false else { return [] }

        let normalizedRatios = aspectRatios.map(displayedAspectRatio)
        var rows: [(range: Range<Int>, height: CGFloat)] = []
        var rowStart = 0
        var rowAspectRatio = CGFloat.zero

        for index in normalizedRatios.indices {
            let candidateAspectRatio = rowAspectRatio + normalizedRatios[index]
            let candidateCount = index - rowStart + 1
            let candidateHeight = rowHeight(
                containerWidth: containerWidth,
                spacing: spacing,
                itemCount: candidateCount,
                aspectRatio: candidateAspectRatio
            )

            guard candidateCount > 1, candidateHeight <= idealRowHeight else {
                rowAspectRatio = candidateAspectRatio
                continue
            }

            let previousCount = candidateCount - 1
            let previousHeight = rowHeight(
                containerWidth: containerWidth,
                spacing: spacing,
                itemCount: previousCount,
                aspectRatio: rowAspectRatio
            )

            // Keep the row whose solved height stays closest to the gallery's target rhythm.
            if abs(previousHeight - idealRowHeight) < abs(candidateHeight - idealRowHeight) {
                rows.append((rowStart..<index, previousHeight))
                rowStart = index
                rowAspectRatio = normalizedRatios[index]
            } else {
                rows.append((rowStart..<(index + 1), candidateHeight))
                rowStart = index + 1
                rowAspectRatio = 0
            }
        }

        // The archive intentionally justifies its final row so the right edge never looks unfinished.
        if rowStart < normalizedRatios.count {
            let itemCount = normalizedRatios.count - rowStart
            rows.append(
                (
                    rowStart..<normalizedRatios.count,
                    rowHeight(
                        containerWidth: containerWidth,
                        spacing: spacing,
                        itemCount: itemCount,
                        aspectRatio: rowAspectRatio
                    )
                )
            )
        }

        return rows
    }

    static func displayedAspectRatio(_ aspectRatio: CGFloat) -> CGFloat {
        guard aspectRatio.isFinite, aspectRatio > 0 else { return 1 }
        return min(max(aspectRatio, 0.6), 2)
    }

    private func naturalWidth(for aspectRatios: [CGFloat]) -> CGFloat {
        let contentWidth = aspectRatios
            .map(Self.displayedAspectRatio)
            .reduce(0, +) * idealRowHeight
        return contentWidth + spacing * CGFloat(max(aspectRatios.count - 1, 0))
    }

    private static func rowHeight(
        containerWidth: CGFloat,
        spacing: CGFloat,
        itemCount: Int,
        aspectRatio: CGFloat
    ) -> CGFloat {
        let contentWidth = max(
            containerWidth - spacing * CGFloat(max(itemCount - 1, 0)),
            0
        )
        return aspectRatio > 0 ? contentWidth / aspectRatio : 0
    }
}
