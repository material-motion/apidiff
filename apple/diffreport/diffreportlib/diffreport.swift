/*
 Copyright 2016-present The Material Motion Authors. All Rights Reserved.

 Licensed under the Apache License, Version 2.0 (the "License");
 you may not use this file except in compliance with the License.
 You may obtain a copy of the License at

 http://www.apache.org/licenses/LICENSE-2.0

 Unless required by applicable law or agreed to in writing, software
 distributed under the License is distributed on an "AS IS" BASIS,
 WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 See the License for the specific language governing permissions and
 limitations under the License.
 */

import Foundation

public typealias JSONObject = AnyObject

typealias SourceKittenNode = [String: AnyObject]
typealias APINode = [String: AnyObject]
typealias ApiNameNodeMap = [String: APINode]

/** A type of API change. */
public enum ChangeType {
  case Addition(apiType: String, name: String)
  case Deletion(apiType: String, name: String)
  case Modification(apiType: String, name: String, modificationType: String, from: String, to: String)
}

/** Generates an API diff report from two SourceKitten JSON outputs. */
public func diffreport(oldApi: JSONObject, newApi: JSONObject) throws -> [String: [ChangeType]] {
  let oldApiNameNodeMap = extractAPINodeMap(from: oldApi as! [SourceKittenNode])
  let newApiNameNodeMap = extractAPINodeMap(from: newApi as! [SourceKittenNode])

  let oldApiNames = Set(oldApiNameNodeMap.keys)
  let newApiNames = Set(newApiNameNodeMap.keys)

  let addedApiNames = newApiNames.subtracting(oldApiNames)
  let deletedApiNames = oldApiNames.subtracting(newApiNames)
  let persistedApiNames = oldApiNames.intersection(newApiNames)

  var changes: [String: [ChangeType]] = [:]

  // Additions

  for usr in (addedApiNames.map { usr in newApiNameNodeMap[usr]! }.sorted(by: apiNodeIsOrderedBefore)) {
    let apiType = prettyString(forKind: usr["key.kind"] as! String)
    let name = prettyName(forApi: usr, apis: newApiNameNodeMap)
    let root = rootName(forApi: usr, apis: newApiNameNodeMap)
    changes[root, withDefault: []].append(.Addition(apiType: apiType, name: name))
  }

  // Deletions

  for usr in (deletedApiNames.map { usr in oldApiNameNodeMap[usr]! }.sorted(by: apiNodeIsOrderedBefore)) {
    let apiType = prettyString(forKind: usr["key.kind"] as! String)
    let name = prettyName(forApi: usr, apis: oldApiNameNodeMap)
    let root = rootName(forApi: usr, apis: oldApiNameNodeMap)
    changes[root, withDefault: []].append(.Deletion(apiType: apiType, name: name))
  }

  // Modifications

  let ignoredKeys = Set(arrayLiteral: "key.doc.line", "key.parsed_scope.end", "key.parsed_scope.start", "key.doc.column")

  for usr in persistedApiNames {
    let oldApi = oldApiNameNodeMap[usr]!
    let newApi = newApiNameNodeMap[usr]!
    let root = rootName(forApi: newApi, apis: newApiNameNodeMap)
    let allKeys = Set(oldApi.keys).union(Set(newApi.keys))

    for key in allKeys {
      if ignoredKeys.contains(key) {
        continue
      }
      if let oldValue = oldApi[key] as? String, let newValue = newApi[key] as? String, oldValue != newValue {
        let apiType = prettyString(forKind: newApi["key.kind"] as! String)
        let name = prettyName(forApi: newApi, apis: newApiNameNodeMap)
        let modificationType = prettyString(forModificationKind: key)
        changes[root, withDefault: []].append(.Modification(apiType: apiType,
                                                            name: name,
                                                            modificationType: modificationType,
                                                            from: oldValue,
                                                            to: newValue))
      }
    }
  }

  return changes
}

extension ChangeType {
  public func toMarkdown() -> String {
    switch self {
    case .Addition(let apiType, let name):
      return "*new* \(apiType): \(name)"
    case .Deletion(let apiType, let name):
      return "*removed* \(apiType): \(name)"
    case .Modification(let apiType, let name, let modificationType, let from, let to):
      return [
        "*modified* \(apiType): \(name)",
        "",
        "| Type of change: | \(modificationType) |",
        "|---|---|",
        "| From: | `\(from.replacingOccurrences(of: "\n", with: " "))` |",
        "| To: | `\(to.replacingOccurrences(of: "\n", with: " "))` |"
      ].joined(separator: "\n")
    }
  }
}

extension ChangeType: Equatable {}

public func == (left: ChangeType, right: ChangeType) -> Bool {
  switch (left, right) {
  case (let .Addition(apiType, name), let .Addition(apiType2, name2)):
    return apiType == apiType2 && name == name2
  case (let .Deletion(apiType, name), let .Deletion(apiType2, name2)):
    return apiType == apiType2 && name == name2
  case (let .Modification(apiType, name, modificationType, from, to),
        let .Modification(apiType2, name2, modificationType2, from2, to2)):
    return apiType == apiType2 && name == name2 && modificationType == modificationType2 && from == from2 && to == to2
  default:
    return false
  }
}

/**
 get-with-default API for Dictionary

 Example usage: dict[key, withDefault: []]
 */
extension Dictionary {
  subscript(key: Key, withDefault value: @autoclosure () -> Value) -> Value {
    mutating get {
      if self[key] == nil {
        self[key] = value()
      }
      return self[key]!
    }
    set {
      self[key] = newValue
    }
  }
}

/**
 Sorting function for APINode instances.

 Sorts by filename.

 Example usage: sorted(by: apiNodeIsOrderedBefore)
 */
func apiNodeIsOrderedBefore(prev: APINode, next: APINode) -> Bool {
  return (prev["key.doc.file"] as! String) < (next["key.doc.file"] as! String)
}

/** Union two dictionaries. */
func += <K, V> (left: inout [K:V], right: [K:V]) {
  for (k, v) in right {
    left.updateValue(v, forKey: k)
  }
}

func prettyString(forKind kind: String) -> String {
  switch kind {
  case "sourcekitten.source.lang.objc.decl.protocol": return "protocol"
  case "sourcekitten.source.lang.objc.decl.typedef": return "typedef"
  case "sourcekitten.source.lang.objc.decl.method.instance": return "method"
  case "sourcekitten.source.lang.objc.decl.property": return "property"
  case "sourcekitten.source.lang.objc.decl.class": return "class"
  default: return kind
  }
}

func prettyString(forModificationKind kind: String) -> String {
  switch kind {
  case "key.swift_declaration": return "swift declaration"
  case "key.parsed_declaration": return "declaration"
  default: return kind
  }
}

/** Walk the APINode to the root node. */
func rootName(forApi api: APINode, apis: ApiNameNodeMap) -> String {
  let name = api["key.name"] as! String
  if let parentUsr = api["parent.usr"] as? String {
    return rootName(forApi: apis[parentUsr]!, apis: apis)
  }
  return name
}

func prettyName(forApi api: APINode, apis: ApiNameNodeMap) -> String {
  let name = api["key.name"] as! String
  if let parentUsr = api["parent.usr"] as? String {
    return "`\(name)` in \(prettyName(forApi: apis[parentUsr]!, apis: apis))"
  }
  return "`\(name)`"
}

/** Normalize data contained in an API node json dictionary. */
func apiNode(from sourceKittenNode: SourceKittenNode) -> APINode {
  var data = sourceKittenNode
  data.removeValue(forKey: "key.substructure")
  for (key, value) in data {
    data[key] = String(value)
  }
  return data
}

/**
 Recursively iterate over each sourcekitten node and extract a flattened map of USR identifier to
 APINode instance.
 */
func extractAPINodeMap(from sourceKittenNodes: [SourceKittenNode]) -> ApiNameNodeMap {
  var map: ApiNameNodeMap = [:]
  for file in sourceKittenNodes {
    for (_, information) in file {
      let substructure = (information as! SourceKittenNode)["key.substructure"] as! [SourceKittenNode]
      for jsonNode in substructure {
        map += extractAPINodeMap(from: jsonNode)
      }
    }
  }
  return map
}

/**
 Recursively iterate over a sourcekitten node and extract a flattened map of USR identifier to
 APINode instance.
 */
func extractAPINodeMap(from sourceKittenNode: SourceKittenNode, parentUsr: String? = nil) -> ApiNameNodeMap {
  var map: ApiNameNodeMap = [:]
  for (key, value) in sourceKittenNode {
    switch key {
    case "key.usr":
      var node = apiNode(from: sourceKittenNode)

      // Create a reference to the parent node
      node["parent.usr"] = parentUsr

      // Store the API node in the map
      map[value as! String] = node

    case "key.substructure":
      let substructure = value as! [SourceKittenNode]
      for subSourceKittenNode in substructure {
        map += extractAPINodeMap(from: subSourceKittenNode, parentUsr: sourceKittenNode["key.usr"] as? String)
      }
    default:
      continue
    }
  }
  return map
}

/**
 Execute sourcekitten with a given umbrella header.

 Only meant to be used in unit test builds.

 @param header Absolute path to an umbrella header.
 */
func runSourceKitten(withHeader header: String) throws -> JSONObject {
  let task = Task()
  task.launchPath = "/usr/bin/env"
  task.arguments = [
    "/usr/local/bin/sourcekitten",
    "doc",
    "--objc",
    header,
    "--",
    "-x",
    "objective-c",
  ]
  let standardOutput = Pipe()
  task.standardOutput = standardOutput
  task.launch()
  task.waitUntilExit()
  var data = standardOutput.fileHandleForReading.readDataToEndOfFile()
  let tmpDir = ProcessInfo.processInfo.environment["TMPDIR"]!.replacingOccurrences(of: "/", with: "\\/")
  let string = String(data: data, encoding: String.Encoding.utf8)!
    .replacingOccurrences(of: tmpDir + "old\\/", with: "")
    .replacingOccurrences(of: tmpDir + "new\\/", with: "")
  data = string.data(using: String.Encoding.utf8)!
  return try JSONSerialization.jsonObject(with: data, options: JSONSerialization.ReadingOptions(rawValue: 0))
}
