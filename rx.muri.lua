-- setup

local NgaVM = require('nga')
local Muri = require('muri')

local ast = {}

-- directives
local function directive_generator(directive)
  local function f(entry)
    table.insert(ast, {directive, entry})
  end
  return f
end

local d = directive_generator('number')
local r = directive_generator('ref')
local s = directive_generator('string')
local l = directive_generator('label')

local function i(...)
  local t = {'instruction_alt'}
  for _, op in ipairs{...} do
    table.insert(t, op)
  end
  table.insert(ast, t)
end

-- ops

local lit = 'lit'
local dup = 'dup'
local drop = 'drop'
local swap = 'swap'
local push = 'push'
local pop = 'pop'
local jump = 'jump'
local call = 'call'
local ccall = 'ccall'
local return_ = 'return_'
local eq = 'eq'
local neq = 'neq'
local lt = 'lt'
local gt = 'gt'
local fetch = 'fetch'
local store = 'store'
local add = 'add'
local sub = 'sub'
local mul = 'mul'
local divmod = 'divmod'
local and_ = 'and_'
local or_ = 'or_'
local xor = 'xor'
local shift = 'shift'
local zret = 'zret'
local end_ = 'end_'
local io_enum = 'io_enum'
local io_query = 'io_query'
local io_interact = 'io_interact'

-- shortcuts
local function call(label)
  -- set next memory cell to label address, push the address to stack
  -- and call it
  i(lit, call)
  r(label)
end

local function jump_to(label)
  i(lit, jump)
  r(label)
end

-- asm codes starts here

-- setup
i(lit, jump)
d(-1)

l('Dictionary')
r('9999')

l('Heap')
d(1536)

l('Version')
d(201907)

-- assign functions to opcode instruction

l('_nop')
d(0)
i(return_)

-- what about the argument of lit?
l('_lit')
d(1)
i(return_)

l('_dup')
d(2)
i(return_)

l('_drop')
d(3)
i(return_)

l('_swap')
d(4)
i(return_)

l('_push')
d(5)
i(return_)

l('_pop')
d(6)
i(return_)

l('_jump')
d(7)
i(return_)

l('_call')
d(8)
i(return_)

l('_ccall')
d(9)
i(return_)

l('_ret')
d(10)
i(return_)

l('_eq')
d(11)
i(return_)

l('_neq')
d(12)
i(return_)

l('_lt')
d(13)
i(return_)

l('_gt')
d(14)
i(return_)

l('_fetch')
d(15)
i(return_)

l('_store')
d(16)
i(return_)

l('_add')
d(17)
i(return_)

l('_sub')
d(18)
i(return_)

l('_mul')
d(19)
i(return_)

l('_divmod')
d(20)
i(return_)

l('_and')
d(21)
i(return_)

l('_or')
d(22)
i(return_)

l('_xor')
d(23)
i(return_)

l('_shift')
d(24)
i(return_)

l('_zret')
d(25)
i(return_)

l('_end')
d(26)
i(return_)

-- fetch-next (addr - next-addr addr-value)
l('fetch-next')
i(dup, lit, add, swap)
d(1)
i(fetch, return_)

-- store-next store an value to the address and return the next
-- address. It use the address stack to store the next address
-- temporally
l('store-next')
i(dup, lit, add, push)
d(1)
i(store, pop, return_)

-- Conditionals

-- choose
-- flag true-pointer false-pointer choose

-- at the begin the stack is [flag true-pointer false-pointer]. Then
-- we store true-pointer to label address choice:true and
-- false-pointer to label address choice:false (remember store is used
-- as: value address store), the stack is [flag]. We lit address of
-- label choice:false and add it with flag (-1 for true and 0 for
-- false, hence the result is address of choice:false if false, or
-- choice:true if true because address of choice:true = address of
-- choice:false - 1). Finally we just fetch the corresponding pointer
-- using fetch and call it with return.

l('choice:true')
d(0)
l('choice:false')
d(0)

l('choose')
i(lit, store, lit, store)
r('choice:false')
r('choice:true')
i(lit, add, fetch, call)
r('choice:false')
i(return_)

-- if and -if
-- flag true-pointer if
-- flag false-pointer -if
-- -if simply switch the flag then fall to if (use push and pop to
-- store the pointer temporally)

l('-if')
i(push, lit, eq, pop)
d(0)

l('if')
i(ccall)
i(return_)

-- Strings

-- the kernel need to get the length of string and compare strings for
-- dictionary

-- count find the first zero cell by repeatedly lit address to stack
-- and use zret to determine if the loop should be terminated. After
-- the call is finished, the address left on stack is actually the
-- cell next to the zero cell

l('count')
i(lit, call)
r('fetch-next')
i(zret)
i(drop, lit, jump)
r('count')

-- s:length use count to find the first non-zero cell, string length =
-- end - begin - 1 (to minus the zero cell itself)

l('s:length')
i(dup, lit, call)
r('count')
-- stack now is [begin_addr end_addr]
i(lit, sub, swap, sub)
d(1)
i(return_)

l('9999')
d(357)

local nga = NgaVM{addr_start=0}
local muri = Muri{
  image_size = nga.conf.image_size,
  addr_start = nga.conf.addr_start,
}

muri:pass1(ast)
muri:pass2(ast)
nga:dump_image('images/test_rx_muri.txt', muri.state.target)
