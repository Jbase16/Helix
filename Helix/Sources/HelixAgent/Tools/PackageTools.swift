import Foundation

/// Tool to install packages using Homebrew.
struct InstallPackageTool: Tool {
    var name: String { "install_package" }
    var description: String { "Installs a package/tool using Homebrew (brew). Use this to install security tools like nmap, sqlmap, etc." }
    var usageSchema: String { "install_package(name=\"<package_name>\")" }
    var requiresPermission: Bool { true }
    var shouldCachePermission: Bool { true }
    
    func run(arguments: [String : String]) async throws -> ToolResult {
        guard let packageName = arguments["name"] else {
             return ToolResult(output: "Error: Missing 'name' argument.", isError: true)
        }
        
        // Prevent installing obviously dangerous or huge things blindly if possible,
        // but for now we trust the user's permission.
        
        // Check if already installed to save time?
        // brew list <name>
        
        let checkCommand = "brew list \(packageName)"
        let checkResult = try await RunCommandTool().run(arguments: ["command": checkCommand])
        if !checkResult.isError {
            return ToolResult(output: "Package '\(packageName)' is already installed.", isError: false)
        }
        
        let installCommand = "brew install \(packageName)"
        let result = try await RunCommandTool().run(arguments: ["command": installCommand])
        
        if result.isError {
            return ToolResult(output: "Failed to install '\(packageName)': \(result.output)", isError: true)
        }
        
        return ToolResult(output: "Successfully installed '\(packageName)'.\nOutput:\n\(result.output)", isError: false)
    }
}

/// Tool to list installed Homebrew packages.
struct ListPackagesTool: Tool {
    var name: String { "list_packages" }
    var description: String { "Lists all packages installed via Homebrew. Useful to see if a tool is already available." }
    var usageSchema: String { "list_packages()" }
    var requiresPermission: Bool { false } // Listing is harmless
    var shouldCachePermission: Bool { true }
    
    func run(arguments: [String : String]) async throws -> ToolResult {
        let command = "brew list"
        let result = try await RunCommandTool().run(arguments: ["command": command])
        return result
    }
}
