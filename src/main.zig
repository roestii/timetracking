const std = @import("std");
const c = @cImport(@cInclude("sqlite3.h"));

const Error = error{
    UnavailableCommand, 
    DatabaseError,
    DateParsingError
};

fn stepToComplete(stmt: *c.sqlite3_stmt) Error!void {
    while (true) {
        switch (c.sqlite3_step(stmt)) {
            c.SQLITE_ROW => continue,
            c.SQLITE_DONE => break,
            else => return Error.DatabaseError
        }
    }
}
 
fn fetchOne(stmt: *c.sqlite3_stmt) Error!u32 {
    const rc = c.sqlite3_step(stmt);
    switch (rc) {
        c.SQLITE_ROW => {
            const res = c.sqlite3_column_int(stmt, 0);
            try stepToComplete(stmt);
            return @intCast(res);
        },
        else => return Error.DatabaseError
    }
}
 
const Datetime = struct {
    second: u8,
    minute: u8,
    hour: u8,
    day: u8,
    month: u8,
    year: u16
};

fn parseTimestamp(timestamp: [*:0]const u8) Error!Datetime {
    // NOTE: default layout of the sqlite3 datetime function:
    // yyyy-mm-dd hh:MM:ss
    const year = std.fmt.parseInt(u16, timestamp[0..4], 10) catch return Error.DateParsingError;
    const month = std.fmt.parseInt(u8, timestamp[5..7], 10) catch return Error.DateParsingError;
    const day = std.fmt.parseInt(u8, timestamp[8..10], 10) catch return Error.DateParsingError;
    
    const hour = std.fmt.parseInt(u8, timestamp[11..13], 10) catch return Error.DateParsingError;
    const minute = std.fmt.parseInt(u8, timestamp[14..16], 10) catch return Error.DateParsingError;
    const second = std.fmt.parseInt(u8, timestamp[17..19], 10) catch return Error.DateParsingError;
    
    return Datetime{
        .second = second,
        .minute = minute,
        .hour = hour,
        .day = day,
        .month = month,
        .year = year
    };
}

pub fn main() !void {
    // var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    // defer arena.deinit();
    // const allocator = arena.allocator();
    
    var args = std.process.args();
    const res = args.skip();
    std.debug.assert(res);

    const command = args.next().?;
    const absolute_path = args.next().?;
    const open_flags = std.fs.File.OpenFlags{};
    try std.fs.accessAbsolute(absolute_path, open_flags);

    var db: ?*c.sqlite3 = null;
    var rc: c_int = c.sqlite3_open(absolute_path, &db);

    if (rc != 0) {
        std.debug.print("we got ourselves a situation here", .{});
    }
    
    switch (command[0]) {
        't' => {
            const time = std.time.timestamp();
            const new_raw = "insert into time values (?);";
            var stmt: ?*c.sqlite3_stmt = null;
            rc = c.sqlite3_prepare_v2(db, new_raw, new_raw.len, &stmt, null);

            if (rc != c.SQLITE_OK) {
                return Error.DatabaseError;
            }

            rc = c.sqlite3_bind_int64(stmt, 1, @intCast(time));
            if (rc != c.SQLITE_OK) {
                return Error.DatabaseError;
            }
            try stepToComplete(stmt.?);
            rc = c.sqlite3_finalize(stmt);
            if (rc != c.SQLITE_OK) {
                return Error.DatabaseError;
            }
        },
        'e' => {
            const raw = "select datetime(timestamp, 'unixepoch') from time;";
            var stmt: ?*c.sqlite3_stmt = null;
            rc = c.sqlite3_prepare_v2(db, raw, raw.len, &stmt, null);
            if (rc != c.SQLITE_OK) {
                return Error.DatabaseError;
            }

            const tstmp_len = comptime "yyyy-mm-dd hh:MM:ss".len;
            var start: ?[tstmp_len]u8 = null;
            const file = try std.fs.cwd().createFile("export.csv", std.fs.File.CreateFlags{});
            _ = try file.write("start,end\n");

            while (true) {
                switch (c.sqlite3_step(stmt)) {
                    c.SQLITE_ROW => { 
                        // TODO: Append to export
                        const timestamp: [*:0]const u8 = std.mem.span(c.sqlite3_column_text(stmt, 0));
                        if (start == null) {
                            start = timestamp[0..tstmp_len].*;
                        } else {
                            const buf_len = comptime tstmp_len * 2 + 2;
                            var buf: [buf_len]u8 = undefined;
                            const line = try std.fmt.bufPrint(
                                &buf,
                                "{s},{s}\n",
                                .{start.?, timestamp}
                            );
                            start = null;
                            _ = try file.write(line);
                        }
                    },
                    c.SQLITE_DONE => {
                        // TODO: Finish export
                        rc = c.sqlite3_finalize(stmt);
                        if (rc != c.SQLITE_OK) {
                            return Error.DatabaseError;
                        }
                        break;
                    },
                    else => return Error.DatabaseError
                }
            }
        },
        else => {
            return Error.UnavailableCommand;
        }
    }
}
