import SwiftUI

public enum CFTypography {
    public static let heroTitle = Font.system(size: 64, weight: .bold, design: .default)
    public static let largeTitle = Font.system(size: 48, weight: .bold, design: .default)
    public static let title = Font.system(size: 32, weight: .semibold, design: .default)
    public static let sectionTitle = Font.system(size: 24, weight: .semibold, design: .default)
    public static let body = Font.system(size: 17, weight: .regular, design: .default)
    public static let bodyEmphasis = Font.system(size: 17, weight: .semibold, design: .default)
    public static let callout = Font.system(size: 15, weight: .medium, design: .default)
    public static let metadata = Font.system(size: 13, weight: .medium, design: .default)
    public static let caption = Font.system(size: 13, weight: .regular, design: .default)
    public static let overline = Font.system(size: 11, weight: .bold, design: .default)
    public static let compactNumber = Font.system(size: 12, weight: .semibold, design: .monospaced)
}
