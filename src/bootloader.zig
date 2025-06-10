const std = @import("std");
const Comm = @import("Comm.zig");
const Flash = @import("flash.zig");

const logger = std.log.scoped(.bootloader);

// list of communication interfaces
pub fn Bootloader(comms: []Comm.Interface, flash: Flash.Flash) type {
    return struct {
        const BL = @This();
        boot_addr: u32,
        active_interface: ?*Comm.Interface,
        allocator: std.mem.Allocator,
        pub fn Init(alloc: std.mem.Allocator, boot_addr: u32) BL {
            for (comms) |interface| {
                interface.init();
            }
            flash.init();
            // maybe start up systick or something so we can track time?
            return .{ .boot_addr = boot_addr, .allocator = alloc };
        }
        fn queryInterfaces(bl: *BL) void {
            var poll = true;
            while (poll) {
                for (comms) |*interface| {
                    if (interface.query()) {
                        poll = false;
                        bl.active_interface = interface;
                        break;
                    }
                }
                // check for timeout here
            }
        }

        // returns number of bytes actually read from the wire
        fn recvSector(buffer: []u8, comm: *Comm.Interface, setup: Comm.SetupMessage) u32 {
            var bytes_read = 0;
            var comm_buffer: [1024]u8 = undefined; // 1024 is arbitrary
            @memset(&comm_buffer, 0);
            var msg: Comm.Message = .{
                .data = comm_buffer,
                .id = .WriteFlash,
            };
            const bytes_to_read = @min(buffer.len, setup.length);
            while (bytes_read < bytes_to_read) {
                const bytes = comm.Read(&msg);
                if (msg.id == .WriteFlash) {
                    @memcpy(buffer[bytes_read..], msg.data[0..bytes]);
                    bytes_read += bytes;
                    if (msg.id == .Done) {
                        break;
                    }
                }
            }
        }

        pub fn writeFlash(bl: *BL, comm: *Comm.Interface, setup: Comm.SetupMessage) !void {
            const sector_size = flash.sectorSize(setup.sector_id);
            const buffer = try bl.allocator.alloc(u8, sector_size);
            defer bl.allocator.free(buffer);
            bl.recvSector(buffer, comm, setup);
            try flash.enableWrite();
            try flash.write(setup.sector_id, buffer);
        }

        pub fn pollLoop(bl: *BL) !void { // noreturn?
            bl.queryInterfaces();
            var comm: *Comm.Interface = undefined;
            if (bl.active_interface) |interface| {
                comm = interface;
            } else {
                return;
            }
            var comm_buffer: [64]u8 = undefined;
            @memset(&comm_buffer, 0);
            var msg: Comm.Message = .{
                .data = comm_buffer,
                .id = .Done,
            };
            while (true) {
                const bytes = try comm.read(&msg);
                _ = bytes;
                switch (msg.id) {
                    .ID => {
                        try comm.ack();
                    },
                    .ReadFlashSetup => {
                        try comm.nack();
                    },
                    .WriteFlashSetup => {
                        const setup_msg = msg.asSetupMsg() catch continue;
                        bl.writeFlash(comm, setup_msg);
                    },
                    .Boot => {
                        try comm.nack();
                    },
                    .BootAddr => {
                        try comm.nack();
                    },
                    else => {},
                }
            }
            // if noreturn then we jump to reset handler here
        }
    };
}
