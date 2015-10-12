require("declare/table_extensions")
require("declare/utils")
deque = require "declare/deque"

rxnodes = {}

rxmodel = {}

function mixin_signals(self)
  self.listeners = {}
  self.inputs = {}
  self.triggered = false
  self.name = self.type

  function self.reset()
    self.triggered = false
  end

  function self.requires(...)
    for i=1,select('#', ...) do
      local property = select(i, ...)
      assert(property, "nil passed to requires!")

      table.insert(property.listeners, self)
      table.insert(self.inputs, property)
    end
    return self
  end

  function self.alters(...)
    for i=1,select('#', ...) do
      local property = select(i, ...)
      assert(property, "nil passed to alters!")

      table.insert(self.listeners, property)
      table.insert(property.inputs, self)
    end
    return self
  end

  function self.visit()
    self.triggered = true
  end
end

function rxnode() -- empty node for setting up topology
  local out = {}
  mixin_signals(out)

  table.insert(rxmodel, out)
  return out
end

function rxproperty(value, name, skipCallbacks)
  local self = {}
  mixin_signals(self)
  self.type = "property"
  self.class_type = "singleton" -- options: "singleton", "each", "all"
  self.name = name or "property"

  self.container = {value=value}

  if not skipCallbacks then
    self.onChanged = rxevent()
    self.onChanged.name = self.name .. '.onChanged'
    table.insert(self.onChanged.inputs, self)
    table.insert(self.listeners, self.onChanged)
  end

  self.triggered = true

  function self.getValue()
    return self.container.value
  end

  function self.set(v)
    -- print(self.name .. ': ' .. tostring(self.value) .. " -> " .. tostring(v))
    if v ~= self.getValue() then
      self.onChanged.triggered = true
    end
    self.container.value = v
  end

  table.insert(rxmodel, self)
  return self
end

function rxevent()
  local self = {}
  mixin_signals(self)
  self.type = "event"

  function self.visit()
    -- pass
  end

  table.insert(rxmodel, self)
  return self
end

function rxcallback(name)
  local self = {}
  self.type = "callback"
  mixin_signals(self)
  self.name = name or 'callback'

  self.action = nil

  function self.callback(f)
    self.action = f
    return self
  end

  function self.getInputs()
    local output = {}
    for _, value in pairs(self.inputs) do
      if value.type == "property" then
        table.insert(output, value.getValue())
      end
    end

    for _, value in pairs(self.listeners) do
      table.insert(output, value)
    end

    return output
  end

  function self.visit()
    if table.all(self.inputs, function(v) return v.triggered end) then
      self.perform()
    end
  end

  function self.perform()
     self.action(unpack(self.getInputs()))
  end

  table.insert(rxmodel, self)
  return self
end

function rxclass(fields, name)
  local self = {}
  self.type = "class"
  self.name = name or "class"
  self.instances = {}
  self.schema = {}

  for name, value in pairs(fields) do
    n = self.name .. "." .. name
    self.schema[name] = rxproperty(value, n)
    self[name] = self.schema[name]
  end

  function self.new()
    local output = {}
    for k, v in pairs(self.schema) do
      output[k] = v.value()
    end
  end

  function self.each()
    local output = rxcallback()
    function output.perform()
      for _, instance in pairs(self.instances) do
        output.action(instance)
      end
    end
    return output
  end

  table.insert(rxmodel, self)
  return self
end

function can_reach(node, target)
  local visited = {} -- {node: true} set
  local nodes = {node} -- list of nodes
  while #nodes > 0 do
    next = table.remove(nodes, 1)
    visited[next] = true
    for _, value in pairs(next.listeners) do
      if value == target then return true end
      if not visited[value] then
        table.insert(nodes, value)
      end
    end
  end
  return false
end

function split_property(property)
  -- Takes a property and splits it out into primed properties
  -- returns the original and all created properties as a list
  local outputs = {property}

  -- Find the incoming edges that are also downstream
  looped_inputs = table.filter(property.inputs, function(input, _, _)
    return can_reach(property, input) 
  end)

  for _, input in pairs(looped_inputs) do
    local split = rxproperty(property.container.value, property.name .. "'", true)
    split.onChanged = property.onChanged
    split.container = property.container
    split.inputs = {input}
    split.listeners = table.clone(property.listeners)
    table.removeValue(split.listeners, input)
    property.listeners = {input}
    table.removeValue(property.inputs, input)

    -- Change the input
    table.replace(input.listeners, property, split)

    -- Change the downstream listeners
    for _, node in pairs(split.listeners) do
      table.replace(node.inputs, property, split)
    end

    property = split
    table.insert(outputs, split)
  end

  return outputs
end

function split_properties(nodes)
  -- splits out the properties and adds them to the nodes list
  properties = table.filter(nodes, function (node, _, _)
    return node.type == "property" 
  end)

  classes = table.filter(nodes, function(node, _, _)
    return node.type == "class"
  end)

  for _, property in pairs(properties) do
    local new_properties = split_property(property)
    for i, property in ipairs(new_properties) do
      if i > 1 then
        table.insert(nodes, property)
      end
    end
  end

  for _, class in pairs(classes) do
    -- Split the class into a "before" and "after" node
    local after = rxnode()
    after.listeners = class.listeners
    class.listeners = {}
    for name, property in pairs(class.schema) do
      table.insert(after.inputs, property)
      table.insert(property.listeners, after)

      table.insert(class.listeners, property)
      table.insert(property.inputs, class)

      table.insert(nodes, property)
    end
    table.insert(nodes, after)
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
    for _, node in pairs(next.listeners) do
      if table.all(node.inputs, function(v, _, _)
        return visited[v]
      end) then
        queue:push_right(node)
      end
    end
  end

  -- Check that all the nodes are reachable
  for _, node in pairs(nodes) do
    assert(table.any(output, function(v, _, _) return v == node end), "node '" .. tostring(node.name) .. "' is unreachable :(")
  end

  return output
end

function reduce_list(nodes)
  return table.filter(nodes, function(node, _, _)
    return node.type ~= "property"
  end)
end

function build_model(nodes)
  function name(v)
    return v.name
  end

  print("model: ")
  print(repl(table.map(nodes, name)))

  properties_expanded = split_properties(nodes)
  print("split: ")
  print(repl(table.map(properties_expanded, name)))


  sorted = topo_sort(properties_expanded)
  print("topo: ")
  print(repl(table.map(sorted, name)))

  reduced = reduce_list(sorted)
  print("reduced: ")
  print(repl(table.map(reduced, name)))
  return reduced
end

function resolve(nodes, verbose)
  for _, node in pairs(nodes) do
    if (verbose) then
      print("visiting " .. node.name)
    end
    node.visit()
  end

  for _, node in pairs(nodes) do
    node.reset()
  end
end
