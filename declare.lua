require("declare/table_extensions")
require("declare/utils")
deque = require "declare/deque"

rxnodes = {}

local rxmodelstore = {}

function mixin_signals(self)
  self.listeners = {}
  self.inputs = {}
  self.name = self.type

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
end

function rxproperty(value, name, skipCallbacks)
  local self = {}
  mixin_signals(self)
  self.type = "property"
  self.class_type = "singleton" -- options: "singleton", "each", "all"
  self.name = "p("..name..")" or "p(???)"
  self.default_value = value

  if not skipCallbacks then
    self.on_changed = rxevent()
    self.on_changed.name = self.name .. '.onChanged'
    table.insert(self.on_changed.inputs, self)
    table.insert(self.listeners, self.on_changed)
  end

  table.insert(rxmodelstore, self)
  return self
end

function rxevent(name)
  local self = {}
  mixin_signals(self)
  self.type = "event"
  self.name = name

  table.insert(rxmodelstore, self)
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

  table.insert(rxmodelstore, self)
  return self
end

function rxclass(fields, name)
  local self = {}
  self.type = "class"
  self.name = name or "class"
  self.schema = {}

  for name, value in pairs(fields) do
    local pname = self.name .. "." .. name
    self.schema[name] = rxproperty(value, pname)
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

  table.insert(rxmodelstore, self)
  return self
end
