import XCTest
@testable import MopeliumCore

final class ConfigTests: XCTestCase {
    func testDefaultConfigCanResolveWithoutFileOrEnv() throws {
        let url = tempConfigURL()
        let config = try CLIConfigStore.resolve(fileURL: url, environment: [:])

        XCTAssertEqual(config.baseURLString, CLIConfig.defaultBaseURL)
        XCTAssertEqual(config.apiKeyEnv, CLIConfig.defaultAPIKeyEnv)
        XCTAssertEqual(config.model, CLIConfig.defaultModel)
        XCTAssertTrue(config.stream)
        XCTAssertFalse(config.apiKeyLoaded)
    }

    func testEnvironmentOverridesFileConfig() throws {
        let url = tempConfigURL()
        try CLIConfigStore.write(
            CLIConfig(
                baseURL: "https://file.example.com/v1",
                apiKeyEnv: "FILE_KEY",
                model: "file-model",
                stream: true
            ),
            to: url
        )

        let config = try CLIConfigStore.resolve(
            fileURL: url,
            environment: [
                "MOPELIUM_BASE_URL": "https://env.example.com/v1",
                "MOPELIUM_API_KEY_ENV": "ENV_KEY",
                "MOPELIUM_MODEL": "env-model",
                "MOPELIUM_STREAM": "false",
                "ENV_KEY": "secret-value"
            ]
        )

        XCTAssertEqual(config.baseURLString, "https://env.example.com/v1")
        XCTAssertEqual(config.apiKeyEnv, "ENV_KEY")
        XCTAssertEqual(config.model, "env-model")
        XCTAssertFalse(config.stream)
        XCTAssertTrue(config.apiKeyLoaded)
    }

    func testRejectsAPIKeyConfigField() {
        XCTAssertThrowsError(try CLIConfigStore.writableField(named: "api_key")) { error in
            XCTAssertTrue(error.localizedDescription.contains("Refusing to store API keys"))
        }
    }

    func testSetWritesNonSecretConfig() throws {
        let url = tempConfigURL()
        try CLIConfigStore.set("base_url", value: "https://api.example.com/v1", fileURL: url)
        try CLIConfigStore.set("model", value: "gpt-test", fileURL: url)
        try CLIConfigStore.set("api_key_env", value: "MOPELIUM_TEST_KEY", fileURL: url)

        let config = try XCTUnwrap(CLIConfigStore.read(from: url))
        XCTAssertEqual(config.baseURL, "https://api.example.com/v1")
        XCTAssertEqual(config.model, "gpt-test")
        XCTAssertEqual(config.apiKeyEnv, "MOPELIUM_TEST_KEY")
    }

    private func tempConfigURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("mopelium-config-tests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("config.json")
    }
}
