local class = require('middleclass')
local utils = require('utils')
local OPMixin = require('op_mixin')

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

  local init_memory = arg.init_memory or false

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

-- ops

NgaVM.static.OPS = {
  'nop',
  'lit', 'dup', 'drop', 'swap', 'push', 'pop',
  'jump', 'call', 'ccall', 'return_', 'eq', 'neq',
  'lt', 'gt', 'fetch', 'store', 'add', 'sub', 'mul', 'divmod',
  'and_', 'or_', 'xor', 'shift', 'zret', 'end_',
  'io_enum', 'io_query', 'io_interact',
}

local _insts = {}
NgaVM.static.OP2INST = _insts

function _insts.nop(vm)
  return
end

function _insts.lit(vm)
  vm.state.sp = vm.state.sp + 1
  vm.state.ip = vm.state.ip + 1
  vm.alias.tos = vm.state.memory[vm.state.ip]
end

function _insts.dup(vm)
  vm.state.sp = vm.state.sp + 1
  vm.alias.tos = vm.alias.nos
  return
end

function _insts.drop(vm)
  vm.state.data[vm.state.sp] = 0
  vm.state.sp = vm.state.sp - 1
  if vm.state.sp < vm.conf.addr_start then
    vm.state.ip = vm.conf.image_size
  end
end

function _insts.swap(vm)
  vm.alias.tos, vm.alias.nos = vm.alias.nos, vm.alias.tos
end

function _insts.push(vm)
  vm.state.rp = vm.state.rp + 1
  vm.alias.tors = vm.alias.tos
  _insts.drop(vm)
end

function _insts.pop(vm)
  vm.state.sp = vm.state.sp + 1
  vm.alias.tos = vm.alias.tors
  vm.state.rp = vm.state.rp - 1
end

function _insts.jump(vm)
  vm.state.ip = vm.alias.tos - 1
  _insts.drop(vm)
end

function _insts.call(vm)
  vm.state.rp = vm.state.rp + 1
  vm.alias.tors = vm.state.ip
  vm.state.ip = vm.alias.tos - 1
  _insts.drop(vm)
end

function _insts.ccall(vm)
  local addr, flag
  addr = vm.alias.tos
  _insts.drop(vm)
  flag = vm.alias.tos
  _insts.drop(vm)

  if flag ~= 0 then
    vm.state.rp = vm.state.rp + 1
    vm.alias.tors = vm.state.ip
    vm.state.ip = addr - 1
  end
end

function _insts.return_(vm)
  vm.state.ip = vm.alias.tors
  vm.state.rp = vm.state.rp - 1
end

function _insts.eq(vm)
  vm.alias.nos = (vm.alias.nos == vm.alias.tos) and -1 or 0
  _insts.drop(vm)
end

function _insts.neq(vm)
  vm.alias.nos = (vm.alias.nos ~= vm.alias.tos) and -1 or 0
  _insts.drop(vm)
end

function _insts.lt(vm)
  vm.alias.nos = (vm.alias.nos < vm.alias.tos) and -1 or 0
  _insts.drop(vm)
end

function _insts.gt(vm)
  vm.alias.nos = (vm.alias.nos > vm.alias.tos) and -1 or 0
  _insts.drop(vm)
end

function _insts.fetch(vm)
  if vm.alias.tos >= vm.conf.addr_start then
    vm.alias.tos = vm.state.memory[vm.alias.tos]
  elseif vm.alias.tos == -1 then
    vm.alias.tos = vm.state.sp - vm.conf.addr_start - 1
  elseif vm.alias.tos == -2 then
    vm.alias.tos = vm.state.rp
  elseif vm.alias.tos == -3 then
    vm.alias.tos = vm.conf.image_size
  end
end

function _insts.store(vm)
  vm.state.memory[vm.alias.tos] = vm.alias.nos
  _insts.drop(vm)
  _insts.drop(vm)
end

function _insts.add(vm)
  vm.alias.nos = vm.alias.nos + vm.alias.tos
  _insts.drop(vm)
end

function _insts.sub(vm)
  vm.alias.nos = vm.alias.nos - vm.alias.tos
  _insts.drop(vm)
end

function _insts.mul(vm)
  vm.alias.nos = vm.alias.nos * vm.alias.tos
  _insts.drop(vm)
end

function _insts.divmod(vm)
  local a, b = vm.alias.tos, vm.alias.nos
  vm.alias.tos = b // a
  vm.alias.nos = b % a
end

function _insts.and_(vm)
  vm.alias.nos = vm.alias.tos & vm.alias.nos
  _insts.drop(vm)
end

function _insts.or_(vm)
  vm.alias.nos = vm.alias.tos | vm.alias.nos
  _insts.drop(vm)
end

function _insts.xor(vm)
  vm.alias.nos = vm.alias.tos ~ vm.alias.nos
  _insts.drop(vm)
end

function _insts.shift(vm)
  local x, y
  y = vm.alias.tos
  x = vm.alias.nos

  if y < 0 then
    vm.alias.nos = x << (-1 * y)
  elseif y > 0 then
    if x < 0 then
      vm.alias.nos = x >> y | ~(~0 >> y)
    else
      vm.alias.nos = x >> y
    end
  end
  _insts.drop(vm)
end

function _insts.zret(vm)
  if vm.alias.tos == 0 then 
    _insts.drop(vm)
    vm.state.ip = vm.alias.tors
    vm.state.rp = vm.state.rp - 1
  end
end

function _insts.end_(vm)
  vm.state.ip = vm.conf.image_size
end

function _insts.io_enum(vm)
  vm.state.sp = vm.state.sp + 1
  vm.alias.tos = vm.num_devices
end

function _insts.io_query(vm)
  local device = vm.alias.tos
  _insts.drop(vm)
  vm.io.query_handlers[device](vm)
end

function _insts.io_interact(vm)
  local device = vm.alias.tos
  _insts.drop(vm)
  vm.io.device_handlers[device](vm)
end

NgaVM:include(OPMixin)

return NgaVM
