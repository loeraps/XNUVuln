//
//  FileContentView.swift
//  XNUVuln
//
//  Created by 이지안 on 5/9/25.
//

import SwiftUI

struct FileContentView: View {
    @ObservedObject var viewModel: FileManagerViewModel
    @Environment(\.presentationMode) var presentationMode

    private func getFileNameForTitle(fromOptionalPath optionalPath: String?) -> String {
        guard let p = optionalPath, !p.isEmpty else { return "File Content" }
        return (p as NSString).lastPathComponent
    }

    @ViewBuilder
    private func contentStatusView() -> some View {
        let fileName = getFileNameForTitle(fromOptionalPath: viewModel.selectedFilePath)

        if viewModel.selectedFilePath == nil {
            Text("No file selected.")
                .padding()
        } else if viewModel.selectedFilePath!.isEmpty { 
            Text("Invalid file path (empty string).")
                .padding()
        } else {
            
            let message = getFileStatusMessage(filePath: viewModel.selectedFilePath!, fileName: fileName)
            Text(message)
                .padding()
        }
    }

    private func getFileStatusMessage(filePath: String, fileName: String) -> String {
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: filePath)
            if let fileSize = attributes[.size] as? NSNumber, fileSize.int64Value == 0 {
                return "\(fileName) is empty (0 bytes)."
            } else {
                return "No text/hex content to display for \(fileName). It might be an unsupported format, an error occurred during loading, or the file is binary and very large (hex display truncated)."
            }
        } catch {
            return "Error accessing attributes for \(fileName). Cannot determine size or content type."
        }
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading) {
                    if let content = viewModel.fileContent {
                        Text(content)
                            .font(.system(.body, design: .monospaced))
                            .padding()
                            .textSelection(.enabled)
                    } else if let hex = viewModel.fileDataHex {
                        Text(hex)
                            .font(.system(.caption, design: .monospaced))
                            .lineLimit(nil)
                            .padding()
                            .textSelection(.enabled)
                    } else {
                        contentStatusView()
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationTitle(Text(getFileNameForTitle(fromOptionalPath: viewModel.selectedFilePath)))
            .navigationBarItems(trailing: Button("Done") {
                presentationMode.wrappedValue.dismiss()
            })
        }
    }
}
