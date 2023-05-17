const std = @import("std");
const testing = std.testing;

// Config properties (These will be overwritten by config)
pub var debug_logging_level: u8 = 1;
pub var ssh_destination: ?[]const u8 = null;

pub const get_buffer_string_cmd = "(with-current-buffer (window-buffer (selected-window)) (substring-no-properties (buffer-string)))";
pub const dismiss_item_cmd = "(org-todo 'done)";

pub fn call_interactively(comptime cmd: []const u8) []const u8 {
    return "(call-interactively '" ++ cmd ++ ")";
}
const node_extract_cmd = call_interactively("org-sm-node-extract");
const node_generate_cloze_cmd = call_interactively("org-sm-node-generate-cloze");
const goto_current_cmd = call_interactively("org-sm-goto-current");
const node_export_at_point_interactive_cmd = call_interactively("org-sm-node-export-at-point-interactive");
const read_point_goto_cmd = call_interactively("org-sm-read-point-goto");
const read_point_set_cmd = call_interactively("org-sm-read-point-set");
const node_set_priority_at_point_cmd = call_interactively("org-sm-node-set-priority-at-point");
const node_postpone_cmd = call_interactively("org-sm-node-postpone");
const goto_next_cmd_grade_0 = "(org-sm-goto-next 0)";
const goto_next_cmd_grade_1 = "(org-sm-goto-next 1)";
const goto_next_cmd_grade_2 = "(org-sm-goto-next 2)";
const goto_next_cmd_grade_3 = "(org-sm-goto-next 3)";
const goto_next_cmd_grade_4 = "(org-sm-goto-next 4)";

pub fn evalRemoteEmacsExprs(
    allocator: std.mem.Allocator,
    lisp_exprs: []const []const u8,
) ![]u8 {
    const cmd_start = "emacsclient --eval \" (progn ";
    const separator = " ";
    const cmd_end = ")\"";
    const copy = std.mem.copy;

    const total_len = blk: {
        var sum: usize = lisp_exprs.len - 1;
        for (lisp_exprs) |slice| sum += slice.len;
        sum += comptime cmd_start.len + cmd_end.len + 1;
        break :blk sum;
    };

    const buf = try allocator.alloc(u8, total_len);
    defer allocator.free(buf);

    // Concatenate lisp commands into command string
    copy(u8, buf, cmd_start);
    var buf_index: usize = cmd_start.len;
    copy(u8, buf[buf_index..], lisp_exprs[0]);
    buf_index += lisp_exprs[0].len;
    for (lisp_exprs[1..]) |slice| {
        copy(u8, buf[buf_index..], separator);
        buf_index += separator.len;
        copy(u8, buf[buf_index..], slice);
        buf_index += slice.len;
    }
    copy(u8, buf[buf_index..], cmd_end);

    const ssh_cmd = buf;

    if (debug_logging_level >= 2)
        std.debug.print("ssh_cmd: {s}\n", .{ssh_cmd});

    return execAndGetStdout(
        allocator,
        &[_][]const u8{ "ssh", ssh_destination.?, ssh_cmd },
    );
}

pub fn evalRemoteEmacsExpr(
    allocator: std.mem.Allocator,
    comptime lisp_expr: []const u8,
) ![]u8 {
    const ssh_cmd = "emacsclient --eval \"" ++ lisp_expr ++ "\"";
    return execAndGetStdout(
        allocator,
        &[_][]const u8{ "ssh", ssh_destination.?, ssh_cmd },
    );
}

const ExecError = error{
    FailureExitCodeFromRemoteExec,
};

pub fn execAndGetStdout(
    allocator: std.mem.Allocator,
    argv: []const []const u8,
) ![]u8 {
    const failure_exit_code = 255;

    const res = try std.ChildProcess.exec(.{
        .allocator = allocator,
        .argv = argv,
        .max_output_bytes = 2048 * 1024, // TODO decide an appropriate amount
    });
    defer allocator.free(res.stderr);
    defer allocator.free(res.stdout);

    const exit_code = switch (res.term) {
        .Exited => |exit_code| brk: {
            if (debug_logging_level >= 3)
                std.debug.print("exit code from remote exec: {d}\n", .{exit_code});
            break :brk exit_code;
        },
        else => unreachable,
    };

    if (debug_logging_level >= 1 and res.stderr.len > 0)
        std.debug.print("stderr from remote exec: {s}\n", .{res.stderr});

    if (exit_code == failure_exit_code) return ExecError.FailureExitCodeFromRemoteExec;

    const buf = try allocator.alloc(u8, res.stdout.len);
    errdefer allocator.free(buf);
    _ = std.mem.replace(u8, res.stdout, "\\n", "\n", buf);

    return buf;
}

const StringError = error{
    SubstringNotFound,
};

fn findFirstOccurence(str: []const u8, needle: []const u8, start_index: usize) !usize {
    var match_index = @as(usize, 0);
    for (str[start_index..]) |char, i| {
        if (char == needle[match_index]) {
            match_index += 1;
            if (match_index == needle.len) {
                return start_index + i - needle.len + 1;
            }
        } else {
            match_index = 0;
        }
    }

    if (debug_logging_level >= 1)
        std.debug.print("findFirstOccurence, needle = `{s}`, str = `{s}`\n", .{ needle, str });

    return StringError.SubstringNotFound;
}

fn replaceClozeDeletion(
    allocator: std.mem.Allocator,
    item_content: []const u8,
    show_answer: bool,
) ![]const u8 {
    const cloze_start = try findFirstOccurence(item_content, "[[cloze:", 0);
    const answer_start = cloze_start + "[[cloze:".len;
    const answer_end = try findFirstOccurence(item_content, "][", answer_start);
    const prompt_start = answer_end + "][".len;
    const prompt_end = try findFirstOccurence(item_content, "]]", prompt_start);
    const cloze_end = prompt_end + "]]".len;

    const buf = if (show_answer) try std.mem.concat(allocator, u8, &[_][]const u8{
        item_content[0..cloze_start],
        "\x1B[33m",
        item_content[answer_start..answer_end],
        "\x1B[97m",
        item_content[cloze_end..],
    }) else try std.mem.concat(allocator, u8, &[_][]const u8{
        item_content[0..cloze_start],
        "\x1B[33m",
        item_content[prompt_start..prompt_end],
        "\x1B[97m",
        item_content[cloze_end..],
    });

    return buf;
}

pub fn submitGrade(allocator: std.mem.Allocator, score: u8) !void {
    std.debug.assert(score >= 0 and score <= 4);
    const cmd = switch (score) {
        0 => goto_next_cmd_grade_0,
        1 => goto_next_cmd_grade_1,
        2 => goto_next_cmd_grade_2,
        3 => goto_next_cmd_grade_3,
        4 => goto_next_cmd_grade_4,
        else => unreachable,
    };
    const buf = try evalRemoteEmacsExprs(
        allocator,
        &[_][]const u8{cmd},
    );
    defer allocator.free(buf);
}

pub fn dismissCurrentItem(allocator: std.mem.Allocator) !void {
    const buf = try evalRemoteEmacsExprs(
        allocator,
        &[_][]const u8{ goto_current_cmd, dismiss_item_cmd },
    );
    defer allocator.free(buf);
}

pub fn getCurrentItemContent(allocator: std.mem.Allocator, show_answer: bool) ![]const u8 {
    const buf = try evalRemoteEmacsExprs(
        allocator,
        &[_][]const u8{ goto_current_cmd, get_buffer_string_cmd },
    );
    defer allocator.free(buf);
    return replaceClozeDeletion(allocator, buf, show_answer);
}

// TODO make a program that lets you enter into emacs using ssh
// Somehow make it so you can exit out and back into your shell with a command
// Somehow make emacs print out that information of how to do that in the window

// TODO make it so if the emacsclient command takes too long, it times out and then will restart emacs

test "goToCurrentFlashCard" {
    const answer = try getCurrentItemContent(testing.allocator, true);
    defer testing.allocator.free(answer);
    std.debug.print("result: {s}\n", .{answer});

    const no_answer = try getCurrentItemContent(testing.allocator, false);
    defer testing.allocator.free(no_answer);
    std.debug.print("result: {s}\n", .{no_answer});

    //const after_score = try submitGrade(testing.allocator, 3);
    //std.debug.print("final result: {s}\n", .{after_score});
}
