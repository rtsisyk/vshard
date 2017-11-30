test_run = require('test_run').new()
vshard = require('vshard')
fiber = require('fiber')

format = {}
format[1] = {name = 'id', type = 'unsigned'}
format[2] = {name = 'status', type = 'string', is_nullable = true}
_bucket = box.schema.create_space('_bucket', {format = format})
_ = _bucket:create_index('pk')
_ = _bucket:create_index('status', {parts = {{2, 'string'}}, unique = false})
_bucket:replace{1, vshard.consts.BUCKET.ACTIVE}
_bucket:replace{2, vshard.consts.BUCKET.RECEIVING}
_bucket:replace{3, vshard.consts.BUCKET.ACTIVE}
_bucket:replace{4, vshard.consts.BUCKET.SENT}
_bucket:replace{5, vshard.consts.BUCKET.GARBAGE}

format = {}
format[1] = {name = 'field1', type = 'unsigned'}
format[2] = {name = 'bucket_id', type = 'unsigned'}
s = box.schema.create_space('test', {format = format})
pk = s:create_index('pk')
sk = s:create_index('sk', {parts = {{2, 'unsigned'}}, unique = false})
s:replace{1, 1}
s:replace{2, 1}
s:replace{3, 2}
s:replace{4, 2}
s:replace{5, 100}
s:replace{6, 100}
s:replace{7, 4}
s:replace{8, 5}

s2 = box.schema.create_space('test2', {format = format})
pk2 = s2:create_index('pk')
sk2 = s2:create_index('sk2', {parts = {{2, 'unsigned'}}, unique = false})
s2:replace{1, 1}
s2:replace{3, 3}
-- Garbage bucket {200} is deleted in two parts: 1000 and 101.
for i = 7, 1107 do s:replace{i, 200} end
s2:replace{4, 200}
s2:replace{5, 100}
s2:replace{5, 300}
s2:replace{6, 4}
s2:replace{7, 5}

garbage_step = vshard.storage.internal.collect_garbage_step
control = {bucket_generation = 0, bucket_generation_collected = -1}

--
-- Test the following case:
-- 1) start garbage collection;
-- 2) deletion of a part of tuples makes long yield;
-- 3) during long yield some of not garbage buckets becames
--    garbage.
-- In such a case restart garbage collection.
--
control.bucket_generation_collected = -1
vshard.storage.internal.errinj.ERRINJ_BUCKET_PART_DELETE_DELAY = true
old_count = #s:select{}
f = fiber.create(function() garbage_step(control) end)
while old_count == #s:select{} do fiber.sleep(0.1) end
_bucket:delete{3}
control.bucket_generation = 1
vshard.storage.internal.errinj.ERRINJ_BUCKET_PART_DELETE_DELAY = false
while f:status() ~= 'dead' do fiber.sleep(0.1) end
-- Bucket {100} deleted.
sk:select{100}
-- Bucket {200} is not deleted - the step had been interrupted by
-- _bucket change.
#sk:select{200}
-- Space 's2' is not changed - the interrupt was on a space 's'.
#s2:select{}
control.bucket_generation_collected
_bucket:replace{3, vshard.consts.BUCKET.ACTIVE}

-- Restart garbage collection.
garbage_step(control)
control.bucket_generation_collected

--
-- Test _bucket generation change during garbage buckets search.
--
control.bucket_generation_collected = -1
control.bucket_generation = 1
vshard.storage.internal.errinj.ERRINJ_BUCKET_FIND_GARBAGE_DELAY = true
f = fiber.create(function() garbage_step(control) end)
_bucket:replace{4, vshard.consts.BUCKET.GARBAGE}
s:replace{5, 4}
s:replace{6, 4}
#s:select{}
vshard.storage.internal.errinj.ERRINJ_BUCKET_FIND_GARBAGE_DELAY = false
while f:status() ~= 'dead' do fiber.sleep(0.1) end
-- Nothing is deleted - _bucket:replace() has changed _bucket
-- generation during search of garbage buckets.
#s:select{}
_bucket:select{4}
-- Next step deletes garbage ok.
garbage_step(control)
#s:select{}
_bucket:delete{4}

--
-- Test WAL error during garbage bucket cleaning.
--
collect_f = vshard.storage.internal.collect_garbage_f
f = fiber.create(collect_f)

vshard.storage.internal.errinj.ERRINJ_BUCKET_PART_DELETE_DELAY = true
_bucket:replace{4, vshard.consts.BUCKET.SENT}
s:replace{5, 4}
s:replace{6, 4}
box_errinj = box.error.injection
box_errinj.set("ERRINJ_WAL_IO", true)
vshard.storage.internal.errinj.ERRINJ_BUCKET_PART_DELETE_DELAY = false
while not test_run:grep_log("default", "Error during garbage collection step") do fiber.sleep(0.1) end
s:select{}
_bucket:select{}
box_errinj.set("ERRINJ_WAL_IO", false)
while _bucket:get{4} ~= nil do fiber.sleep(0.1) end

f:cancel()

s2:drop()
s:drop()
_bucket:drop()