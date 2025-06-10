const std = @import("std");
const microzig = @import("microzig");
const builtin = @import("builtin");
const itm = @import("itm.zig");
const bootloader = @import("bootloader.zig");
const bsp = microzig.board;
const cpu = microzig.cpu;

const logger = std.log.scoped(.main);

const bl = bootloader.Bootloader(.{}, .{});

const Handler = microzig.interrupt.Handler;

pub fn panic(message: []const u8, _: ?*std.builtin.StackTrace, _: ?usize) noreturn {
    // put whatever you want here
    bsp.init_uart();
    for (message) |chr| {
        bsp.tx(chr);
    }
    bsp.tx('\r');
    bsp.tx('\n');
    @breakpoint();
    while (true) {}
}

fn HardFault() callconv(.C) void {
    @panic("We got a hard fault!");
}

pub const microzig_options: microzig.Options = .{ //
    .interrupts = .{
        .HardFault = Handler{ .c = &HardFault },
    },
    .logFn = bsp.log,
};

pub fn main() !void {
    bsp.init_rcc();
    itm.enable_itm(84000000, 2000000);

    // check to see if we should boot or wait for firmware

    // deinit everything

    // jump to app
}
