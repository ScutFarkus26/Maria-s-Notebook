// OnboardingView.swift
// First-run onboarding experience for new users

import SwiftUI

struct OnboardingView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var currentPage = 0

    private let pages: [OnboardingPage] = [
        OnboardingPage(
            icon: "book.and.wrench.fill",
            title: "Welcome to Maria's Notebook",
            description: "A comprehensive planning tool for Montessori and classroom educators."
                + " Manage students, lessons, work tracking, and observations — all in one place.",
            accentColor: .blue
        ),
        OnboardingPage(
            icon: "person.3.fill",
            title: "Add Your Students",
            description: "Start by adding students to your roster."
                + " You can organize them by level, track birthdays, and view their lesson history at a glance.",
            accentColor: .pink
        ),
        OnboardingPage(
            icon: "text.book.closed.fill",
            title: "Plan Your Lessons",
            description: "Build your lesson library, assign lessons to students,"
                + " and track progress through the work lifecycle: active, review, and complete.",
            accentColor: .purple
        ),
        OnboardingPage(
            icon: "sparkles",
            title: "Quick Notes & More",
            description: "Long-press the floating button for quick access to notes,"
                + " presentations, work items, and to-dos. Use the Today view for your daily overview.",
            accentColor: .orange
        )
    ]

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $currentPage) {
                ForEach(Array(pages.enumerated()), id: \.offset) { index, page in
                    onboardingPageView(page)
                        .tag(index)
                }
            }
            #if os(iOS)
            .tabViewStyle(.page(indexDisplayMode: .always))
            #endif

            // Bottom buttons
            HStack {
                if currentPage < pages.count - 1 {
                    Button("Skip") {
                        hasCompletedOnboarding = true
                    }
                    .font(AppTheme.ScaledFont.body)
                    .foregroundStyle(.secondary)

                    Spacer()

                    Button {
                        adaptiveWithAnimation {
                            currentPage += 1
                        }
                    } label: {
                        Text("Next")
                            .font(AppTheme.ScaledFont.bodySemibold)
                            .frame(width: 120)
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Spacer()

                    Button {
                        hasCompletedOnboarding = true
                    } label: {
                        Text("Get Started")
                            .font(AppTheme.ScaledFont.bodySemibold)
                            .frame(width: 160)
                    }
                    .buttonStyle(.borderedProminent)

                    Spacer()
                }
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 40)
        }
        .background(.background)
    }

    private func onboardingPageView(_ page: OnboardingPage) -> some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: page.icon)
                .font(.system(size: 64))
                .foregroundStyle(page.accentColor)
                .padding(.bottom, 8)

            Text(page.title)
                .font(AppTheme.ScaledFont.titleLarge)
                .multilineTextAlignment(.center)

            Text(page.description)
                .font(AppTheme.ScaledFont.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 340)

            Spacer()
            Spacer()
        }
        .padding(.horizontal, 32)
    }
}

private struct OnboardingPage {
    let icon: String
    let title: String
    let description: String
    let accentColor: Color
}
