//
//  PermissionManager.swift
//  Helix
//
//  Manages tool permissions with persistence, audit logging, and path-based whitelisting.
//

import Foundation
import Combine

@MainActor
final class PermissionManager: ObservableObject {
    
    @Published var grantedPermissions: [String: PermissionScope] = [:]
    @Published var auditLog: [AuditEntry] = []
    
    private let maxAuditEntries = 1000
    private let userDefaults = UserDefaults.standard
    private let permissionsKey = "HelixGrantedPermissions"
    private let auditKey = "HelixAuditLog"
    
    // MARK: - Models
    
    struct PermissionScope: Codable {
        let toolName: String
        let allowedPaths: [String]? // nil = all paths allowed
        let grantedAt: Date
        var expiresAt: Date?
        let sessionOnly: Bool // If true, clear on app restart
    }
    
    struct AuditEntry: Codable, Identifiable {
        let id: UUID
        let toolName: String
        let arguments: [String: String]
        let timestamp: Date
        let approved: Bool
        let path: String? // Extracted path for file operations
        
        init(toolName: String, arguments: [String: String], approved: Bool) {
            self.id = UUID()
            self.toolName = toolName
            self.arguments = arguments
            self.timestamp = Date()
            self.approved = approved
            self.path = arguments["path"]
        }
    }
    
    enum PermissionStatus {
        case granted
        case denied
        case needsApproval
    }
    
    // MARK: - Init
    
    init() {
        loadPermissions()
        loadAudit()
        cleanExpiredPermissions()
    }
    
    // MARK: - Permission Checking
    
    /// Check if permission is granted for a tool call.
    func checkPermission(for call: ToolCall) -> PermissionStatus {
        guard let scope = grantedPermissions[call.toolName] else {
            return .needsApproval
        }
        
        // Check expiration
        if let expiresAt = scope.expiresAt, expiresAt < Date() {
            revokePermission(toolName: call.toolName)
            return .needsApproval
        }
        
        // Check path whitelist if applicable
        if let allowedPaths = scope.allowedPaths,
           let requestedPath = call.arguments["path"] {
            let allowed = allowedPaths.contains { allowedPath in
                requestedPath.hasPrefix(allowedPath)
            }
            return allowed ? .granted : .needsApproval
        }
        
        return .granted
    }
    
    // MARK: - Permission Management
    
    /// Grant permission for a tool.
    func grantPermission(for call: ToolCall, scope: PermissionScope) {
        grantedPermissions[call.toolName] = scope
        
        if !scope.sessionOnly {
            savePermissions()
        }
        
        // Log approval
        saveAudit(AuditEntry(toolName: call.toolName, arguments: call.arguments, approved: true))
    }
    
    /// Revoke permission for a tool.
    func revokePermission(toolName: String) {
        grantedPermissions.removeValue(forKey: toolName)
        savePermissions()
    }
    
    /// Clear all permissions.
    func clearAllPermissions() {
        grantedPermissions.removeAll()
        savePermissions()
    }
    
    // MARK: - Audit Logging
    
    /// Log a permission denial.
    func logDenial(for call: ToolCall) {
        saveAudit(AuditEntry(toolName: call.toolName, arguments: call.arguments, approved: false))
    }
    
    /// Save an audit entry.
    private func saveAudit(_ entry: AuditEntry) {
        auditLog.append(entry)
        
        // Keep only recent entries
        if auditLog.count > maxAuditEntries {
            auditLog.removeFirst(auditLog.count - maxAuditEntries)
        }
        
        persistAudit()
    }
    
    /// Clear all audit logs.
    func clearAuditLog() {
        auditLog.removeAll()
        persistAudit()
    }
    
    // MARK: - Persistence
    
    private func savePermissions() {
        // Filter out session-only permissions
        let persistentPermissions = grantedPermissions.filter { !$0.value.sessionOnly }
        
        if let encoded = try? JSONEncoder().encode(persistentPermissions) {
            userDefaults.set(encoded, forKey: permissionsKey)
        }
    }
    
    private func loadPermissions() {
        guard let data = userDefaults.data(forKey: permissionsKey),
              let decoded = try? JSONDecoder().decode([String: PermissionScope].self, from: data) else {
            return
        }
        grantedPermissions = decoded
    }
    
    private func persistAudit() {
        if let encoded = try? JSONEncoder().encode(auditLog) {
            userDefaults.set(encoded, forKey: auditKey)
        }
    }
    
    private func loadAudit() {
        guard let data = userDefaults.data(forKey: auditKey),
              let decoded = try? JSONDecoder().decode([AuditEntry].self, from: data) else {
            return
        }
        auditLog = decoded
    }
    
    private func cleanExpiredPermissions() {
        let now = Date()
        grantedPermissions = grantedPermissions.filter { _, scope in
            if let expiresAt = scope.expiresAt {
                return expiresAt > now
            }
            return true
        }
        savePermissions()
    }
}
