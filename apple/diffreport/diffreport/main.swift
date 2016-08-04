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
import diffreportlib

if Process.arguments.count < 3 {
  print("usage: diffreport <old sourcekitten output> <new sourcekitten output>")
  exit(1)
}

/** Load a file from disk, parse it as JSON, and return the result. */
func readJsonObject(fromFilePath path: String) throws -> AnyObject {
  let url = URL(fileURLWithPath: path)
  let options = JSONSerialization.ReadingOptions(rawValue: 0)
  return try JSONSerialization.jsonObject(with: Data(contentsOf: url), options: options)
}

let oldApi = try readJsonObject(fromFilePath: Process.arguments[1])
let newApi = try readJsonObject(fromFilePath: Process.arguments[2])

let report = try diffreport(oldApi: oldApi, newApi: newApi)

// Generate markdown output

for (symbol, entries) in report {
  print("## \(symbol)\n")
  print(entries.map({ change in change.toMarkdown() }).joined(separator: "\n\n"))
}
