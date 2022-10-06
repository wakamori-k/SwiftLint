import Foundation
import PackagePlugin

@main
struct SwiftLintPlugin: BuildToolPlugin {
    func createBuildCommands(
        context: PackagePlugin.PluginContext,
        target: PackagePlugin.Target
    ) async throws -> [PackagePlugin.Command] {
        [
            .buildCommand(
                displayName: "SwiftLint",
                executable: try context.tool(named: "swiftlint").path,
                arguments: [
                    "lint",
                    "--cache-path", "\(context.pluginWorkDirectory)"
                ],
                environment: environment
            )
        ]
    }
}

private extension SwiftLintPlugin {
    var environment: [String: CustomStringConvertible] {
        var environment: [String: CustomStringConvertible] = [:]
        let keys = ["DEVELOPER_DIR"]
        for key in keys {
            environment[key] = ProcessInfo.processInfo.environment[key]
        }
        return environment
    }
}

#if canImport(XcodeProjectPlugin)
import XcodeProjectPlugin

extension SwiftLintPlugin: XcodeBuildToolPlugin {
    func createBuildCommands(
        context: XcodePluginContext,
        target: XcodeTarget
    ) throws -> [Command] {
        [
            .buildCommand(
                displayName: "SwiftLint",
                executable: try context.tool(named: "swiftlint").path,
                arguments: [
                    "lint",
                    "--cache-path", "\(context.pluginWorkDirectory)"
                ],
                environment: environment
            )
        ]
    }
}
#endif
