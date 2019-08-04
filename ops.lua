-- ops

local ops = {}

ops.ops = {
  'lit', 'dup', 'drop', 'swap', 'push', 'pop',
  'jump', 'call', 'ccall', 'return_', 'eq', 'neq',
  'lt', 'gt', 'fetch', 'store', 'add', 'sub', 'mul', 'divmod',
  'and_', 'or_', 'xor', 'shift', 'zret', 'end_',
  'io_enum', 'io_query', 'io_interact',
}

ops.ops[0] = 'nop'

ops.shortname2op = {}

for _, op in pairs(ops.ops) do
  local shortname = op:sub(1, 2)
  ops.shortname2op[shortname] = op
end

ops.shortname2op['..'] = 'nop'

local _insts = {}
ops.insts = _insts

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
  -- because instruction/memory pointer will be increased by 1 after
  -- jump is executed, so we need to minus the jump-to address by 1 to
  -- make it right
  vm.state.ip = vm.alias.tos - 1
  _insts.drop(vm)
end

function _insts.call(vm)
  -- push current ip to address stack. after return is executed, ip
  -- will be increased by one so go to the next instruction
  vm.state.rp = vm.state.rp + 1
  vm.alias.tors = vm.state.ip

  -- after call is executed, ip will be increased by one so need to
  -- minus the jump-to address by 1
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
  -- set ip to the return address. then the vm loop will increase the ip by 1 so vm will actually execute next instruction (as we want)
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

-- add your own opcodes here
-- 1. add entry in ops.ops
-- 2. add entry in ops.shortname2op
-- 3. add entry in _insts

-- end of customized additional opcodes

ops.op2code = {}

for code, op in pairs(ops.ops) do
  ops.op2code[op] = code
end

return ops
