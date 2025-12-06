import Foundation

// Paste the logic from PipeReader.swift and ShellTools.swift (RunCommandTool) here to test it standalone
// MOCKING the Tool protocol and Context

final class PipeReader: @unchecked Sendable {
    private nonisolated(unsafe) var data = Data()
    private let queue = DispatchQueue(label: "com.helix.pipereader")
    
    nonisolated init() {}
    
    nonisolated func append(_ chunk: Data) {
        queue.async { [weak self] in
            self?.data.append(chunk)
        }
    }
    
    nonisolated func read() -> Data {
        queue.sync { return data }
    }
}

struct ToolResult {
    let output: String
    let isError: Bool
}

func runCommand(command: String) async throws -> ToolResult {
    return try await withCheckedThrowingContinuation { continuation in
        let process = Process()
        let pipe = Pipe()
        let errorPipe = Pipe()
        
        let outputReader = PipeReader()
        let errorReader = PipeReader()
        
        var environment = ProcessInfo.processInfo.environment
        let currentPath = environment["PATH"] ?? ""
        let newPath = "/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin:" + currentPath
        environment["PATH"] = newPath
        process.environment = environment
        
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-c", command]
        process.standardOutput = pipe
        process.standardError = errorPipe
        
        pipe.fileHandleForReading.readabilityHandler = { handle in
            outputReader.append(handle.availableData)
        }
        errorPipe.fileHandleForReading.readabilityHandler = { handle in
            errorReader.append(handle.availableData)
        }
        
        process.terminationHandler = { proc in
            pipe.fileHandleForReading.readabilityHandler = nil
            errorPipe.fileHandleForReading.readabilityHandler = nil
            
            // Give a tiny buffer for dispatch queue to finish appending?
            // PipeReader.read() runs on queue.sync, so it implicitly waits for async blocks IF they are already scheduled.
            // But readabilityHandler runs on arbitrary queue.
            
            // Wait a callback cycle for safety? 
            // In production code we might need Group.notify, but let's test straight.
            
            Thread.sleep(forTimeInterval: 0.1) // Hacky sync for test
            
            let outputData = outputReader.read()
            let errorData = errorReader.read()
            
            let output = String(data: outputData, encoding: .utf8) ?? ""
            let errorOutput = String(data: errorData, encoding: .utf8) ?? ""
            let combined = output + (errorOutput.isEmpty ? "" : "\nSTDERR:\n\(errorOutput)")
            
            if proc.terminationStatus == 0 {
                continuation.resume(returning: ToolResult(output: combined, isError: false))
            } else {
                continuation.resume(returning: ToolResult(output: "Exit \(proc.terminationStatus): \(combined)", isError: true))
            }
        }
        
        do {
            try process.run()
            print("Process launched...")
        } catch {
            continuation.resume(returning: ToolResult(output: "Failed launch: \(error)", isError: true))
        }
    }
}

// TEST
let group = DispatchGroup()
group.enter()

Task {
    print("Testing 'ls -la'...")
    let result = try! await runCommand(command: "ls -la /")
    print("RESULT:\n\(result.output)")
    
    print("Testing 'sleep 2; echo done'...")
    let result2 = try! await runCommand(command: "sleep 2; echo done")
    print("RESULT 2:\n\(result2.output)")
    
    group.leave()
}

group.wait()
print("Finished.")
