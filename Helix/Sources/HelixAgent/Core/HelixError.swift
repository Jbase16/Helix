//
//  HelixError.swift
//  Helix
//
//  Central error type for the Helix engine.
//  This keeps all “things went wrong” states in one place
//  so the UI and higher-level logic can reason about them.
//

import Foundation

/// Top‑level error type for Helix’s core engine.
///
/// This is intentionally expressive and opinionated so you can:
/// - surface meaningful messages to the UI
/// - log structured errors
/// - branch behavior based on type (network vs model vs internal)
enum HelixError: Error, LocalizedError, Identifiable {
    /// An underlying networking failure (timeout, DNS, connection reset, etc).
    case network(underlying: Error)

    /// The server responded, but with a non‑2xx HTTP status code.
    case invalidResponse(statusCode: Int)

    /// JSON / data decoding failed for a response we expected to parse.
    case decoding(underlying: Error)

    /// Ollama does not appear to be running on the expected host/port.
    case ollamaNotRunning

    /// The requested model is not available / not pulled yet.
    case modelNotAvailable(String)

    /// The user (or the app) cancelled an in‑flight request.
    case cancellation

    /// Something about our internal state was inconsistent with expectations.
    /// Example: no active thread selected when we expected one.
    case internalInconsistentState(String)

    /// A generic “we didn’t have a dedicated case for this” error.
    case unknown(message: String)

    // MARK: - Identifiable

    /// Allows this error to be used directly in SwiftUI alerts.
    var id: String {
        // Use the localized description as a stable identifier.
        localizedDescription
    }

    // MARK: - LocalizedError

    var errorDescription: String? {
        switch self {
        case .network(let underlying):
            return "Network error: \(underlying.localizedDescription)"

        case .invalidResponse(let statusCode):
            return "Unexpected response from model server (HTTP \(statusCode))."

        case .decoding(let underlying):
            return "Failed to decode model response: \(underlying.localizedDescription)"

        case .ollamaNotRunning:
            return "Could not reach the local model server. Is Ollama running on this machine?"

        case .modelNotAvailable(let name):
            return "The requested model “\(name)” is not available. Make sure it is pulled in Ollama."

        case .cancellation:
            return "The operation was cancelled."

        case .internalInconsistentState(let message):
            return "Internal Helix state error: \(message)"

        case .unknown(let message):
            return message.isEmpty ? "An unknown error occurred." : message
        }
    }
}
