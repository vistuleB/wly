import desugaring

pub fn main() {
  let args = ["--which", "course", "--verbose"]
  assert desugaring.handle_help_requests(args, fn() {
      panic as "local usage must not be evaluated without --help"
    })
    == #(args, False)

  assert desugaring.handle_help_requests(
      [
        "--which", "course", "--track-help", "--help", "--verbose", "--esoteric",
        "--help",
      ],
      fn() { "local usage" },
    )
    == #(["--which", "course", "--verbose"], True)

  assert desugaring.handle_help_requests(
      ["--which", "course", "-h", "-help"],
      fn() { "local usage" },
    )
    == #(["--which", "course"], True)
}
