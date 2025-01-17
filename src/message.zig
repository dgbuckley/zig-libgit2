const std = @import("std");
const c = @import("internal/c.zig");
const internal = @import("internal/internal.zig");
const log = std.log.scoped(.git);

const git = @import("git.zig");

/// Represents an array of git message trailers.
pub const MessageTrailerArray = extern struct {
    trailers: [*]MessageTrailer,
    count: usize,

    /// private
    _trailer_block: *u8,

    pub fn getTrailers(self: MessageTrailerArray) []MessageTrailer {
        return self.trailers[0..self.count];
    }

    pub fn deinit(self: *MessageTrailerArray) void {
        log.debug("MessageTrailerArray.deinit called", .{});

        c.git_message_trailer_array_free(@ptrCast(*c.git_message_trailer_array, self));

        log.debug("message trailer array freed successfully", .{});
    }

    /// Represents a single git message trailer.
    pub const MessageTrailer = extern struct {
        key: [*:0]const u8,
        value: [*:0]const u8,

        comptime {
            std.testing.refAllDecls(@This());
        }
    };

    comptime {
        std.testing.refAllDecls(@This());
    }
};

comptime {
    std.testing.refAllDecls(@This());
}
