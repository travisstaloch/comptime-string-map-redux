This is a revision of std.ComptimeStringMap()

Differences:
* returns a regular struct with known field types and an init() method
* adds a `getPartial(str)` method supporting 'starts with' queries
* adds an `initRuntime(kvs_list, allocator)` method which accepts an allocator

Advantages:
* easier to understand for users and tooling such as zls
* becomes usable with runtime data
* removing `kvs_list` from type parameters makes the type name much shorter and makes it possible reuse the type with different `kvs_list`s.