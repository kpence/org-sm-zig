const std = @import("std");
const testing = std.testing;

// TODO make a config file library which you will use for
// TODO the following code will be extracted out into one of my libraries

const ConfigError = error{
    InvalidConfigSyntax, // TODO print the line number where error was parsed?
    HashMapError,
    ReadConfigFiles,
};

pub const PropertyHashMap = struct {
    map: std.StringHashMap([]const u8),
    key_buffer: []u8,
    allocator: std.mem.Allocator,
    line_number_map: ?std.StringHashMap(usize),
    config_file_path: []const u8,

    pub fn init(
        allocator: std.mem.Allocator,
        key_buffer: []u8,
        config_file_path: []const u8,
        store_config_line_numbers: bool,
    ) PropertyHashMap {
        return .{
            .map = std.StringHashMap([]const u8).init(allocator),
            .line_number_map = if (store_config_line_numbers) std.StringHashMap(usize).init(allocator) else null,
            .key_buffer = key_buffer,
            .allocator = allocator,
            .config_file_path = config_file_path,
        };
    }

    pub fn deinit(self: *PropertyHashMap) void {
        self.map.deinit();
        if (self.line_number_map != null)
            self.line_number_map.?.deinit();
        self.allocator.free(self.key_buffer);
    }
};

pub const ParseConfigOptions = struct {
    store_config_line_numbers: bool,
};

pub const ReadConfigFilesResult = struct {
    file_bytes: []u8,
    config_file_path: []const u8,
};

pub fn readAndParseIniConfigFiles(
    allocator: std.mem.Allocator,
    stderr_file: std.fs.File,
    absolute_paths: []const []const u8,
    options: ParseConfigOptions,
) ConfigError!PropertyHashMap {
    const new_line_char = '\n';
    const comment_char = '#';
    const key_value_delimiter_char = '=';

    // [key]=[value] (No ws allowed in key or value, ws in edge is ignored)
    // TODO [key]="[value]" (ws is allowed in string)
    const ParseStage = enum {
        ws_before_key,
        key,
        ws_after_key,
        ws_before_val,
        val,
        ws_after_val,
        skip_until_newline,
    };

    const read_files_result = readConfigFiles(allocator, stderr_file, absolute_paths) catch return ConfigError.ReadConfigFiles;
    const file_bytes = read_files_result.file_bytes;
    var prop_map = PropertyHashMap.init(allocator, file_bytes, read_files_result.config_file_path, options.store_config_line_numbers);

    var line_number: usize = 0;
    var key_start: ?usize = null;
    var key_end: ?usize = null;
    var val_start: ?usize = null;

    var stage = ParseStage.ws_before_key;

    for (file_bytes) |char, i| {
        if (char == new_line_char) line_number += 1;
        switch (stage) {
            .ws_before_key => switch (char) {
                comment_char => stage = .skip_until_newline,
                key_value_delimiter_char => return ConfigError.InvalidConfigSyntax,
                ' ', '\t', new_line_char => {},
                else => {
                    std.debug.print("nocheckin key start {d}\n", .{i});
                    key_start = i;
                    stage = .key;
                },
            },
            .key => switch (char) {
                comment_char, new_line_char => return ConfigError.InvalidConfigSyntax,
                key_value_delimiter_char => {
                    std.debug.print("nocheckin key end {d}\n", .{i});
                    key_end = i;
                    stage = .ws_before_val;
                },
                ' ', '\t' => {
                    std.debug.print("nocheckin key end {d}\n", .{i});
                    key_end = i;
                    stage = .ws_after_key;
                },
                else => {},
            },
            .ws_after_key => switch (char) {
                comment_char, new_line_char => return ConfigError.InvalidConfigSyntax,
                key_value_delimiter_char => {
                    std.debug.print("nocheckin {d}\n", .{i});
                    key_end = i;
                    stage = .ws_before_val;
                },
                ' ', '\t' => {},
                else => return ConfigError.InvalidConfigSyntax,
            },
            .ws_before_val => switch (char) {
                ' ', '\t' => {},
                new_line_char, comment_char => return ConfigError.InvalidConfigSyntax,
                else => {
                    std.debug.print("nocheckin {d}\n", .{i});
                    val_start = i;
                    stage = .val;
                },
            },
            .val => switch (char) {
                key_value_delimiter_char => return ConfigError.InvalidConfigSyntax,
                new_line_char, ' ', '\t', comment_char => {
                    std.debug.print("nocheckin END {d}\n", .{i});
                    const val_end = i;

                    const key = file_bytes[key_start.?..key_end.?];
                    const value = file_bytes[val_start.?..val_end];
                    prop_map.map.put(key, value) catch |err| {
                        std.debug.print("config: Hash map error is {?}\n", .{err});
                        return ConfigError.HashMapError;
                    };

                    if (options.store_config_line_numbers) {
                        prop_map.line_number_map.?.put(key, line_number) catch |err| {
                            std.debug.print("config: Hash map error occured when storing line numbers for config properties for debugging. The hash map error is {?}\n", .{err});
                            return ConfigError.HashMapError;
                        };
                    }

                    val_start = null;
                    key_end = null;
                    key_start = null;

                    stage = switch (char) {
                        ' ', '\t' => .ws_after_val,
                        new_line_char => .ws_before_key,
                        comment_char => .skip_until_newline,
                        else => unreachable,
                    };
                },
                else => {},
            },
            else => {},
        }
    }
    return prop_map;
}

pub fn readConfigFiles(
    allocator: std.mem.Allocator,
    stderr_file: std.fs.File,
    absolute_paths: []const []const u8,
) !ReadConfigFilesResult {
    const config_file_max_bytes = 1024 * 1024; // TODO figure this out
    const stderr = stderr_file.writer();

    // TODO explain that the order of paths arg matters
    var first_valid_path: ?[]const u8 = null;
    for (absolute_paths) |path| {
        const file_exists = if (std.fs.accessAbsolute(path, .{})) true else |err| err == std.os.AccessError.FileNotFound;
        if (file_exists) {
            if (first_valid_path != null) {
                try stderr.print("Warning: config file in `{s}` will not be read. Instead `{s}` will be read, because it was found first.\n", .{ path, first_valid_path.? });
            } else {
                first_valid_path = path;
            }
        }
    }

    if (first_valid_path == null) {
        return error.NoConfigFileFound;
    }

    const config_file_path = first_valid_path.?;

    const file = try std.fs.cwd().openFile(config_file_path, .{});
    defer file.close();

    return .{
        .config_file_path = config_file_path,
        .file_bytes = try file.readToEndAlloc(allocator, config_file_max_bytes),
    };
}

test "test config on .smrc" {
    const stderr_file = std.io.getStdErr();
    var prop_map = try readAndParseIniConfigFiles(testing.allocator, stderr_file, &[_][]const u8{
        "/home/kpence/.smrc",
    });
    defer prop_map.deinit();
    std.debug.print("Number of entries: {any}\n", .{prop_map.map.count()});
    const ssh_destination = prop_map.map.get("ssh_destination");
    try testing.expect(ssh_destination != null);
    std.debug.print("Result of parse: {s}\n", .{ssh_destination.?});
    try testing.expect(std.mem.eql(u8, ssh_destination.?, "foobar"));
}
