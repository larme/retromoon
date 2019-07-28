require("profiler")
local class = require('middleclass')
local NgaVM = require('nga')
local utils = require('utils')

local TestNgaVM = class('TestNgaVM', NgaVM)

function TestNgaVM:find_entry(named)
  local header = self.state.memory[2]
  local done = false
  while header ~= 0 and not done do
    if named == self:extract_string(header + 3) then
      done = true
    else
      header = self.state.memory[header]
    end
  end
  return header
end

function TestNgaVM:extract_string(at)
  local offset = 0
  local buffer = {}
  while true do
    local ch = self.state.memory[at + offset]
    if ch == 0 then
      return table.concat(buffer)
    end
    offset = offset + 1
    buffer[offset] = string.char(ch)
  end
end

function TestNgaVM:inject_string(s, to)
  for i=1, #s do
    ch = s:sub(i, i)
    self.state.memory[to + i - 1] = string.byte(ch)
  end
  self.state.memory[to + #s] = 0
end

function TestNgaVM:exec(entry)
  self.state.ip = entry
  self.state.rp = self.state.rp + 1
  self.alias.tors = 0
  local notfound = self.state.memory[self:find_entry('err:notfound') + 1]
  while self.state.ip < 100000 and self.state.rp > 0 do
    -- print("ip: ", self.ip)
    if self.state.ip == notfound then
      print("ERROR: word not found!")
    end

    local raw_code = self.state.memory[self.state.ip]

    local status = self:exec_packed_opcodes(raw_code)
    if not status then
      print("Invalid Bytecode", raw_code, self.state.ip)
      self.state.ip = 2000000
    end
    self.state.ip = self.state.ip + 1
  end
end

local io_query_handlers = {}

io_query_handlers[0] = function(vm)
  vm.state.sp = vm.state.sp + 1
  vm.alias.tos = 0
  vm.alias.nos = 0
end

local io_device_handlers = {}

local function disp_char(vm)
  local char = vm.alias.tos
  if char > 0 and char < 128 then
    local c = string.char(char)
    io.stdout:write(c)
    if char == 8 then
      io.stdout:write(string.char)
    end
  end
  vm._ops.op2inst.drop(vm)
  io.stdout:flush()
end

io_device_handlers[0] = disp_char

function run()
  local vm = TestNgaVM{
    addr_start = 0,
    io_device_handlers = io_device_handlers,
    io_query_handlers = io_query_handlers,
    num_devices = 1,
  }
  vm:setup()
  vm:load_image('image.txt')

  local done = false
  interpreter_addr = vm:find_entry('interpret') + 1
  interpreter = vm.state.memory[interpreter_addr]

  while not done do
    for i=vm.conf.addr_start, vm.state.sp do
      io.stdout:write(tostring(vm.state.data[i]) .. ' ')
    end
    io.stdout:write("\nOK> ")
    local line = io.stdin:read()
    if line == 'bye' then
      done = true
    else
      for _, token in ipairs(utils.ssplit(line)) do
	vm:inject_string(token, 1025)
	vm.state.sp = vm.state.sp + 1
	vm.alias.tos = 1025
	vm:exec(interpreter)
      end
    end
  end
end

function run_profiler()
  local vm = TestNgaVM{
    addr_start = 0,
    io_device_handlers = io_device_handlers,
    io_query_handlers = io_query_handlers,
  }
  vm:setup()
  vm:load_image('image.txt')

  local done = false
  interpreter_addr = vm:find_entry('interpret') + 1
  interpreter = vm.state.memory[interpreter_addr]

  profilerStart()
  for i=1,1 do
    print(i)
    for i=vm.conf.addr_start, vm.state.sp do
      io.stdout:write(tostring(vm.state.data[i]) .. ' ')
    end
    io.stdout:write("\n")
    -- local line = '#1 #5 dup dup + dup #1 #5 dup dup + dup #1 #5 dup dup + dup #1 #5 dup dup + dup #1 #5 dup dup + dup #1 #5 dup dup + dup #1 #5 dup dup + dup #1 #5 dup dup + dup'
    local line = '#1 #5 dup dup + dup'
    for _, token in ipairs(utils.ssplit(line)) do
      print(token)
      vm:inject_string(token, 1025)
      vm.state.sp = vm.state.sp + 1
      vm.alias.tos = 1025
      vm:exec(interpreter)
    end
  end
  profilerStop()
  profilerReport("profiler.log")
end

-- run_profiler()
run()

return TestNgaVM
