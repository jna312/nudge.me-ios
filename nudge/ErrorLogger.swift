import Foundation
import SwiftData
import os.log

/// Centralized error logging for debugging
enum ErrorLogger {
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.nudge", category: "errors")
    
    /// Log an error with context
    static func log(_ error: Error, context: String, file: String = #file, function: String = #function, line: Int = #line) {
        let fileName = (file as NSString).lastPathComponent
        logger.error("[\(fileName):\(line)] \(context): \(error.localizedDescription)")
        
        #if DEBUG
        print("❌ [\(fileName):\(line)] \(context): \(error)")
        #endif
    }
    
    /// Log a message for debugging
    static func debug(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        #if DEBUG
        let fileName = (file as NSString).lastPathComponent
        print("🔍 [\(fileName):\(line)] \(message)")
        #endif
    }
    
    /// Execute a throwing operation with error logging
    static func attempt<T>(_ context: String, operation: () throws -> T) -> T? {
        do {
            return try operation()
        } catch {
            log(error, context: context)
            return nil
        }
    }
    
    /// Execute an async throwing operation with error logging
    static func attemptAsync<T>(_ context: String, operation: () async throws -> T) async -> T? {
        do {
            return try await operation()
        } catch {
            log(error, context: context)
            return nil
        }
    }
}

// MARK: - Convenience Extensions

extension ModelContext {
    /// Save with error logging
    func saveWithLogging(context: String = "Saving model context") {
        do {
            try save()
        } catch {
            ErrorLogger.log(error, context: context)
        }
    }
}
