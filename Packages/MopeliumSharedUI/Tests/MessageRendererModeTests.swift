import XCTest
@testable import MopeliumSharedUI

final class MessageRendererModeTests: XCTestCase {
    func testDefaultsToMicrosoftWhenNoPreferenceExistsAfterCutover() {
        XCTAssertEqual(
            MopeliumMessageRendererMode.resolve(
                persistedRawValue: nil,
                arguments: ["Mopelium"]),
            .microsoft)
    }

    func testPersistedPlainSafeModeIsPreserved() {
        XCTAssertEqual(
            MopeliumMessageRendererMode.resolve(
                persistedRawValue: MopeliumMessageRendererMode.plainSafe.rawValue,
                arguments: ["Mopelium"]),
            .plainSafe)
    }

    func testLaunchArgumentsOverridePersistedPreference() {
        XCTAssertEqual(
            MopeliumMessageRendererMode.resolve(
                persistedRawValue: MopeliumMessageRendererMode.microsoft.rawValue,
                arguments: ["Mopelium", MopeliumMessageRendererMode.plainSafeLaunchArgument]),
            .plainSafe)
        XCTAssertEqual(
            MopeliumMessageRendererMode.resolve(
                persistedRawValue: MopeliumMessageRendererMode.plainSafe.rawValue,
                arguments: ["Mopelium", MopeliumMessageRendererMode.microsoftLaunchArgument]),
            .microsoft)
    }

    func testPlainSafeWinsContradictoryLaunchArguments() {
        XCTAssertEqual(
            MopeliumMessageRendererMode.resolve(
                persistedRawValue: nil,
                arguments: [
                    "Mopelium",
                    MopeliumMessageRendererMode.microsoftLaunchArgument,
                    MopeliumMessageRendererMode.plainSafeLaunchArgument,
                ]),
            .plainSafe)
    }

    func testUnknownPersistedValueFailsToPlainSafe() {
        XCTAssertEqual(
            MopeliumMessageRendererMode.resolve(
                persistedRawValue: "future-value",
                arguments: ["Mopelium"]),
            .plainSafe)
    }

    func testLegacyRichPreferenceAndLaunchArgumentMigrateToMicrosoft() {
        XCTAssertEqual(
            MopeliumMessageRendererMode.resolve(
                persistedRawValue: "rich",
                arguments: ["Mopelium"]),
            .microsoft)
        XCTAssertEqual(
            MopeliumMessageRendererMode.resolve(
                persistedRawValue: MopeliumMessageRendererMode.plainSafe.rawValue,
                arguments: ["Mopelium", MopeliumMessageRendererMode.legacyRichLaunchArgument]),
            .microsoft)
    }

    func testPlainSafeRenderPlanPreservesRawTextAndLineEndings() {
        let raw = "  **first**\r\n| a | b |\r`$code$`\n公式 $x_i$ 与 \\$29.99  "
        let plan = MopeliumMessageRenderPlan.resolve(
            rawText: raw,
            isComplete: true,
            policyIsRich: true,
            rendererMode: .plainSafe)

        XCTAssertEqual(plan.displayText, raw)
        XCTAssertEqual(Data(plan.displayText.utf8), Data(raw.utf8))
        XCTAssertFalse(plan.usesRichRenderer)
    }

    func testEmptyStreamingRenderPlanUsesPlaceholderWithoutRichWork() {
        let plan = MopeliumMessageRenderPlan.resolve(
            rawText: "",
            isComplete: false,
            policyIsRich: true,
            rendererMode: .plainSafe)

        XCTAssertEqual(plan.displayText, "…")
        XCTAssertFalse(plan.usesRichRenderer)
    }

    func testCompletedEmptyMessageRemainsByteExactEmptyText() {
        let plan = MopeliumMessageRenderPlan.resolve(
            rawText: "",
            isComplete: true,
            policyIsRich: true,
            rendererMode: .plainSafe)

        XCTAssertEqual(plan.displayText, "")
        XCTAssertFalse(plan.usesRichRenderer)
    }

    func testRichModeRoutesEligibleMessagesToRichRenderer() {
        let plan = MopeliumMessageRenderPlan.resolve(
            rawText: "**assistant source**",
            isComplete: true,
            policyIsRich: true,
            rendererMode: .microsoft)

        XCTAssertEqual(plan.displayText, "**assistant source**")
        XCTAssertTrue(plan.usesRichRenderer)
        XCTAssertTrue(plan.acceptsRichDocument(rawText: "**assistant source**"))
        XCTAssertFalse(plan.acceptsRichDocument(rawText: "**older snapshot**"))
    }

    func testRolePolicyCanAlwaysForcePlainRendering() {
        let plan = MopeliumMessageRenderPlan.resolve(
            rawText: "**user source**",
            isComplete: true,
            policyIsRich: false,
            rendererMode: .microsoft)

        XCTAssertEqual(plan.displayText, "**user source**")
        XCTAssertFalse(plan.usesRichRenderer)
    }
}
