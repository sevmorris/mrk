// set-default — make an app the default for content types it may take
//
// Usage: set-default <app path> <type>...
//
// install.sh compiles this into Audio Opener.app/Contents/Resources when it
// builds the app. A type moves to the app only while Music opens it, or no app
// does: a type given to another app stays with it. One line is printed for
// each type, "type<TAB>result", where result is set, already, kept <bundle id>,
// declined <message> or error <message>. A type that needs the user's answer
// has an "asking" line first, printed as its dialog goes up.
//
// macOS asks the user to confirm each change in a dialog of its own, and
// NSWorkspace answers only when the user does. So the types go one at a time,
// each waiting up to two minutes: sent together, the dialogs stacked, their
// buttons moved under the pointer, and "Keep Music" was clicked by mistake.
// "Keep" comes back as an error ("The file couldn't be opened"), which is
// reported as declined.
//
// NSWorkspace, not LSSetDefaultRoleHandlerForContentType: on macOS 27 the
// deprecated call returns noErr and changes nothing. osascript cannot pass the
// completion block NSWorkspace needs, so this is Swift.

import AppKit
import UniformTypeIdentifiers

let args = CommandLine.arguments
guard args.count >= 3 else {
  FileHandle.standardError.write("usage: set-default <app path> <type>...\n".data(using: .utf8)!)
  exit(2)
}
// Each line goes out at once, so install.sh can report it while the next
// dialog is up.
func emit(_ line: String) {
  print(line)
  fflush(stdout)
}

let appURL = URL(fileURLWithPath: args[1])
guard let appID = Bundle(url: appURL)?.bundleIdentifier?.lowercased() else {
  FileHandle.standardError.write("set-default: no bundle identifier in \(args[1])\n".data(using: .utf8)!)
  exit(2)
}

for id in args.dropFirst(2) {
  guard let type = UTType(id) else {
    emit("\(id)\terror unknown type")
    continue
  }
  let current = NSWorkspace.shared.urlForApplication(toOpen: type)
    .flatMap { Bundle(url: $0)?.bundleIdentifier?.lowercased() } ?? ""
  if current == appID {
    emit("\(id)\talready")
    continue
  }
  if !current.isEmpty && current != "com.apple.music" {
    emit("\(id)\tkept \(current)")
    continue
  }
  emit("\(id)\tasking")
  var finished = false
  var message: String?
  NSWorkspace.shared.setDefaultApplication(at: appURL, toOpen: type) { error in
    DispatchQueue.main.async {
      message = error?.localizedDescription
      finished = true
    }
  }
  // The answer is handed to the main queue, so the run loop turns while this
  // waits for the user.
  let deadline = Date().addingTimeInterval(120)
  while !finished && Date() < deadline {
    RunLoop.main.run(until: Date().addingTimeInterval(0.1))
  }
  if !finished {
    emit("\(id)\terror no answer in two minutes")
  } else if let message {
    emit("\(id)\tdeclined \(message)")
  } else {
    emit("\(id)\tset")
  }
}
