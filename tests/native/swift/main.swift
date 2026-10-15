import Foundation

func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
  if !condition() { fatalError(message) }
}

func parse(_ value: String) -> Double? {
  switch value {
  case "null": return nil
  case "nan": return .nan
  case "inf": return .infinity
  case "-inf": return -.infinity
  default: return Double(value)!
  }
}

let fixture = try String(contentsOfFile: CommandLine.arguments[1], encoding: .utf8)
let cases = fixture.split(separator: "\n").dropFirst()
for line in cases {
  let columns = line.split(separator: "\t").map(String.init)
  let name = columns[0]
  let shouldFail = columns[4] == "error"
  do {
    let result = try VideoTrimRange.resolve(
      startMs: parse(columns[1]), endMs: parse(columns[2]), durationMs: Double(columns[3])!
    )
    expect(!shouldFail, "\(name): accepted an invalid range")
    expect(result?.startMs == parse(columns[4]), "\(name): incorrect start")
    expect(result?.endMs == parse(columns[5]), "\(name): incorrect end")
  } catch {
    expect(shouldFail && error is VideoTrimRange.ValidationError, "\(name): unexpected error \(error)")
  }
}
expect(cases.count == 25, "Missing range contract cases")

let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: directory) }
let source = directory.appendingPathComponent("source.mp4")
let output = directory.appendingPathComponent("output.mp4")
let originalData = Data(repeating: 1, count: 32)
let largerClip = Data(repeating: 2, count: 64)
let smallerClip = Data(repeating: 3, count: 16)
try originalData.write(to: source)

for (trimmed, muted, encoded, expected) in [
  (true, false, largerClip, largerClip),
  (true, true, largerClip, largerClip),
  (false, true, largerClip, largerClip),
  (false, false, largerClip, originalData),
  (false, false, smallerClip, smallerClip),
] {
  try encoded.write(to: output)
  VideoCompressionFallback.restoreOriginalIfLarger(
    sourceURL: source, outputURL: output, hasTrimRange: trimmed, muteAudio: muted
  )
  let actual = try Data(contentsOf: output)
  expect(actual == expected, "Incorrect output contents for trimmed=\(trimmed), muted=\(muted)")
}
print("Passed \(cases.count) range cases and 5 compression fallback cases")
