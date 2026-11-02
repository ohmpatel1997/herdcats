#if DEBUG
import SwiftUI
import UIKit

/// Temporary instrumentation for the "cannot scroll back to the top of the
/// pane output while the keyboard is up" bug.
///
/// Prints one line per observed change to the pane output scroll view so the
/// failing layer can be identified: the scroll container's position on screen,
/// the content's offset inside it, and the keyboard frame that triggered the
/// change. Remove once the root cause is fixed.
enum PaneScrollDiag {
    static let space = "pane-output-scroll"

    private static var lastLine: [String: String] = [:]

    static func log(_ channel: String, _ line: String) {
        guard lastLine[channel] != line else { return }
        lastLine[channel] = line
        print("[pane-scroll] \(channel) \(line)")
    }
}

struct PaneScrollContainerInfo: Equatable, Sendable {
    var height: CGFloat = 0
    var globalMinY: CGFloat = 0
    var globalMaxY: CGFloat = 0
    var safeTop: CGFloat = 0
    var safeBottom: CGFloat = 0
}

struct PaneScrollContentInfo: Equatable, Sendable {
    var height: CGFloat = 0
    /// Content's top edge measured in the scroll container's coordinate space.
    /// 0 means "scrolled to the very top"; negative means scrolled down by that
    /// many points. If this never returns to 0 while dragging down, the top of
    /// the content is unreachable.
    var topInContainer: CGFloat = 0
}

private struct PaneScrollContainerKey: PreferenceKey {
    static let defaultValue = PaneScrollContainerInfo()
    static func reduce(value: inout PaneScrollContainerInfo, nextValue: () -> PaneScrollContainerInfo) {
        value = nextValue()
    }
}

private struct PaneScrollContentKey: PreferenceKey {
    static let defaultValue = PaneScrollContentInfo()
    static func reduce(value: inout PaneScrollContentInfo, nextValue: () -> PaneScrollContentInfo) {
        value = nextValue()
    }
}

private func fmt(_ value: CGFloat) -> String {
    String(format: "%.1f", value)
}

extension View {
    /// Apply to the scroll content (inside the `ScrollView`).
    func paneScrollContentProbe() -> some View {
        background {
            GeometryReader { geo in
                Color.clear.preference(
                    key: PaneScrollContentKey.self,
                    value: PaneScrollContentInfo(
                        height: geo.size.height,
                        topInContainer: geo.frame(in: .named(PaneScrollDiag.space)).minY
                    )
                )
            }
        }
    }

    /// Apply to the `ScrollView` itself.
    func paneScrollDiagnostics(tag: String) -> some View {
        coordinateSpace(name: PaneScrollDiag.space)
            .background {
                GeometryReader { geo in
                    Color.clear.preference(
                        key: PaneScrollContainerKey.self,
                        value: PaneScrollContainerInfo(
                            height: geo.size.height,
                            globalMinY: geo.frame(in: .global).minY,
                            globalMaxY: geo.frame(in: .global).maxY,
                            safeTop: geo.safeAreaInsets.top,
                            safeBottom: geo.safeAreaInsets.bottom
                        )
                    )
                }
            }
            .onPreferenceChange(PaneScrollContainerKey.self) { info in
                PaneScrollDiag.log(
                    "container[\(tag)]",
                    "h=\(fmt(info.height)) globalY=\(fmt(info.globalMinY))…\(fmt(info.globalMaxY)) safeTop=\(fmt(info.safeTop)) safeBottom=\(fmt(info.safeBottom))"
                )
            }
            .onPreferenceChange(PaneScrollContentKey.self) { info in
                PaneScrollDiag.log(
                    "content[\(tag)]",
                    "h=\(fmt(info.height)) top=\(fmt(info.topInContainer))"
                )
            }
            .modifier(PaneKeyboardDiagnostics(tag: tag))
    }
}

/// Logs keyboard frames next to the hosting window's bounds.
private struct PaneKeyboardDiagnostics: ViewModifier {
    let tag: String
    @State private var hostWindow = HostingWindow()

    func body(content: Content) -> some View {
        content
            .background(HostingWindowReader(window: hostWindow))
            .onReceive(
                NotificationCenter.default.publisher(
                    for: UIResponder.keyboardWillChangeFrameNotification
                )
            ) { note in
                let end = (note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue ?? .zero
                let bounds = hostWindow.window?.bounds ?? .zero
                PaneScrollDiag.log(
                    "keyboard[\(tag)]",
                    "endY=\(fmt(end.minY)) h=\(fmt(end.height)) windowH=\(fmt(bounds.height))"
                )
            }
    }
}
#endif
