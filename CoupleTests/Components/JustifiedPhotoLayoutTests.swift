import CoreGraphics
import Testing
@testable import Couple

struct JustifiedPhotoLayoutTests {
    @Test func rowUsesTheFullContainerWidth() throws {
        let spacing: CGFloat = 8
        let ratios: [CGFloat] = [2 / 3, 1.5, 0.75]
        let rows = JustifiedPhotoLayout.rows(
            containerWidth: 350,
            spacing: spacing,
            idealRowHeight: 144,
            aspectRatios: ratios
        )
        let row = try #require(rows.first)
        let contentWidth = row.range.reduce(CGFloat.zero) { width, index in
            width + row.height * JustifiedPhotoLayout.displayedAspectRatio(ratios[index])
        }
        let renderedWidth = contentWidth + spacing * CGFloat(row.range.count - 1)

        #expect(abs(renderedWidth - 350) < 0.001)
    }

    @Test func everyWrappedRowUsesTheFullContainerWidth() {
        let containerWidth: CGFloat = 350
        let spacing: CGFloat = 8
        let ratios: [CGFloat] = [1.5, 1.5, 0.67, 0.67, 0.67, 1.5]
        let rows = JustifiedPhotoLayout.rows(
            containerWidth: containerWidth,
            spacing: spacing,
            idealRowHeight: 144,
            aspectRatios: ratios
        )

        #expect(rows.count > 1)
        for row in rows {
            let contentWidth = row.range.reduce(CGFloat.zero) { width, index in
                width + row.height * JustifiedPhotoLayout.displayedAspectRatio(ratios[index])
            }
            let renderedWidth = contentWidth + spacing * CGFloat(row.range.count - 1)
            #expect(abs(renderedWidth - containerWidth) < 0.001)
        }
    }

    @Test(
        "Invalid and extreme ratios stay within tile bounds",
        arguments: [
            (CGFloat.zero, CGFloat(1)),
            (CGFloat.infinity, CGFloat(1)),
            (CGFloat(0.2), CGFloat(0.6)),
            (CGFloat(3), CGFloat(2))
        ]
    )
    func aspectRatioIsSafe(input: CGFloat, expected: CGFloat) {
        #expect(JustifiedPhotoLayout.displayedAspectRatio(input) == expected)
    }
}
