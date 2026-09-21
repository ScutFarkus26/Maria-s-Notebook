import SwiftUI

/// The two "test students" preferences, declared once.
///
/// Thirty-one views used to repeat the same pair of `@AppStorage` properties —
/// `UserDefaultsKeys.generalShowTestStudents` and
/// `UserDefaultsKeys.generalTestStudentNames` — with the default name list
/// spelled out longhand in every copy. A view now writes
/// `@TestStudentVisibility private var testStudents` and reads
/// `testStudents.show` / `testStudents.namesRaw`, or asks
/// `testStudents.visible(_:)` for the roster.
///
/// Reactivity is unchanged. This wrapper is itself a `DynamicProperty`, and
/// SwiftUI installs the `DynamicProperty` values it finds stored inside one, so
/// the nested `@AppStorage` properties are still hooked up to the defaults
/// store and still invalidate the enclosing view when either preference
/// changes — exactly as they did when each view declared them directly.
///
/// A view that has to *write* a preference (a `Toggle` binding, a text field)
/// keeps its own `@AppStorage`, because this wrapper is read-only by design:
/// see `TestStudentsSettingsView`.
@propertyWrapper
struct TestStudentVisibility: DynamicProperty {

    /// The read-only pair handed to the enclosing view.
    struct Value {
        /// True when the teacher has asked to see the test students.
        let show: Bool

        /// The stored list of test-student names, comma- or
        /// semicolon-separated, exactly as the settings screen wrote it.
        let namesRaw: String

        /// The normalized (lowercased, trimmed) names to hide. Empty when
        /// `show` is true.
        var hiddenNames: Set<String> {
            TestStudentsFilter.normalizedHiddenNames(show: show, namesRaw: namesRaw)
        }

        /// The active roster under these settings: former students and
        /// CloudKit duplicate-ID artifacts dropped, test students hidden
        /// unless `show` is true.
        func visible(_ students: some Sequence<CDStudent>) -> [CDStudent] {
            students.visibleRoster(showTest: show, testNames: namesRaw)
        }
    }

    @AppStorage private var show: Bool
    @AppStorage private var namesRaw: String

    init() {
        self.init(store: nil)
    }

    /// - Parameter store: The defaults store to read. `nil` means the
    ///   environment's `defaultAppStorage` (i.e. `UserDefaults.standard`),
    ///   which is what every view used before this wrapper existed. Tests pass
    ///   their own suite so they start from an empty store.
    init(store: UserDefaults?) {
        _show = AppStorage(
            wrappedValue: false,
            UserDefaultsKeys.generalShowTestStudents,
            store: store
        )
        _namesRaw = AppStorage(
            wrappedValue: TestStudentsFilter.defaultNames,
            UserDefaultsKeys.generalTestStudentNames,
            store: store
        )
    }

    var wrappedValue: Value {
        Value(show: show, namesRaw: namesRaw)
    }
}
