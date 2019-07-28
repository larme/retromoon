local class = require('middleclass')

local MAX_NAMES = 1024

local Muri = class('Muri')

function Muri:initialize(arg)
  local conf = {}
  conf.image_size = assert(arg.image_size)
  conf.addr_start = assert(arg.addr_start)
  conf.op2code = assert(arg.op2code)
  self.conf = conf

  local init_target = arg.init_target
  if init_target == nil then
    init_target = true
  end

  self:reset(init_target)
end

function Muri:init_target()
  local start = self.conf.addr_start
  local end_ = self.conf.image_size + start - 1
  for i=start, end_ do
    self.state.target[i] = 0
  end
end  

function Muri:reset(init_target)
  if init_target == nil then
    init_target = true
  end

  local state = self.state
  state.target = {}
  state.labels = {}
  state.ptrs = {}
  state.here = self.conf.addr_start
  self.state = state

  if init_target then
    self:init_target()
  end
end

function Muri:add_label(name, slice)
  if self.state.labels[name] then
    print("Fatal error: " .. name .. " already defined")
    os.exit(0)
  end
  self.state.labels[name] = slice
end

function Muri:code_for(op)
  return self.op2code[op] or 0
end

return Muri
