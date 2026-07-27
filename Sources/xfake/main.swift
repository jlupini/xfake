import Foundation

let arguments = Array(CommandLine.arguments.dropFirst())
switch arguments.first {
case "doctor":
    exit(runDoctor())
case "up":
    exit(runUp())
case "run":
    exit(runHeadless())
case "reset":
    exit(runReset())
case nil:
    runMenuBarApp() // Task 11; until then:
default:
    fputs("usage: xfake [doctor|up|run|reset]\n", stderr)
    exit(64)
}
