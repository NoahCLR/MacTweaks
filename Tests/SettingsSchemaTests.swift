import XCTest

final class SettingsSchemaTests: XCTestCase {
    private let suiteName = "com.ncleroy.MacTweaks.SettingsSchemaTests"

    private func emptyDefaults() -> UserDefaults {
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    override func tearDown() {
        UserDefaults().removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    func testFileValueWinsOverDefault() {
        let value = SettingsSchema.cutFilesEnabled.resolved(
            file: [SettingsKey.cutFilesEnabled: true],
            defaults: emptyDefaults()
        )
        XCTAssertTrue(value)
    }

    func testDefaultsSuiteUsedWhenFileMissing() {
        let defaults = emptyDefaults()
        defaults.set(true, forKey: SettingsKey.cutFilesEnabled)
        let value = SettingsSchema.cutFilesEnabled.resolved(file: [:], defaults: defaults)
        XCTAssertTrue(value)
    }

    func testBuiltInDefaultWhenAbsentEverywhere() {
        // openContainingFolderForFiles defaults false; masterEnabled defaults true.
        XCTAssertFalse(SettingsSchema.openContainingFolderForFiles.resolved(file: [:], defaults: emptyDefaults()))
        XCTAssertTrue(SettingsSchema.masterEnabled.resolved(file: [:], defaults: emptyDefaults()))
    }

    func testURLSettingDecodesStoredPath() {
        let value = SettingsSchema.ideApplicationURL.resolved(
            file: [SettingsKey.ideApplicationPath: "/Applications/Xcode.app"],
            defaults: emptyDefaults()
        )
        XCTAssertEqual(value, URL(fileURLWithPath: "/Applications/Xcode.app"))
    }

    func testURLSettingEmptyPathFallsBackToDefault() {
        let value = SettingsSchema.ideApplicationURL.resolved(
            file: [SettingsKey.ideApplicationPath: ""],
            defaults: emptyDefaults()
        )
        XCTAssertEqual(value, SettingsSchema.ideApplicationURL.defaultValue)
    }

    func testActionOrderRoundTripsThroughRawStrings() {
        let order = SettingsSchema.finderActionOrder
        let stored = order.encode(FinderMenuAction.defaultOrder)
        let decoded = order.resolved(file: [SettingsKey.finderActionOrder: stored], defaults: emptyDefaults())
        XCTAssertEqual(decoded, FinderMenuAction.defaultOrder)
    }

    func testDefaultStoredEncodesTheDefault() {
        XCTAssertEqual(SettingsSchema.openContainingFolderForFiles.defaultStored as? Bool, false)
        XCTAssertEqual(SettingsSchema.masterEnabled.defaultStored as? Bool, true)
    }

    func testRegistryKeysAreUniqueAndNonEmpty() {
        let keys = SettingsSchema.all.map(\.key)
        XCTAssertFalse(keys.contains(where: \.isEmpty))
        XCTAssertEqual(keys.count, Set(keys).count, "duplicate key in SettingsSchema.all")
    }

    func testEveryDefaultIsPropertyListStorable() {
        // Guards the codecs: a default must round-trip through the plist/defaults
        // layers, so every encoded default must be a property-list type.
        for setting in SettingsSchema.all {
            let stored = setting.defaultStored
            let isPlist = stored is Bool || stored is String || stored is [String] || stored is NSNumber || stored is [String: Int]
            XCTAssertTrue(isPlist, "\(setting.key) default is not property-list storable: \(type(of: stored))")
        }
    }
}
