function simple_clone(table)
  -- Shallow clone
  local output = {}
  for key, value in pairs(table) do
    output[key] = value
  end
  return output
end

shallow_clone = simple_clone

function repl(tabl)
  local output = {}
  for key, value in pairs(tabl) do
    table.insert(output, tostring(key) .. ": " .. tostring(value))
  end
  return "{" .. table.concat(output, ", ") .. "}"
end
