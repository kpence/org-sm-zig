const std = @import("std");
const testing = std.testing;

// TODO make a config file library which you will use for
// TODO the following code will be extracted out into one of my libraries

const ConfigError = error{
    InvalidConfigSyntax, // TODO print the line number where error was parsed?
    HashMapError,
    ReadConfigFiles,
};

pub fn readAndParseIniConfigFiles(
    allocator: std.mem.Allocator,
    stderr_file: std.fs.File,
    absolute_paths: []const []const u8,
) ConfigError!std.StringHashMap([]const u8) {
    const file_bytes = readConfigFiles(allocator, stderr_file, absolute_paths) catch return ConfigError.ReadConfigFiles;
    defer allocator.free(file_bytes);
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

    var map = std.StringHashMap([]const u8).init(allocator);

    var key_start: ?usize = null;
    var key_end: ?usize = null;
    var val_start: ?usize = null;

    var stage = ParseStage.ws_before_key;
    for (file_bytes) |char, i| switch (stage) {
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

                map.put(file_bytes[key_start.?..key_end.?], file_bytes[val_start.?..val_end]) catch |err| {
                    std.debug.print("config: Hash map error is {?}\n", .{err});
                    return ConfigError.HashMapError;
                };

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
    };
    return map;
}

pub fn readConfigFiles(
    allocator: std.mem.Allocator,
    stderr_file: std.fs.File,
    absolute_paths: []const []const u8,
) ![]u8 {
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

    const file = try std.fs.cwd().openFile(first_valid_path.?, .{});
    defer file.close();

    return file.readToEndAlloc(allocator, config_file_max_bytes);
}

test "test config on .smrc" {
    const stderr_file = std.io.getStdErr();
    var map = try readAndParseIniConfigFiles(testing.allocator, stderr_file, &[_][]const u8{
        "/home/kpence/.smrc",
    });
    defer map.deinit();
    std.debug.print("Number of entries: {any}\n", .{map.count()});
    const ssh_destination = map.get("ssh_destination");
    try testing.expect(ssh_destination != null);
    std.debug.print("Result of parse: {s}\n", .{ssh_destination.?});
    try testing.expect(std.mem.eql(u8, ssh_destination.?, "foobar"));
}
