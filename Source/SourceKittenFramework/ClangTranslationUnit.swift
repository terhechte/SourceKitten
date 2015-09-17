//
//  ClangTranslationUnit.swift
//  SourceKitten
//
//  Created by JP Simard on 2015-01-12.
//  Copyright (c) 2015 SourceKitten. All rights reserved.
//

extension CXString {
    func str() -> String? {
        return String.fromCString(clang_getCString(self))
    }
}

struct Index {
    private let cx = clang_createIndex(0, 1)

    func open(file file: String, args: [UnsafePointer<Int8>]) -> CXTranslationUnit {
        return clang_createTranslationUnitFromSourceFile(cx,
            file,
            Int32(args.count),
            args,
            0,
            nil)
    }
}

extension CXTranslationUnit {
    func visit(block: ((CXCursor, CXCursor) -> CXChildVisitResult)) {
        clang_visitChildrenWithBlock(clang_getTranslationUnitCursor(self), block)
    }
}

/// Represents a group of CXTranslationUnits.
public struct ClangTranslationUnit {
    /// Array of CXTranslationUnits.
    private let clangTranslationUnits: [CXTranslationUnit]

    /// Array of sorted & deduplicated source declarations.
    private var declarations: [SourceDeclaration] {
        return Set(
            clangTranslationUnits
                .flatMap(commentXML)
                .flatMap(SourceDeclaration.init)
        ).sort(<)
    }

    /**
    Create a ClangTranslationUnit by passing Objective-C header files and clang compiler arguments.

    - parameter headerFiles:       Objective-C header files to document.
    - parameter compilerArguments: Clang compiler arguments.
    */
    public init(headerFiles: [String], compilerArguments: [String]) {
        let cStringCompilerArguments = compilerArguments.map { ($0 as NSString).UTF8String }
        let clangIndex = Index()
        clangTranslationUnits = headerFiles.map { clangIndex.open(file: $0, args: cStringCompilerArguments) }
    }

    /**
    Failable initializer to create a ClangTranslationUnit by passing Objective-C header files and
    `xcodebuild` arguments. Optionally pass in a `path`.

    - parameter headerFiles:         Objective-C header files to document.
    - parameter xcodeBuildArguments: The arguments necessary pass in to `xcodebuild` to link these header files.
    - parameter path:                Path to run `xcodebuild` from. Uses current path by default.
    */
    public init?(headerFiles: [String], xcodeBuildArguments: [String], inPath path: String = NSFileManager.defaultManager().currentDirectoryPath) {
        let xcodeBuildOutput = runXcodeBuild(xcodeBuildArguments + ["-dry-run"], inPath: path) ?? ""
        guard let clangArguments = parseCompilerArguments(xcodeBuildOutput, language: .ObjC, moduleName: nil) else {
            fputs("could not parse compiler arguments\n", stderr)
            fputs("\(xcodeBuildOutput)\n", stderr)
            return nil
        }
        self.init(headerFiles: headerFiles, compilerArguments: clangArguments)
    }
}

// MARK: CustomStringConvertible

extension ClangTranslationUnit: CustomStringConvertible {
    /// A textual JSON representation of `ClangTranslationUnit`.
    public var description: String { return toJSON(groupDeclarationsByFile(declarations)) }
}

// MARK: Helpers

/**
Returns an array of XML comments by iterating over a Clang translation unit.

- parameter translationUnit: Clang translation unit created from Clang index, file path and compiler arguments.

- returns: An array of XML comments by iterating over a Clang translation unit.
*/
public func commentXML(translationUnit: CXTranslationUnit) -> [String] {
    var commentXMLs = [String]()
    translationUnit.visit { cursor, parent in
        guard clang_isDeclaration(cursor.kind) != 0 else {
            return CXChildVisit_Continue
        }
        guard let commentXML = clang_FullComment_getAsXML(clang_Cursor_getParsedComment(cursor)).str() else {
            return CXChildVisit_Recurse
        }

        var file = CXFile()
        var line: UInt32 = 0
        var column: UInt32 = 0
        var offset: UInt32 = 0
        clang_getSpellingLocation(clang_getCursorLocation(parent),
            &file,
            &line,
            &column,
            &offset)
        print("\(file) \(line) \(column) \(offset)")
        print("parent hash: \(clang_hashCursor(parent))\nparent: \(parent)\nchild comment: \(commentXML)")
        commentXMLs.append(commentXML)
        return CXChildVisit_Recurse
    }
    return commentXMLs
}

private func groupDeclarationsByFile(declarations: [SourceDeclaration]) -> [String: [String: [AnyObject]]] {
    let files = Set(declarations.map({ $0.file }))
    var groupedDeclarations = [String: [String: [AnyObject]]]()
    for file in files {
        groupedDeclarations[file] = ["key.substructure": declarations.filter { $0.file == file }.map { $0.dictionaryValue }]
    }
    return groupedDeclarations
}
