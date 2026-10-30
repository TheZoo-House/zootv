import Foundation

enum BoundedFeed {
    static func read<S: AsyncSequence>(_ bytes: S, declaredLength: Int64 = -1, limit: Int = 8_000_000) async throws -> Data where S.Element == UInt8 {
        guard declaredLength <= Int64(limit) else { throw GuideError.oversizedFeed }
        var data = Data()
        for try await byte in bytes {
            try Task.checkCancellation()
            guard data.count < limit else { throw GuideError.oversizedFeed }
            data.append(byte)
        }
        return data
    }
}
