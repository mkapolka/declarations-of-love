function rxNode(model)
  local self = {}
  self.class = "node"
  self.model = model

  if model then
    self.name = "n(" .. model.name .. ")"
  else
    self.name = "n()"
  end

  self.inputs = {}
  self.outputs = {}
  return self
end

function rxPropertyNode(property)
  local self = rxNode(property)
  self.class = "property"
  self.property = property

  function self.split(input)
    -- Creates the downstream split property node (property')
    -- This one keeps only input, (property') gets the rest
    local output = rxPropertyNode(self.property)
    output.name = self.name .. "'"
    output.inputs = self.inputs
    table.removeValue(output.inputs, input)
    output.outputs = self.outputs

    self.inputs = {input}
    self.outputs = {output}

    -- Update upstream nodes' outputs
    for _, node in pairs(output.inputs) do
      table.replace(node.outputs, self, output)
    end

    -- Update the downstream nodes' inputs
    for _, node in pairs(output.outputs) do
      table.replace(node.inputs, self, output)
    end
    return output
  end

  return self
end

function rxEventNode(event)
  local self = rxNode(event)
  self.class = "event"
  self.event = event
  return self
end

function rxCallbackNode(callback)
  local self = rxNode(callback)
  self.class = "callback"
  self.callback = callback
  return self
end

function nodify(models, type_name, type_class)
  local filtered = table.filter(models, function(v, _, _) return v.type == type_name end)
  local nodes = {}
  for _, model in pairs(filtered) do
    nodes[model] = type_class(model)
  end
  return filtered, nodes
end

function can_reach(node, target)
  local visited = {} -- {node: true} set
  local nodes = {node} -- list of nodes
  while #nodes > 0 do
    next = table.remove(nodes, 1)
    visited[next] = true
    for _, value in pairs(next.outputs) do
      if value == target then return true end
      if not visited[value] then
        table.insert(nodes, value)
      end
    end
  end
  return false
end

function split_property_node(propertyNode)
  -- Takes a property node and splits it out into primed property nodes
  -- returns the new properties as a list
  local outputs = {}

  -- Find the incoming edges that are also downstream
  print("splitting " .. propertyNode.name .. " ... inputs = " .. repl(table.map(propertyNode.inputs, function(v) return v.name end)))
  looped_inputs = table.filter(propertyNode.inputs, function(input, _, _)
    return can_reach(propertyNode, input) 
  end)

  for _, input in pairs(looped_inputs) do
    local split = propertyNode.split(input)
    table.insert(outputs, split)
    propertyNode = split
    print("splitted into " .. propertyNode.name .. " ... inputs = " .. repl(table.map(propertyNode.inputs, function(v) return v.name end)) .. " outputs: " .. repl(table.map(propertyNode.outputs, function(v) return v.name end)))
  end


  return outputs
end

function create_graph(models)
  local nodes = {}
  properties, propertyNodes = nodify(models, "property", rxPropertyNode)
  callbacks, callbackNodes = nodify(models, "callback", rxCallbackNode)
  events, eventNodes = nodify(models, "event", rxEventNode)

  -- Add property callbacks to events
  for _, property in pairs(properties) do
    local eventNode = rxEventNode(property.onChanged)
    local propertyNode = propertyNodes[property]
    table.insert(eventNode.inputs, propertyNode)
    table.insert(propertyNode.outputs, eventNode)
    table.insert(events, property.onChanged) 
    eventNodes[property.onChanged] = eventNode
  end

  for _, someNodes in pairs({propertyNodes, callbackNodes, eventNodes}) do
    for _, node in pairs(someNodes) do
      table.insert(nodes, node)
    end
  end

  -- Set up dependencies between callbacks and properties, events
  for callback, cbNode in pairs(callbackNodes) do
    for _, listener in pairs(callback.listeners) do
      if listener.type == "property" then
        modelNode = propertyNodes[listener]
      end

      if listener.type == "event" then
        modelNode = eventNodes[listener]
      end

      table.insert(modelNode.inputs, cbNode)
      table.insert(cbNode.outputs, modelNode)
    end

    for _, input in pairs(callback.inputs) do
      if input.type == "property" then
        modelNode = propertyNodes[input]
      end

      if input.type == "event" then
        modelNode = eventNodes[input]
      end

      table.insert(modelNode.outputs, cbNode)
      table.insert(cbNode.inputs, modelNode)
    end
  end

  -- Split nodes with circular dependencies
  for _, propertyNode in pairs(propertyNodes) do
    local splitProperties = split_property_node(propertyNode)
    for _, primeProperty in pairs(splitProperties) do
      table.insert(nodes, primeProperty)
    end
  end

  return nodes
end

function topo_sort(nodes)
  local output = {}
  local visited = {} -- set
  local no_inc_edges = table.filter(nodes, 
    function (node, key, t)
      return #(node.inputs) == 0      
    end)
  local queue = deque.new()
  for _, node in pairs(no_inc_edges) do
    queue:push_left(node)
  end

  while not queue:is_empty() do
    --print('pop'..repl(table.map(queue:contents(), function(v) return v.name end)))
    local next = queue:pop_left()
    visited[next] = true
    table.insert(output, next)
    for _, node in pairs(next.outputs) do
      if table.all(node.inputs, function(v, _, _)
        return visited[v]
      end) then
        if not visited[node] then
          queue:push_right(node)
        end
      end
    end
  end

  -- Check that all the nodes are reachable
  for _, node in pairs(nodes) do
    assert(table.any(output, function(v, _, _) return v == node end), "node '" .. tostring(node.name) .. "' is unreachable :(")
  end

  return output
end

function graph_to_model(graph)
  local output = {}
  for _, node in pairs(graph) do
    -- Ignore property, property', and class nodes
    if node.class == "callback" then
      table.insert(output, node.callback)
    end

    if node.class == "event" then
      -- If the event doesn't have any listeners, get rid of it
      if #node.outputs > 0 then
        table.insert(output, node.event)
      end
    end
  end
  return output
end


function create_model(things)
  local output = things
  print("things: " .. repl(table.map(output, function(v) return v.name end)))
  output = create_graph(output)
  print("graph: " .. repl(table.map(output, function(v) return v.name end)))
  output = topo_sort(output)
  print("topo: " .. repl(table.map(output, function(v) return v.name end)))
  output = graph_to_model(output)
  print("models: " .. repl(table.map(output, function(v) return v.name end)))
  return output
end
