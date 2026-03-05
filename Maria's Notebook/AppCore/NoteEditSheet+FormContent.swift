import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

// MARK: - Form Content Sections

extension NoteEditSheet {

    var formContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Main text editor - the star of the show
                TextEditor(text: $bodyText)
                    .focused($isTextEditorFocused)
                    .font(AppTheme.ScaledFont.titleSmall)
                    .lineSpacing(6)
                    .frame(minHeight: 300)
                    .padding(.horizontal, 28)
                    .padding(.vertical, 24)
                    .scrollContentBackground(.hidden)
                    .background(Color.clear)

                Divider()
                    .padding(.horizontal, 28)

                // Metadata section - subtle and compact
                VStack(alignment: .leading, spacing: 20) {
                    // Tags section
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Tags")
                            .font(AppTheme.ScaledFont.captionSemibold)
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)
                            .tracking(0.5)

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(tags, id: \.self) { tag in
                                    HStack(spacing: 4) {
                                        TagBadge(tag: tag)
                                        Button {
                                            adaptiveWithAnimation { tags.removeAll { $0 == tag } }
                                        } label: {
                                            Image(systemName: "xmark.circle.fill")
                                                .font(.system(size: 12))
                                                .foregroundStyle(.secondary)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                Button {
                                    showingTagPicker = true
                                } label: {
                                    HStack(spacing: 4) {
                                        Image(systemName: "plus")
                                            .font(.system(size: 12, weight: .medium))
                                        Text("Add Tag")
                                            .font(AppTheme.ScaledFont.bodySemibold)
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(Color.secondary.opacity(0.1))
                                    .clipShape(RoundedRectangle(cornerRadius: 16))
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.horizontal, 2)
                        }
                    }

                    // Toggles and image indicator
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 20) {
                            Toggle(isOn: $isPinned) {
                                HStack(spacing: 6) {
                                    Image(systemName: "pin.fill")
                                        .font(.system(size: 12))
                                        .foregroundStyle(AppColors.warning)
                                    Text("Pin to Top")
                                        .font(AppTheme.ScaledFont.body)
                                }
                            }
                            .toggleStyle(.switch)

                            Toggle(isOn: $needsFollowUp) {
                                HStack(spacing: 6) {
                                    Image(systemName: "flag.fill")
                                        .font(.system(size: 12))
                                        .foregroundStyle(AppColors.destructive)
                                    Text("Follow Up")
                                        .font(AppTheme.ScaledFont.body)
                                }
                            }
                            .toggleStyle(.switch)

                            Toggle(isOn: $includeInReport) {
                                HStack(spacing: 6) {
                                    Image(systemName: "doc.text.fill")
                                        .font(.system(size: 12))
                                    Text("Include in Report")
                                        .font(AppTheme.ScaledFont.body)
                                }
                            }
                            .toggleStyle(.switch)

                            Spacer()
                        }

                        if let path = note.imagePath, !path.isEmpty {
                            HStack(spacing: 6) {
                                Image(systemName: "photo.fill")
                                    .font(.system(size: 12))
                                Text("Photo attached")
                                    .font(AppTheme.ScaledFont.body)
                            }
                            .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 20)
                #if os(macOS)
                .background(Color(NSColor.textBackgroundColor))
                #else
                .background(Color(uiColor: .systemBackground))
                #endif
            }
        }
        #if os(macOS)
        .background(Color(NSColor.textBackgroundColor))
        #else
        .background(Color(uiColor: .systemBackground))
        #endif
        .dismissKeyboardOnScroll()
        .sheet(isPresented: $showingTagPicker) {
            NoteTagPickerSheet(selectedTags: $tags)
        }
    }
}
