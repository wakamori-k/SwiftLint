#if canImport(Darwin)
import Darwin
#endif
import Foundation
import SourceKittenFramework
import SwiftParser
import SwiftSyntax

private let warnSyntaxParserFailureOnceImpl: Void = {
    queuedPrintError("Could not parse the syntax tree for at least one file. Results may be invalid.")
}()

private func warnSyntaxParserFailureOnce() {
    _ = warnSyntaxParserFailureOnceImpl
}

private typealias FileCacheKey = UUID
private var responseCache = Cache({ file -> [String: SourceKitRepresentable]? in
    do {
        return try Request.editorOpen(file: file.file).sendIfNotDisabled()
    } catch let error as Request.Error {
        queuedPrintError(error.description)
        return nil
    } catch {
        return nil
    }
})
private var structureCache = Cache({ file -> Structure? in
    if let structure = responseCache.get(file).map(Structure.init) {
        queueForRebuild.append(structure)
        return structure
    }
    return nil
})

private var structureDictionaryCache = Cache({ file in
    return structureCache.get(file).map { SourceKittenDictionary($0.dictionary) }
})

private var syntaxTreeCache = Cache({ file -> SourceFileSyntax? in
    do {
        return try Parser.parse(source: file.contents)
    } catch {
        warnSyntaxParserFailureOnce()
        return nil
    }
})

private var commandsCache = Cache({ file -> [Command] in
    guard file.contents.contains("swiftlint:"), let locationConverter = file.locationConverter else {
        return []
    }
    return CommandVisitor(locationConverter: locationConverter)
        .walk(file: file, handler: \.commands)
})

private var syntaxMapCache = Cache({ file in
    responseCache.get(file).map { SwiftLintSyntaxMap(value: SyntaxMap(sourceKitResponse: $0)) }
})
private var syntaxKindsByLinesCache = Cache({ file in file.syntaxKindsByLine() })
private var syntaxTokensByLinesCache = Cache({ file in file.syntaxTokensByLine() })

internal typealias AssertHandler = () -> Void
// Re-enable once all parser diagnostics in tests have been addressed.
// https://github.com/realm/SwiftLint/issues/3348
internal var parserDiagnosticsDisabledForTests = false

private var assertHandlers = [FileCacheKey: AssertHandler]()
private var assertHandlerCache = Cache({ file in assertHandlers[file.cacheKey] })

private struct RebuildQueue {
    private let lock = PlatformLock()
    private var queue = [Structure]()

    mutating func append(_ structure: Structure) {
        lock.doLocked {
            queue.append(structure)
        }
    }

    mutating func clear() {
        lock.doLocked {
            queue.removeAll(keepingCapacity: false)
        }
    }
}

private var queueForRebuild = RebuildQueue()

private class Cache<T> {
    private var values = [FileCacheKey: T]()
    private let factory: (SwiftLintFile) -> T
    private let lock = PlatformLock()

    fileprivate init(_ factory: @escaping (SwiftLintFile) -> T) {
        self.factory = factory
    }

    fileprivate func get(_ file: SwiftLintFile) -> T {
        let key = file.cacheKey
        return lock.doLocked {
            if let cachedValue = values[key] {
                return cachedValue
            }
            let value = factory(file)
            values[key] = value
            return value
        }
    }

    fileprivate func invalidate(_ file: SwiftLintFile) {
        lock.doLocked { values.removeValue(forKey: file.cacheKey) }
    }

    fileprivate func clear() {
        lock.doLocked { values.removeAll(keepingCapacity: false) }
    }

    fileprivate func set(key: FileCacheKey, value: T) {
        lock.doLocked { values[key] = value }
    }

    fileprivate func unset(key: FileCacheKey) {
        lock.doLocked { values.removeValue(forKey: key) }
    }
}

extension SwiftLintFile {
    fileprivate var cacheKey: FileCacheKey {
        return id
    }

    internal var sourcekitdFailed: Bool {
        get {
            return responseCache.get(self) == nil
        }
        set {
            if newValue {
                responseCache.set(key: cacheKey, value: nil)
            } else {
                responseCache.unset(key: cacheKey)
            }
        }
    }

    internal var assertHandler: AssertHandler? {
        get {
            return assertHandlerCache.get(self)
        }
        set {
            assertHandlerCache.set(key: cacheKey, value: newValue)
        }
    }

    internal var parserDiagnostics: [String]? {
        if parserDiagnosticsDisabledForTests {
            return nil
        }

        guard let syntaxTree = syntaxTree else {
            if let handler = assertHandler {
                handler()
                return nil
            }
            queuedFatalError("Could not get diagnostics for file.")
        }

        return ParseDiagnosticsGenerator.diagnostics(for: syntaxTree)
            .filter { $0.diagMessage.severity == .error }
            .map(\.message)
            .filter { message in
                // Workaround for https://github.com/apple/swift-syntax/issues/888
                return !message.starts(with: "unexpected text '.?.")
            }
    }

    internal var structure: Structure {
        guard let structure = structureCache.get(self) else {
            if let handler = assertHandler {
                handler()
                return Structure(sourceKitResponse: [:])
            }
            queuedFatalError("Never call this for file that sourcekitd fails.")
        }
        return structure
    }

    internal var structureDictionary: SourceKittenDictionary {
        guard let structureDictionary = structureDictionaryCache.get(self) else {
            if let handler = assertHandler {
                handler()
                return SourceKittenDictionary([:])
            }
            queuedFatalError("Never call this for file that sourcekitd fails.")
        }
        return structureDictionary
    }

    internal var syntaxMap: SwiftLintSyntaxMap {
        guard let syntaxMap = syntaxMapCache.get(self) else {
            if let handler = assertHandler {
                handler()
                return SwiftLintSyntaxMap(value: SyntaxMap(data: []))
            }
            queuedFatalError("Never call this for file that sourcekitd fails.")
        }
        return syntaxMap
    }

    internal var syntaxTree: SourceFileSyntax? { syntaxTreeCache.get(self) }

    internal var locationConverter: SourceLocationConverter? {
        syntaxTree.map { SourceLocationConverter(file: path ?? "<nopath>", tree: $0) }
    }

    internal var commands: [Command] { commandsCache.get(self) }

    internal var syntaxTokensByLines: [[SwiftLintSyntaxToken]] {
        guard let syntaxTokensByLines = syntaxTokensByLinesCache.get(self) else {
            if let handler = assertHandler {
                handler()
                return []
            }
            queuedFatalError("Never call this for file that sourcekitd fails.")
        }
        return syntaxTokensByLines
    }

    internal var syntaxKindsByLines: [[SyntaxKind]] {
        guard let syntaxKindsByLines = syntaxKindsByLinesCache.get(self) else {
            if let handler = assertHandler {
                handler()
                return []
            }
            queuedFatalError("Never call this for file that sourcekitd fails.")
        }
        return syntaxKindsByLines
    }

    /// Invalidates all cached data for this file.
    public func invalidateCache() {
        responseCache.invalidate(self)
        assertHandlerCache.invalidate(self)
        structureCache.invalidate(self)
        structureDictionaryCache.invalidate(self)
        syntaxMapCache.invalidate(self)
        syntaxTokensByLinesCache.invalidate(self)
        syntaxKindsByLinesCache.invalidate(self)
        syntaxTreeCache.invalidate(self)
        commandsCache.invalidate(self)
    }

    internal static func clearCaches() {
        queueForRebuild.clear()
        responseCache.clear()
        assertHandlerCache.clear()
        structureCache.clear()
        structureDictionaryCache.clear()
        syntaxMapCache.clear()
        syntaxTokensByLinesCache.clear()
        syntaxKindsByLinesCache.clear()
        syntaxTreeCache.clear()
        commandsCache.clear()
    }
}

private final class PlatformLock {
#if canImport(Darwin)
    private let primitiveLock: UnsafeMutablePointer<os_unfair_lock>
#else
    private let primitiveLock = NSLock()
#endif

    init() {
#if canImport(Darwin)
        primitiveLock = UnsafeMutablePointer<os_unfair_lock>.allocate(capacity: 1)
        primitiveLock.initialize(to: os_unfair_lock())
#endif
    }

    @discardableResult
    func doLocked<U>(_ closure: () -> U) -> U {
#if canImport(Darwin)
        os_unfair_lock_lock(primitiveLock)
        defer { os_unfair_lock_unlock(primitiveLock) }
        return closure()
#else
        primitiveLock.lock()
        defer { primitiveLock.unlock() }
        return closure()
#endif
    }
}
