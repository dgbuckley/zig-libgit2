const std = @import("std");
const raw = @import("internal/raw.zig");
const internal = @import("internal/internal.zig");
const log = std.log.scoped(.git);

const git = @import("git.zig");

/// Filters are applied in one of two directions: smudging - which is exporting a file from the Git object database to the working
/// directory, and cleaning - which is importing a file from the working directory to the Git object database. These values
/// control which direction of change is being applied.
pub const FilterMode = enum(c_uint) {
    TO_WORKTREE = 0,
    TO_ODB = 1,

    pub const SMUDGE = FilterMode.TO_WORKTREE;
    pub const CLEAN = FilterMode.TO_ODB;
};

pub const FilterFlags = packed struct {
    /// Don't error for `safecrlf` violations, allow them to continue.
    ALLOW_UNSAFE: bool = false,

    /// Don't load `/etc/gitattributes` (or the system equivalent)
    NO_SYSTEM_ATTRIBUTES: bool = false,

    /// Load attributes from `.gitattributes` in the root of HEAD
    ATTRIBUTES_FROM_HEAD: bool = false,

    /// Load attributes from `.gitattributes` in a given commit. This can only be specified in a `FilterOptions`
    ATTRIBUTES_FROM_COMMIT: bool = false,

    z_padding: u28 = 0,

    pub fn format(
        value: FilterFlags,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        return internal.formatWithoutFields(
            value,
            options,
            writer,
            &.{"z_padding"},
        );
    }

    test {
        try std.testing.expectEqual(@sizeOf(raw.git_filter_flag_t), @sizeOf(FilterFlags));
        try std.testing.expectEqual(@bitSizeOf(raw.git_filter_flag_t), @bitSizeOf(FilterFlags));
    }

    comptime {
        std.testing.refAllDecls(@This());
    }
};

pub const FilterOptions = struct {
    flags: FilterFlags = .{},

    /// The commit to load attributes from, when `FilterFlags.ATTRIBUTES_FROM_COMMIT` is specified.
    commit_id: ?*git.Oid = null,

    pub fn toC(self: FilterOptions) raw.git_filter_options {
        return .{
            .version = raw.GIT_FILTER_OPTIONS_VERSION,
            .flags = @bitCast(u32, self.flags),
            .commit_id = if (self.commit_id) |commit| internal.toC(commit) else null,
        };
    }
};

/// A filter that can transform file data
///
/// This represents a filter that can be used to transform or even replace file data. 
/// Libgit2 includes one built in filter and it is possible to write your own (see git2/sys/filter.h for information on that).
///
/// The two builtin filters are:
///
/// - "crlf" which uses the complex rules with the "text", "eol", and "crlf" file attributes to decide how to convert between LF
///   and CRLF line endings
/// - "ident" which replaces "$Id$" in a blob with "$Id: <blob OID>$" upon checkout and replaced "$Id: <anything>$" with "$Id$" on
///   checkin.
pub const Filter = opaque {
    comptime {
        std.testing.refAllDecls(@This());
    }
};

/// List of filters to be applied
///
/// This represents a list of filters to be applied to a file / blob. You can build the list with one call, apply it with another,
/// and dispose it with a third. In typical usage, there are not many occasions where a `FilterList` is needed directly since the
/// library will generally handle conversions for you, but it can be convenient to be able to build and apply the list sometimes.
pub const FilterList = opaque {

    /// Query the filter list to see if a given filter (by name) will run.
    /// The built-in filters "crlf" and "ident" can be queried, otherwise this is the name of the filter specified by the filter
    /// attribute.
    ///
    /// ## Parameters
    /// * `name` - The name of the filter to query
    pub fn contains(self: *const FilterList, name: [:0]const u8) bool {
        log.debug("FilterList.contains called, name={s}", .{name});

        const ret = raw.git_filter_list_contains(internal.toC(self), name.ptr) != 0;

        log.debug("filter list contains filter: {}", .{ret});

        return ret;
    }

    /// Apply filter list to a data buffer.
    ///
    /// ## Parameters
    /// * `name` - Buffer containing the data to filter
    pub fn applyToBuffer(self: *const FilterList, in: [:0]const u8) !git.Buf {
        log.debug("FilterList.applyToBuffer called, in={s}", .{in});

        var ret: git.Buf = undefined;

        try internal.wrapCall("git_filter_list_apply_to_buffer", .{
            internal.toC(&ret),
            internal.toC(self),
            in.ptr,
            in.len,
        });

        log.debug("result: {s}", .{ret.toSlice()});

        return ret;
    }

    /// Apply a filter list to the contents of a file on disk
    ///
    /// ## Parameters
    /// * `repo` - the repository in which to perform the filtering
    /// * `path` - the path of the file to filter, a relative path will be taken as relative to the workdir
    pub fn applyToFile(self: *const FilterList, repo: *const git.Repository, path: [:0]const u8) !git.Buf {
        log.debug("FilterList.applyToFile called, repo={*}, path={s}", .{ repo, path });

        var ret: git.Buf = undefined;

        try internal.wrapCall("git_filter_list_apply_to_file", .{
            internal.toC(&ret),
            internal.toC(self),
            internal.toC(repo),
            path.ptr,
        });

        log.debug("result: {s}", .{ret.toSlice()});

        return ret;
    }

    /// Apply a filter list to the contents of a blob
    ///
    /// ## Parameters
    /// * `blob` - the blob to filter
    pub fn applyToBlob(self: *const FilterList, blob: *const git.Blob) !git.Buf {
        log.debug("FilterList.applyToBlob called, blob={*}", .{blob});

        var ret: git.Buf = undefined;

        try internal.wrapCall("git_filter_list_apply_to_blob", .{
            internal.toC(&ret),
            internal.toC(self),
            internal.toC(blob),
        });

        log.debug("result: {s}", .{ret.toSlice()});

        return ret;
    }

    /// Apply a filter list to an arbitrary buffer as a stream
    ///
    /// ## Parameters
    /// * `buffer` - the buffer to filter
    /// * `target` - the stream into which the data will be written
    pub fn applyToBufferToStream(self: *const FilterList, buffer: [:0]const u8, target: *git.WriteStream) !void {
        log.debug("FilterList.applyToBufferToStream called, buffer={s}, target={*}", .{ buffer, target });

        try internal.wrapCall("git_filter_list_stream_buffer", .{
            internal.toC(self),
            buffer.ptr,
            buffer.len,
            @ptrCast(*raw.git_writestream, target),
        });

        log.debug("successfully filtered buffer to stream", .{});
    }

    /// Apply a filter list to a file as a stream
    ///
    /// ## Parameters
    /// * `repo` - the repository in which to perform the filtering
    /// * `path` - the path of the file to filter, a relative path will be taken as relative to the workdir
    /// * `target` - the stream into which the data will be written
    pub fn applyToFileToStream(
        self: *const FilterList,
        repo: *const git.Repository,
        path: [:0]const u8,
        target: *git.WriteStream,
    ) !void {
        log.debug("FilterList.applyToFileToStream called, repo={*}, path={s}, target={*}", .{ repo, path, target });

        try internal.wrapCall("git_filter_list_stream_file", .{
            internal.toC(self),
            internal.toC(repo),
            path.ptr,
            @ptrCast(*raw.git_writestream, target),
        });

        log.debug("successfully filtered file to stream", .{});
    }

    /// Apply a filter list to a blob as a stream
    ///
    /// ## Parameters
    /// * `blob` - the blob to filter
    /// * `target` - the stream into which the data will be written
    pub fn applyToBlobToStream(self: *const FilterList, blob: *const git.Blob, target: *git.WriteStream) !void {
        log.debug("FilterList.applyToBlobToStream called, blob={*}, target={*}", .{ blob, target });

        try internal.wrapCall("git_filter_list_stream_blob", .{
            internal.toC(self),
            internal.toC(blob),
            @ptrCast(*raw.git_writestream, target),
        });

        log.debug("successfully filtered blob to stream", .{});
    }

    pub fn deinit(self: *FilterList) void {
        log.debug("FilterList.deinit called", .{});

        raw.git_filter_list_free(internal.toC(self));

        log.debug("filter list freed successfully", .{});
    }

    comptime {
        std.testing.refAllDecls(@This());
    }
};

comptime {
    std.testing.refAllDecls(@This());
}
