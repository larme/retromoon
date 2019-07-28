local utils = {}

-- string/simple split
function utils.ssplit(s, sep)
  if sep == nil then
    sep = '%s'
  end

  local t = {}
  for subs in string.gmatch(s, '([^' .. sep .. ']+)') do
    table.insert(t, subs)
  end
  return t
end

-- opcode packing/unpacking
function utils.unpack_opcodes(raw_code, code_num)
  local ret = {}
  for i=1,code_num do
    ret[i] = raw_code & 0xFF
    raw_code = raw_code >> 8
  end
  return ret
end

function utils.pack_opcodes(opcodes)
  local ret = 0
  for i=1,#opcodes do
    local shift = (i - 1) * 8
    local opcode = opcodes[i]
    ret = ret + (opcode << shift)
  end
  return ret
end

return utils
