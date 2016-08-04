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

import XCTest
@testable import diffreportlib

// These tests require sourcekitten to be installed as a command line tool.
// brew install sourcekitten
class UnitTests: XCTestCase {
  func testNoChanges() throws {
    let report = try generateReport(forOld: "@interface TestObject\n@end", new: "@interface TestObject\n@end")
    XCTAssertEqual(report.count, 0)
  }

  func testAddition() throws {
    let report = try generateReport(forOld: "", new: "@interface TestObject\n@end")
    XCTAssertEqual(report["TestObject"]!.count, 1)
    XCTAssertEqual(report["TestObject"]!.first, ChangeType.Addition(apiType: "class", name: "`TestObject`"))
  }

  func testDeletion() throws {
    let report = try generateReport(forOld: "@interface TestObject\n@end", new: "")
    XCTAssertEqual(report["TestObject"]!.count, 1)
    XCTAssertEqual(report["TestObject"]!.first, ChangeType.Deletion(apiType: "class", name: "`TestObject`"))
  }

  func testModification() throws {
    let report = try generateReport(forOld: "/** Docs */\n@interface TestObject\n\n@property(nonatomic) id object;\n\n@end", new: "/** Docs */\n@interface TestObject\n\n@property(atomic) id object;\n\n@end")
    XCTAssertEqual(report["TestObject"]!.count, 1)
    XCTAssertEqual(report["TestObject"]!.first, ChangeType.Modification(apiType: "property", name: "`object` in `TestObject`", modificationType: "declaration", from: "@property(nonatomic) id object", to: "@property(atomic) id object"))
  }

  let oldPath = ProcessInfo.processInfo.environment["TMPDIR"]!.appending("old/Header.h")
  let newPath = ProcessInfo.processInfo.environment["TMPDIR"]!.appending("new/Header.h")

  override func setUp() {
    do {
      try FileManager.default.createDirectory(atPath: ProcessInfo.processInfo.environment["TMPDIR"]!.appending("old"), withIntermediateDirectories: true, attributes: nil)
      try FileManager.default.createDirectory(atPath: ProcessInfo.processInfo.environment["TMPDIR"]!.appending("new"), withIntermediateDirectories: true, attributes: nil)
    } catch {

    }
  }

  func generateReport(forOld old: String, new: String) throws -> [String: [ChangeType]] {
    try old.write(toFile: oldPath, atomically: true, encoding: String.Encoding.utf8)
    try new.write(toFile: newPath, atomically: true, encoding: String.Encoding.utf8)
    let oldApi = try runSourceKitten(withHeader: oldPath)
    let newApi = try runSourceKitten(withHeader: newPath)
    return try diffreport(oldApi: oldApi, newApi: newApi)
  }
}
