-- table.filter({"a", "b", "c", "d"}, function(o, k, i) return o >= "c" end)  --> {"c","d"}
--
-- @FGRibreau - Francois-Guillaume Ribreau
-- @Redsmin - A full-feature client for Redis http://redsmin.com
table.filter = function(t, filterIter)
  local out = {}

  for k, v in pairs(t) do
    if filterIter(v, k, t) then out[k] = v end
  end

  return out
end

function table.map(t, f)
  local out = {}
  for k, v in pairs(t) do
    out[k] = f(v)
  end
  return out
end

function table.any(t, f)
  for k, v in pairs(t) do
    if f(v) then
      return true
    end
  end
  return false
end

function table.all(t, f)
  return not table.any(t, function(v) return not f(v) end)
end

function table.replace(t, v1, v2)
  for k, v in pairs(t) do
    if t[k] == v1 then
      t[k] = v2
    end
  end
end

function table.removeValue(table, value)
  for k, v in pairs(table) do
    if v == value then
      table[k] = nil
      return
    end
  end
end

function table.chain(...)
  local output = {}
  for _, t in pairs({...}) do
    for _, v in pairs(t) do
      table.insert(output, v)
    end
  end
  return output
end

function table.clone(table)
  local output = {}
  for k, v in pairs(table) do
    output[k] = v
  end
  return output
end
