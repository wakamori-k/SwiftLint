import Foundation
import PackagePlugin

@main
struct SwiftLintAutoCorrectPlugin: BuildToolPlugin {
    func createBuildCommands(
        context: PackagePlugin.PluginContext,
        target: PackagePlugin.Target
    ) async throws -> [PackagePlugin.Command] {
        [
            .prebuildCommand(
                displayName: "SwiftLintFix",
                executable: try context.tool(named: "swiftlint").path,
                arguments: [
                    "lint", context.package.directory.string,
                    "--autocorrect",
                    "--cache-path", context.pluginWorkDirectory,
                ],
                outputFilesDirectory: context.pluginWorkDirectory
            )
        ]
    }
}

#if canImport(XcodeProjectPlugin)
import XcodeProjectPlugin

extension SwiftLintAutoCorrectPlugin: XcodeBuildToolPlugin {
    func createBuildCommands(
        context: XcodePluginContext,
        target: XcodeTarget
    ) throws -> [Command] {
        [
            .prebuildCommand(
                displayName: "SwiftLintFix",
                executable: try context.tool(named: "swiftlint").path,
                arguments: [
                    "lint", context.xcodeProject.directory.string,
                    "--autocorrect",
                    "--cache-path", context.pluginWorkDirectory,
                ],
                outputFilesDirectory: context.pluginWorkDirectory
            )
        ]
    }
}
#endif
