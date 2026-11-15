import XCTest
@testable import ZooTV

@MainActor private final class Cloud: FavoritesCloudStorage {
    var dictionaryRepresentation: [String: Any] = [:]
    var available = true
    var writes: [String: Bool] = [:]
    func set(_ value: Bool, forKey key: String) {
        dictionaryRepresentation[key] = value
        writes[key] = value
    }
    func synchronize() -> Bool { available }
}

final class FavoritesStoreTests: XCTestCase {
    @MainActor private func fixture() -> (UserDefaults, Cloud, NotificationCenter) {
        let name = "FavoritesStoreTests.\(UUID())"
        let defaults = UserDefaults(suiteName: name)!
        addTeardownBlock { UserDefaults.standard.removePersistentDomain(forName: name) }
        return (defaults, Cloud(), NotificationCenter())
    }

    @MainActor private func notify(_ cloud: Cloud, _ center: NotificationCenter, reason: Int,
                                   keys: [String]? = nil) {
        var info: [String: Any] = [NSUbiquitousKeyValueStoreChangeReasonKey: reason]
        if let keys { info[NSUbiquitousKeyValueStoreChangedKeysKey] = keys }
        center.post(name: NSUbiquitousKeyValueStore.didChangeExternallyNotification, object: cloud, userInfo: info)
    }

    @MainActor func testLocalEditsSurviveRelaunchAndInitialDownloadWithoutReplacingOtherChannels() throws {
        let (defaults, cloud, center) = fixture()
        cloud.available = false
        var store: FavoritesStore? = FavoritesStore(defaults: defaults, cloud: cloud, notifications: center, identity: { "account-a" as NSString })
        store!.toggle("offline")
        XCTAssertTrue(store!.isFavorite("offline"), "Favorites work without iCloud")
        store = nil
        let restored = FavoritesStore(defaults: defaults, cloud: cloud, notifications: center, identity: { "account-a" as NSString })
        XCTAssertTrue(restored.isFavorite("offline"), "Local edits must survive termination")

        // A second device's edits use the same production key mapping.
        let (otherDefaults, otherCloud, otherCenter) = fixture()
        let other = FavoritesStore(defaults: otherDefaults, cloud: otherCloud, notifications: otherCenter, identity: { "account-a" as NSString })
        other.toggle("remote")
        cloud.dictionaryRepresentation = otherCloud.dictionaryRepresentation
        cloud.available = true
        notify(cloud, center, reason: NSUbiquitousKeyValueStoreInitialSyncChange)
        XCTAssertTrue(restored.isFavorite("offline"), "Initial download must retain pending local edits")
        XCTAssertTrue(restored.isFavorite("remote"), "Initial download must preserve existing cloud favorites")
        XCTAssertEqual(cloud.dictionaryRepresentation.count, 2)
    }

    @MainActor func testRemoteRemovalWinsAfterHandoffAndDuplicateNotificationsDoNotWriteBack() throws {
        let (defaults, cloud, center) = fixture()
        let store = FavoritesStore(defaults: defaults, cloud: cloud, notifications: center, identity: { "account-a" as NSString })
        store.toggle("a")
        let key = try XCTUnwrap(cloud.writes.keys.first)
        cloud.writes = [:]
        cloud.dictionaryRepresentation[key] = false
        for _ in 0..<2 { notify(cloud, center, reason: NSUbiquitousKeyValueStoreServerChange, keys: [key]) }
        XCTAssertFalse(store.isFavorite("a"))
        XCTAssertTrue(cloud.writes.isEmpty, "Incoming changes must not echo back as local edits")
        let restored = FavoritesStore(defaults: defaults, cloud: cloud, notifications: center, identity: { "account-a" as NSString })
        XCTAssertFalse(restored.isFavorite("a"), "A removal must not reappear from the local cache")
        cloud.dictionaryRepresentation[key] = true
        notify(cloud, center, reason: NSUbiquitousKeyValueStoreServerChange, keys: [key])
        XCTAssertTrue(store.isFavorite("a"))
        XCTAssertTrue(cloud.writes.isEmpty)
    }

    @MainActor func testOfflineRemovalRemainsATombstoneAfterReconnect() throws {
        let (defaults, cloud, center) = fixture()
        let store = FavoritesStore(defaults: defaults, cloud: cloud, notifications: center, identity: { "account-a" as NSString })
        store.toggle("a")
        let key = try XCTUnwrap(cloud.writes.keys.first)
        cloud.available = false
        store.toggle("a")
        cloud.dictionaryRepresentation[key] = true
        notify(cloud, center, reason: NSUbiquitousKeyValueStoreInitialSyncChange)
        XCTAssertFalse(store.isFavorite("a"), "Stale cloud state must not resurrect a pending removal")
        cloud.available = true
        store.refresh()
        XCTAssertEqual(cloud.dictionaryRepresentation[key] as? Bool, false)
        XCTAssertFalse(store.isFavorite("a"))
    }

    @MainActor func testAccountReplacementDropsOldCacheAndPendingEditsBeforeAnyUpload() {
        let (defaults, cloud, center) = fixture()
        var identity: NSObject? = "account-a" as NSString
        var store: FavoritesStore? = FavoritesStore(defaults: defaults, cloud: cloud, notifications: center, identity: { identity })
        cloud.available = false
        store!.toggle("a")
        let oldCloud = cloud.dictionaryRepresentation
        identity = "account-b" as NSString
        cloud.dictionaryRepresentation = [:]
        cloud.writes = [:]
        center.post(name: .NSUbiquityIdentityDidChange, object: nil)
        XCTAssertFalse(store!.isFavorite("a"), "Never display the previous account's favorites")
        store!.toggle("b")
        store = nil
        cloud.dictionaryRepresentation = oldCloud
        store = FavoritesStore(defaults: defaults, cloud: cloud, notifications: center, identity: { identity })
        XCTAssertFalse(store!.isFavorite("a"), "A relaunch while the replacement account loads must not read the old cloud cache")
        XCTAssertTrue(cloud.writes.isEmpty, "A relaunch must not submit new-account work to the previous account's cache")
        cloud.dictionaryRepresentation = [:]
        cloud.writes = [:]
        cloud.available = true
        notify(cloud, center, reason: NSUbiquitousKeyValueStoreAccountChange)
        XCTAssertFalse(store!.isFavorite("a"))
        XCTAssertTrue(store!.isFavorite("b"), "Keep edits made for the new account while its store loads")
        XCTAssertEqual(cloud.writes.count, 1, "Only the new account's edit may be uploaded")
        store = nil
        identity = "account-c" as NSString
        cloud.writes = [:]
        let next = FavoritesStore(defaults: defaults, cloud: cloud, notifications: center, identity: { identity })
        XCTAssertFalse(next.isFavorite("b"), "Detect account replacement while the app was not running")
        XCTAssertTrue(cloud.writes.isEmpty, "Old cached cloud contents must not be uploaded on launch")
    }

    @MainActor func testAccountNotificationWithoutIdentityTokenAlsoClearsOldPendingWork() {
        let (defaults, cloud, center) = fixture()
        let store = FavoritesStore(defaults: defaults, cloud: cloud, notifications: center, identity: { nil })
        cloud.available = false
        store.toggle("a")
        cloud.dictionaryRepresentation = [:]
        cloud.writes = [:]
        cloud.available = true
        notify(cloud, center, reason: NSUbiquitousKeyValueStoreAccountChange)
        XCTAssertFalse(store.isFavorite("a"))
        XCTAssertTrue(cloud.writes.isEmpty)
    }

    @MainActor func testQuotaKeepsLocalFavoritesAndBoundsCloudKeys() {
        let (defaults, cloud, center) = fixture()
        cloud.dictionaryRepresentation = Dictionary(uniqueKeysWithValues: (0..<1024).map { ("other.\($0)", true) })
        let store = FavoritesStore(defaults: defaults, cloud: cloud, notifications: center, identity: { "account-a" as NSString })
        let longID = String(repeating: "🎬", count: 200)
        store.toggle(longID)
        XCTAssertTrue(store.isFavorite(longID))
        XCTAssertTrue(cloud.writes.isEmpty, "Do not exceed the shared iCloud key quota")
        XCTAssertNotNil(store.syncError)
        cloud.dictionaryRepresentation = ["other.payload": Data(repeating: 0, count: 1_048_576)]
        store.refresh()
        XCTAssertTrue(cloud.writes.isEmpty, "Do not exceed the shared iCloud byte quota")
        cloud.dictionaryRepresentation = [:]
        store.refresh()
        XCTAssertEqual(cloud.writes.count, 1)
        XCTAssertTrue(cloud.writes.keys.allSatisfy { $0.utf16.count <= 128 }, "Long channel IDs must fit iCloud's key limit")
        XCTAssertNil(store.syncError)
    }
}
