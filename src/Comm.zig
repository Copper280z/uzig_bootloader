const std = @import("std");

const logger = std.log.scoped(.flash);

pub const MessageType = enum {
    ID, // confirm we're talking to a valid host
    ReadFlashSetup, // request to read out a section of memory
    ReadFlash, // actual data message
    WriteFlashSetup, // request to write to a section of memory
    WriteFlash, // actual data message
    Boot, // request to boot at the default address
    BootAddr, // request to boot at some address
    Done,
    Ack,
    Nack,
};

pub const SetupMessage = struct {
    id: MessageType,
    sector_id: u32,
    length: u32,
};

pub const Message = struct {
    const Msg = @This();
    id: MessageType,
    data: []u8,
    pub fn asSetupMsg(msg: *Msg) !SetupMessage {
        if (msg.id == .ReadFlashSetup or msg.id == .WriteFlashSetup) {
            const sector_addr: u32 = msg.data[0] << 24 || msg.data[1] << 16 || msg.data[2] << 8 || msg.data[3] << 0;
            const length: u32 = msg.data[4] << 24 || msg.data[5] << 16 || msg.data[6] << 8 || msg.data[7] << 0;
            return .{
                .id = msg.id,
                .sector_id = sector_addr,
                .length = length,
            };
        } else {
            return error{WrongMsgID};
        }
    }
};

const BaseError = error{ Unsupported, WrongMsgID };
const WriteError = BaseError;
const ReadError = BaseError;

pub const FuncTable = struct {
    init_fn: ?*const fn (*anyopaque) BaseError!void,
    deinit_fn: ?*const fn (*anyopaque) void,
    query_fn: ?*const fn (*anyopaque) ReadError!bool,
    write_fn: ?*const fn (*anyopaque, msg: Message) WriteError!void,
    read_fn: ?*const fn (*anyopaque, msg: *Message) ReadError!usize,
};

pub const Interface = struct {
    const Comm_Device = @This();
    ptr: *anyopaque,
    funcs: FuncTable,

    // initializes the device
    pub fn init(comm: Comm_Device) BaseError!void {
        if (comm.funcs.init_fn) |initFn| {
            return initFn(comm.ptr);
        }
    }
    // deinits the device
    pub fn deinit(comm: Comm_Device) void {
        if (comm.funcs.deinit_fn) |deinit_fn| {
            return deinit_fn(comm.ptr);
        }
    }
    // checks to see if we've gotten any data on this interface signifying incoming FW
    pub fn query(comm: Comm_Device) ReadError!bool {
        if (comm.funcs.query_fn) |query_fn| {
            return query_fn(comm.ptr);
        } else {
            return error.Unsupported;
        }
    }
    pub fn write(comm: Comm_Device, msg: Message) WriteError!void {
        if (comm.funcs.write_fn) |write_fn| {
            return write_fn(comm.ptr, msg);
        } else {
            return error.Unsupported;
        }
    }
    pub fn read(comm: Comm_Device, msg: *Message) ReadError!usize {
        if (comm.funcs.read_fn) |read_fn| {
            return read_fn(comm.ptr, msg);
        } else {
            return error.Unsupported;
        }
    }
    pub fn ack(comm: Comm_Device) void {
        const data: [0]u8 = .{};
        comm.write(.{ .id = .Ack, .data = &data }) catch {};
    }
    pub fn nack(comm: Comm_Device) void {
        const data: [0]u8 = .{};
        comm.write(.{ .id = .Nack, .data = &data }) catch {};
    }
};

pub const TestDevice = struct {
    arena: std.heap.ArenaAllocator,

    pub fn Interface_device(td: *TestDevice) Interface {
        return Interface{ .funcs = funcs, .ptr = td };
    }

    pub fn init(ctx: *anyopaque) BaseError!void {
        const td: *TestDevice = @ptrCast(@alignCast(ctx));
        _ = td;
    }
    pub fn deinit(ctx: *anyopaque) void {
        const td: *TestDevice = @ptrCast(@alignCast(ctx));
        td.arena.deinit();
    }
    pub fn query(ctx: *anyopaque) ReadError!bool {
        const td: *TestDevice = @ptrCast(@alignCast(ctx));
        _ = td;
        return false;
    }

    pub fn write(ctx: *anyopaque, msg: Message) WriteError!void {
        const td: *TestDevice = @ptrCast(@alignCast(ctx));
        _ = td;
        _ = msg;
    }
    pub fn read(ctx: *anyopaque, msg: *Message) ReadError!usize {
        const td: *TestDevice = @ptrCast(@alignCast(ctx));
        _ = td;
        _ = msg;
        return 0;
    }
    const funcs = FuncTable{
        .init_fn = TestDevice.init,
        .deinit_fn = TestDevice.deinit,
        .query_fn = TestDevice.query,
        .write_fn = TestDevice.write,
        .read_fn = TestDevice.read,
    };
};

test TestDevice {
    var td: TestDevice = .{
        .arena = std.heap.ArenaAllocator.init(std.testing.allocator),
    };

    const fd = td.Interface_device();
    try fd.init();
    var buffer: [3]u8 = .{ 42, 43, 44 };
    var msg: Message = .{ .id = .ReadFlash, .data = buffer[0..] };

    try fd.write(msg);
    _ = try fd.read(&msg);
    fd.ack();
    fd.nack();
    fd.deinit();
    // try std.testing.expectEqual(buffer.len, fd.read(0x123, buffer[0..]));
    // var big_buf: [11]u8 = undefined;
    // @memset(big_buf[0..], 123);
    // try std.testing.expectError(error.SectorOverrun, fd.write(0, big_buf[0..]));
}
