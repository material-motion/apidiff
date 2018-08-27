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
  
  static var allTests = [
    ("testNoChanges", testNoChanges),
    ("testAddition", testAddition),
    ("testDeletion", testDeletion),
    ("testModification", testModification),
  ]
  
  func testNoChanges() throws {
    let report = try generateReport(forOld: """
@interface TestObject
@end
""",
                                    new: """
@interface TestObject
@end
""")
    XCTAssertEqual(report.count, 0)
  }

  func testAddition() throws {
    let report = try generateReport(forOld: """
""", new: """
@interface TestObject
@end
""")
    XCTAssertEqual(report["TestObject"]!.count, 1)
    XCTAssertEqual(report["TestObject"]!.first, ApiChange.addition(apiType: "class", name: "`TestObject`"))
  }

  func testDeletion() throws {
    let report = try generateReport(forOld: """
@interface TestObject
@end
""", new: """
""")
    XCTAssertEqual(report["TestObject"]!.count, 1)
    XCTAssertEqual(report["TestObject"]!.first, ApiChange.deletion(apiType: "class", name: "`TestObject`"))
  }

  func testModification() throws {
    let report = try generateReport(forOld: """
/** Docs */
@interface TestObject

@property(nonatomic) id object;

@end
""", new: """
/** Docs */
@interface TestObject

@property(atomic) id object;

@end
""")
    XCTAssertEqual(report["TestObject"]!.count, 1)
    XCTAssertEqual(report["TestObject"]!.first!,
                   ApiChange.modification(apiType: "property",
                                          name: "`object` in `TestObject`",
                                          modificationType: "Declaration",
                                          from: "@property(nonatomic) id object",
                                          to: "@property(atomic) id object"))
  }

  func testNewPropertyOnClass() throws {
    let report = try generateReport(forOld: """
@interface MDCAlertControllerView
@end
""",
                                    new: """
@interface MDCAlertControllerView
@property(nonatomic, strong, nullable) id buttonInkColor;
@end
""")
    XCTAssertEqual(report["MDCAlertControllerView"]!.count, 1)
    XCTAssertEqual(report["MDCAlertControllerView"]!.first!,
                   .addition(apiType: "property",
                             name: "`buttonInkColor` in `MDCAlertControllerView`"))
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

  func generateReport(forOld old: String, new: String) throws -> [String: [ApiChange]] {
    try old.write(toFile: oldPath, atomically: true, encoding: String.Encoding.utf8)
    try new.write(toFile: newPath, atomically: true, encoding: String.Encoding.utf8)
    let oldApi = try runSourceKitten(withHeader: oldPath)
    let newApi = try runSourceKitten(withHeader: newPath)
    return try diffreport(oldApi: oldApi, newApi: newApi)
  }
}

