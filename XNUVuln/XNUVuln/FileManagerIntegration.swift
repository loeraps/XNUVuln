//
//  FileManagerIntegration.swift
//  XNUVuln
//
//  Created by 이지안 on 5/9/25.
//

import SwiftUI
import Foundation

// Structure to represent a file or directory item
struct FileItem: Identifiable, Hashable {
    let id = UUID()
    var name: String
    var path: String
    var isDirectory: Bool
    var size: Int64? // Optional: for files
    var modificationDate: Date? // Optional
}

class FileManagerViewModel: ObservableObject {
    @Published var selectedFilePath: String?
    @Published var operationStatus: String = "Ready."
    @Published var currentPath: String = "/"
    @Published var itemsInCurrentPath: [FileItem] = []
    @Published var fileContent: String?
    @Published var fileDataHex: String?

    private let fileManager = FileManager.default

        init() {
            if let documentsPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first?.path {
                currentPath = documentsPath
                navigateTo(path: documentsPath)
            } else {
                let bundlePath = Bundle.main.bundlePath
                currentPath = bundlePath
                navigateTo(path: bundlePath)
            }
            if currentPath.isEmpty || currentPath == "/" && itemsInCurrentPath.isEmpty {
                 if !fileManager.fileExists(atPath: currentPath) || itemsInCurrentPath.isEmpty {
                    navigateTo(path: "/")
                }
            }
        
            if operationStatus == "Ready." && !currentPath.isEmpty {
                 operationStatus = "Browsing: \((currentPath as NSString).lastPathComponent)"
            } else if operationStatus == "Ready." && currentPath.isEmpty {
                operationStatus = "Could not determine initial path."
            }
        }

    private func getFileName(fromPath path: String?) -> String {
        guard let p = path, !p.isEmpty else { return "N/A" }
        return (p as NSString).lastPathComponent
    }

    func attemptToZeroOutFilePage(filePath: String, offset: off_t = 0) {
        let fileName = getFileName(fromPath: filePath)
        #if targetEnvironment(simulator)
        let simStatus = "SIMULATOR: Would attempt to zero out page for \(fileName) at offset \(offset)"
        print(simStatus)
        DispatchQueue.main.async {
            self.selectedFilePath = filePath
            self.operationStatus = simStatus
        }
        return
        #else
        DispatchQueue.main.async { self.selectedFilePath = filePath }

        DispatchQueue.global(qos: .userInitiated).async {
            var statusMessage = ""
            if filePath.isEmpty {
                statusMessage = "File path cannot be empty."
            } else {
                filePath.withCString { cPathPtr in // cPathPtr = UnsafePointer<CChar>
                    let result = zero_out_file_page(cPathPtr, offset)
                    if result == 0 {
                        statusMessage = "Successfully attempted to zero out page for \(fileName) at offset \(offset)."
                    } else {
                        statusMessage = "Failed to zero out page for \(fileName). Error code: \(result)."
                    }
                }
            }
            if statusMessage.isEmpty && !filePath.isEmpty {
                 statusMessage = "C string conversion or unexpected error for \(fileName)."
            } else if statusMessage.isEmpty && filePath.isEmpty {
                statusMessage = "File path was empty, operation aborted."
            }


            DispatchQueue.main.async {
                self.operationStatus = statusMessage
                print(statusMessage)
                if (filePath as NSString).deletingLastPathComponent == self.currentPath {
                    self.listDirectoryContents(atPath: self.currentPath)
                }
            }
        }
        #endif
    }

    func attemptToZeroOutEntireFile(filePath: String) {
        let fileName = getFileName(fromPath: filePath)
        #if targetEnvironment(simulator)
        let simStatus = "SIMULATOR: Would attempt to zero out entire file \(fileName)"
        print(simStatus)
        DispatchQueue.main.async {
            self.selectedFilePath = filePath
            self.operationStatus = simStatus
        }
        return
        #else
        DispatchQueue.main.async { self.selectedFilePath = filePath }

        DispatchQueue.global(qos: .userInitiated).async {
            var finalStatus = ""
            if filePath.isEmpty {
                finalStatus = "File path cannot be empty for zeroing out entire file."
                DispatchQueue.main.async { self.operationStatus = finalStatus; print(finalStatus) }
                return
            }
            
            do {
                let attributes = try self.fileManager.attributesOfItem(atPath: filePath)
                guard let fileSize = attributes[.size] as? NSNumber else {
                    finalStatus = "Could not get file size for \(fileName)."
                    DispatchQueue.main.async { self.operationStatus = finalStatus; print(finalStatus) }
                    return
                }

                let exploitPageSize: off_t = 16384
                var offset: off_t = 0
                let totalSize = fileSize.int64Value
                var pagesProcessed = 0
                var errorOccurred = false

                if totalSize == 0 {
                    finalStatus = "\(fileName) is empty. Nothing to zero out."
                    DispatchQueue.main.async { self.operationStatus = finalStatus; print(finalStatus) }
                    return
                }

                while offset < totalSize && !errorOccurred {
                    var pageProcessAttemptedInClosure = false
                    filePath.withCString { cPathPtr -> Void in
                        pageProcessAttemptedInClosure = true
                        let result = zero_out_file_page(cPathPtr, offset)
                        if result != 0 {
                            finalStatus = "Failed to zero out page at offset \(offset) for \(fileName). Error: \(result). Aborting."
                            errorOccurred = true
                            return
                        }
                        pagesProcessed += 1
                    }

                    if !pageProcessAttemptedInClosure && !errorOccurred {
                        finalStatus = "Critical C string conversion error for \(fileName). Aborting."
                        errorOccurred = true
                    }
                    
                    if errorOccurred { break }
                    
                    offset += exploitPageSize
                }

                if !errorOccurred {
                    finalStatus = "Successfully attempted to zero out \(pagesProcessed) page(s) for entire file: \(fileName)."
                } else if finalStatus.isEmpty {
                    finalStatus = "An unspecified error occurred while zeroing out \(fileName)."
                }

            } catch {
                finalStatus = "Error processing file \(fileName): \(error.localizedDescription)."
            }
            DispatchQueue.main.async {
                self.operationStatus = finalStatus
                print(finalStatus)
                if (filePath as NSString).deletingLastPathComponent == self.currentPath {
                    self.listDirectoryContents(atPath: self.currentPath)
                }
            }
        }
        #endif
    }

    func navigateTo(path: String) {
        var standardizedPath = (path as NSString).standardizingPath
        if standardizedPath.isEmpty {
            standardizedPath = "/"
        }
        
        var isDir: ObjCBool = false
        if !fileManager.fileExists(atPath: standardizedPath, isDirectory: &isDir) || !isDir.boolValue {
            operationStatus = "Path '\(getFileName(fromPath: standardizedPath))' not accessible or not a directory. Trying Documents."
            print(operationStatus)
            if let documentsPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first?.path {
                standardizedPath = documentsPath
            } else {
                currentPath = "/"
                itemsInCurrentPath = []
                operationStatus = "Could not navigate. Fallback to root failed."
                print(operationStatus)
                return
            }
        }
        
        currentPath = standardizedPath
        listDirectoryContents(atPath: currentPath)
        if itemsInCurrentPath.isEmpty && currentPath != "/" {
        }
        operationStatus = "Browsing: \(getFileName(fromPath: currentPath))"
    }

    func goUpOneLevel() {
        if currentPath != "/" {
            let parentPath = (currentPath as NSString).deletingLastPathComponent
            navigateTo(path: parentPath.isEmpty ? "/" : parentPath)
        } else {
            operationStatus = "Already at root."
        }
    }

    func listDirectoryContents(atPath path: String) {
        var tempItems: [FileItem] = []
        do {
            let contents = try fileManager.contentsOfDirectory(atPath: path)
            for itemName in contents.sorted() {
                let fullPath = (path as NSString).appendingPathComponent(itemName)
                var isDir: ObjCBool = false
                var itemSize: Int64? = nil
                var modDate: Date? = nil

                if fileManager.fileExists(atPath: fullPath, isDirectory: &isDir) {
                    do {
                        let attributes = try fileManager.attributesOfItem(atPath: fullPath)
                        itemSize = attributes[.size] as? Int64
                        modDate = attributes[.modificationDate] as? Date
                    } catch {
                    }
                    tempItems.append(FileItem(name: itemName, path: fullPath, isDirectory: isDir.boolValue, size: itemSize, modificationDate: modDate))
                }
            }
             itemsInCurrentPath = tempItems.sorted {
                if $0.isDirectory != $1.isDirectory {
                    return $0.isDirectory
                }
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
            if tempItems.isEmpty {
                operationStatus = "Directory '\(getFileName(fromPath: path))' is empty or inaccessible."
            }

        } catch {
            operationStatus = "Error listing '\(getFileName(fromPath: path))': \(error.localizedDescription)"
            print(operationStatus)
            itemsInCurrentPath = []
        }
    }

    func loadFileContent(filePath: String) {
        let fileName = getFileName(fromPath: filePath)
        self.selectedFilePath = filePath
        self.fileContent = nil
        self.fileDataHex = nil
        operationStatus = "Loading content for \(fileName)..."

        DispatchQueue.global(qos: .userInitiated).async {
            var loadedContent: String? = nil
            var loadedHex: String? = nil
            var statusMsg: String

            do {
                let data = try Data(contentsOf: URL(fileURLWithPath: filePath), options: .mappedIfSafe)
                
                if data.isEmpty {
                    statusMsg = "\(fileName) is empty."
                } else if let textContent = String(data: data, encoding: .utf8) {
                    loadedContent = textContent
                    statusMsg = "Loaded text content for \(fileName)."
                } else {
                    let chunkSize = 1024 * 16
                    var hexChunks: [String] = []
                    var offset = 0
                    while offset < data.count {
                        let chunkEnd = min(offset + chunkSize, data.count)
                        let chunk = data[offset..<chunkEnd]
                        hexChunks.append(chunk.map { String(format: "%02hhx", $0) }.joined(separator: " "))
                        offset = chunkEnd
                         if hexChunks.count * chunkSize > 2 * 1024 * 1024 {
                            hexChunks.append("... (content truncated due to size)")
                            break
                        }
                    }
                    loadedHex = hexChunks.joined(separator: "\n") 
                    statusMsg = "Loaded hex content for \(fileName) (binary or non-UTF8)."
                }
            } catch {
                statusMsg = "Error loading file content for \(fileName): \(error.localizedDescription)"
            }

            DispatchQueue.main.async {
                self.fileContent = loadedContent
                self.fileDataHex = loadedHex
                self.operationStatus = statusMsg
                print(statusMsg)
            }
        }
    }
}
