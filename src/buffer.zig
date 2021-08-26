const std = @import("std");
const raw = @import("internal/raw.zig");
const internal = @import("internal/internal.zig");
const log = std.log.scoped(.git);
const old_version: bool = @import("build_options").old_version;
const git = @import("git.zig");

/// A data buffer for exporting data from libgit2
pub const Buf = extern struct {
    ptr: ?[*]u8 = null,
    asize: usize = 0,
    size: usize = 0,

    pub fn fromSlice(slice: []u8) Buf {
        return .{ .ptr = slice.ptr, .size = slice.len };
    }

    pub fn toSlice(self: Buf) []const u8 {
        if (self.size == 0) return &[_]u8{};
        return self.ptr.?[0..self.size];
    }

    /// Free the memory referred to by the `Buf`
    ///
    /// *Note*: This will not free the memory if it looks like it was not allocated by libgit2, but it will clear the buffer back
    /// to the empty state.
    pub fn deinit(self: *Buf) void {
        log.debug("Buf.deinit called", .{});

        raw.git_buf_dispose(internal.toC(self));

        log.debug("Buf freed successfully", .{});
    }

    /// Resize the buffer allocation to make more space.
    ///
    /// If the buffer refers to memory that was not allocated by libgit2, then `ptr` will be replaced with a newly allocated block
    /// of data.  Be careful so that memory allocated by the caller is not lost.
    /// If you pass `target_size` = 0 and the memory is not allocated by libgit2, this will allocate a new buffer of size `size`
    /// and copy the external data into it.
    ///
    /// Currently, this will never shrink a buffer, only expand it.
    ///
    /// If the allocation fails, this will return an error and the buffer will be marked as invalid for future operations,
    /// invaliding the contents.
    pub fn grow(self: *Buf, target_size: usize) !void {
        log.debug("Buf.grow called, target_size={}", .{target_size});

        try internal.wrapCall("git_buf_grow", .{ internal.toC(self), target_size });

        log.debug("Buf grown successfully", .{});
    }

    pub fn isBinary(self: Buf) bool {
        log.debug("Buf.isBinary called", .{});

        const ret = raw.git_buf_is_binary(internal.toC(&self)) == 1;

        log.debug("Buf is binary: {}", .{ret});

        return ret;
    }

    pub fn containsNull(self: Buf) bool {
        log.debug("Buf.isBinary called", .{});

        const ret = std.mem.indexOfScalar(u8, self.toSlice(), 0) != null;

        log.debug("Buf contains null: {}", .{ret});

        return ret;
    }

    test {
        try std.testing.expectEqual(@sizeOf(raw.git_buf), @sizeOf(Buf));
        try std.testing.expectEqual(@bitSizeOf(raw.git_buf), @bitSizeOf(Buf));
    }

    comptime {
        std.testing.refAllDecls(@This());
    }
};

comptime {
    std.testing.refAllDecls(@This());
}