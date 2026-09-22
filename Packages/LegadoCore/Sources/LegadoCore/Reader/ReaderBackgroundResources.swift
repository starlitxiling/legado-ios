import Foundation

public enum ReaderBackgroundResources {
    public static let names = [
        "午后沙滩.jpg",
        "宁静夜色.jpg",
        "山水墨影.jpg",
        "山水画.jpg",
        "护眼漫绿.jpg",
        "新羊皮纸.jpg",
        "明媚倾城.jpg",
        "深宫魅影.jpg",
        "清新时光.jpg",
        "羊皮纸1.jpg",
        "羊皮纸2.jpg",
        "羊皮纸3.jpg",
        "羊皮纸4.jpg",
        "边彩画布.jpg"
    ]

    public static func url(named name: String) -> URL? {
        guard names.contains(name) else { return nil }
        return Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "ReaderBackgrounds")
    }
}
