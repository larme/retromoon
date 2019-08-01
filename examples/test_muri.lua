local NgaVM = require('nga')
local Muri = require('muri')

local nga = NgaVM{addr_start=0}
local muri = Muri{
  image_size = nga.conf.image_size,
  addr_start = nga.conf.addr_start,
}

local src = muri:load_file('examples/rx.muri')
local ast = muri:parse_source(src)
muri:pass1(ast)
muri:pass2(ast)
nga:dump_image('images/test_muri.txt', muri.state.target)
