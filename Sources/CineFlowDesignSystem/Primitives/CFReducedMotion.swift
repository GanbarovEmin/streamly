import SwiftUI

private struct CFReduceMotionKey: EnvironmentKey {
    static let defaultValue = false
}

public extension EnvironmentValues {
    var cfReduceMotion: Bool {
        get { self[CFReduceMotionKey.self] }
        set { self[CFReduceMotionKey.self] = newValue }
    }
}

public extension View {
    @ViewBuilder
    func cfAnimation(_ motion: Animation?, value: some Equatable, reduceMotion: Bool) -> some View {
        if reduceMotion {
            self.animation(nil, value: value)
        } else {
            self.animation(motion, value: value)
        }
    }
}
