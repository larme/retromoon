-- op mixin

local OPMixin = {}

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
end

function OPMixin:setup_op_exec()
  local num_ops = self._ops.num_ops
  local vm = self._vm_proxy -- for faster access
  local code2inst = self._ops.code2inst
  local op2inst = self._ops.op2inst

  function self:exec_opcode(code)
    local inst = code2inst[code]
    inst(vm)
  end

  function self:exec_op(op)
    local inst = op2inst[op]
    inst(vm)
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

  local old_setup = cls.setup
  function cls:setup(arg)
    old_setup(self)
    self._vm_proxy._ops = self._ops
    self:setup_op_exec()
  end
end

return OPMixin
