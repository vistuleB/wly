import desugaring as ds
import desugaring/desugarers as dl
import gleam/list
import gleam/option.{None, Some}
import vxml
import vxml/blame

fn stopping_monitor() -> ds.Monitor {
  ds.new_monitor("test-monitor", 0, fn(_vxml, state, context) {
    case state, context {
      0, ds.PipelineStepContext(0, None, Some(next)) -> {
        assert next.name == "identity"
        Ok(#(1, []))
      }
      1, ds.PipelineStepContext(1, Some(previous), None) -> {
        assert previous.name == "identity"
        Error("requested stop")
      }
      _, _ -> panic as "unexpected monitor context"
    }
  })
}

pub fn main() {
  let options =
    ds.RendererOptions(..ds.vanilla_options(), monitors: [stopping_monitor()])
  assert list.length(options.monitors) == 1

  let input = vxml.V(blame.no_blame, "root", [], [])
  let result =
    ds.run_pipeline(input, [dl.identity()], [stopping_monitor()], False, True)
  let assert Error(ds.PipelineMonitorError(failure)) = result
  let ds.MonitorFailure(name, step_no, message) = failure
  assert name == "test-monitor"
  assert step_no == 1
  assert message == "requested stop"
}
