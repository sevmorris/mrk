// lsdefault — read and set the app that opens a file type or a URL scheme
//
// Usage:
//   lsdefault get TYPE...
//   lsdefault app BUNDLE-ID...
//   lsdefault set BUNDLE-ID TYPE...
//
// scripts/default-apps compiles this into ~/.mrk/bin when the binary is
// missing or was built from a different source, and runs it. A TYPE is a
// uniform type identifier, such as public.mp3, or scheme:NAME for a URL
// scheme, such as scheme:https. Bundle identifiers are printed in lower case,
// as Launch Services keeps them.
//
// get prints one line for each TYPE: the type, then app, none or unknown,
// then the bundle identifier of the app that opens it (empty unless app).
// unknown is a type identifier that no app on this Mac declares.
//
// app prints one line for each BUNDLE-ID: the identifier and the path of the
// app, or an empty path when the app is not on this Mac.
//
// set makes the app the default for each TYPE, one at a time, and prints one
// line for each: the type, then set, already, declined MESSAGE, unknown or
// error MESSAGE. A type that needs the user's answer has an "asking" line
// first, printed as the dialog goes up. It exits 1 when the app is not on
// this Mac.
//
// macOS asks the user to confirm each change in a dialog of its own, and
// NSWorkspace answers only when the user does. So the types go one at a time,
// each waiting up to two minutes: sent together, the dialogs stacked, their
// buttons moved under the pointer, and the wrong button was clicked. "Keep"
// comes back as an error ("The file couldn't be opened"), which is reported
// as declined.
//
// NSWorkspace, not LSSetDefaultRoleHandlerForContentType: on macOS 27 the
// deprecated call returns noErr and changes nothing. osascript cannot pass the
// completion block NSWorkspace needs, so this is Swift.

import AppKit
import UniformTypeIdentifiers

func fail(_ message: String, _ code: Int32) -> Never {
  FileHandle.standardError.write("lsdefault: \(message)\n".data(using: .utf8)!)
  exit(code)
}

// Each line goes out at once, so default-apps can report it while the next
// dialog is up.
func emit(_ fields: String...) {
  print(fields.joined(separator: "\t"))
  fflush(stdout)
}

func bundleID(_ url: URL?) -> String {
  url.flatMap { Bundle(url: $0)?.bundleIdentifier?.lowercased() } ?? ""
}

enum Target {
  case type(UTType)
  case scheme(String)
  case unknown
}

func target(_ id: String) -> Target {
  if id.hasPrefix("scheme:") {
    let name = String(id.dropFirst("scheme:".count))
    return name.isEmpty ? .unknown : .scheme(name)
  }
  guard let type = UTType(id), !type.isDynamic else { return .unknown }
  return .type(type)
}

func current(_ t: Target) -> String {
  switch t {
  case .type(let type):
    return bundleID(NSWorkspace.shared.urlForApplication(toOpen: type))
  case .scheme(let name):
    guard let url = URL(string: name + ":") else { return "" }
    return bundleID(NSWorkspace.shared.urlForApplication(toOpen: url))
  case .unknown:
    return ""
  }
}

let args = Array(CommandLine.arguments.dropFirst())
guard let command = args.first else {
  fail("usage: lsdefault get TYPE... | app BUNDLE-ID... | set BUNDLE-ID TYPE...", 2)
}

switch command {
case "get":
  for id in args.dropFirst() {
    let t = target(id)
    if case .unknown = t {
      emit(id, "unknown", "")
      continue
    }
    let app = current(t)
    emit(id, app.isEmpty ? "none" : "app", app)
  }

case "app":
  for id in args.dropFirst() {
    emit(id, NSWorkspace.shared.urlForApplication(withBundleIdentifier: id)?.path ?? "")
  }

case "set":
  guard args.count >= 3 else { fail("usage: lsdefault set BUNDLE-ID TYPE...", 2) }
  let appID = args[1].lowercased()
  guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: args[1]) else {
    fail("no app with the bundle identifier \(args[1]) on this Mac", 1)
  }
  for id in args.dropFirst(2) {
    let t = target(id)
    if case .unknown = t {
      emit(id, "unknown")
      continue
    }
    if current(t) == appID {
      emit(id, "already")
      continue
    }
    emit(id, "asking")
    var finished = false
    var message: String?
    let done: (Error?) -> Void = { error in
      DispatchQueue.main.async {
        message = error?.localizedDescription
        finished = true
      }
    }
    switch t {
    case .type(let type):
      NSWorkspace.shared.setDefaultApplication(at: appURL, toOpen: type, completion: done)
    case .scheme(let name):
      NSWorkspace.shared.setDefaultApplication(at: appURL, toOpenURLsWithScheme: name, completion: done)
    case .unknown:
      break
    }
    // The answer is handed to the main queue, so the run loop turns while
    // this waits for the user.
    let deadline = Date().addingTimeInterval(120)
    while !finished && Date() < deadline {
      RunLoop.main.run(until: Date().addingTimeInterval(0.1))
    }
    if !finished {
      emit(id, "error no answer in two minutes")
    } else if let message {
      emit(id, "declined " + message)
    } else {
      emit(id, "set")
    }
  }

default:
  fail("unknown command \(command): use get, app or set", 2)
}
