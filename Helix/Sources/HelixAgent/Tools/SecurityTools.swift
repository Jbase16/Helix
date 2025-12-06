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
        
        // Sanitize target: remove protocol and trailing slashes for nmap compatibility
        var target = targetRaw
            .replacingOccurrences(of: "https://", with: "")
            .replacingOccurrences(of: "http://", with: "")
        
        if let slashIndex = target.firstIndex(of: "/") {
            target = String(target[..<slashIndex])
        }
        
        // Dependency Check
        let checkNmap = try await RunCommandTool().run(arguments: ["command": "which nmap"])
        if checkNmap.isError {
            return ToolResult(output: "Error: 'nmap' is not installed. Please run `install_package(name=\"nmap\")` first.", isError: true)
        }
        
        var report = "=== 🛡️ HELIX VULNERABILITY REPORT 🛡️ ===\n"
        report += "Target: \(target)\n"
        report += "Date: \(Date())\n\n"
        
        // 1. Nmap Scan (Pro Mode: -Pn skip ping, -sV version detection, -F fast ports)
        report += "### 1. Network / Service Recon (Nmap)\n"
        let nmapCmd = "nmap -Pn -sV -F \(target)"
        let nmapResult = try await RunCommandTool().run(arguments: ["command": nmapCmd])
        
        if nmapResult.isError {
            report += "⚠️ Nmap Warning: \(nmapResult.output)\n\n"
        } else {
            report += "```\n\(nmapResult.output)\n```\n\n"
        }
        
        // Logic: Decide if Web Recon is needed
        // If ports 80/443/8080 are open OR if the target looks like a domain (has a dot), force web recon.
        let nmapRaw = nmapResult.output
        let hasWebPorts = nmapRaw.contains("80/tcp") || nmapRaw.contains("443/tcp") || nmapRaw.contains("8080/tcp")
        let isDomain = target.contains(".") && !target.allSatisfy({ $0.isNumber || $0 == "." }) // Simple heuristic
        
        if hasWebPorts || isDomain {
            report += "### 2. Web Vulnerability Recon\n"
            
            // 2A. Nikto Scan
            let checkNikto = try await RunCommandTool().run(arguments: ["command": "which nikto"])
            if checkNikto.isError {
                 report += "⚠️ 'nikto' not installed. Skipping.\n"
            } else {
                report += "#### Nikto Scan\n"
                // -Tuning b (Software Identification), x (Reverse Logic) to save time, or just standard.
                // Using standard but with timeout limiting.
                let niktoCmd = "nikto -h \(target) -maxtime 90"
                let niktoResult = try await RunCommandTool().run(arguments: ["command": niktoCmd])
                report += "```\n\(niktoResult.output)\n```\n"
            }
            
            // 2B. Nuclei Scan (The "Pro" Tool)
            let checkNuclei = try await RunCommandTool().run(arguments: ["command": "which nuclei"])
            if checkNuclei.isError {
                report += "\n⚠️ 'nuclei' not installed. Recommended for pro-level scanning. Run `install_package(name=\"nuclei\")`.\n"
            } else {
                report += "\n#### Nuclei Scan (Critical/High/Medium)\n"
                // Run silent scan, only output findings.
                let nucleiCmd = "nuclei -u \(target) -s critical,high,medium -silent"
                let nucleiResult = try await RunCommandTool().run(arguments: ["command": nucleiCmd])
                if nucleiResult.output.isEmpty {
                     report += "No critical/high/medium vulnerabilities found by Nuclei.\n"
                } else {
                     report += "```\n\(nucleiResult.output)\n```\n"
                }
            }
            
            // 2C. Cognitive Logic Analysis (The "Game Changer")
            report += "\n### 3. Cognitive Logic Analysis (AI Engine)\n"
            let logicResult = try await AnalyzeLogicTool().run(arguments: ["target": target])
            if logicResult.isError {
                report += "⚠️ Logic analysis failed: \(logicResult.output)\n"
            } else {
                // Extract only the meat from the report (skip header/footer)
                let logicOutput = logicResult.output
                    .replacingOccurrences(of: "=== 🧠 COGNITIVE LOGIC ANALYSIS: \(target) ===", with: "")
                    .replacingOccurrences(of: "=== End Analysis ===", with: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                report += logicOutput + "\n"
            }
            
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
