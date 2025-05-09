//
//  FileBrowserView.swift
//  XNUVuln
//
//  Created by 이지안 on 5/9/25.
//

import SwiftUI

struct FileBrowserView: View {
    @ObservedObject var viewModel: FileManagerViewModel
    @Binding var selectedFileForExploitBinding: String? 

    @State private var showFileContentView = false

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Button(action: {
                    viewModel.goUpOneLevel()
                }) {
                    Image(systemName: "arrow.up.circle.fill")
                    Text("Up")
                }
                .disabled(viewModel.currentPath == "/" && !canGoUpFromPseudoRoot())

                Spacer()
                Text("Path: \((viewModel.currentPath as NSString).abbreviatingWithTildeInPath)")
                    .font(.caption2)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Button(action: {
                    viewModel.listDirectoryContents(atPath: viewModel.currentPath)
                }) {
                     Image(systemName: "arrow.clockwise.circle.fill")
                }
            }
            .padding(.horizontal)
            .padding(.top, 5)

            List {
                ForEach(viewModel.itemsInCurrentPath) { item in
                    HStack {
                        Image(systemName: item.isDirectory ? "folder.fill" : "doc.fill")
                            .foregroundColor(item.isDirectory ? .blue : .gray)
                        Text(item.name)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        if !item.isDirectory, let size = item.size {
                            Text(formatFileSize(size))
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if item.isDirectory {
                            viewModel.navigateTo(path: item.path)
                        } else {
                            selectedFileForExploitBinding = item.path
                            viewModel.operationStatus = "Target: \(item.name)"
                        }
                    }
                    .contextMenu {
                        if item.isDirectory {
                             Button {
                                viewModel.navigateTo(path: item.path)
                            } label: {
                                Label("Open Directory", systemImage: "folder")
                            }
                        } else {
                            Button {
                                selectedFileForExploitBinding = item.path
                                viewModel.operationStatus = "Target: \(item.name)"
                            } label: {
                                Label("Select for Exploit", systemImage: "hammer.fill")
                            }
                            Button {
                                viewModel.loadFileContent(filePath: item.path)
                                self.showFileContentView = true
                            } label: {
                                Label("View Content", systemImage: "eye.fill")
                            }
                        }
                    }
                }
            }
            .listStyle(.plain)
        }
        .sheet(isPresented: $showFileContentView) {
            // Pass the same viewModel instance
            FileContentView(viewModel: viewModel)
        }
    }

        private func canGoUpFromPseudoRoot() -> Bool {
            if let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?.path {
                if viewModel.currentPath == documentsPath && (documentsPath as NSString).pathComponents.count > 1 {
                    return true
                }
            }

            let bundlePath = Bundle.main.bundlePath
            if viewModel.currentPath == bundlePath && (bundlePath as NSString).pathComponents.count > 1 {
                return true
            }
            return viewModel.currentPath != "/" && (viewModel.currentPath as NSString).pathComponents.count > 1
        }
    
    private func formatFileSize(_ size: Int64) -> String {
        return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }
}

