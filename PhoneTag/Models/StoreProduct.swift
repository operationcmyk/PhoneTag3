import Foundation

struct StoreProduct: Identifiable, Sendable {
    let id: String
    let item: ArsenalItem
    let quantity: Int
    let price: String
    let description: String

    var displayName: String {
        "\(quantity) \(item.displayName)\(quantity > 1 ? "s" : "")"
    }

    static let catalog: [StoreProduct] = [
        StoreProduct(
            id: "com.operationcmyk.phonetag.basictag.10",
            item: .basicTag,
            quantity: 10,
            price: "$0.99",
            description: "10 basic tags (~1 block radius)"
        ),
        StoreProduct(
            id: "com.operationcmyk.phonetag.wideradius.5",
            item: .wideRadiusTag,
            quantity: 5,
            price: "$1.99",
            description: "5 wide radius tags (~3-5 blocks)"
        ),
        StoreProduct(
            id: "com.operationcmyk.phonetag.radar.3",
            item: .radar,
            quantity: 3,
            price: "$1.99",
            description: "3 radar pings to locate players"
        ),
        StoreProduct(
            id: "com.operationcmyk.phonetag.tripwire.3",
            item: .tripwire,
            quantity: 3,
            price: "$1.99",
            description: "3 tripwires to place at locations"
        ),
    ]
}
