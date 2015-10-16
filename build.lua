require("declare/love_declare")
require("declare/graph")
require("declare/runtime")

function create_model(things)
  local output = things
  print("things: " .. repl(table.map(output, function(v) return v.name end)))
  output = create_graph(output)
  print("graph: " .. repl(table.map(output, function(v) return v.name end)))
  output = topo_sort(output)
  print("topo: " .. repl(table.map(output, function(v) return v.name end)))
  output = graph_to_model(output)
  print("models: " .. repl(table.map(output.runtimes, function(v) return v.name end)))
  return output
end
