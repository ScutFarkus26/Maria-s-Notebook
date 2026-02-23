// TypeAliases.swift
// Common type aliases for improved readability

import Foundation

/// A callback that takes no parameters and returns nothing.
typealias VoidCallback = () -> Void

/// A callback that receives a Student.
typealias StudentCallback = (Student) -> Void

/// A callback that receives a Lesson.
typealias LessonCallback = (Lesson) -> Void

/// A callback that receives a UUID.
typealias UUIDCallback = (UUID) -> Void

/// A callback that receives a String.
typealias StringCallback = (String) -> Void

/// A callback that receives a Bool.
typealias BoolCallback = (Bool) -> Void

/// A callback that receives a Date.
typealias DateCallback = (Date) -> Void
