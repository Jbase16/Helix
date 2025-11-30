//
//  FileTools.swift
//  Helix
//
//  Created by Helix Agent.
//

import Foundation

/// Tool to read the contents of a file.
struct ReadFileTool: Tool {
    let name = "read_file"
    let description = "Reads the contents of a file at the given path."
    let usageSchema = """
    <tool_code>
    read_file(path="<absolute_path>")
    </tool_code>
    """
    let requiresPermission = false
    
    func run(arguments: [String : String]) async throws -> ToolResult {
        guard let path = arguments["path"] else {
            return ToolResult(output: "Error: Missing 'path' argument.", isError: true)
        }
        
        let url = URL(fileURLWithPath: path)
        do {
            let data = try Data(contentsOf: url)
            let content = String(data: data, encoding: .utf8) ?? "Error: File is not valid UTF-8 text."
            return ToolResult(output: content, isError: false)
        } catch {
            return ToolResult(output: "Error reading file: \(error.localizedDescription)", isError: true)
        }
    }
}

/// Tool to list the contents of a directory.
struct ListDirTool: Tool {
    let name = "list_dir"
    let description = "Lists the files and subdirectories in a given directory."
    let usageSchema = """
    <tool_code>
    list_dir(path="<absolute_path>")
    </tool_code>
    """
    let requiresPermission = false
    
    func run(arguments: [String : String]) async throws -> ToolResult {
        guard let path = arguments["path"] else {
            return ToolResult(output: "Error: Missing 'path' argument.", isError: true)
        }
        
        let url = URL(fileURLWithPath: path)
        let fm = FileManager.default
        
        do {
            let items = try fm.contentsOfDirectory(atPath: path)
            if items.isEmpty {
                return ToolResult(output: "(Directory is empty)", isError: false)
            }
            
            // Add a trailing slash to directories for clarity
            let formattedItems = items.map { item -> String in
                var isDir: ObjCBool = false
                let fullPath = url.appendingPathComponent(item).path
                if fm.fileExists(atPath: fullPath, isDirectory: &isDir), isDir.boolValue {
                    return item + "/"
                }
                return item
            }
            
            return ToolResult(output: formattedItems.sorted().joined(separator: "\n"), isError: false)
        } catch {
            return ToolResult(output: "Error listing directory: \(error.localizedDescription)", isError: true)
        }
    }
}
