local class = require('middleclass')
local utils = require('utils')

local IMAGE_SIZE = 52488 * 16
local ADDRESSES = 2048
local STACK_DEPTH = 512
local NUM_DEVICES = 0

local ADDR_START = 1
-- op mixin

local OPMixin = {}
OPMixin.static = {}

function OPMixin:propagate_op_info()
  local op2code = {}
  local code2op = {}
  local code2inst = {}
  local op2inst = self._ops.op2inst

  self._ops.op2code = op2code
  self._ops.code2op = code2op
  self._ops.code2inst = code2inst
  self._ops.num_ops = 0

  for _code, op in pairs(self._ops.ops) do
    self._ops.num_ops = self._ops.num_ops + 1
    code = _code - 1
    op2code[op] = code
    code2op[code] = op
    code2inst[code] = op2inst[op]
  end

  local num_ops = self._ops.num_ops

  function self:exec_opcode(code)
    local inst = code2inst[code]
    inst(self)
  end

  function self:exec_op(op)
    local inst = op2inst[op]
    inst(self)
  end

  function self:is_valid_opcode(code)
    -- the assumption is that opcode starts with 0 and ends with NUM_OPS - 1
    return code >= 0 and code < num_ops
  end

end

function OPMixin:included(cls)
  local old_init = cls.initialize

  function cls:initialize(arg)
    old_init(self, arg)
    self._ops = {}
    self._ops.ops = arg.ops or self.class.OPS
    self._ops.op2inst = arg.op2inst or self.class.OP2INST
    self:propagate_op_info()
  end
end

-- nga vm

-- data - STACK_DEPTH
-- address - addresses
-- memory - image_size

local NgaVM = class('NgaVM')

function NgaVM:initialize(arg)
  raw = {}
  rawset(self, 'raw', raw)
  self.image_size = arg.image_size or IMAGE_SIZE
  self.addresses = arg.addresses or ADDRESSES
  self.stack_depth = arg.stack_depth or STACK_DEPTH
  self.num_devices = arg.num_devices or NUM_DEVICES
  self.addr_start = arg.addr_start or ADDR_START
  self.packed_opcode_num = arg.packed_opcode_num or 4
  local init_memory = arg.init_memory or false

  self.io_device_handlers = arg.io_device_handlers or {}
  self.io_query_handlers = arg.io_query_handlers or {}

  -- tos, nos, tors
  local alias_mt = {}

  function alias_mt.__index(_, k)
    if k == 'tos' then
      return self.data[self.sp]
    elseif k == 'nos' then
      return self.data[self.sp - 1]
    elseif k == 'tors' then
      return self.address[self.rp]
    end
  end

  function alias_mt.__newindex(_, k, v)
    if k == 'tos' then
      self.data[self.sp] = v
    elseif k == 'nos' then
      self.data[self.sp - 1] = v
    elseif k == 'tors' then
      self.address[self.rp] = v
    end
  end

  self.alias = {}
  setmetatable(self.alias, alias_mt)

  -- set vm up
  self:reset(init_memory)

end

-- reset/prepare
function NgaVM:reset(init_memory)
  if init_memory == nil then
    init_memory = true
  end

  self.memory = {}
  self.data = {}
  self.address = {}
  self.ip = self.addr_start
  self.sp = self.addr_start
  self.rp = self.addr_start

  if init_memory then
    self:init_mem()
  end
end

function NgaVM:init_mem()
  local start = self.addr_start

  local nop = self.class.OP2CODE.nop
  for i=start, self.image_size + start - 1 do
    self.memory[i] = nop
  end

  for i=start, self.stack_depth + start - 1 do
    self.data[i] = nop
  end

  for i=start, self.addresses + start - 1 do
    self.address[i] = nop
  end
end

function NgaVM:print_stack()
  io.stdout:write("stack:\t")
  for i=self.addr_start,self.sp do
    io.stdout:write(tostring(self.data[i]))
    io.stdout:write("\t")
  end
  io.stdout:write("\n")
end

function NgaVM:load_image(path)
  -- each line is a cell
  local f = assert(io.open(path))
  idx = self.addr_start
  for line in io.lines(path) do
    cell = tonumber(line)
    self.memory[idx] = cell
    idx = idx + 1
  end
  assert(f:close())
end

function NgaVM:exec_packed_opcodes(raw_code)
  local current
  local valid = true
  local opcodes = utils.unpack_opcodes(raw_code, self.packed_opcode_num)

  for i=1,self.packed_opcode_num do
    current = opcodes[i]
    if not self:is_valid_opcode(current) then
      valid = false
      break
    end
  end

  if valid then
    for i=1,self.packed_opcode_num do
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
  vm.sp = vm.sp + 1
  vm.ip = vm.ip + 1
  vm.alias.tos = vm.memory[vm.ip]
end

function _insts.dup(vm)
  vm.sp = vm.sp + 1
  vm.alias.tos = vm.alias.nos
  return
end

function _insts.drop(vm)
  vm.data[vm.sp] = 0
  vm.sp = vm.sp - 1
  if vm.sp < vm.addr_start then
    vm.ip = vm.image_size
  end
end

function _insts.swap(vm)
  vm.alias.tos, vm.alias.nos = vm.alias.nos, vm.alias.tos
end

function _insts.push(vm)
  vm.rp = vm.rp + 1
  vm.alias.tors = vm.alias.tos
  vm:exec_op('drop')
end

function _insts.pop(vm)
  vm.sp = vm.sp + 1
  vm.alias.tos = vm.alias.tors
  vm.rp = vm.rp - 1
end

function _insts.jump(vm)
  vm.ip = vm.alias.tos - 1
  vm:exec_op('drop')
end

function _insts.call(vm)
  vm.rp = vm.rp + 1
  vm.alias.tors = vm.ip
  vm.ip = vm.alias.tos - 1
  vm:exec_op('drop')
end

function _insts.ccall(vm)
  local addr, flag
  addr = vm.alias.tos
  vm:exec_op('drop')
  flag = vm.alias.tos
  vm:exec_op('drop')

  if flag ~= 0 then
    vm.rp = vm.rp + 1
    vm.alias.tors = vm.ip
    vm.ip = addr - 1
  end
end

function _insts.return_(vm)
  vm.ip = vm.alias.tors
  vm.rp = vm.rp - 1
end

function _insts.eq(vm)
  vm.alias.nos = (vm.alias.nos == vm.alias.tos) and -1 or 0
  vm:exec_op('drop')
end

function _insts.neq(vm)
  vm.alias.nos = (vm.alias.nos ~= vm.alias.tos) and -1 or 0
  vm:exec_op('drop')
end

function _insts.lt(vm)
  vm.alias.nos = (vm.alias.nos < vm.alias.tos) and -1 or 0
  vm:exec_op('drop')
end

function _insts.gt(vm)
  vm.alias.nos = (vm.alias.nos > vm.alias.tos) and -1 or 0
  vm:exec_op('drop')
end

function _insts.fetch(vm)
  if vm.alias.tos >= vm.addr_start then
    vm.alias.tos = vm.memory[vm.alias.tos]
  elseif vm.alias.tos == -1 then
    vm.alias.tos = vm.sp - vm.addr_start - 1
  elseif vm.alias.tos == -2 then
    vm.alias.tos = vm.rp
  elseif vm.alias.tos == -3 then
    vm.alias.tos = vm.image_size
  end
end

function _insts.store(vm)
  vm.memory[vm.alias.tos] = vm.alias.nos
  vm:exec_op('drop')
  vm:exec_op('drop')
end

function _insts.add(vm)
  vm.alias.nos = vm.alias.nos + vm.alias.tos
  vm:exec_op('drop')
end

function _insts.sub(vm)
  vm.alias.nos = vm.alias.nos - vm.alias.tos
  vm:exec_op('drop')
end

function _insts.mul(vm)
  vm.alias.nos = vm.alias.nos * vm.alias.tos
  vm:exec_op('drop')
end

function _insts.divmod(vm)
  local a, b = vm.alias.tos, vm.alias.nos
  vm.alias.tos = b // a
  vm.alias.nos = b % a
end

function _insts.and_(vm)
  vm.alias.nos = vm.alias.tos & vm.alias.nos
  vm:exec_op('drop')
end

function _insts.or_(vm)
  vm.alias.nos = vm.alias.tos | vm.alias.nos
  vm:exec_op('drop')
end

function _insts.xor(vm)
  vm.alias.nos = vm.alias.tos ~ vm.alias.nos
  vm:exec_op('drop')
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
  vm:exec_op('drop')
end

function _insts.zret(vm)
  if vm.alias.tos == 0 then 
    vm:exec_op('drop')
    vm.ip = vm.alias.tors
    vm.rp = vm.rp - 1
  end
end

function _insts.end_(vm)
  vm.ip = vm.image_size
end

function _insts.io_enum(vm)
  vm.sp = vm.sp + 1
  vm.alias.tos = vm.num_devices
end

function _insts.io_query(vm)
  local device = vm.alias.tos
  vm:exec_op('drop')
  vm.io_query_handlers[device](vm)
end

function _insts.io_interact(vm)
  local device = vm.alias.tos
  vm:exec_op('drop')
  vm.io_device_handlers[device](vm)
end

NgaVM:include(OPMixin)

return NgaVM
