import gleam/io
import gleam/int
import gleam/list
import gleam/string as text
import gleam/erlang/process.{type Subject, spawn, send, receive}
import input.{input}

type Message {
  ProducedString(content: String, count: Int)
  ProducerFinished
}

const lorem_ipsum_base =
  "Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat. Duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla pariatur. Excepteur sint occaecat cupidatat non proident, sunt in culpa qui officia deserunt mollit anim id est laborum."

const string_count = 20
const string_length = 100

fn producer(main_process_subject: Subject(Message), z: Int) -> Nil {
  let item_base = text.slice(lorem_ipsum_base, 0, string_length)
  list.range(1, z)
  |> list.each(fn(i) {
    let message = item_base <> " (" <> int.to_string(i) <> "/" <> int.to_string(string_count) <> ")"
    send(main_process_subject, ProducedString(content: message, count: i))
    io.println("[Producer] Sent message number " <> int.to_string(i)) 
    process.sleep(3000)
  })
  send(main_process_subject, ProducerFinished)
}

pub fn main() {
  io.println("Main process started. Spawning producer process...")
  io.println("Ensure 'gleam add input@1' has been run to use the 'input' package.")
  let main_subject = process.new_subject()
  let _producer_pid = spawn(fn() { producer(main_subject, 3) })
  loop(main_subject)
}

fn loop(subject: Subject(Message)) -> Nil {
  case receive(subject, within: 10000) {
    Ok(ProducedString(content, count)) -> {
      io.println("\n--- Received message " <> int.to_string(count) <> ": ---")
      io.println(content)

      // Use input.input to block and wait for user input (Enter key)
      // The prompt is printed to stderr.
      case input(prompt: "\nPress Enter to display the next string...") {
        Ok(_) -> {
          // Input received, continue the loop
          loop(subject)
        }
        Error(_) -> {
          io.println("Error reading input, exiting.")
          Nil
        }
      }
    }
    Ok(ProducerFinished) -> {
      io.println("\n--- Producer finished all work. All messages displayed. ---")
      Nil // End the loop and the program terminates
    }
    Error(_) -> {
      // Timeout occurred
      io.println("Timeout while waiting for messages. Is the producer stuck?")
      Nil
    }
  }
}
