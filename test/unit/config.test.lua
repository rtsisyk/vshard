test_run = require('test_run').new()
vshard = require('vshard')
util = require('vshard.util')

--
-- Check sharding config sanity.
--
test_run:cmd("setopt delimiter ';'")
check_config = util.sanity_check_config
function check_error(func, ...)
	local status, err = pcall(func, ...)
	assert(not status)
	err = string.gsub(err, '.*/[a-z]+.lua.*[0-9]+: ', '')
	return err
end;
test_run:cmd("setopt delimiter ''");

-- Not array.
check_error(check_config, 100)
check_error(check_config, {[100] = {{ uri = 'uri', name = 'storage'}}})

-- Replicaset is not array.
check_error(check_config, {100})
check_error(check_config, {{[100] = { uri = 'uri', name = 'storage'}}})

server = {}
replicaset = {server}
cfg = {replicaset}

-- URI is not string.
check_error(check_config, cfg)
server.uri = 100
check_error(check_config, cfg)
server.uri = 'uri'

-- Name is not string.
check_error(check_config, cfg)
server.name = 100
check_error(check_config, cfg)
server.name = 'storage'

-- Master is not boolean.
server.master = 100
check_error(check_config, cfg)
server.master = true

-- Multiple masters.
server2 = {uri = 'uri2', name = 'storage2', master = true}
replicaset[2] = server2
check_error(check_config, cfg)
replicaset[2] = nil

-- URI duplicate in one replicaset.
server2 = {uri = 'uri', name = 'storage2'}
replicaset[2] = server2
check_error(check_config, cfg)
replicaset[2] = nil

-- URI duplicate in different replicasets.
replicaset2 = {{uri = 'uri', name = 'storage2'}}
cfg[2] = replicaset2
check_error(check_config, cfg)
cfg[2] = nil

-- Name duplicate in one replicaset.
server2 = {uri = 'uri2', name = 'storage'}
replicaset[2] = server2
check_error(check_config, cfg)
replicaset[2] = nil

-- Name duplicate in different replicasets.
replicaset2 = {{uri = 'uri2', name = 'storage'}}
cfg[2] = replicaset2
check_error(check_config, cfg)
cfg[2] = nil

--
-- Check storage initial configuration.
--
parse_config = vshard.storage.internal.parse_config
apply_config = vshard.storage.cfg

test_run:cmd("setopt delimiter ';'")
cfg = {
	{
		{uri = 'uri1', name = 'storage_1_b'},
		{uri = 'uri2', name = 'storage_1_a', master = true},
	},
	{
		{uri = 'uri3', name = 'storage_2_a'},
		{uri = 'uri4', name = 'storage_2_b', master = true},
	}
};
test_run:cmd("setopt delimiter ''");

replicaset, replica, to_discovery, new_self_replicasets = parse_config({}, cfg, 'storage_1_a')

replicaset
replica
to_discovery
new_self_replicasets

-- Error on unknown replica.
check_error(parse_config, {}, cfg, 'not_existing_name')

-- Error on no name.
check_error(apply_config, cfg, nil)

-- Error on forbidden options.
cfg.listen = 3313
check_error(apply_config, cfg, 'storage_1_a')
cfg.listen = nil
cfg.replication = {}
check_error(apply_config, cfg, 'storage_1_a')
cfg.replication = nil

-- Error on bad uri.
check_error(apply_config, {sharding = cfg}, 'storage_1_a')

--
-- Check storage reconfiguration.
--
existing_replicasets = {uuid2 = { master_uri = 'uri4'}}
cfg[3] = { {uri = 'uri5', name = 'storage_3_a', master = true} }
replicaset, replica, to_discovery, new_self_replicasets = parse_config(existing_replicasets, cfg, 'storage_1_a')
replicaset
replica
to_discovery
new_self_replicasets
