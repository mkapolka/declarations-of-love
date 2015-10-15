function rxmodel(nodes)
  local self = {}
  self.models = nodes
  self.visitable = nodes

  function self.reset()
    for _, node in pairs(self.models) do
      node.reset()
    end
  end

  function self.iterate()
    for _, node in pairs(self.models) do
      node.visit()
    end
  end
  return self
end

function rx_runtime_node(node)
  self = {}
  self.node = node
  self.model = node.model
  self.name = "r(" .. self.model.name .. ")"

  function self.visit()
    --
  end

  function self.reset()
    --
  end

  return self
end

function rx_runtime_property(property)
  self = rx_runtime_node(property)
  self.value = property.default_value
  self.on_changed = property.on_changed

  function self.get()
    return self.value
  end

  function self.set(value)
    if value ~= self.value then
      self.on_changed.triggered = true
    end
    self.value = value
  end

  return self
end

function rx_runtime_event(event)
  self = rx_runtime_node(event)
  self.triggered = false

  function self.reset()
    self.triggered = false
  end

  function self.trigger()
    self.triggered = true
  end

  return self
end

function rx_runtime_callback(callback)
  self = rx_runtime_node(callback)
  self.action = callback.action
  self.requires = {}
  self.alters = {}

  function self.get_function_parameters()
    local output = {}
    -- Get requires
    local requires = table.filter(self.requires, function(v) return v.type == "property" end)
    local alters = self.alters

    return table.chain(requires, alters)
  end

  function self.get_required_events()
    return table.filter(self.requires, function(v) return v.type == "event" end)
  end

  function self.visit()
    if table.all(self.get_required_events(), function(v) return v.triggered == true end) then
      self.action(unpack(self.get_function_parameters()))
    end
  end

  return self
end

function to_runtime_model(node)
  n_classes = {
    property = rx_runtime_property,
    event = rx_runtime_event,
    callback = rx_runtime_callback
  }
  for name, class in pairs(n_classes) do
    if node.class == name then
      return class(node)
    end
  end
  --error "Can't convert a node into a runtime object!"
end

function graph_to_model(graph)
  runtimes = table.map(graph, to_runtime_model)
  decls = {}

  -- Map from decls -> runtimes
  for _, runtime in pairs(runtimes) do
    decls[runtime.model] = runtime
  end

  -- Hook up the callbacks to their runtime properties
  for _, runtime in pairs(runtimes) do
    if runtime.type == "callback" then
      for _, decl in pairs(runtime.model.inputs) do
        table.insert(runtime.requires, decls[decl])
      end

      for _, decl in pairs(runtime.model.listeners) do
        table.insert(runtime.alters, decls[decl])
      end
    end
  end

  return rxmodel(runtimes)
end
