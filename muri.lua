local class = require('middleclass')
local utils = require('utils')

local MAX_NAMES = 1024
local OP2CODE = {
  ['..'] = 0, li = 1,
  du = 2, dr = 3,
  sw = 4, pu = 5,
  po = 6, ju = 7,
  ca = 8, cc = 9,
  re = 10, eq = 11,
  ne = 12, lt = 13,
  gt = 14, fe = 15,
  st = 16, ad = 17,
  su = 18, mu = 19,
  di = 20, an = 21,
  ['or'] = 22, xo = 23,
  sh = 24, zr = 25,
  en = 26, ie = 27,
  iq = 28, ii = 29,
}

local Muri = class('Muri')

function Muri:initialize(arg)
  local conf = {}
  conf.image_size = assert(arg.image_size)
  conf.addr_start = assert(arg.addr_start)
  conf.op2code = arg.op2code or OP2CODE
  self.conf = conf

  local init_target = arg.init_target
  if init_target == nil then
    init_target = true
  end

  self.state = {}
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
  state.here = self.conf.addr_start
  self.state = state

  if init_target then
    self:init_target()
  end
end

function Muri:fatal_error(msg)
  print("Fatal error: " .. msg)
  os.exit(0)
end

function Muri:add_label(name, slice)
  if self.state.labels[name] then
    self:fatal_error(name .. " already defined")
  end
  self.state.labels[name] = slice
end

function Muri:lookup_label(name)
  return self.state.labels[name]
end

function Muri:code_for(op)
  return self.conf.op2code[op] or 0
end

function Muri:write_cell(cell)
  local state = self.state
  state.target[state.here] = cell
  state.here = state.here + 1
end

-- load literate muri file
function Muri:load_file(path)
  local f = io.open(path)
  local in_block = false
  local src_t = {}

  for line in f:lines() do
    if line == '~~~' then
      if in_block then
	in_block = false
      else
	in_block = true
      end
    else
      if in_block and line ~= '' then
	table.insert(src_t, line)
      end
    end
  end

  f:close()
  return src_t

end

-- parse retro's muri source to ast. src is a table of source lines
function Muri:parse_source(src)
  local translation_table = {
    i = 'instruction',
    d = 'number', 
    r = 'ref', 
    s = 'string',
    [':'] = 'label',
  }

  local ast = {}
  for _, line in ipairs(src) do
    local entry = utils.ssplit(line)
    local directive = translation_table[entry[1]]
    if not directive then
      self:fatal_error("illegal directive " .. directive)
    end
    entry[1] = directive
    table.insert(ast, entry)
  end
  return ast
end

function Muri:_pass(ast, directives)
  self.state.here = self.conf.addr_start

  -- ast in {directive data...}
  for _, entry in ipairs(ast) do
    local directive = entry[1]
    local processor = directives[directive]
    if not processor then
      self:fatal_error("illegal directive " .. directive)
    end
    processor(self, entry)
  end
end

function Muri:pass1(ast)
  local ds = self.class.directives.pass1
  self:_pass(ast, ds)
end

function Muri:pass2(ast)
  local ds = self.class.directives.pass2
  self:_pass(ast, ds)
end

Muri.static.directives = {}

local _pass1 = {}
Muri.static.directives.pass1 = _pass1

function _pass1.instruction(self, entry)
  local ops = entry[2]
  local opcodes = {}
  local pack_num = 4
  for i=1, pack_num do
    local op = ops:sub(2 * i - 1, 2 * i)
    opcodes[i] = self:code_for(op)
  end
  local packed_opcode = utils.pack_opcodes(opcodes)
  self:write_cell(packed_opcode)
end

function _pass1.number(self, entry)
  local num = tonumber(entry[2])
  self:write_cell(num)
end

function _pass1.string(self, entry)
  local s = entry[2]
  for i=1, #s do
    local char = string.byte(s, i)
    self:write_cell(char)
  end
  self:write_cell(0)
end

function _pass1.label(self, entry)
  local label = entry[2]
  self:add_label(label, self.state.here)
end

function _pass1.ref(self, entry)
  self:write_cell(-1)
end

local _pass2 = {}
Muri.static.directives.pass2 = _pass2

local function _move_on(self, entry)
  self.state.here = self.state.here + 1
end

_pass2.instruction = _move_on
_pass2.number = _move_on

function _pass2.label(self, entry)
  -- do nothing
  return
end

function _pass2.string(self, entry)
  local s = entry[2]
  self.state.here = self.state.here + #s + 1
end

function _pass2.ref(self, entry)
  local label = entry[2]
  local addr = self:lookup_label(label)
  if not addr then
    self:fatal_error("label look up failed: " .. label)
  end
  self:write_cell(addr)
end

return Muri
