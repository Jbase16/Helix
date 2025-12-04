//
//  PermissionsView.swift
//  Helix
//
//  UI for managing persistent permissions and viewing the audit log.
//

import SwiftUI

struct PermissionsView: View {
    @ObservedObject var permissionManager: PermissionManager
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        VStack(spacing: 0) {
            // Header with close button
            HStack {
                Text("Manage Permissions")
                    .font(.headline)
                Spacer()
                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding()
            .background(Color(nsColor: .windowBackgroundColor))
            
            TabView {
                GrantedPermissionsList(manager: permissionManager)
                    .tabItem {
                        Label("Permissions", systemImage: "lock.shield")
                    }
                
                AuditLogList(manager: permissionManager)
                    .tabItem {
                        Label("Audit Log", systemImage: "list.bullet.rectangle")
                    }
            }
        }
        .frame(width: 600, height: 450)
    }
}

struct GrantedPermissionsList: View {
    @ObservedObject var manager: PermissionManager
    
    var body: some View {
        VStack(alignment: .leading) {
            Text("Granted Permissions")
                .font(.headline)
                .padding(.bottom, 4)
            
            if manager.grantedPermissions.isEmpty {
                Text("No persistent permissions granted.")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(manager.grantedPermissions.keys.sorted(), id: \.self) { toolName in
                        if let scope = manager.grantedPermissions[toolName] {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(toolName)
                                        .font(.system(.body, design: .monospaced))
                                        .bold()
                                    
                                    if scope.sessionOnly {
                                        Text("Session Only")
                                            .font(.caption)
                                            .foregroundColor(.orange)
                                    } else {
                                        Text("Persistent")
                                            .font(.caption)
                                            .foregroundColor(.green)
                                    }
                                    
                                    if let expires = scope.expiresAt {
                                        Text("Expires: \(expires.formatted())")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                
                                Spacer()
                                
                                Button("Revoke") {
                                    manager.revokePermission(toolName: toolName)
                                }
                                .buttonStyle(.bordered)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
            
            Spacer()
            
            Button("Revoke All") {
                manager.clearAllPermissions()
            }
            .disabled(manager.grantedPermissions.isEmpty)
        }
        .padding()
    }
}

struct AuditLogList: View {
    @ObservedObject var manager: PermissionManager
    
    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Text("Audit Log")
                    .font(.headline)
                Spacer()
                Button("Clear Log") {
                    manager.clearAuditLog()
                }
                .disabled(manager.auditLog.isEmpty)
            }
            .padding(.bottom, 4)
            
            if manager.auditLog.isEmpty {
                Text("No activity recorded.")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(manager.auditLog.reversed()) { entry in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(entry.toolName)
                                    .font(.system(.subheadline, design: .monospaced))
                                    .bold()
                                
                                Spacer()
                                
                                Text(entry.timestamp.formatted(date: .numeric, time: .standard))
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            
                            if !entry.arguments.isEmpty {
                                Text(entry.arguments.description)
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundColor(.secondary)
                                    .lineLimit(2)
                            }
                            
                            if entry.approved {
                                Text("Approved")
                                    .font(.caption)
                                    .foregroundColor(.green)
                            } else {
                                Text("Denied")
                                    .font(.caption)
                                    .foregroundColor(.red)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
        .padding()
    }
}
