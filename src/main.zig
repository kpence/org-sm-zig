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
    }

    try bw.flush(); // don't forget to flush!
}
