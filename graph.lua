deque = require "declare/deque"

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
    -- Creates the downstream split property node property'
    -- Given an upstream input node that will instead write to property'
    local split = rxPropertyNode(self.property)
    split.name = self.name .. "'"
    split.inputs = {input}
    split.outputs = {}

    table.removeValue(self.inputs, input)

    table.replace(input.outputs, self, split)

    return split
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
  local nodes = deque.new() -- list of nodes
  nodes:push_left(node)
  while nodes:length() > 0 do
    local next = nodes:pop_left()
    visited[next] = true
    for _, value in pairs(next.outputs) do
      if value == target then return true end
      if not visited[value] then
        nodes:push_right(value)
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
    -- print("Can reach " .. input.name .. "? " .. tostring(can_reach(propertyNode, input)))
    return can_reach(propertyNode, input) 
  end)

  non_looped_outputs = table.filter(propertyNode.outputs, function(output, _, _)
    -- print("Can reach " .. output.name .. "? " .. tostring(can_reach(output, propertyNode)))
    return not can_reach(output, propertyNode) 
  end)

  for _, input in pairs(looped_inputs) do
    print("splitting " .. propertyNode.name .. " with " .. input.name)
    local split = propertyNode.split(input)
    table.insert(outputs, split)
    print("split into " .. split.name .. " ... inputs = " .. repl(table.map(split.inputs, function(v) return v.name end)) .. " outputs: " .. repl(table.map(split.outputs, function(v) return v.name end)))
  end

  -- Set up the property^n node, only if we've actually split anything
  if #non_looped_outputs > 0 and #outputs > 0 then
    local last = rxPropertyNode(propertyNode.property)
    last.name = propertyNode.name .. ".last"
    for _, node in pairs(outputs) do
      table.insert(last.inputs, node)
      table.insert(node.outputs, last)
    end

    for _, node in pairs(non_looped_outputs) do
      table.insert(last.outputs, node)
      table.replace(node.inputs, propertyNode, last)
      print("non looped output " .. node.name .. " ... inputs = " .. repl(table.map(node.inputs, function(v) return v.name end)))
    end


    table.insert(outputs, last)
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
    local eventNode = rxEventNode(property.on_changed)
    local propertyNode = propertyNodes[property]
    table.insert(eventNode.inputs, propertyNode)
    table.insert(propertyNode.outputs, eventNode)
    table.insert(events, property.on_changed) 
    eventNodes[property.on_changed] = eventNode
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
