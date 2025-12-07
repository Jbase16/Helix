import Foundation

/// Tool to perform a multi-step reconnaissance chain on a target.
struct AutoReconTool: Tool {
    var name: String { "auto_recon" }
    var description: String { "Performs an autonomous reconnaissance chain: 1. Nmap scan 2. If web ports (80/443) open, runs Nikto and Gobuster. Returns a consolidated report." }
    var usageSchema: String { "auto_recon(target=\"<ip_or_domain>\")" }
    var requiresPermission: Bool { true }
    var shouldCachePermission: Bool { true }
    
    func run(arguments: [String : String]) async throws -> ToolResult {
        guard let targetRaw = arguments["target"] else {
             return ToolResult(output: "Error: Missing 'target' argument.", isError: true)
        }
        
        // 1. Sanitize Target for NMAP (Hostname Only)
        // Remove https/http
        var nmapTarget = targetRaw
            .replacingOccurrences(of: "https://", with: "")
            .replacingOccurrences(of: "http://", with: "")
        // Remove trailing path/fragments (e.g. /#/ or /index.html)
        if let slashIndex = nmapTarget.firstIndex(of: "/") {
            nmapTarget = String(nmapTarget[..<slashIndex])
        }
        // Remove bad chars that might have crept in (like trailing dots or # if no slash was present)
        nmapTarget = nmapTarget.trimmingCharacters(in: CharacterSet(charactersIn: ".#"))
        
        // 2. Prepare Target for WEB TOOLS (Full URL)
        // Ensure it has protocol
        var webURL = targetRaw
        if !webURL.lowercased().hasPrefix("http") {
             webURL = "https://" + webURL
        }
        
        // Dependency Check
        let checkNmap = try await RunCommandTool().run(arguments: ["command": "which nmap"])
        if checkNmap.isError {
            return ToolResult(output: "Error: 'nmap' is not installed. Please run `install_package(name=\"nmap\")` first.", isError: true)
        }
        
        var report = "=== 🛡️ HELIX VULNERABILITY REPORT 🛡️ ===\n"
        report += "Target Host: \(nmapTarget)\n"
        report += "Target URL: \(webURL)\n"
        report += "Date: \(Date())\n\n"
        
        // 1. Nmap Scan (Optimized for speed)
        report += "### 1. Network / Service Recon (Nmap Fast)\n"
        // -F: Fast mode (top 100 ports)
        // -T4: Aggressive timing (faster)
        // --open: Only show open ports
        let nmapCmd = "nmap -Pn -F -T4 --open \(nmapTarget)"
        let nmapResult = try await RunCommandTool().run(arguments: ["command": nmapCmd, "timeout": "120"])
        
        if nmapResult.isError {
            report += "⚠️ Nmap Warning: \(nmapResult.output)\n\n"
        } else {
            report += "```\n\(nmapResult.output)\n```\n\n"
        }
        
        // Logic: Decide if Web Recon is needed
        let nmapRaw = nmapResult.output
        let hasWebPorts = nmapRaw.contains("80/tcp") || nmapRaw.contains("443/tcp") || nmapRaw.contains("8080/tcp")
        let isDomain = nmapTarget.contains(".")
        
        if hasWebPorts || isDomain {
            report += "### 2. Web Vulnerability Recon (Nuclei)\n"
            
            // 2A. Nuclei Scan (Fast & Silent)
            let checkNuclei = try await RunCommandTool().run(arguments: ["command": "which nuclei"])
            if checkNuclei.isError {
                report += "\n⚠️ 'nuclei' not installed. Run `install_package(name=\"nuclei\")`.\n"
            } else {
                // Run critical/high severity scan
                let nucleiCmd = "nuclei -u \(webURL) -s critical,high -silent"
                // Nuclei can prompt for templates on first run; enforce a timeout to avoid hanging the agent.
                let nucleiResult = try await RunCommandTool().run(arguments: ["command": nucleiCmd, "timeout": "120"])
                if nucleiResult.output.isEmpty {
                     report += "No critical/high vulnerabilities found by Nuclei.\n"
                } else {
                     report += "```\n\(nucleiResult.output)\n```\n"
                }
            }
            
            // 2B. Cognitive Logic Analysis (AI Engine)
            // (Only if users asked for it explicitly? No, auto_recon implies full suite. But logic analysis uses tokens. Let's keep it but maybe it's fast enough 5-10s?)
            // report += "\n### 3. Cognitive Logic Analysis...\n"
            // skip for speed unless specifically requested via another tool
        } else {
            report += "### 2. Web Recon Skipped (No web ports or domain detected)\n"
        }
        
        report += "\n=== End of Report ===\n"
        
        return ToolResult(output: report, isError: false)
    }
}

/// Tool to run Nuclei specifically (standalone).
struct NucleiTool: Tool {
    var name: String { "nuclei_scan" }
    var description: String { "Runs ProjectDiscovery Nuclei scanner. Industry standard for bug bounty. Detects CVEs, misconfigurations, and logic bugs." }
    var usageSchema: String { "nuclei_scan(target=\"<url>\", severity=\"<critical|high|medium|low|info>\")" }
    var requiresPermission: Bool { true }
    var shouldCachePermission: Bool { true }
    
    func run(arguments: [String : String]) async throws -> ToolResult {
        guard let target = arguments["target"] else {
             return ToolResult(output: "Error: Missing 'target' argument.", isError: true)
        }
        let severity = arguments["severity"] ?? "critical,high,medium"
        
        let check = try await RunCommandTool().run(arguments: ["command": "which nuclei"])
        if check.isError {
             return ToolResult(output: "Error: 'nuclei' is not installed. Please run `install_package(name=\"nuclei\")` first.", isError: true)
        }
        
        // Strip protocol for nuclei? Nuclei handles URLs fine, but let's ensure it has one if missing, or leave as is.
        // Nuclei prefers full URLs (http://...) for web scanning.
        // If the user provided just "domain.com", we might want to prepend http/https or let nuclei handle it.
        // Nuclei is smart. We'll pass it raw but sanitized of spaces.
        let cleanTarget = target.trimmingCharacters(in: .whitespacesAndNewlines)
        
        let cmd = "nuclei -u \"\(cleanTarget)\" -s \(severity)"
        return try await RunCommandTool().run(arguments: ["command": cmd])
    }
}

/// Tool to search Exploit-DB for known vulnerabilities.
struct ExploitSearchTool: Tool {
    var name: String { "search_exploits" }
    var description: String { "Searches Exploit-DB (searchsploit) for known exploits matching a query (e.g., 'Apache 2.4')." }
    var usageSchema: String { "search_exploits(query=\"<software_version>\")" }
    var requiresPermission: Bool { true }
    var shouldCachePermission: Bool { true }
    
    func run(arguments: [String : String]) async throws -> ToolResult {
        guard let query = arguments["query"] else {
             return ToolResult(output: "Error: Missing 'query' argument.", isError: true)
        }
        
        let check = try await RunCommandTool().run(arguments: ["command": "which searchsploit"])
        if check.isError {
            return ToolResult(output: "Error: 'searchsploit' (Exploit-DB) is not installed. Please run `install_package(name=\"exploitdb\")` first.", isError: true)
        }
        
        let cmd = "searchsploit \"\(query)\""
        let result = try await RunCommandTool().run(arguments: ["command": cmd])
        return result
    }
}
