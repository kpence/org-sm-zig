const std = @import("std");
const emacs = @import("emacs");
const config = @import("config");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    // stdout is for the actual output of your application, for example if you
    // are implementing gzip, then only the compressed bytes should be sent to
    // stdout, not any debugging messages.
    const stdout_file = std.io.getStdOut().writer();
    var bw = std.io.bufferedWriter(stdout_file);
    const stdout = bw.writer();

    const ArgCommandOpt = enum {
        SendGrade,
        Reveal,
        Default,
        Dismiss,
        Help,
        OpenEmacs,
    };

    const arg_command: ArgCommandOpt =
        if (args.len == 1)
        .Default
    else if (args.len == 2)
        if (std.mem.eql(u8, args[1], "r")) .Reveal else if (std.mem.eql(u8, args[1], "d")) .Dismiss else .Help
    else if (args.len == 3)
        if (std.mem.eql(u8, args[1], "g")) .SendGrade else .Help
    else
        .Help;

    // TODO parse flags passed in, one of them will be --debug-init
    var flags = struct {
        debug_init: bool,
    }{
        .debug_init = true,
    };

    const stderr_file = std.io.getStdErr();
    var prop_map = try config.readAndParseIniConfigFiles(allocator, stderr_file, &[_][]const u8{
        "/home/kpence/.smrc",
    }, .{
        .store_config_line_numbers = flags.debug_init,
    });
    defer prop_map.deinit();

    if (prop_map.map.get("debug_logging_level")) |debug_logging_level| {
        const value = std.fmt.parseInt(u8, debug_logging_level, 10) catch |err| {
            const stderr = stderr_file.writer();
            if (flags.debug_init) {
                const line_number = prop_map.line_number_map.?.get("debug_logging_level").?;
                try stderr.print("Fatal error: failed to parse valid number [acceptable range: 0-255] from config property `debug_logging_level`.\n" ++ "The config file being used is: {s}\n" ++ "At line {d}, `debug_logging_level` is set to: {s}\n", .{ prop_map.config_file_path, line_number, debug_logging_level });
            } else {
                try stderr.print("Fatal error: failed to parse valid number [acceptable range: 0-255] from config property `debug_logging_level`.\n" ++ "The config file being used is: {s}.\n" ++ "`debug_logging_level` is set to: `{s}`\n", .{ prop_map.config_file_path, debug_logging_level });
            }
            return err;
        };
        emacs.debug_logging_level = value;
    }

    if (prop_map.map.get("ssh_destination")) |ssh_destination| {
        emacs.ssh_destination = ssh_destination;
    }

    switch (arg_command) {
        .SendGrade => {
            // Validate the scorse
            if (args[2].len != 1 or args[2][0] < '1' or args[2][0] > '5') {
                // return error?
                return error.Error;
            } else {
                const grade = args[2][0] - '1';
                try emacs.submitGrade(allocator, grade);
            }
        },
        .Default => {
            const str = try emacs.getCurrentItemContent(allocator, false);
            defer allocator.free(str);
            try stdout.print("{s}\n", .{str});
        },
        .Help => {
            try stdout.print("TODO write full usage \n", .{});
            try stdout.print("For now: There's the following options: [sr] \n", .{});
        },
        .Reveal => {
            const str = try emacs.getCurrentItemContent(allocator, true);
            defer allocator.free(str);
            try stdout.print("{s}\n", .{str});
        },
        .Dismiss => {
            try emacs.dismissCurrentItem(allocator);
            try stdout.print("Dimissed item\n", .{});
        },
        .OpenEmacs => {
            // TODO
            std.debug.print("This hasn't been implemented yet!!!!!\n", .{});
            unreachable;
        },
    }

    try bw.flush(); // don't forget to flush!
}
