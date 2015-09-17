//
//  SourceSourceDeclaration.swift
//  SourceKitten
//
//  Created by JP Simard on 7/15/15.
//  Copyright © 2015 SourceKitten. All rights reserved.
//

public struct SourceLocation {
    let file: String
    let line: UInt32
    let column: UInt32
    let offset: UInt32
}

public enum Text {
    case Para(String, String?)
}

public struct Parameter {
    let name: String
    let discussion: [Text]

    init(comment: CXComment) {
        name = comment.paramName() ?? "<none>"
        discussion = comment.paragraph().paragraphToString()
    }
}

/// Represents a source code declaration.
public struct SourceDeclaration {
    let type: ObjCDeclarationKind?
    let location: SourceLocation

    let name: String?
    let usr: String?
    let declaration: String?
    let children: [SourceDeclaration]

    let parameters: [Parameter]
    let discussion: [Text]
    let returnDiscussion: [Text]

    init?(cursor: CXCursor) {
        guard clang_isDeclaration(cursor.kind) != 0 else {
            return nil
        }
        let comment = cursor.parsedComment()
        guard comment.kind() != CXComment_Null else {
            return nil
        }

        location = cursor.location()
        name = cursor.name()
        type = ObjCDeclarationKind.fromClang(cursor.kind)
        usr = cursor.usr()
        declaration = cursor.text()
        children = cursor.flatMap(SourceDeclaration.init)

        var params = [Parameter]()
        var d = [Text]()
        var r = [Text]()

        for i in 0..<comment.count() {
            let c = comment[i]
            switch c.kind().rawValue {
            case CXComment_Text.rawValue:
                d += c.paragraphToString()
                break
            case CXComment_InlineCommand.rawValue:
                break
            case CXComment_HTMLStartTag.rawValue: break
            case CXComment_HTMLEndTag.rawValue: break
            case CXComment_Paragraph.rawValue:
                d += c.paragraphToString()
                break
            case CXComment_BlockCommand.rawValue:
                let command = c.commandName()
                if command == "return" {
                    r += c.paragraphToString()
                }
                else {
                    d += c.paragraphToString(command)
                }
                break
            case CXComment_ParamCommand.rawValue:
                params.append(Parameter(comment: c))
                break
            case CXComment_VerbatimBlockCommand.rawValue: break
            case CXComment_VerbatimBlockLine.rawValue: break
            case CXComment_VerbatimLine.rawValue: break
            default: break
            }
        }

        parameters = params
        discussion = d
        returnDiscussion = r
    }
}

extension SourceDeclaration: Hashable {
    public var hashValue: Int {
        return usr?.hashValue ?? 0
    }
}

public func ==(lhs: SourceDeclaration, rhs: SourceDeclaration) -> Bool {
    return lhs.usr == rhs.usr
}

// MARK: Comparable

extension SourceDeclaration: Comparable {}

/// A [strict total order](http://en.wikipedia.org/wiki/Total_order#Strict_total_order)
/// over instances of `Self`.
public func <(lhs: SourceDeclaration, rhs: SourceDeclaration) -> Bool {
    // Sort by file path.
    switch lhs.location.file.compare(rhs.location.file) {
    case .OrderedDescending:
        return false
    case .OrderedAscending:
        return true
    case .OrderedSame:
        break
    }

    // Then line.
    if lhs.location.line > rhs.location.line {
        return false
    } else if lhs.location.line < rhs.location.line {
        return true
    }

    // Then column.
    if lhs.location.column > rhs.location.column {
        return false
    }

    return true
}
