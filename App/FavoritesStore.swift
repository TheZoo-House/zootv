import Foundation
import Observation
import CryptoKit
import UIKit

@MainActor protocol FavoritesCloudStorage: AnyObject {
    var dictionaryRepresentation: [String: Any] { get }
    func set(_ value: Bool, forKey key: String)
    func synchronize() -> Bool
}

extension NSUbiquitousKeyValueStore: FavoritesCloudStorage {}

/// Separate from GuideStore because preferences outlive feed refreshes.
@MainActor @Observable final class FavoritesStore {
    private(set) var syncError: String?
    private var values: [String: Bool]
    @ObservationIgnored private var pending: [String: Bool]
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let cloud: any FavoritesCloudStorage
    @ObservationIgnored private let notifications: NotificationCenter
    @ObservationIgnored private let identity: () -> NSObject?
    @ObservationIgnored private var account: NSObject?
    @ObservationIgnored private var identityKnown: Bool
    @ObservationIgnored private var awaitingAccount: Bool
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    private static let prefix = "zootv.favorite.v1."
    private static let storageKey = "zootv.favorites.v1"

    init(defaults: UserDefaults = .standard, cloud: any FavoritesCloudStorage = NSUbiquitousKeyValueStore.default,
         notifications: NotificationCenter = .default, identity: @escaping () -> NSObject? = {
             FileManager.default.ubiquityIdentityToken as? NSObject
         }) {
        self.defaults = defaults; self.cloud = cloud; self.notifications = notifications; self.identity = identity
        let saved = defaults.dictionary(forKey: Self.storageKey) ?? [:]
        values = saved["values"] as? [String: Bool] ?? [:]
        pending = saved["pending"] as? [String: Bool] ?? [:]
        identityKnown = saved["identityKnown"] as? Bool ?? false
        awaitingAccount = saved["awaitingAccount"] as? Bool ?? false
        if let data = saved["identity"] as? Data,
           let decoder = try? NSKeyedUnarchiver(forReadingFrom: data) {
            decoder.requiresSecureCoding = false // Apple's opaque identity token conforms to NSCoding.
            account = decoder.decodeObject(forKey: NSKeyedArchiveRootObjectKey) as? NSObject
            decoder.finishDecoding()
        }
        observe(NSUbiquitousKeyValueStore.didChangeExternallyNotification, object: cloud) { store, reason, keys in
            store.cloudChanged(reason: reason, keys: keys)
        }
        observe(.NSUbiquityIdentityDidChange) { store, _, _ in
            store.checkIdentity()
        }
        observe(UIApplication.didBecomeActiveNotification) { store, _, _ in store.refresh() }
        for name in [UIApplication.willResignActiveNotification, UIApplication.willTerminateNotification] {
            observe(name) { store, _, _ in store.save() }
        }
        refresh()
    }

    isolated deinit {
        for observer in observers { notifications.removeObserver(observer) }
    }

    func isFavorite(_ channelID: String) -> Bool { values[Self.key(channelID)] == true }

    func toggle(_ channelID: String) {
        checkIdentity()
        let key = Self.key(channelID)
        let value = values[key] != true
        values[key] = value
        pending[key] = value // Keep explicit false tombstones so removals sync too.
        save()
        flush()
    }

    func refresh() {
        checkIdentity()
        _ = cloud.synchronize()
        guard !awaitingAccount, account != nil else { return }
        merge()
        flush()
    }

    private static func key(_ channelID: String) -> String {
        // Stable across TVs and bounded below iCloud's 128 UTF-16-unit key limit.
        prefix + SHA256.hash(data: Data(channelID.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private func observe(_ name: Notification.Name, object: Any? = nil,
                         action: @escaping @MainActor (FavoritesStore, Int?, [String]?) -> Void) {
        observers.append(notifications.addObserver(forName: name, object: object, queue: .main) { [weak self] note in
            let reason = note.userInfo?[NSUbiquitousKeyValueStoreChangeReasonKey] as? Int
            let keys = note.userInfo?[NSUbiquitousKeyValueStoreChangedKeysKey] as? [String]
            // Main-queue delivery keeps account resets and writes synchronous, with no stale queued upload tasks.
            MainActor.assumeIsolated { if let self { action(self, reason, keys) } }
        })
    }

    private func checkIdentity() {
        let current = identity()
        let same = account?.isEqual(current) ?? (current == nil)
        if identityKnown, !same {
            values = [:]; pending = [:]; syncError = nil
            awaitingAccount = true // The cloud cache may still belong to the old account.
        }
        account = current
        identityKnown = true
        save()
    }

    private func cloudChanged(reason: Int?, keys: [String]?) {
        guard let reason else { return }
        checkIdentity()
        switch reason {
        case NSUbiquitousKeyValueStoreAccountChange:
            if !awaitingAccount { values = [:]; pending = [:] }
            awaitingAccount = false
        case NSUbiquitousKeyValueStoreInitialSyncChange:
            awaitingAccount = false
        case NSUbiquitousKeyValueStoreServerChange:
            guard !awaitingAccount else { return }
        case NSUbiquitousKeyValueStoreQuotaViolationChange:
            syncError = "Favorites saved on this Apple TV. iCloud storage is full."
            return
        default: return
        }
        guard account != nil else { save(); return }
        merge(keys: reason == NSUbiquitousKeyValueStoreServerChange ? keys : nil)
        flush()
    }

    private func merge(keys: [String]? = nil) {
        let remote = cloud.dictionaryRepresentation
        let keys = keys ?? Array(remote.keys)
        for key in keys where key.hasPrefix(Self.prefix) && pending[key] == nil {
            values[key] = remote[key] as? Bool
        }
        save()
    }

    private func flush() {
        guard !awaitingAccount, account != nil else { return }
        var proposed = cloud.dictionaryRepresentation
        var handedOff: [String] = []
        for (key, value) in pending {
            guard proposed[key] != nil || proposed.count < 1024 else { continue }
            var candidate = proposed
            candidate[key] = value
            // Conservatively count the entire property list, including unrelated app keys.
            guard let data = try? PropertyListSerialization.data(fromPropertyList: candidate, format: .binary, options: 0),
                  data.count <= 1_048_576 else { continue }
            cloud.set(value, forKey: key)
            proposed = candidate
            handedOff.append(key)
        }
        if !handedOff.isEmpty, cloud.synchronize() {
            // This hands durability to Apple's store; it is not a cross-device delivery acknowledgement.
            for key in handedOff { pending.removeValue(forKey: key) }
        }
        syncError = pending.isEmpty ? nil : "Favorites saved on this Apple TV. iCloud sync is pending."
        save()
    }

    private func save() {
        var saved: [String: Any] = ["values": values, "pending": pending, "identityKnown": identityKnown,
                                    "awaitingAccount": awaitingAccount]
        if let account, let data = try? NSKeyedArchiver.archivedData(withRootObject: account, requiringSecureCoding: false) {
            saved["identity"] = data
        }
        // Commit account identity, cache and outbox together so a terminated write cannot mix accounts.
        defaults.set(saved, forKey: Self.storageKey)
    }
}
