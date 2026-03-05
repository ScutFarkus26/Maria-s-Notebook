// PasswordStrengthValidator.swift
// Validates password strength for backup encryption

import Foundation
import SwiftUI

/// Validates password strength for backup encryption.
/// Provides feedback on password requirements and strength levels.
public struct PasswordStrengthValidator {

    // MARK: - Types

    /// Password strength levels
    public enum StrengthLevel: Int, CaseIterable, Comparable {
        case veryWeak = 0
        case weak = 1
        case fair = 2
        case strong = 3
        case veryStrong = 4

        public var description: String {
            switch self {
            case .veryWeak: return "Very Weak"
            case .weak: return "Weak"
            case .fair: return "Fair"
            case .strong: return "Strong"
            case .veryStrong: return "Very Strong"
            }
        }

        public var color: Color {
            switch self {
            case .veryWeak: return .red
            case .weak: return .orange
            case .fair: return .yellow
            case .strong: return .green
            case .veryStrong: return .green
            }
        }

        public var systemImage: String {
            switch self {
            case .veryWeak: return "exclamationmark.triangle.fill"
            case .weak: return "exclamationmark.triangle"
            case .fair: return "checkmark.circle"
            case .strong: return "checkmark.circle.fill"
            case .veryStrong: return "checkmark.seal.fill"
            }
        }

        public static func < (lhs: StrengthLevel, rhs: StrengthLevel) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }

    /// Individual validation requirement
    public struct Requirement: Identifiable {
        public let id = UUID()
        public let description: String
        public let isMet: Bool

        public init(description: String, isMet: Bool) {
            self.description = description
            self.isMet = isMet
        }
    }

    /// Complete validation result
    public struct ValidationResult {
        public let strength: StrengthLevel
        public let requirements: [Requirement]
        public let score: Int
        public let isAcceptable: Bool
        public let feedback: String

        public var allRequirementsMet: Bool {
            requirements.allSatisfy { $0.isMet }
        }
    }

    // MARK: - Configuration

    /// Minimum password length
    public var minimumLength: Int = 8

    /// Recommended password length for strong passwords
    public var recommendedLength: Int = 12

    /// Minimum strength level to be considered acceptable
    public var minimumAcceptableStrength: StrengthLevel = .fair

    /// Whether to require at least one uppercase letter
    public var requireUppercase: Bool = true

    /// Whether to require at least one lowercase letter
    public var requireLowercase: Bool = true

    /// Whether to require at least one digit
    public var requireDigit: Bool = true

    /// Whether to require at least one special character
    public var requireSpecialCharacter: Bool = false

    // MARK: - Initialization

    public init() {}

    public init(
        minimumLength: Int = 8,
        recommendedLength: Int = 12,
        minimumAcceptableStrength: StrengthLevel = .fair,
        requireUppercase: Bool = true,
        requireLowercase: Bool = true,
        requireDigit: Bool = true,
        requireSpecialCharacter: Bool = false
    ) {
        self.minimumLength = minimumLength
        self.recommendedLength = recommendedLength
        self.minimumAcceptableStrength = minimumAcceptableStrength
        self.requireUppercase = requireUppercase
        self.requireLowercase = requireLowercase
        self.requireDigit = requireDigit
        self.requireSpecialCharacter = requireSpecialCharacter
    }

    // MARK: - Validation

    /// Validates a password and returns a complete validation result.
    ///
    /// - Parameter password: The password to validate
    /// - Returns: ValidationResult with strength, requirements, and feedback
    public func validate(_ password: String) -> ValidationResult {
        var requirements: [Requirement] = []
        var score = 0

        // Length requirement
        let meetsMinLength = password.count >= minimumLength
        requirements.append(Requirement(
            description: "At least \(minimumLength) characters",
            isMet: meetsMinLength
        ))
        if meetsMinLength { score += 1 }

        // Bonus for longer passwords
        if password.count >= recommendedLength {
            score += 1
        }
        if password.count >= 16 {
            score += 1
        }

        // Uppercase requirement
        let hasUppercase = password.contains(where: { $0.isUppercase })
        if requireUppercase {
            requirements.append(Requirement(
                description: "At least one uppercase letter",
                isMet: hasUppercase
            ))
        }
        if hasUppercase { score += 1 }

        // Lowercase requirement
        let hasLowercase = password.contains(where: { $0.isLowercase })
        if requireLowercase {
            requirements.append(Requirement(
                description: "At least one lowercase letter",
                isMet: hasLowercase
            ))
        }
        if hasLowercase { score += 1 }

        // Digit requirement
        let hasDigit = password.contains(where: { $0.isNumber })
        if requireDigit {
            requirements.append(Requirement(
                description: "At least one number",
                isMet: hasDigit
            ))
        }
        if hasDigit { score += 1 }

        // Special character requirement
        let specialCharacters = CharacterSet.punctuationCharacters.union(.symbols)
        let hasSpecial = password.unicodeScalars.contains(where: { specialCharacters.contains($0) })
        if requireSpecialCharacter {
            requirements.append(Requirement(
                description: "At least one special character",
                isMet: hasSpecial
            ))
        }
        if hasSpecial { score += 1 }

        // Check for common patterns (penalize)
        if containsCommonPattern(password) {
            score = max(0, score - 2)
        }

        // Check for sequential characters (penalize)
        if hasSequentialCharacters(password) {
            score = max(0, score - 1)
        }

        // Check for repeated characters (penalize)
        if hasRepeatedCharacters(password) {
            score = max(0, score - 1)
        }

        // Calculate strength level
        let strength = calculateStrength(score: score)

        // Determine if acceptable
        let isAcceptable = strength >= minimumAcceptableStrength &&
            requirements.filter { _ in
                // Only check configured requirements
                true
            }.allSatisfy { $0.isMet }

        // Generate feedback
        let feedback = generateFeedback(
            strength: strength,
            requirements: requirements,
            password: password
        )

        return ValidationResult(
            strength: strength,
            requirements: requirements,
            score: score,
            isAcceptable: isAcceptable,
            feedback: feedback
        )
    }

    /// Quick check if a password meets minimum requirements.
    ///
    /// - Parameter password: The password to check
    /// - Returns: True if the password is acceptable
    public func isAcceptable(_ password: String) -> Bool {
        validate(password).isAcceptable
    }

    /// Returns just the strength level without full validation.
    ///
    /// - Parameter password: The password to check
    /// - Returns: The strength level
    public func strengthLevel(_ password: String) -> StrengthLevel {
        validate(password).strength
    }

    // MARK: - Private Helpers

    private func calculateStrength(score: Int) -> StrengthLevel {
        switch score {
        case 0...1: return .veryWeak
        case 2...3: return .weak
        case 4...5: return .fair
        case 6...7: return .strong
        default: return .veryStrong
        }
    }

    private func containsCommonPattern(_ password: String) -> Bool {
        let lowercased = password.lowercased()
        let commonPatterns = [
            "password", "123456", "qwerty", "abc123",
            "letmein", "welcome", "admin", "login",
            "passw0rd", "p@ssword", "backup"
        ]
        return commonPatterns.contains { lowercased.contains($0) }
    }

    private func hasSequentialCharacters(_ password: String) -> Bool {
        let characters = Array(password.lowercased())
        var sequentialCount = 0

        for i in 0..<(characters.count - 1) {
            if let ascii1 = characters[i].asciiValue,
               let ascii2 = characters[i + 1].asciiValue,
               abs(Int(ascii2) - Int(ascii1)) == 1 {
                sequentialCount += 1
                if sequentialCount >= 3 {
                    return true
                }
            } else {
                sequentialCount = 0
            }
        }
        return false
    }

    private func hasRepeatedCharacters(_ password: String) -> Bool {
        let characters = Array(password)
        var repeatCount = 0

        for i in 0..<(characters.count - 1) {
            if characters[i] == characters[i + 1] {
                repeatCount += 1
                if repeatCount >= 3 {
                    return true
                }
            } else {
                repeatCount = 0
            }
        }
        return false
    }

    private func generateFeedback(
        strength: StrengthLevel,
        requirements: [Requirement],
        password: String
    ) -> String {
        let unmetRequirements = requirements.filter { !$0.isMet }

        if unmetRequirements.isEmpty {
            switch strength {
            case .veryWeak, .weak:
                return "Try using a longer password with more variety."
            case .fair:
                return "Good password. Consider making it longer for extra security."
            case .strong:
                return "Strong password!"
            case .veryStrong:
                return "Excellent password!"
            }
        } else {
            return "Missing: " + unmetRequirements.map { $0.description }.joined(separator: ", ")
        }
    }
}

// MARK: - SwiftUI View for Password Strength Indicator

/// A SwiftUI view that displays password strength with visual feedback.
public struct PasswordStrengthIndicator: View {
    public let result: PasswordStrengthValidator.ValidationResult

    public init(result: PasswordStrengthValidator.ValidationResult) {
        self.result = result
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Strength bar
            HStack(spacing: 4) {
                ForEach(0..<5) { index in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(index <= result.strength.rawValue ? result.strength.color : Color.gray.opacity(0.3))
                        .frame(height: 4)
                }
            }

            // Strength label
            HStack {
                Image(systemName: result.strength.systemImage)
                    .foregroundStyle(result.strength.color)
                Text(result.strength.description)
                    .font(.caption)
                    .foregroundStyle(result.strength.color)
            }

            // Feedback
            Text(result.feedback)
                .font(.caption)
                .foregroundStyle(.secondary)

            // Requirements list (collapsed by default, shown for weak passwords)
            if result.strength < .fair {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(result.requirements) { req in
                        HStack(spacing: 6) {
                            Image(systemName: req.isMet ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(req.isMet ? .green : .gray)
                                .font(.caption2)
                            Text(req.description)
                                .font(.caption2)
                                .foregroundStyle(req.isMet ? .secondary : .primary)
                        }
                    }
                }
                .padding(.top, 4)
            }
        }
    }
}
