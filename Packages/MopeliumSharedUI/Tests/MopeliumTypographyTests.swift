#if canImport(SwiftUI)
import XCTest
@testable import MopeliumSharedUI

final class MopeliumTypographyTests: XCTestCase {
    func testSharedTypographyRolesKeepTheCrossPlatformDesignContract() {
        let expected: [MopeliumTypographyRole: MopeliumTypographySpec] = [
            .brand: MopeliumTypographySpec(
                nominalPointSize: 28,
                weight: .semibold,
                design: .serif),
            .largeTitle: MopeliumTypographySpec(
                nominalPointSize: 30,
                weight: .semibold,
                design: .serif),
            .title: MopeliumTypographySpec(
                nominalPointSize: 20,
                weight: .semibold,
                design: .serif),
            .headline: MopeliumTypographySpec(
                nominalPointSize: 16,
                weight: .semibold,
                design: .sansSerif),
            .body: MopeliumTypographySpec(
                nominalPointSize: 14,
                weight: .regular,
                design: .sansSerif),
            .caption: MopeliumTypographySpec(
                nominalPointSize: 12,
                weight: .medium,
                design: .sansSerif),
            .metadata: MopeliumTypographySpec(
                nominalPointSize: 10,
                weight: .medium,
                design: .sansSerif),
            .monospaced: MopeliumTypographySpec(
                nominalPointSize: 13,
                weight: .regular,
                design: .monospaced),
            .chat: MopeliumTypographySpec(
                nominalPointSize: 15,
                weight: .regular,
                design: .sansSerif),
        ]

        XCTAssertEqual(Set(expected.keys), Set(MopeliumTypographyRole.allCases))
        for role in MopeliumTypographyRole.allCases {
            XCTAssertEqual(MopeliumTypography.spec(for: role), expected[role])
        }
    }
}
#endif
