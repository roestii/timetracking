const std = @import("std");
const c = @cImport(@cInclude("sqlite3.h"));

const Error = error{
    UnavailableCommand, 
    DatabaseError
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

            while (true) {
                switch (c.sqlite3_step(stmt)) {
                    c.SQLITE_ROW => { 
                        // TODO: Append to export
                        const timestamp: [*:0]const u8 = std.mem.span(c.sqlite3_column_text(stmt, 0));
                        std.debug.print("{s}\n", .{timestamp});
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
