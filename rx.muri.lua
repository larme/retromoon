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
local function call_at(label)
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

-- string comparisons

-- s:eq repeatedly compare characters from s1 and s2. If 2 characters
-- are different, it calls mismatch subroutine, which will simply
-- clear the stacks (both data stack and address stack because we
-- don't want to go back to s:eq routine if two strings are mismatch
-- due to the way we write it) and return 0 at the stack; otherwise it
-- will call matched, which will do some bookkeeping works and call
-- s:eq to compare the next pair of characters if the string is not
-- yet end, or else it will go to the final part of s:eq and return -1.

-- `s:eq` and subroutines' address stack changes are a little bit
-- confusing for me. Assuming the address stack right before caller
-- (the caller can be `s:eq` itself because `matched` and `s:eq` call
-- each other recursively.) call `s:eq` is [*], and after caller call
-- `s:eq` is [* r0] where r0 is caller's return address. Then `s:eq`
-- will call `choose` to call either `mismatch` or `matched`, where
-- the address stack would become [* r0 r1 r2], where r2 is the
-- address return to `choose` while r1 is the address return to
-- `s:eq`. pop r1 will return to the final part of s:eq i.e. drop 2
-- strings' pointer and lit -1 (true) to stack. When 2 string are
-- equal, the zret of `matched` will be executed and return to
-- `choose` (popping r2) and then the `choose` will return (popping
-- r1) to `s:eq`, and then the final part of `s:eq` will be executed
-- and return to caller (popping r0, and the address stack is back to
-- [*]). This is the only case the call/return cycle is done
-- "properly". Otherwise both `mismatch` and `matched` want to go back
-- to caller directly, so they need to change the address stack from
-- [* r0 r1 r2] to [* r0] before return. That’s why there's 2 pop and
-- drop pair for each routine.

-- data stack changes: [s2_next_ptr s1_next_ptr s1_char] ->> [0]
-- address stack changes: [address_return_to_s:eq
-- address_return_to_choose] -> []
l('mismatch')
i(drop, drop, drop, lit)
d(0)
i(pop, pop, drop, drop)
i(return_)

-- data stack changes: [s2_next_ptr s1_next_ptr s1_char] ->
-- [s2_next_ptr s1_next_ptr]
-- address stack changes: [address_return_to_s:eq
-- address_return_to_choose] -> []
l('matched')
i(zret)
i(drop, lit, call)
r('s:eq')
i(pop, pop, drop, drop)
i(return_)

l('s:eq')

-- stack changes: [s1_ptr s2_ptr] -> [s1_ptr s2_ptr s2_ptr] -> [s1_ptr
-- s2_ptr s2_char] -> [s1_ptr s2_ptr] -> [s1_ptr s2_ptr 1]
-- address stack changes: [] -> [s2_char]
i(dup, fetch, push, lit)
d(1)

-- stack changes: [s1_ptr s2_ptr 1] -> [s1_ptr s2_next_ptr] ->
-- [s2_next_ptr s1_ptr] -> [s2_next_ptr s1_ptr s1_ptr] -> [s2_next_ptr
-- s1_ptr s1_char]
-- address stack is [s2_char]
i(add, swap, dup, fetch)

-- we left a s1_char on stack so matched can determine if the
-- strings are terminated
-- stack changes: [s2_next_ptr s1_ptr s1_char] -> [s2_next_ptr s1_ptr]
-- -> [s2_next_ptr s1_ptr 1] -> [s2_next_ptr s1_next_ptr] ->
-- [s2_next_ptr s1_next_ptr s1_char] -> [s2_next_ptr s1_next_ptr
-- s1_char s1_char] -> [s2_next_ptr s1_next_ptr s1_char s1_char
-- s2_char] -> [s2_next_ptr s1_next_ptr s1_char if_not_eq_flag] ->>
-- [s2_next_ptr s1_next_ptr s1_char if_not_eq_flag mismatch_ptr
-- matched_ptr choose_ptr] then call -> [s2_next_ptr s1_next_ptr s1_char]
-- after call address stack is [addr_back_to_final_part]

-- address stack changes: [s2_char] -> [s2_char s1_char] -> [s2_char]
-- -> [] -> [address_return_to_s:eq] -> [address_return_to_s:eq
-- address_return_to_choose]
i(push, lit, add, pop)
d(1)
i(dup, pop, neq, lit)
r('mismatch')
i(lit, lit, call)
r('matched')
r('choose')

-- this is the final part of s:eq, only if matched's zret execute
-- would the code reach here so that two string is exhausted and every
-- pair of characters are equal. In this case we clear the stack and
-- return -1.
-- stack changes: [s2_next_ptr s1_next_ptr] ->> [] -> [-1]
i(drop, drop, lit, return_)
d(-1)

-- Interpreter & Compiler

-- Compiler Core

-- comma, store a value into memory and increments a variable (Heap)
-- pointing to the next free address

l('comma')
i(lit, fetch, lit, call)
r('Heap')
r('store-next')
i(lit, store, return_)
r('Heap')

-- comma:opcode simply fetch the opcode from _opcode label address and
-- compile it to heap
l('comma:opcode')
i(fetch, lit, jump)
r('comma')

-- ($) fetch characters of string until the zero termination, then
-- store characters to heap

l('($)')
call_at('fetch-next')
i(zret)
call_at('comma')
jump_to('($)')

-- comma:string call ($), then clear the stack (the next address) and
-- compile a 0 to end the string

l('comma:string')
call_at('($)')
i(drop, lit, lit, jump)
d(0)
r('comma')

-- if we are in compiler mode
l('Compiler')
d(0)

-- ; to add an _ret at the end of a function then terminate compiling

l(';')
i(lit, lit, call)
r('_ret')
r('comma:opcode')
-- set compiler mode back to 0 (false)
i(lit, lit, store, return_)
d(0)
r('Compiler')

-- Word Classes

l('class:data')
-- if not in compiler mode return immediately
i(lit, fetch, zret)
r('Compiler')
-- else prepend lit before the data
i(drop, lit, lit, call)
r('_lit')
r('comma:opcode')
jump_to('comma')

l('class:word:interpret')
i(jump)

l('class:word:compile')
i(lit, lit, call)
d(2049) -- packed opcode of lit and call
r('comma')
jump_to('comma')

l('class:word')
i(lit, fetch, lit, lit)
r('Compiler')
r('class:word:compile')
r('class:word:interpret')
jump_to('choose')

l('class:primitive')
i(lit, fetch, lit, lit)
r('Compiler')
r('comma:opcode')
r('class:word:interpret')
jump_to('choose')

l('class:macro')
i(jump)

-- Dictionary

-- read rx.muri to get a grasp of the structure of the dictionary. we
-- have 4 accessors: d:link (link to the previous entry), d:xt, (link
-- to start of the function) d:class (link to the class handler
-- function) and d:name (zero terminated string of the name)

l('d:link')
i(return_)

l('d:xt')
i(lit, add, return_)
d(1)

l('d:class')
i(lit, add, return_)
d(2)

l('d:name')
i(lit, add, return_)
d(3)

-- d:add-header saa-
-- create a dictionary entry

l('d:add-header')

-- data stack with params: [name cls xt]
i(lit, fetch, push, lit)
r('Heap')
r('Dictionary')

-- data stack now: [name cls xt dict-ptr]
-- address stack now: [heap-value]
-- following line fetch dictionary address then compile it to the
-- first cell of free heap, hence it becomes the link to the previous
-- dictionary entry part. The heap address is also increased. So we
-- use the address stack to keep a copy of original free heap address
i(fetch, lit, call)
r('comma')

-- data stack now: [name cls xt]
-- address stack now: [heap-value]
-- the following 3 lines compile dictionary function pointer, class
-- and name
call_at('comma')
call_at('comma')
call_at('comma:string')

-- data stack now: []
-- address stack now: [heap-value]
-- we now store the original heap address (the pointer point to the
-- dictionary we just created) to Dictionary address.
i(pop, lit, store, return_)
r('Dictionary')

-- Dictionary Search

-- store the result here
l('Which')
d(0)

-- store the target pointer here
l('Needle')
d(0)

-- after entry found, store the address at Which, setup a faked entry
-- address (with value 0) so that find_next loop will break and return
l('found')
-- stack changes: [found-entry-ptr] -> [address_of_nop]
i(lit, store, lit, return_)
r('Which')
r('_nop')

-- find initialize Which, fetch the most recent dictionary entry to
-- stack, then go to the find_next loop
l('find')
i(lit, lit, store, lit)
d(0)
r('Which')
r('Dictionary')
i(fetch)

-- find_next loop will accept a dictionary entry pointer (if zero then
-- return), then compare it with the string given (pointer stored at
-- Needle), if equal then call found (using ccall), else continue
-- find_next looping

l('find_next')
-- stack: [entry-ptr]
-- if entry-ptr is zero then either the dictionary is exhausted or
-- entry is found (`found` will lit _nop's address to stack so the
-- last fetch of find_next which is used to get previous entry address
-- will get a 0 to stack)

i(zret)
i(dup, lit, call)
r('d:name')
-- stack: [entry-ptr entry-name-ptr]
-- get target string pointer from Needle and call s:eq
i(lit, fetch, lit, call)
r('Needle')
r('s:eq')
-- stack: [entry-ptr comp-result]
-- call found if compare result is true
i(lit, ccall)
r('found')
-- stack: [entry-ptr]
-- entry-ptr fetch will get us the previous entry-ptr, now call
-- find-next with new entry-ptr on stack
i(fetch, lit, jump)
r('find_next')

-- d:lookup setup needle and call find, after finished put result from
-- Which on stack and return
l('d:lookup')
i(lit, store, lit, call)
r('Needle')
r('find')
i(lit, fetch, return_)
r('Which')

-- Number Conversion

l('next')
-- stack changes [sign accum s] -> [sign accum s-next-ptr ch]
call_at('fetch-next')
-- if at the end of string, return.
-- stack changes: [sign accum s-next-ptr ch] -> [sign accum s-next-ptr]
i(zret)
-- else get the digit value = ascii code of ch - 48 (ascii code of 0)
-- stack changes: [sign accum s-next-ptr ch] -> [sign accum s-next-ptr
-- ch 48] -> [sign accum s-next-ptr digit] -> [sign accum digit
-- s-next-ptr] -> [sign accum digit]
i(lit, sub, swap, push)
d(48)
-- add the digit to accum * 10
-- stack changes: [sign accum digit] -> [sign digit accum 10] -> [sign
-- digit accum*10] -> [sign new-accum]
i(swap, lit, mul, add)
d(10)
-- pop next character pointer back to stack and loop again
i(pop, lit, jump)
r('next')

-- check sign
l('check')
-- stack changes: [1 s] -> [1 s s] -> [1 s ch] -> [1 s ch neg-ch] ->
-- [1 s neg-flag]
i(dup, fetch, lit, eq)
d(45)
-- if not negative, return directly
-- stack changes: [1 s neg-flag] -> [1 s]
i(zret)
-- else we set sign to -1 and drop the negative character
-- stack stack changes: [1 s neg-flag] -> [1 s] -> [s 1] -> [s] -> [s
-- -1] -> [-1 s] -> [-1 s 1] -> [-1 s-next]
i(drop, swap, drop, lit)
d(-1)
i(swap, lit, add, return_)
d(1)

-- s:to-number (s-n)
l('s:to-number')
-- stack changes: [s] -> [s 1] -> [1 s] -> call check -> [sign s]
-- here we first lit 1 as the default sign
i(lit, swap, lit, call)
d(1)
r('check')
-- stack changes [sign s] -> [sign s 0] -> [sign 0 s] -> call next ->
i(lit, swap, lit, call)
d(0)
r('next')
-- drop next ptr and multiple absolute value with sign
-- stack changes: [sign accum s] -> [number]
i(drop, mul, return_)

-- token processing

l('prefix:no')
d(32)
d(0)

l('prefix:handler')
d(0)

-- string template for prefix-handler name
l('prefixed')
s('prefix:_')

-- construct prefix:<prefix-char> handler name
-- stack changes: [prefix-ch] -> []
l('prefix:prepare')
i(fetch, lit, lit, add)
r('prefixed')
d(7)
i(store, return_)

l('prefix:has-token?')
-- stack changes: [s] -> [s s] -> [s s-length]
i(dup, lit, call)
r('s:length')
i(lit, eq, zret)
d(1)
i(drop, drop, lit, return_)
r('prefix:no')

l('prefix?')
call_at('prefix:has-token?')
call_at('prefix:prepare')
-- find pointer to prefix handler
i(lit, lit, call)
r('prefixed')
r('d:lookup')
-- store pointer to prefixed handler and make sure it's not 0
i(dup, lit, store, lit)
r('prefix:handler')
d(0)
i(neq, return_)

-- ( (s-) comment prefix
l('prefix:(')
i(drop, return_)

-- # (s-n) number prefix class:data
l('prefix:#')
call_at('s:to-number')
jump_to('class:data')

-- $ fetch (s-c) fetch class:data
l('prefix:$')
i(fetch, lit, jump)
r('class:data')

-- : (s-) definition class:word
l('prefix::')
i(lit, lit, fetch, lit)
r('class:word')
r('Heap')
r('d:add-header')
i(call)
i(lit, fetch, lit, fetch)
r('Heap')
r('Dictionary')
call_at('d:xt')
i(store, lit, lit, store)
d(-1)
r('Compiler')
i(return_)

-- & (s-a)
l('prefix:&')
call_at('d:lookup')
call_at('d:xt')
i(fetch, lit, jump)
r('class:data')

-- quotations

-- some notes on why [ and ] is implemented in current way:

-- inside [ ] pair, the compiler mode is switched on and all token are
-- processed by their class using different class handler's compiler
-- mode to process these tokens.

-- example 1 shows how different class of data is processed
-- #42 is processed by prefix:# and treated by class:data
-- &dup is processed by prefix:& and treated by class:data
-- n:put is treated by class:word(:compile)

-- OK> [ #42 &dup n:put ]
-- [ #42 &dup n:put ]
-- data stack: ( 0 10463 )
-- address stack: ( 0 )
-- heap starts from 10461: ( 1793 10470 1 42 1 9 2049 10274 10 1 10463 )

-- now you can see that there are 2 extra cells both before and after the
-- quotation body (and a ret opcode). Each quotation is compiled like
-- below:

-- ( liju lit-after-return quotation-entry-point
--   ... quotation body ... ret
--   lit quotation-entry-point )

-- for the top level quotation, execution jumps directly to quotation
-- entry point, and return before the ending lit opcode so that 4
-- cells don't have any effect. when quotations are nested, quotations
-- of all level will be compiled at once. But when the first level
-- quotation is called, the nested quotation should not be executed
-- (unless called in first level quotation) and simply return a
-- address to be called. To do this, thhe first 2 cells of nested
-- quotation let execution jump directly to the last 2 cells of nested
-- quotation and lit the entry point of the nested quotation to stack.

-- let's take a look at example 2

-- OK> [ #42 [ #114 dup ] swap dup + n:put ]
-- data stack: ( 10463 )
-- address stack: ( )
-- heap starts from 10461: ( 1793 10479 1 42 1793 10471 1 114 2 10 1 10467 4 2 17 2049 10274 10 1 10463 )

-- heap details (address, value, annotation):
-- | 10461 | 10462 | 10463 | 10464 | 10465 | 10466 | 10467 | 10468 | 10469 | 10470 | 10471 | 10472 | 10473 | 10474 | 10475 | 10476 | 10477 | 10478 | 10479 | 10480 |
-- | 1793  | 10479 |   1   |  42   | 1793  | 10471 |   1   |  114  |   2   |  10   |   1   | 10467 |   4   |   2   |  17   | 2049  | 10274 |  10   |   1   | 10463 |
-- | liju  | 10479 |  lit  |  42   | liju  | 10471 |  lit  |  114  |  dup  |  ret  |  lit  | 10467 | swap  |  dup  |  add  | lica  | n:put |  ret  |  lit  | 10463 |

-- now let's call the top level quotation

-- OK> call
-- 84data stack: ( 10467 )
-- address stack: ( )

-- when called, execution jump to entry point of top level quotation
-- 14063 (instead of 10461, the start of top level quotation), then at
-- 10465/10466 (first 2 cells of nested quotation) it jump to the end
-- of the nested quotation body at 10471, lit the entry point of
-- nested quotation 10467 to stack, then execute the following code of
-- top level quotation, finally return at 10478. cell 10479 and 10480
-- (for top level quotation) is ignored. And the address of the nested
-- quotation is left on stack to be used later

-- in the final example we can see that quotation in function
-- definition works similarly to a nested quotation

-- OK> :mytest [ #1 ] dup ;
-- data stack: ( )
-- address stack: ( )
-- heap starts from 10461: ( 10329 10471 147 109 121 116 101 115 116 0 1793 10476 1 1 10 1 10473 2 10 )

-- OK> mytest
-- data stack: ( 10473 10473 )
-- address stack: ( )

l('[')

-- get free heap address + 2, this is the entry point of quotation
-- stack changes: [] -> [heap-ptr+2]

i(lit, fetch, lit, add)
r('Heap')
d(2)

-- save previous compiler status and prepare to set compiler mode to true
-- stack changes: [heap-ptr+2] ->> [heap-ptr previous-compiler-status
-- -1 compiler-addr]

i(lit, fetch, lit, lit)
r('Compiler')
d(-1)
r('Compiler')

-- write compiler mode to true, compile a jump-to code at
-- heap-ptr. hence now heap point to heap-ptr+1
-- stack changes: [heap-ptr+2 previous-compiler-status -1
-- compiler-addr] -> [heap-ptr+2 previous-compiler-status] ->
-- [heap-ptr+2 previous-compiler-status jump-to comma-ptr] ->
-- [heap-ptr+2 previous-compiler-status]

i(store, lit, lit, call)
d(1793) -- jump-to
r('comma')

-- compile 0 at new-heap-ptr, which now point to heap-ptr+1. After
-- that heap now point to heap-ptr+2.
-- The heap looks like: | 1793 | 0 | ... from heap-ptr

-- stack changes: [heap-ptr+2 previous-compiler-status] ->>
-- [heap-ptr+2 previous-compiler-status heap-ptr+1 0 comma-ptr] ->
-- [heap-ptr+2 previous-compiler-status heap-ptr+1]

i(lit, fetch, lit, lit)
r('Heap')
d(0)
r('comma')
i(call)

-- stack changes: [heap-ptr+2 previous-compiler-status heap-ptr+1] ->
-- [heap-ptr+2 previous-compiler-status heap-ptr+1 heap-ptr+2]

i(lit, fetch, return_)
r('Heap')

l(']')

-- compile a ret opcode at the end of a quotation block, heap-ptr
-- become heap-ptr+1
-- stack: [start-heap-ptr+2 previous-compiler-status start-heap-ptr+1
-- start-heap-ptr+2]

i(lit, lit, call)
r('_ret')
r('comma:opcode')

-- compile lit and start-heap-ptr+2 to heap. start-heap-ptr+2 is the
-- entry point of this quotation. heap-ptr+1 (point to lit) is the
-- address to which we skip the quotation body and jump when the
-- quotation is nested in another quotation. After the jump the entry
-- point of this quotation (start-heap-ptr+2) is lit to stack

-- stack changes: [start-heap-ptr+2 previous-compiler-status
-- start-heap-ptr+1 start-heap-ptr+2] -> [start-heap-ptr+2
-- previous-compiler-status start-heap-ptr+1 start-heap-ptr+2
-- heap-ptr+1] -> [start-heap-ptr+2 previous-compiler-status
-- start-heap-ptr+1 heap-ptr+1 start-heap-ptr+2] -> [start-heap-ptr+2
-- previous-compiler-status start-heap-ptr+1 heap-ptr+1
-- start-heap-ptr+2 lit-ptr] -> compile lit, current heap ptr become
-- heap-ptr+2 -> [start-heap-ptr+2 previous-compiler-status
-- start-heap-ptr+1 heap-ptr+1 start-heap-ptr+2] -> compile
-- start-heap-ptr+2 to heap, current heap ptr become heap-ptr+3 ->
-- [start-heap-ptr+2 previous-compiler-status start-heap-ptr+1
-- heap-ptr+1]

-- heap from heap-ptr (end of quotation body):
-- | ret | lit | start-heap-ptr+2

i(lit, fetch, swap, lit)
r('Heap')
r('_lit')
call_at('comma:opcode')
call_at('comma')

-- store the skip pointer heap-ptr+1 at the beginning of the
-- quotation. Save previous compiler status back to compiler.
-- Now the quotation looks like:
-- | 1793 | addr to lit | quotation body | ret | lit | addr to entry |

-- stack changes: [start-heap-ptr+2 previous-compiler-status
-- start-heap-ptr+1 heap-ptr+1] -> [start-heap-ptr+2
-- previous-compiler-status heap-ptr+1 start-heap-ptr+1] ->
-- [start-heap-ptr+2 previous-compiler-status] ->> [start-heap-ptr+2]

i(swap, store, lit, store)
r('Compiler')

-- get current compiler status, if zero then return, keep quotation
-- entry point on stack, else clear quotation entry point
i(lit, fetch, zret)
r('Compiler')
i(drop, drop, return_)

-- Lightweight Control Structures

-- compiler macros, only used within a definition or quotation

-- repeat start a loop by put current heap on stack
-- stack changes: [] -> [loop-start]
l('repeat')
i(lit, fetch, return_)
r('Heap')

-- again close a loop by compile ( lit loop-start jump ) at the end of
-- a loop

-- stack changes: [loop-start] ->> [loop-start lit-ptr
-- comma:opcode-ptr] -> compile lit -> [loop-start] -> compile
-- loop-start -> []
l('again')
i(lit, lit, call)
r('_lit')
r('comma:opcode')
call_at('comma')
-- compile jump to jump back to loop-start
i(lit, lit, jump)
r('_jump')
r('comma:opcode')

-- 0; break the loop if data on top of stack is 0
l('0;')
i(lit, lit, jump)
r('_zret')
r('comma:opcode')

-- push and pop, move a value to/from the address stack

l('push')
i(lit, lit, jump)
r('_push')
r('comma:opcode')

l('pop')
i(lit, lit, jump)
r('_pop')
r('comma:opcode')

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
