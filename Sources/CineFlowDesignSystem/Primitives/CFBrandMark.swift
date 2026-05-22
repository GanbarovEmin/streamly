import AppKit
import SwiftUI

public struct CFBrandMark: View {
    private let size: CGFloat
    private static let logoImage: NSImage? = {
        guard let url = logoResourceURL() else {
            return nil
        }
        return NSImage(contentsOf: url)
    }()

    public init(size: CGFloat = 38) {
        self.size = size
    }

    public var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .fill(CFColors.backgroundSecondary.opacity(0.72))
                .overlay(
                    RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                        .stroke(CFColors.separator, lineWidth: CFSeparators.width)
                )

            if let image = Self.logoImage {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .padding(size * 0.12)
            } else {
                Image(systemName: "play.fill")
                    .font(.system(size: size * 0.36, weight: .black))
                    .foregroundStyle(CFColors.primaryGradient)
                    .offset(x: size * 0.03)
            }
        }
        .frame(width: size, height: size)
        .cfShadow(.hover)
        .accessibilityHidden(true)
    }

    static let releaseResourceBundleNames = [
        "Streamly_CineFlowDesignSystem.bundle",
        "CineFlowDesignSystem_CineFlowDesignSystem.bundle",
        "CineFlow_CineFlowDesignSystem.bundle"
    ]

    static func releaseResourceBundle(resourceURL: URL?, appBundleURL: URL?) -> Bundle? {
        var searchRoots: [URL] = []
        if let resourceURL {
            searchRoots.append(resourceURL)
        }
        if let appBundleURL {
            searchRoots.append(appBundleURL)
        }

        for root in searchRoots {
            for bundleName in releaseResourceBundleNames {
                let bundleURL = root.appendingPathComponent(bundleName, isDirectory: true)
                if let bundle = Bundle(url: bundleURL) {
                    return bundle
                }
            }
        }
        return nil
    }

    static func logoResourceURL(
        resourceURL: URL? = Bundle.main.resourceURL,
        appBundleURL: URL? = Bundle.main.bundleURL,
        includeSwiftPackageFallback: Bool = true
    ) -> URL? {
        if let bundle = releaseResourceBundle(resourceURL: resourceURL, appBundleURL: appBundleURL),
           let url = bundle.url(forResource: "streamly-mark", withExtension: "png") {
            return url
        }

        if includeSwiftPackageFallback, appBundleURL?.pathExtension.lowercased() != "app" {
            return Bundle.module.url(forResource: "streamly-mark", withExtension: "png")
        }

        return nil
    }
}
