#if os(iOS)
import SwiftUI

extension EnvironmentValues {
    /// Whether the attendance tiles sit on a plain backdrop (the notebook's
    /// roll, and the Assistant's Sky or Plain): tiles keep their solid card
    /// and clear absence. False frosts them so their shapes read on a picture.
    @Entry var attendanceBackdropIsQuiet = true
}
#endif
