import Foundation

struct Note: Identifiable, Hashable {
    var id: String { filename }
    var filename: String
    var title: String
    var content: String
    let createdAt: Date
    var modifiedAt: Date
}
