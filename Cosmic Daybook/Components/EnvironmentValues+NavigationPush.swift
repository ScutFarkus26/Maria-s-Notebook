import SwiftUI

extension EnvironmentValues {
    /// Set while a page sits inside a stack it did not make (the iPhone More
    /// tab). Nil when the page is a root of its own: a tab, the iPad sidebar's
    /// detail, the Mac's Settings window.
    @Entry var navigationPush: NavigationPushAction?
}
