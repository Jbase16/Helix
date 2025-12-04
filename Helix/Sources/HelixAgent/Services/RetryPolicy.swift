//
//  RetryPolicy.swift
//  Helix
//
//  Encapsulates retry logic for network operations.
//

import Foundation

struct RetryPolicy {
    let maxAttempts: Int
    let initialBackoff: TimeInterval
    let multiplier: Double
    
    init(maxAttempts: Int = 3, initialBackoff: TimeInterval = 2.0, multiplier: Double = 2.0) {
        self.maxAttempts = maxAttempts
        self.initialBackoff = initialBackoff
        self.multiplier = multiplier
    }
    
    func execute<T>(operation: () async throws -> T) async throws -> T {
        var currentBackoff = initialBackoff
        
        for attempt in 1...maxAttempts {
            do {
                return try await operation()
            } catch {
                if Task.isCancelled { throw HelixError.cancellation }
                
                // Only retry on specific errors (e.g. timeout)
                let shouldRetry = shouldRetry(error: error)
                
                if !shouldRetry || attempt == maxAttempts {
                    throw error
                }
                
                print("[RetryPolicy] Attempt \(attempt) failed: \(error). Retrying in \(currentBackoff)s...")
                try await Task.sleep(nanoseconds: UInt64(currentBackoff * 1_000_000_000))
                currentBackoff *= multiplier
            }
        }
        
        throw HelixError.unknown(message: "Retry policy failed unexpectedly")
    }
    
    private func shouldRetry(error: Error) -> Bool {
        if let urlError = error as? URLError {
            return urlError.code == .timedOut || 
                   urlError.code == .networkConnectionLost ||
                   urlError.code == .notConnectedToInternet
        }
        return false
    }
}
