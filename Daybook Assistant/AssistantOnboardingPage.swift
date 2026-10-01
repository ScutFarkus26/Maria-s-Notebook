import SwiftUI

/// One onboarding page: an icon, a title and a line under it, the page's own
/// content, and its buttons pinned to the bottom in thumb reach. The content
/// scrolls when it runs long (an SE, large text); the buttons never do.
struct AssistantOnboardingPage<Content: View, Actions: View>: View {
    var systemImage: String?
    var tint: Color = .accentColor
    let title: String
    var message: String?
    @ViewBuilder var content: Content
    @ViewBuilder var actions: Actions

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                content
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 16)
            .frame(maxWidth: 520, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 6) { actions }
                .padding(.horizontal, 24)
                .padding(.top, 12)
                .padding(.bottom, 8)
                .frame(maxWidth: 520)
                .frame(maxWidth: .infinity)
                .background(.background)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(tint)
                    .frame(width: 60, height: 60)
                    .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .accessibilityHidden(true)
            }
            Text(title)
                .font(.system(.largeTitle, design: .rounded, weight: .bold))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            if let message {
                Text(message)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

extension AssistantOnboardingPage where Actions == EmptyView {
    init(
        systemImage: String? = nil,
        tint: Color = .accentColor,
        title: String,
        message: String? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.init(systemImage: systemImage, tint: tint, title: title, message: message, content: content) {
            EmptyView()
        }
    }
}

/// The page's main button: full width, filled.
struct OnboardingPrimaryButton: View {
    let title: String
    var isEnabled = true
    let action: () -> Void

    init(_ title: String, isEnabled: Bool = true, action: @escaping () -> Void) {
        self.title = title
        self.isEnabled = isEnabled
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.roundedRectangle(radius: 16))
        .controlSize(.large)
        .disabled(!isEnabled)
    }
}

/// A second choice under the main button: plain text, full width.
struct OnboardingSecondaryButton: View {
    let title: String
    let action: () -> Void

    init(_ title: String, action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.body.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.borderless)
    }
}

/// Something wrong, said in words she can act on.
struct OnboardingNotice: View {
    let text: String
    let systemImage: String

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.callout)
            .foregroundStyle(.orange)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

/// A card of rows, each an icon, a bold line and a line under it.
struct OnboardingCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
            .padding(.horizontal, 16)
            .background(
                Color(.secondarySystemBackground),
                in: RoundedRectangle(cornerRadius: 20, style: .continuous)
            )
    }
}

struct OnboardingCardRow<Icon: View>: View {
    let title: String
    var detail: String?
    var showsDivider = true
    @ViewBuilder var icon: Icon

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            icon
                .font(.title3)
                .frame(width: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body.weight(.semibold))
                if let detail {
                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 14)
        .overlay(alignment: .top) {
            if showsDivider { Divider().padding(.leading, 42) }
        }
        .accessibilityElement(children: .combine)
    }
}

/// "1", "2", "3" in a small circle, beside a step.
struct OnboardingStep: View {
    let number: Int
    let text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Text("\(number)")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.tint)
                .frame(width: 28, height: 28)
                .background(Color.accentColor.opacity(0.12), in: Circle())
                .accessibilityHidden(true)
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}
