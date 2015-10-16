function rxmodel(runtimes)
  local self = {}
  self.runtimes = runtimes
  self.visitable = runtimes

  self.decls = {}
  for _, runtime in pairs(runtimes) do
    self.decls[runtime.decl] = runtime
  end

  function self.reset()
    for _, runtime in pairs(self.runtimes) do
      runtime.reset()
    end
  end

  function self.iterate()
    for _, runtime in pairs(self.runtimes) do
      runtime.visit()
    end
  end

  function self.from_declaration(decl)
    return self.decls[decl]
  end

  return self
end

function rx_runtime_node(decl)
  local self = {}
  self.decl = decl
  self.type = decl.type
  self.name = "r(" .. self.decl.name .. ")"

  function self.visit()
    --
  end

  function self.reset()
    --
  end

  return self
end

function rx_runtime_property(property)
  local self = rx_runtime_node(property)
  self.value = property.default_value
  self.on_changed = nil -- hook up when creating model

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
  local self = rx_runtime_node(event)
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
  local self = rx_runtime_node(callback)
  self.action = callback.action
  self.requires = {}
  self.alters = {}

  function self.get_function_parameters()
    local output = {}
    -- Get requires
    local requires = table.filter(self.requires, function(v) return v.type == "property" end)
    requires = table.map(requires, function(v) return v.get() end)
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
      return class(node.model)
    end
  end
  --error "Can't convert a node into a runtime object!"
end

function graph_to_model(graph)
  runtimes = table.map(graph, to_runtime_model)
  decls = {}

  -- Map from decls -> runtimes
  for _, runtime in pairs(runtimes) do
    decls[runtime.decl] = runtime
  end


  -- Hook up the properties and their on_changed callbacks
  for _, property_runtime in pairs(table.filter(runtimes, function(v) return v.type == "property" end)) do 
    on_changed = decls[property_runtime.decl.on_changed]
    property_runtime.on_changed = on_changed
  end

  -- Hook up the callbacks to their runtime properties
  for _, runtime in pairs(runtimes) do
    if runtime.type == "callback" then
      for _, decl in pairs(runtime.decl.inputs) do
        table.insert(runtime.requires, decls[decl])
      end

      for _, decl in pairs(runtime.decl.listeners) do
        table.insert(runtime.alters, decls[decl])
      end
    end
  end

  return rxmodel(runtimes)
end
