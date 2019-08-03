local class = require('middleclass')
local utils = require('utils')
local OPMixin = require('op_mixin')
local ops = require('ops')

-- default values

local IMAGE_SIZE = 52488 * 16
local ADDRESSES = 2048
local STACK_DEPTH = 512
local NUM_DEVICES = 0

local ADDR_START = 1

-- data - stack
-- address - address
-- memory - image

local NgaVM = class('NgaVM')

function NgaVM:initialize(arg)
  self.state = {}
  local conf = {}
  conf.image_size = arg.image_size or IMAGE_SIZE
  conf.addresses = arg.addresses or ADDRESSES
  conf.stack_depth = arg.stack_depth or STACK_DEPTH
  conf.num_devices = arg.num_devices or NUM_DEVICES
  conf.addr_start = arg.addr_start or ADDR_START
  conf.packed_opcode_num = arg.packed_opcode_num or 4
  self.conf = conf

  local init_memory = arg.init_memory
  if init_memory == nil then
    init_memory = true
  end

  self.io = {}
  self.io.device_handlers = arg.io_device_handlers or {}
  self.io.query_handlers = arg.io_query_handlers or {}

  -- set vm up
  self:reset(init_memory)

end

-- after instances are created and every time state/conf/io table is
-- replaced, call this
function NgaVM:setup()
  self:setup_alias()
  self:setup_proxy()
end

function NgaVM:setup_alias()

  -- tos, nos, tors
  local alias_mt = {}
  local state = self.state
  local data = state.data
  local address = state.address

  function alias_mt.__index(_, k)
    if k == 'tos' then
      return data[state.sp]
    elseif k == 'nos' then
      return data[state.sp - 1]
    elseif k == 'tors' then
      return address[state.rp]
    end
  end

  function alias_mt.__newindex(_, k, v)
    if k == 'tos' then
      data[state.sp] = v
    elseif k == 'nos' then
      data[state.sp - 1] = v
    elseif k == 'tors' then
      address[state.rp] = v
    end
  end

  self.alias = {}
  setmetatable(self.alias, alias_mt)

end

function NgaVM:setup_proxy()
  local proxy = {}
  proxy.conf = self.conf
  proxy.alias = self.alias
  proxy.state = self.state
  proxy.io = self.io
  self._vm_proxy = proxy
end

-- reset/prepare
function NgaVM:reset(init_memory)
  if init_memory == nil then
    init_memory = true
  end

  local state = self.state
  state.memory = {}
  state.data = {}
  state.address = {}
  state.ip = self.conf.addr_start
  state.sp = self.conf.addr_start
  state.rp = self.conf.addr_start

  if init_memory then
    self:init_mem()
  end
end

function NgaVM:init_mem()
  local start = self.conf.addr_start

  local nop = 0
  for i=start, self.conf.image_size + start - 1 do
    self.state.memory[i] = nop
  end

  for i=start, self.conf.stack_depth + start - 1 do
    self.state.data[i] = nop
  end

  for i=start, self.conf.addresses + start - 1 do
    self.state.address[i] = nop
  end
end

function NgaVM:print_stack()
  io.stdout:write("stack:\t")
  for i=self.conf.addr_start,self.state.sp do
    io.stdout:write(tostring(self.state.data[i]))
    io.stdout:write("\t")
  end
  io.stdout:write("\n")
end

function NgaVM:load_image(path)
  -- each line is a cell
  local f = assert(io.open(path))
  local idx = self.conf.addr_start
  for line in io.lines(path) do
    local cell = tonumber(line)
    self.state.memory[idx] = cell
    idx = idx + 1
  end
  assert(f:close())
end

function NgaVM:dump_image(path, memory, start, end_, keep_trailing_zeros)
  local cell

  if not memory then
    memory = self.state.memory
  end

  if not start then
    start = self.conf.addr_start
  end

  if not end_ then
    end_ = self.conf.image_size + self.conf.addr_start - 1
  end

  if not keep_trailing_zeros then
    local last_non_zero_idx = start
    for i=start, end_ do
      cell = memory[i]
      if cell and cell ~= 0 then
	last_non_zero_idx = i
      end
    end
    end_ = last_non_zero_idx
  end

  local f = assert(io.open(path, 'w'))
  for i=start, end_ do
    cell = memory[i]
    f:write(cell, '\n')
  end
  f:close()
end

function NgaVM:exec_packed_opcodes(raw_code)
  local current
  local valid = true
  local packed_num = self.conf.packed_opcode_num
  local opcodes = utils.unpack_opcodes(raw_code, packed_num)

  for i=1,packed_num do
    current = opcodes[i]
    if not self:is_valid_opcode(current) then
      valid = false
      break
    end
  end

  if valid then
    for i=1,packed_num do
      current = opcodes[i]
      self:exec_opcode(current)
    end
  end

  return valid

end

NgaVM.static.OPS = ops.ops
NgaVM.static.OP2CODE = ops.op2code
NgaVM.static.OP2INST = ops.insts

NgaVM:include(OPMixin)

return NgaVM
