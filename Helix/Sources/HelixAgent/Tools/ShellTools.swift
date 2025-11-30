//
//  ShellTools.swift
//  Helix
//
//  Created by Helix Agent.
//

import Foundation

/// Tool to run a shell command.
struct RunCommandTool: Tool {
    let name = "run_command"
    let description = "Executes a shell command on the system. Use with caution."
    let usageSchema = """
    <tool_code>
    run_command(command="<command_string>")
    </tool_code>
    """
    let requiresPermission = true
    
    func run(arguments: [String : String]) async throws -> ToolResult {
        guard let command = arguments["command"] else {
            return ToolResult(output: "Error: Missing 'command' argument.", isError: true)
        }
        
        let process = Process()
        let pipe = Pipe()
        let errorPipe = Pipe()
        
        // Run via /bin/zsh to support pipes, wildcards, etc.
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-c", command]
        process.standardOutput = pipe
        process.standardError = errorPipe
        
        do {
            try process.run()
            
            // Read output
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            
            process.waitUntilExit()
            
            let output = String(data: data, encoding: .utf8) ?? ""
            let errorOutput = String(data: errorData, encoding: .utf8) ?? ""
            
            let combined = output + (errorOutput.isEmpty ? "" : "\nSTDERR:\n\(errorOutput)")
            
            if process.terminationStatus == 0 {
                return ToolResult(output: combined.trimmingCharacters(in: .whitespacesAndNewlines), isError: false)
            } else {
                return ToolResult(output: "Command failed (Exit \(process.terminationStatus)):\n\(combined)", isError: true)
            }
            
        } catch {
            return ToolResult(output: "Failed to run command: \(error.localizedDescription)", isError: true)
        }
    }
}
