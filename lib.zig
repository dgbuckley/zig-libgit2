const std = @import("std");
const raw = @import("raw.zig");

const log = std.log.scoped(.git);
const old_version: bool = @import("build_options").old_version;

pub const GIT_PATH_LIST_SEPARATOR = raw.GIT_PATH_LIST_SEPARATOR;

/// Init the global state
///
/// This function must be called before any other libgit2 function in order to set up global state and threading.
///
/// This function may be called multiple times.
pub fn init() !Handle {
    log.debug("init called", .{});

    const number = try wrapCallWithReturn("git_libgit2_init", .{});

    if (number == 1) {
        log.debug("libgit2 initalization successful", .{});
    } else {
        log.debug("{} ongoing initalizations without shutdown", .{number});
    }

    return Handle{};
}

/// Get detailed information regarding the last error that occured on this thread.
pub fn getDetailedLastError() ?GitDetailedError {
    return GitDetailedError{
        .e = raw.git_error_last() orelse return null,
    };
}

/// This type bundles all functionality that does not act on an instance of an object
pub const Handle = struct {
    /// Shutdown the global state
    /// 
    /// Clean up the global state and threading context after calling it as many times as `init` was called.
    pub fn deinit(self: Handle) void {
        _ = self;

        log.debug("Handle.deinit called", .{});

        const number = wrapCallWithReturn("git_libgit2_shutdown", .{}) catch unreachable;

        if (number == 0) {
            log.debug("libgit2 shutdown successful", .{});
        } else {
            log.debug("{} initializations have not been shutdown (after this one)", .{number});
        }
    }

    /// Creates a new Git repository in the given folder.
    ///
    /// ## Parameters
    /// * `path` - the path to the repository
    /// * `is_bare` - If true, a Git repository without a working directory is created at the pointed path. 
    ///               If false, provided path will be considered as the working directory into which the .git directory will be 
    ///               created.
    pub fn repositoryInit(self: Handle, path: [:0]const u8, is_bare: bool) !GitRepository {
        _ = self;

        log.debug("Handle.repositoryInit called, path={s}, is_bare={}", .{ path, is_bare });

        var repo: ?*raw.git_repository = undefined;

        try wrapCall("git_repository_init", .{ &repo, path.ptr, @boolToInt(is_bare) });

        log.debug("repository created successfully", .{});

        return GitRepository{ .repo = repo.? };
    }

    /// Create a new Git repository in the given folder with extended controls.
    ///
    /// This will initialize a new git repository (creating the repo_path if requested by flags) and working directory as needed.
    /// It will auto-detect the case sensitivity of the file system and if the file system supports file mode bits correctly.
    ///
    /// ## Parameters
    /// * `path` - the path to the repository
    /// * `options` - The options to use during the creation of the repository
    pub fn repositoryInitExtended(self: Handle, path: [:0]const u8, options: GitRepositoryInitExtendedOptions) !GitRepository {
        _ = self;

        log.debug("Handle.repositoryInitExtended called, path={s}, options={}", .{ path, options });

        var opts: raw.git_repository_init_options = undefined;
        if (old_version) {
            try wrapCall("git_repository_init_init_options", .{ &opts, raw.GIT_REPOSITORY_INIT_OPTIONS_VERSION });
        } else {
            try wrapCall("git_repository_init_options_init", .{ &opts, raw.GIT_REPOSITORY_INIT_OPTIONS_VERSION });
        }

        opts.flags = options.flags.toInt();
        opts.mode = options.mode.toInt();
        opts.workdir_path = if (options.workdir_path) |slice| slice.ptr else null;
        opts.description = if (options.description) |slice| slice.ptr else null;
        opts.template_path = if (options.template_path) |slice| slice.ptr else null;
        opts.initial_head = if (options.initial_head) |slice| slice.ptr else null;
        opts.origin_url = if (options.origin_url) |slice| slice.ptr else null;

        var repo: ?*raw.git_repository = undefined;

        try wrapCall("git_repository_init_ext", .{ &repo, path.ptr, &opts });

        log.debug("repository created successfully", .{});

        return GitRepository{ .repo = repo.? };
    }

    pub const GitRepositoryInitExtendedOptions = struct {
        flags: GitRepositoryInitExtendedFlags = .{},
        mode: InitMode = .shared_umask,

        /// The path to the working dir or NULL for default (i.e. repo_path parent on non-bare repos). IF THIS IS RELATIVE PATH, 
        /// IT WILL BE EVALUATED RELATIVE TO THE REPO_PATH. If this is not the "natural" working directory, a .git gitlink file 
        /// will be created here linking to the repo_path.
        workdir_path: ?[:0]const u8 = null,

        /// If set, this will be used to initialize the "description" file in the repository, instead of using the template 
        /// content.
        description: ?[:0]const u8 = null,

        /// When GIT_REPOSITORY_INIT_EXTERNAL_TEMPLATE is set, this contains the path to use for the template directory. If this 
        /// is `null`, the config or default directory options will be used instead.
        template_path: ?[:0]const u8 = null,

        /// The name of the head to point HEAD at. If NULL, then this will be treated as "master" and the HEAD ref will be set to
        /// "refs/heads/master".
        /// If this begins with "refs/" it will be used verbatim; otherwise "refs/heads/" will be prefixed.
        initial_head: ?[:0]const u8 = null,

        /// If this is non-NULL, then after the rest of the repository initialization is completed, an "origin" remote will be 
        /// added pointing to this URL.
        origin_url: ?[:0]const u8 = null,

        pub const GitRepositoryInitExtendedFlags = packed struct {
            /// Create a bare repository with no working directory.
            bare: bool = false,

            /// Return an GIT_EEXISTS error if the repo_path appears to already be an git repository.
            no_reinit: bool = false,

            /// Normally a "/.git/" will be appended to the repo path for non-bare repos (if it is not already there), but passing 
            /// this flag prevents that behavior.
            no_dotgit_dir: bool = false,

            /// Make the repo_path (and workdir_path) as needed. Init is always willing to create the ".git" directory even without 
            /// this flag. This flag tells init to create the trailing component of the repo and workdir paths as needed.
            mkdir: bool = false,

            /// Recursively make all components of the repo and workdir paths as necessary.
            mkpath: bool = false,

            /// libgit2 normally uses internal templates to initialize a new repo. This flags enables external templates, looking the
            /// "template_path" from the options if set, or the `init.templatedir` global config if not, or falling back on 
            /// "/usr/share/git-core/templates" if it exists.
            external_template: bool = false,

            /// If an alternate workdir is specified, use relative paths for the gitdir and core.worktree.
            relative_gitlink: bool = false,

            z_padding: std.meta.Int(.unsigned, @bitSizeOf(c_uint) - 7) = 0,

            pub fn toInt(self: GitRepositoryInitExtendedFlags) c_uint {
                return @bitCast(c_uint, self);
            }

            pub fn format(
                value: GitRepositoryInitExtendedFlags,
                comptime fmt: []const u8,
                options: std.fmt.FormatOptions,
                writer: anytype,
            ) !void {
                _ = fmt;
                return formatWithoutFields(
                    value,
                    options,
                    writer,
                    &.{"z_padding"},
                );
            }

            test {
                try std.testing.expectEqual(@sizeOf(c_uint), @sizeOf(GitRepositoryInitExtendedFlags));
                try std.testing.expectEqual(@bitSizeOf(c_uint), @bitSizeOf(GitRepositoryInitExtendedFlags));
            }

            comptime {
                std.testing.refAllDecls(@This());
            }
        };

        pub const InitMode = union(enum) {
            /// Use permissions configured by umask - the default.
            shared_umask: void,

            /// Use "--shared=group" behavior, chmod'ing the new repo to be group writable and "g+sx" for sticky group assignment.
            shared_group: void,

            /// Use "--shared=all" behavior, adding world readability.
            shared_all: void,

            custom: c_uint,

            pub fn toInt(self: InitMode) c_uint {
                return switch (self) {
                    .shared_umask => 0,
                    .shared_group => 0o2775,
                    .shared_all => 0o2777,
                    .custom => |custom| custom,
                };
            }
        };

        comptime {
            std.testing.refAllDecls(@This());
        }
    };

    /// Open a git repository.
    ///
    /// The `path` argument must point to either a git repository folder, or an existing work dir.
    ///
    /// The method will automatically detect if 'path' is a normal or bare repository or fail is `path` is neither.
    ///
    /// ## Parameters
    /// * `path` - the path to the repository
    pub fn repositoryOpen(self: Handle, path: [:0]const u8) !GitRepository {
        _ = self;

        log.debug("Handle.repositoryOpen called, path={s}", .{path});

        var repo: ?*raw.git_repository = undefined;

        try wrapCall("git_repository_open", .{ &repo, path.ptr });

        log.debug("repository opened successfully", .{});

        return GitRepository{ .repo = repo.? };
    }

    /// Find and open a repository with extended controls.
    ///
    /// The `path` argument must point to either a git repository folder, or an existing work dir.
    ///
    /// The method will automatically detect if 'path' is a normal or bare repository or fail is `path` is neither.
    ///
    /// *Note:* `path` can only be null if the `open_from_env` option is used.
    ///
    /// ## Parameters
    /// * `path` - the path to the repository
    /// * `flags` - A combination of the GIT_REPOSITORY_OPEN flags above.
    /// * `ceiling_dirs` - A `GIT_PATH_LIST_SEPARATOR` delimited list of path prefixes at which the search for a containing
    ///                    repository should terminate. `ceiling_dirs` can be `null`.
    pub fn repositoryOpenExtended(
        self: Handle,
        path: ?[:0]const u8,
        flags: GitRepositoryOpenExtendedFlags,
        ceiling_dirs: ?[:0]const u8,
    ) !GitRepository {
        _ = self;

        log.debug("Handle.repositoryOpenExtended called, path={s}, flags={}, ceiling_dirs={s}", .{ path, flags, ceiling_dirs });

        var repo: ?*raw.git_repository = undefined;

        const path_temp: [*c]const u8 = if (path) |slice| slice.ptr else null;
        const ceiling_dirs_temp: [*c]const u8 = if (ceiling_dirs) |slice| slice.ptr else null;
        try wrapCall("git_repository_open_ext", .{ &repo, path_temp, flags.toInt(), ceiling_dirs_temp });

        log.debug("repository opened successfully", .{});

        return GitRepository{ .repo = repo.? };
    }

    pub const GitRepositoryOpenExtendedFlags = packed struct {
        /// Only open the repository if it can be immediately found in the start_path. Do not walk up from the start_path looking 
        /// at parent directories.
        no_search: bool = false,

        /// Unless this flag is set, open will not continue searching across filesystem boundaries (i.e. when `st_dev` changes 
        /// from the `stat` system call).  For example, searching in a user's home directory at "/home/user/source/" will not 
        /// return "/.git/" as the found repo if "/" is a different filesystem than "/home".
        cross_fs: bool = false,

        /// Open repository as a bare repo regardless of core.bare config, and defer loading config file for faster setup.
        /// Unlike `Handle.repositoryOpenBare`, this can follow gitlinks.
        bare: bool = false,

        /// Do not check for a repository by appending /.git to the start_path; only open the repository if start_path itself 
        /// points to the git directory.     
        no_dotgit: bool = false,

        /// Find and open a git repository, respecting the environment variables used by the git command-line tools. If set, 
        /// `Handle.repositoryOpenExtended` will ignore the other flags and the `ceiling_dirs` argument, and will allow a null 
        /// `path` to use `GIT_DIR` or search from the current directory.
        /// The search for a repository will respect $GIT_CEILING_DIRECTORIES and $GIT_DISCOVERY_ACROSS_FILESYSTEM.  The opened 
        /// repository will respect $GIT_INDEX_FILE, $GIT_NAMESPACE, $GIT_OBJECT_DIRECTORY, and $GIT_ALTERNATE_OBJECT_DIRECTORIES.
        /// In the future, this flag will also cause `Handle.repositoryOpenExtended` to respect $GIT_WORK_TREE and 
        /// $GIT_COMMON_DIR; currently, `Handle.repositoryOpenExtended` with this flag will error out if either $GIT_WORK_TREE or 
        /// $GIT_COMMON_DIR is set.
        open_from_env: bool = false,

        z_padding: std.meta.Int(.unsigned, @bitSizeOf(c_uint) - 5) = 0,

        pub fn toInt(self: GitRepositoryOpenExtendedFlags) c_uint {
            return @bitCast(c_uint, self);
        }

        pub fn format(
            value: GitRepositoryOpenExtendedFlags,
            comptime fmt: []const u8,
            options: std.fmt.FormatOptions,
            writer: anytype,
        ) !void {
            _ = fmt;
            return formatWithoutFields(
                value,
                options,
                writer,
                &.{"z_padding"},
            );
        }

        test {
            try std.testing.expectEqual(@sizeOf(c_uint), @sizeOf(GitRepositoryOpenExtendedFlags));
            try std.testing.expectEqual(@bitSizeOf(c_uint), @bitSizeOf(GitRepositoryOpenExtendedFlags));
        }

        comptime {
            std.testing.refAllDecls(@This());
        }
    };

    /// Open a bare repository on the serverside.
    ///
    /// This is a fast open for bare repositories that will come in handy if you're e.g. hosting git repositories and need to 
    /// access them efficiently
    ///
    /// ## Parameters
    /// * `path` - the path to the repository
    pub fn repositoryOpenBare(self: Handle, path: [:0]const u8) !GitRepository {
        _ = self;

        log.debug("Handle.repositoryOpenBare called, path={s}", .{path});

        var repo: ?*raw.git_repository = undefined;

        try wrapCall("git_repository_open_bare", .{ &repo, path.ptr });

        log.debug("repository opened successfully", .{});

        return GitRepository{ .repo = repo.? };
    }

    /// Look for a git repository and provide its path.
    ///
    /// The lookup start from base_path and walk across parent directories if nothing has been found. The lookup ends when the
    /// first repository is found, or when reaching a directory referenced in ceiling_dirs or when the filesystem changes 
    /// (in case across_fs is true).
    ///
    /// The method will automatically detect if the repository is bare (if there is a repository).
    ///
    /// ## Parameters
    /// * `start_path` - The base path where the lookup starts.
    /// * `across_fs` - If true, then the lookup will not stop when a filesystem device change is detected while exploring parent 
    ///                 directories.
    /// * `ceiling_dirs` - A `GIT_PATH_LIST_SEPARATOR` separated list of absolute symbolic link free paths. The lookup will stop 
    ///                    when any of this paths is reached. Note that the lookup always performs on `start_path` no matter 
    ///                    `start_path` appears in `ceiling_dirs`. `ceiling_dirs` can be `null`.
    pub fn repositoryDiscover(self: Handle, start_path: [:0]const u8, across_fs: bool, ceiling_dirs: ?[:0]const u8) !GitBuf {
        _ = self;

        log.debug(
            "Handle.repositoryDiscover called, start_path={s}, across_fs={}, ceiling_dirs={s}",
            .{ start_path, across_fs, ceiling_dirs },
        );

        var git_buf = GitBuf.zero();

        const ceiling_dirs_temp: [*c]const u8 = if (ceiling_dirs) |slice| slice.ptr else null;
        try wrapCall("git_repository_discover", .{ &git_buf.buf, start_path.ptr, @boolToInt(across_fs), ceiling_dirs_temp });

        log.debug("repository discovered - {s}", .{git_buf.slice()});

        return git_buf;
    }

    comptime {
        std.testing.refAllDecls(@This());
    }
};

/// In-memory representation of a reference.
pub const GitReference = struct {
    ref: *raw.git_reference,

    /// Free the given reference.
    pub fn deinit(self: *GitReference) void {
        log.debug("GitReference.deinit called", .{});

        raw.git_reference_free(self.ref);
        self.* = undefined;

        log.debug("reference freed successfully", .{});
    }

    comptime {
        std.testing.refAllDecls(@This());
    }
};

/// Representation of an existing git repository, including all its object contents
pub const GitRepository = struct {
    repo: *raw.git_repository,

    /// Free a previously allocated repository
    ///
    /// *Note:* that after a repository is free'd, all the objects it has spawned will still exist until they are manually closed 
    /// by the user, but accessing any of the attributes of an object without a backing repository will result in undefined 
    /// behavior
    pub fn deinit(self: *GitRepository) void {
        log.debug("GitRepository.deinit called", .{});

        raw.git_repository_free(self.repo);
        self.* = undefined;

        log.debug("repository closed successfully", .{});
    }

    /// These values represent possible states for the repository to be in, based on the current operation which is ongoing.
    pub const RepositoryState = enum(c_int) {
        NONE,
        MERGE,
        REVERT,
        REVERT_SEQUENCE,
        CHERRYPICK,
        CHERRYPICK_SEQUENCE,
        BISECT,
        REBASE,
        REBASE_INTERACTIVE,
        REBASE_MERGE,
        APPLY_MAILBOX,
        APPLY_MAILBOX_OR_REBASE,
    };

    /// Determines the status of a git repository - ie, whether an operation (merge, cherry-pick, etc) is in progress.
    pub fn getState(self: GitRepository) RepositoryState {
        log.debug("GitRepository.getState called", .{});

        const ret = @intToEnum(RepositoryState, raw.git_repository_state(self.repo));

        log.debug("repository state: {s}", .{@tagName(ret)});

        return ret;
    }

    /// Retrieve the configured identity to use for reflogs
    ///
    /// The memory is owned by the repository and must not be freed by the user.
    pub fn getIdentity(self: GitRepository) !Identity {
        log.debug("GitRepository.getIdentity called", .{});

        var c_name: [*c]u8 = undefined;
        var c_email: [*c]u8 = undefined;

        try wrapCall("git_repository_ident", .{ &c_name, &c_email, self.repo });

        const name: ?[:0]const u8 = if (c_name) |ptr| std.mem.sliceTo(ptr, 0) else null;
        const email: ?[:0]const u8 = if (c_email) |ptr| std.mem.sliceTo(ptr, 0) else null;

        log.debug("identity acquired: name={s}, email={s}", .{ name, email });

        return Identity{ .name = name, .email = email };
    }

    /// Set the identity to be used for writing reflogs
    ///
    /// If both are set, this name and email will be used to write to the reflog. Pass `null` to unset. When unset, the identity
    /// will be taken from the repository's configuration.
    pub fn setIdentity(self: GitRepository, identity: Identity) !void {
        log.debug("GitRepository.setIdentity called, identity.name={s}, identity.email={s}", .{ identity.name, identity.email });

        const name_temp: [*c]const u8 = if (identity.name) |slice| slice.ptr else null;
        const email_temp: [*c]const u8 = if (identity.email) |slice| slice.ptr else null;
        try wrapCall("git_repository_set_ident", .{ self.repo, name_temp, email_temp });

        log.debug("successfully set identity", .{});
    }

    /// Get the currently active namespace for this repository
    pub fn getNamespace(self: GitRepository) !?[:0]const u8 {
        log.debug("GitRepository.getNamespace called", .{});

        const ret = raw.git_repository_get_namespace(self.repo);

        if (ret) |ptr| {
            const slice = std.mem.sliceTo(ptr, 0);
            log.debug("namespace: {s}", .{slice});
            return slice;
        }

        log.debug("no namespace", .{});

        return null;
    }

    /// Sets the active namespace for this Git Repository
    ///
    /// This namespace affects all reference operations for the repo.
    /// See `man gitnamespaces`
    /// ## Parameters
    /// * `namespace` - The namespace. This should not include the refs folder, e.g. to namespace all references under 
    ///                 "refs/namespaces/foo/", use "foo" as the namespace.
    pub fn setNamespace(self: *GitRepository, namespace: [:0]const u8) !void {
        log.debug("GitRepository.setNamespace called, namespace={s}", .{namespace});

        try wrapCall("git_repository_set_namespace", .{ self.repo, namespace.ptr });

        log.debug("successfully set namespace", .{});
    }

    /// Check if a repository's HEAD is detached
    ///
    /// A repository's HEAD is detached when it points directly to a commit instead of a branch.
    pub fn isHeadDetached(self: GitRepository) !bool {
        log.debug("GitRepository.isHeadDetached called", .{});

        const ret = (try wrapCallWithReturn("git_repository_head_detached", .{self.repo})) == 1;

        log.debug("is head detached: {}", .{ret});

        return ret;
    }

    /// Retrieve and resolve the reference pointed at by HEAD.
    pub fn getHead(self: GitRepository) !GitReference {
        log.debug("GitRepository.head called", .{});

        var ref: ?*raw.git_reference = undefined;

        try wrapCall("git_repository_head", .{ &ref, self.repo });

        log.debug("reference opened successfully", .{});

        return GitReference{ .ref = ref.? };
    }

    /// Make the repository HEAD point to the specified reference.
    ///
    /// If the provided reference points to a Tree or a Blob, the HEAD is unaltered and -1 is returned.
    ///
    /// If the provided reference points to a branch, the HEAD will point to that branch, staying attached, or become attached if
    /// it isn't yet.
    /// If the branch doesn't exist yet, no error will be return. The HEAD will then be attached to an unborn branch.
    ///
    /// Otherwise, the HEAD will be detached and will directly point to the Commit.
    ///
    /// ## Parameters
    /// * `ref_name` - Canonical name of the reference the HEAD should point at
    pub fn setHead(self: *GitRepository, ref_name: [:0]const u8) !void {
        log.debug("GitRepository.setHead called, workdir={s}", .{ref_name});

        try wrapCall("git_repository_set_head", .{ self.repo, ref_name.ptr });

        log.debug("successfully set head", .{});
    }

    /// Make the repository HEAD directly point to the Commit.
    ///
    /// If the provided committish cannot be found in the repository, the HEAD is unaltered and GIT_ENOTFOUND is returned.
    ///
    /// If the provided commitish cannot be peeled into a commit, the HEAD is unaltered and -1 is returned.
    ///
    /// Otherwise, the HEAD will eventually be detached and will directly point to the peeled Commit.
    ///
    /// ## Parameters
    /// * `commitish` - Object id of the Commit the HEAD should point to
    pub fn setHeadDetached(self: *GitRepository, commitish: GitOid) !void {
        // This check is to prevent formating the oid when we are not going to print anything
        if (@enumToInt(std.log.Level.debug) <= @enumToInt(std.log.level)) {
            var buf: [GitOid.HEX_BUFFER_SIZE]u8 = undefined;
            const slice = try commitish.formatHex(&buf);
            log.debug("GitRepository.setHeadDetached called, commitish={s}", .{slice});
        }

        try wrapCall("git_repository_set_head_detached", .{ self.repo, commitish.oid });

        log.debug("successfully set head", .{});
    }

    /// Make the repository HEAD directly point to the Commit.
    ///
    /// This behaves like `GitRepository.setHeadDetached` but takes an annotated commit, which lets you specify which 
    /// extended sha syntax string was specified by a user, allowing for more exact reflog messages.
    ///
    /// See the documentation for `GitRepository.setHeadDetached`.
    pub fn setHeadDetachedFromAnnotated(self: *GitRepository, commitish: GitAnnotatedCommit) !void {
        log.debug("GitRepository.setHeadDetachedFromAnnotated called", .{});

        try wrapCall("git_repository_set_head_detached_from_annotated", .{ self.repo, commitish.commit });

        log.debug("successfully set head", .{});
    }

    /// Detach the HEAD.
    ///
    /// If the HEAD is already detached and points to a Commit, 0 is returned.
    ///
    /// If the HEAD is already detached and points to a Tag, the HEAD is updated into making it point to the peeled Commit, and 0
    /// is returned.
    ///
    /// If the HEAD is already detached and points to a non commitish, the HEAD is unaltered, and -1 is returned.
    ///
    /// Otherwise, the HEAD will be detached and point to the peeled Commit.
    pub fn detachHead(self: *GitRepository) !void {
        log.debug("GitRepository.detachHead called", .{});

        try wrapCall("git_repository_detach_head", .{self.repo});

        log.debug("successfully detached the head", .{});
    }

    /// Check if a worktree's HEAD is detached
    ///
    /// A worktree's HEAD is detached when it points directly to a commit instead of a branch.
    ///
    /// ## Parameters
    /// * `name` - name of the worktree to retrieve HEAD for
    pub fn isHeadForWorktreeDetached(self: GitRepository, name: [:0]const u8) !bool {
        log.debug("GitRepository.isHeadForWorktreeDetached called, name={s}", .{name});

        const ret = (try wrapCallWithReturn(
            "git_repository_head_detached_for_worktree",
            .{ self.repo, name.ptr },
        )) == 1;

        log.debug("head for worktree {s} is detached: {}", .{ name, ret });

        return ret;
    }

    /// Retrieve the referenced HEAD for the worktree
    ///
    /// ## Parameters
    /// * `name` - name of the worktree to retrieve HEAD for
    pub fn headForWorktree(self: GitRepository, name: [:0]const u8) !GitReference {
        log.debug("GitRepository.headForWorktree called, name={s}", .{name});

        var ref: ?*raw.git_reference = undefined;

        try wrapCall("git_repository_head_for_worktree", .{ &ref, self.repo, name.ptr });

        log.debug("reference opened successfully", .{});

        return GitReference{ .ref = ref.? };
    }

    /// Check if the current branch is unborn
    ///
    /// An unborn branch is one named from HEAD but which doesn't exist in the refs namespace, because it doesn't have any commit
    /// to point to.
    pub fn isHeadUnborn(self: GitRepository) !bool {
        log.debug("GitRepository.isHeadUnborn called", .{});

        const ret = (try wrapCallWithReturn("git_repository_head_unborn", .{self.repo})) == 1;

        log.debug("is head unborn: {}", .{ret});

        return ret;
    }

    /// Determine if the repository was a shallow clone
    pub fn isShallow(self: GitRepository) bool {
        log.debug("GitRepository.isShallow called", .{});

        const ret = raw.git_repository_is_shallow(self.repo) == 1;

        log.debug("is repository a shallow clone: {}", .{ret});

        return ret;
    }

    /// Check if a repository is empty
    ///
    /// An empty repository has just been initialized and contains no references apart from HEAD, which must be pointing to the
    /// unborn master branch.
    pub fn isEmpty(self: GitRepository) !bool {
        log.debug("GitRepository.isEmpty called", .{});

        const ret = (try wrapCallWithReturn("git_repository_is_empty", .{self.repo})) == 1;

        log.debug("is repository empty: {}", .{ret});

        return ret;
    }

    /// Check if a repository is bare
    pub fn isBare(self: GitRepository) bool {
        log.debug("GitRepository.isBare called", .{});

        const ret = raw.git_repository_is_bare(self.repo) == 1;

        log.debug("is repository bare: {}", .{ret});

        return ret;
    }

    /// Check if a repository is a linked work tree
    pub fn isWorktree(self: GitRepository) bool {
        log.debug("GitRepository.isWorktree called", .{});

        const ret = raw.git_repository_is_worktree(self.repo) == 1;

        log.debug("is repository worktree: {}", .{ret});

        return ret;
    }

    /// Get the location of a specific repository file or directory
    ///
    /// This function will retrieve the path of a specific repository item. It will thereby honor things like the repository's
    /// common directory, gitdir, etc. In case a file path cannot exist for a given item (e.g. the working directory of a bare
    /// repository), `NOTFOUND` is returned.
    pub fn getItemPath(self: GitRepository, item: RepositoryItem) !GitBuf {
        log.debug("GitRepository.itemPath called, item={s}", .{item});

        var buf = GitBuf.zero();

        try wrapCall("git_repository_item_path", .{ &buf.buf, self.repo, @enumToInt(item) });

        log.debug("item path: {s}", .{buf.slice()});

        return buf;
    }

    pub const RepositoryItem = enum(c_uint) {
        GITDIR,
        WORKDIR,
        COMMONDIR,
        INDEX,
        OBJECTS,
        REFS,
        PACKED_REFS,
        REMOTES,
        CONFIG,
        INFO,
        HOOKS,
        LOGS,
        MODULES,
        WORKTREES,
    };

    /// Get the path of this repository
    ///
    /// This is the path of the `.git` folder for normal repositories, or of the repository itself for bare repositories.
    pub fn getPath(self: GitRepository) [:0]const u8 {
        log.debug("GitRepository.path called", .{});

        const slice = std.mem.sliceTo(raw.git_repository_path(self.repo), 0);

        log.debug("path: {s}", .{slice});

        return slice;
    }

    /// Get the path of the working directory for this repository
    ///
    /// If the repository is bare, this function will always return `null`.
    pub fn getWorkdir(self: GitRepository) ?[:0]const u8 {
        log.debug("GitRepository.workdir called", .{});

        if (raw.git_repository_workdir(self.repo)) |ret| {
            const slice = std.mem.sliceTo(ret, 0);

            log.debug("workdir: {s}", .{slice});

            return slice;
        }

        log.debug("no workdir", .{});

        return null;
    }

    /// Set the path to the working directory for this repository
    pub fn setWorkdir(self: *GitRepository, workdir: [:0]const u8, update_gitlink: bool) !void {
        log.debug("GitRepository.setWorkdir called, workdir={s}, update_gitlink={}", .{ workdir, update_gitlink });

        try wrapCall("git_repository_set_workdir", .{ self.repo, workdir.ptr, @boolToInt(update_gitlink) });

        log.debug("successfully set workdir", .{});
    }

    /// Get the path of the shared common directory for this repository.
    ///
    /// If the repository is bare, it is the root directory for the repository. If the repository is a worktree, it is the parent 
    /// repo's gitdir. Otherwise, it is the gitdir.
    pub fn getCommondir(self: GitRepository) ?[:0]const u8 {
        log.debug("GitRepository.commondir called", .{});

        if (raw.git_repository_commondir(self.repo)) |ret| {
            const slice = std.mem.sliceTo(ret, 0);

            log.debug("commondir: {s}", .{slice});

            return slice;
        }

        log.debug("no commondir", .{});

        return null;
    }

    /// Get the configuration file for this repository.
    ///
    /// If a configuration file has not been set, the default config set for the repository will be returned, including global 
    /// and system configurations (if they are available). The configuration file must be freed once it's no longer being used by
    /// the user.
    pub fn getConfig(self: GitRepository) !GitConfig {
        log.debug("GitRepository.getConfig called", .{});

        var config: ?*raw.git_config = undefined;

        try wrapCall("git_repository_config", .{ &config, self.repo });

        log.debug("repository config acquired successfully", .{});

        return GitConfig{ .config = config.? };
    }

    /// Get a snapshot of the repository's configuration
    ///
    /// Convenience function to take a snapshot from the repository's configuration. The contents of this snapshot will not 
    /// change, even if the underlying config files are modified.
    ///
    /// The configuration file must be freed once it's no longer being used by the user.
    pub fn getConfigSnapshot(self: GitRepository) !GitConfig {
        log.debug("GitRepository.getConfigSnapshot called", .{});

        var config: ?*raw.git_config = undefined;

        try wrapCall("git_repository_config_snapshot", .{ &config, self.repo });

        log.debug("repository config acquired successfully", .{});

        return GitConfig{ .config = config.? };
    }

    /// Get the Object Database for this repository.
    ///
    /// If a custom ODB has not been set, the default database for the repository will be returned (the one located in 
    /// `.git/objects`).
    ///
    /// The ODB must be freed once it's no longer being used by the user.
    pub fn getOdb(self: GitRepository) !GitOdb {
        log.debug("GitRepository.getOdb called", .{});

        var odb: ?*raw.git_odb = undefined;

        try wrapCall("git_repository_odb", .{ &odb, self.repo });

        log.debug("repository odb acquired successfully", .{});

        return GitOdb{ .odb = odb.? };
    }

    /// Get the Reference Database Backend for this repository.
    ///
    /// If a custom refsdb has not been set, the default database for the repository will be returned (the one that manipulates
    /// loose and packed references in the `.git` directory).
    /// 
    /// The refdb must be freed once it's no longer being used by the user.
    pub fn getRefDb(self: GitRepository) !GitRefDb {
        log.debug("GitRepository.getRefDb called", .{});

        var ref_db: ?*raw.git_refdb = undefined;

        try wrapCall("git_repository_refdb", .{ &ref_db, self.repo });

        log.debug("repository refdb acquired successfully", .{});

        return GitRefDb{ .ref_db = ref_db.? };
    }

    /// Get the Reference Database Backend for this repository.
    ///
    /// If a custom refsdb has not been set, the default database for the repository will be returned (the one that manipulates
    /// loose and packed references in the `.git` directory).
    /// 
    /// The refdb must be freed once it's no longer being used by the user.
    pub fn getIndex(self: GitRepository) !GitIndex {
        log.debug("GitRepository.getIndex called", .{});

        var index: ?*raw.git_index = undefined;

        try wrapCall("git_repository_index", .{ &index, self.repo });

        log.debug("repository index acquired successfully", .{});

        return GitIndex{ .index = index.? };
    }

    /// Retrieve git's prepared message
    ///
    /// Operations such as git revert/cherry-pick/merge with the -n option stop just short of creating a commit with the changes 
    /// and save their prepared message in .git/MERGE_MSG so the next git-commit execution can present it to the user for them to
    /// amend if they wish.
    ///
    /// Use this function to get the contents of this file. Don't forget to remove the file after you create the commit.
    pub fn getPreparedMessage(self: GitRepository) !GitBuf {
        // TODO: Change this function and others to return null instead of `GitError.NotFound`

        log.debug("GitRepository.getPreparedMessage called", .{});

        var buf = GitBuf.zero();

        try wrapCall("git_repository_message", .{ &buf.buf, self.repo });

        log.debug("prepared message: {s}", .{buf.slice()});

        return buf;
    }

    /// Remove git's prepared message.
    ///
    /// Remove the message that `getPreparedMessage` retrieves.
    pub fn removePreparedMessage(self: *GitRepository) !void {
        log.debug("GitRepository.removePreparedMessage called", .{});

        try wrapCall("git_repository_message_remove", .{self.repo});

        log.debug("successfully removed prepared message", .{});
    }

    /// Remove all the metadata associated with an ongoing command like merge, revert, cherry-pick, etc.
    /// For example: MERGE_HEAD, MERGE_MSG, etc.
    pub fn stateCleanup(self: *GitRepository) !void {
        log.debug("GitRepository.stateCleanup called", .{});

        try wrapCall("git_repository_state_cleanup", .{self.repo});

        log.debug("successfully cleaned state", .{});
    }

    /// Invoke `callback_fn` for each entry in the given FETCH_HEAD file.
    ///
    /// Return a non-zero value from the callback to stop the loop.
    ///
    /// ## Parameters
    /// * `callback_fn` - the callback function
    ///
    /// ## Callback Parameters
    /// * `ref_name` - The reference name
    /// * `remote_url` - The remote URL
    /// * `oid` - The reference target OID
    /// * `is_merge` - Was the reference the result of a merge
    pub fn foreachFetchHead(
        self: GitRepository,
        comptime callback_fn: fn (
            ref_name: [:0]const u8,
            remote_url: [:0]const u8,
            oid: GitOid,
            is_merge: bool,
        ) c_int,
    ) !c_int {
        const cb = struct {
            pub fn cb(
                ref_name: [:0]const u8,
                remote_url: [:0]const u8,
                oid: GitOid,
                is_merge: bool,
                _: *u8,
            ) c_int {
                return callback_fn(ref_name, remote_url, oid, is_merge);
            }
        }.cb;

        var dummy_data: u8 = undefined;
        return self.foreachFetchHeadWithUserData(&dummy_data, cb);
    }

    /// Invoke `callback_fn` for each entry in the given FETCH_HEAD file.
    ///
    /// Return a non-zero value from the callback to stop the loop.
    ///
    /// ## Parameters
    /// * `user_data` - pointer to user data to be passed to the callback
    /// * `callback_fn` - the callback function
    ///
    /// ## Callback Parameters
    /// * `ref_name` - The reference name
    /// * `remote_url` - The remote URL
    /// * `oid` - The reference target OID
    /// * `is_merge` - Was the reference the result of a merge
    /// * `user_data_ptr` - pointer to user data
    pub fn foreachFetchHeadWithUserData(
        self: GitRepository,
        user_data: anytype,
        comptime callback_fn: fn (
            ref_name: [:0]const u8,
            remote_url: [:0]const u8,
            oid: GitOid,
            is_merge: bool,
            user_data_ptr: @TypeOf(user_data),
        ) c_int,
    ) !c_int {
        const UserDataType = @TypeOf(user_data);

        const cb = struct {
            pub fn cb(
                c_ref_name: [*c]const u8,
                c_remote_url: [*c]const u8,
                c_oid: [*c]const raw.git_oid,
                c_is_merge: c_uint,
                payload: ?*c_void,
            ) callconv(.C) c_int {
                return callback_fn(
                    std.mem.sliceTo(c_ref_name, 0),
                    std.mem.sliceTo(c_remote_url, 0),
                    GitOid{ .oid = c_oid.? },
                    c_is_merge == 1,
                    @ptrCast(UserDataType, payload),
                );
            }
        }.cb;

        log.debug("GitRepository.foreachFetchHeadWithUserData called", .{});

        const ret = try wrapCallWithReturn("git_repository_fetchhead_foreach", .{ self.repo, cb, user_data });

        log.debug("callback returned: {}", .{ret});

        return ret;
    }

    /// If a merge is in progress, invoke 'callback' for each commit ID in the MERGE_HEAD file.
    ///
    /// Return a non-zero value from the callback to stop the loop.
    ///
    /// ## Parameters
    /// * `callback_fn` - the callback function
    ///
    /// ## Callback Parameters
    /// * `oid` - The merge OID
    pub fn foreachMergeHead(
        self: GitRepository,
        comptime callback_fn: fn (oid: GitOid) c_int,
    ) !c_int {
        const cb = struct {
            pub fn cb(oid: GitOid, _: *u8) c_int {
                return callback_fn(oid);
            }
        }.cb;

        var dummy_data: u8 = undefined;
        return self.foreachMergeHeadWithUserData(&dummy_data, cb);
    }

    /// If a merge is in progress, invoke 'callback' for each commit ID in the MERGE_HEAD file.
    ///
    /// Return a non-zero value from the callback to stop the loop.
    ///
    /// ## Parameters
    /// * `user_data` - pointer to user data to be passed to the callback
    /// * `callback_fn` - the callback function
    ///
    /// ## Callback Parameters
    /// * `oid` - The merge OID
    /// * `user_data_ptr` - pointer to user data
    pub fn foreachMergeHeadWithUserData(
        self: GitRepository,
        user_data: anytype,
        comptime callback_fn: fn (
            oid: GitOid,
            user_data_ptr: @TypeOf(user_data),
        ) c_int,
    ) !c_int {
        const UserDataType = @TypeOf(user_data);

        const cb = struct {
            pub fn cb(c_oid: [*c]const raw.git_oid, payload: ?*c_void) callconv(.C) c_int {
                return callback_fn(GitOid{ .oid = c_oid.? }, @ptrCast(UserDataType, payload));
            }
        }.cb;

        log.debug("GitRepository.foreachMergeHeadWithUserData called", .{});

        const ret = try wrapCallWithReturn("git_repository_mergehead_foreach", .{ self.repo, cb, user_data });

        log.debug("callback returned: {}", .{ret});

        return ret;
    }

    /// Calculate hash of file using repository filtering rules.
    ///
    /// If you simply want to calculate the hash of a file on disk with no filters, you can just use the `GitOdb.hashFile` API.
    /// However, if you want to hash a file in the repository and you want to apply filtering rules (e.g. crlf filters) before
    /// generating the SHA, then use this function.
    ///
    /// Note: if the repository has `core.safecrlf` set to fail and the filtering triggers that failure, then this function will
    /// return an error and not calculate the hash of the file.
    ///
    /// ## Parameters
    /// * `path` - Path to file on disk whose contents should be hashed. This can be a relative path.
    /// * `object_type` - The object type to hash as (e.g. `GitObject.BLOB`)
    /// * `as_path` - The path to use to look up filtering rules. If this is `null`, then the `path` parameter will be used
    ///               instead. If this is passed as the empty string, then no filters will be applied when calculating the hash.
    pub fn hashFile(self: GitRepository, path: [:0]const u8, object_type: GitObject, as_path: ?[:0]const u8) !GitOid {
        log.debug("GitRepository.hashFile called, path={s}, object_type={}, as_path={s}", .{ path, object_type, as_path });

        var oid: ?*raw.git_oid = undefined;

        const as_path_temp: [*c]const u8 = if (as_path) |slice| slice.ptr else null;
        try wrapCall("git_repository_hashfile", .{ oid, self.repo, path.ptr, @enumToInt(object_type), as_path_temp });

        const ret = GitOid{ .oid = oid.? };

        // This check is to prevent formating the oid when we are not going to print anything
        if (@enumToInt(std.log.Level.debug) <= @enumToInt(std.log.level)) {
            var buf: [GitOid.HEX_BUFFER_SIZE]u8 = undefined;
            const slice = try ret.formatHex(&buf);
            log.debug("file hash acquired successfully, hash={s}", .{slice});
        }

        return ret;
    }

    /// Get file status for a single file.
    ///
    /// This tries to get status for the filename that you give.  If no files match that name (in either the HEAD, index, or
    /// working directory), this returns GIT_ENOTFOUND.
    ///
    /// If the name matches multiple files (for example, if the `path` names a directory or if running on a case- insensitive
    /// filesystem and yet the HEAD has two entries that both match the path), then this returns GIT_EAMBIGUOUS because it cannot
    /// give correct results.
    ///
    /// This does not do any sort of rename detection.  Renames require a set of targets and because of the path filtering, there
    /// is not enough information to check renames correctly.  To check file status with rename detection, there is no choice but
    /// to do a full `git_status_list_new` and scan through looking for the path that you are interested in.
    pub fn fileStatus(self: GitRepository, path: [:0]const u8) !FileStatus {
        log.debug("GitRepository.fileStatus called, path={s}", .{path});

        var flags: c_uint = undefined;

        try wrapCall("git_status_file", .{ &flags, self.repo, path.ptr });

        const ret = @bitCast(FileStatus, flags);

        log.debug("file status: {}", .{ret});

        return ret;
    }

    comptime {
        std.testing.refAllDecls(@This());
    }
};

/// Status flags for a single file
///
/// A combination of these values will be returned to indicate the status of a file.  Status compares the working directory, the
/// index, and the current HEAD of the repository.  
/// The `INDEX` set of flags represents the status of file in the  index relative to the HEAD, and the `WT` set of flags represent
/// the status of the file in the working directory relative to the index.
pub const FileStatus = packed struct {
    CURRENT: bool = false,
    INDEX_NEW: bool = false,
    INDEX_MODIFIED: bool = false,
    INDEX_DELETED: bool = false,
    INDEX_RENAMED: bool = false,
    INDEX_TYPECHANGE: bool = false,
    WT_NEW: bool = false,
    WT_MODIFIED: bool = false,
    WT_DELETED: bool = false,
    WT_TYPECHANGE: bool = false,
    WT_RENAMED: bool = false,
    WT_UNREADABLE: bool = false,
    IGNORED: bool = false,
    CONFLICTED: bool = false,

    z_padding1: u2 = 0,
    z_padding2: u16 = 0,

    pub fn format(
        value: FileStatus,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        return formatWithoutFields(
            value,
            options,
            writer,
            &.{ "z_padding1", "z_padding2" },
        );
    }

    test {
        try std.testing.expectEqual(@sizeOf(c_uint), @sizeOf(FileStatus));
        try std.testing.expectEqual(@bitSizeOf(c_uint), @bitSizeOf(FileStatus));
    }

    comptime {
        std.testing.refAllDecls(@This());
    }
};

pub const Identity = struct {
    name: ?[:0]const u8,
    email: ?[:0]const u8,
};

/// Annotated commits, the input to merge and rebase.
pub const GitAnnotatedCommit = struct {
    commit: *raw.git_annotated_commit,

    /// Free the annotated commit
    pub fn deinit(self: *GitAnnotatedCommit) void {
        log.debug("GitAnnotatedCommit.deinit called", .{});

        raw.git_annotated_commit_free(self.commit);
        self.* = undefined;

        log.debug("annotated commit freed successfully", .{});
    }

    /// Gets the commit ID that the given `GitAnnotatedCommit` refers to.
    pub fn getCommitId(self: GitAnnotatedCommit) !GitOid {
        log.debug("GitAnnotatedCommit.getCommitId called", .{});

        const oid = GitOid{ .oid = raw.git_annotated_commit_ref(self.commit).? };

        // This check is to prevent formating the oid when we are not going to print anything
        if (@enumToInt(std.log.Level.debug) <= @enumToInt(std.log.level)) {
            var buf: [GitOid.HEX_BUFFER_SIZE]u8 = undefined;
            const slice = try oid.formatHex(&buf);
            log.debug("annotated commit id acquired: {s}", .{slice});
        }

        return oid;
    }
};

/// Basic type (loose or packed) of any Git object.
pub const GitObject = enum(c_int) {
    /// Object can be any of the following
    ANY = -2,
    /// Object is invalid.
    INVALID = -1,
    /// A commit object.
    COMMIT = 1,
    /// A tree (directory listing) object.
    TREE = 2,
    /// A file revision object.
    BLOB = 3,
    /// An annotated tag object.
    TAG = 4,
    /// A delta, base is given by an offset.
    OFS_DELTA = 6,
    /// A delta, base is given by object id.
    REF_DELTA = 7,
};

/// Unique identity of any object (commit, tree, blob, tag).
pub const GitOid = struct {
    oid: *const raw.git_oid,

    /// Size (in bytes) of a hex formatted oid
    pub const HEX_BUFFER_SIZE = raw.GIT_OID_HEXSZ;

    /// Format a git_oid into a hex string.
    ///
    /// ## Parameters
    /// * `buf` - Slice to format the oid into, must be atleast `HEX_BUFFER_SIZE` long.
    pub fn formatHex(self: GitOid, buf: []u8) ![]const u8 {
        if (buf.len < HEX_BUFFER_SIZE) return error.BufferTooShort;

        try wrapCall("git_oid_fmt", .{ buf.ptr, self.oid });

        return buf[0..HEX_BUFFER_SIZE];
    }

    /// Format a git_oid into a zero-terminated hex string.
    ///
    /// ## Parameters
    /// * `buf` - Slice to format the oid into, must be atleast `HEX_BUFFER_SIZE` + 1 long.
    pub fn formatHexZ(self: GitOid, buf: []u8) ![:0]const u8 {
        if (buf.len < (HEX_BUFFER_SIZE + 1)) return error.BufferTooShort;

        try wrapCall("git_oid_fmt", .{ buf.ptr, self.oid });
        buf[HEX_BUFFER_SIZE] = 0;

        return buf[0..HEX_BUFFER_SIZE :0];
    }

    comptime {
        std.testing.refAllDecls(@This());
    }
};

/// Memory representation of an index file.
pub const GitIndex = struct {
    index: *raw.git_index,

    /// Free an existing index object.
    pub fn deinit(self: *GitIndex) void {
        log.debug("GitIndex.deinit called", .{});

        raw.git_index_free(self.index);
        self.* = undefined;

        log.debug("index freed successfully", .{});
    }

    comptime {
        std.testing.refAllDecls(@This());
    }
};

/// An open refs database handle.
pub const GitRefDb = struct {
    ref_db: *raw.git_refdb,

    /// Free the configuration and its associated memory and files
    pub fn deinit(self: *GitRefDb) void {
        log.debug("GitRefDb.deinit called", .{});

        raw.git_refdb_free(self.ref_db);
        self.* = undefined;

        log.debug("refdb freed successfully", .{});
    }

    comptime {
        std.testing.refAllDecls(@This());
    }
};

/// Memory representation of a set of config files
pub const GitConfig = struct {
    config: *raw.git_config,

    /// Free the configuration and its associated memory and files
    pub fn deinit(self: *GitConfig) void {
        log.debug("GitConfig.deinit called", .{});

        raw.git_config_free(self.config);
        self.* = undefined;

        log.debug("config freed successfully", .{});
    }

    comptime {
        std.testing.refAllDecls(@This());
    }
};

/// Representation of a working tree
pub const GitWorktree = struct {
    worktree: *raw.git_worktree,

    /// Free a previously allocated worktree
    pub fn deinit(self: *GitWorktree) void {
        log.debug("GitWorktree.deinit called", .{});

        raw.git_worktree_free(self.worktree);
        self.* = undefined;

        log.debug("worktree freed successfully", .{});
    }

    /// Open working tree as a repository
    ///
    /// Open the working directory of the working tree as a normal repository that can then be worked on.
    pub fn repositoryOpen(self: GitWorktree) !GitRepository {
        log.debug("GitWorktree.repositoryOpen called", .{});

        var repo: ?*raw.git_repository = undefined;

        try wrapCall("git_repository_open_from_worktree", .{ &repo, self.worktree });

        log.debug("repository opened successfully", .{});

        return GitRepository{ .repo = repo.? };
    }

    comptime {
        std.testing.refAllDecls(@This());
    }
};

/// An open object database handle.
pub const GitOdb = struct {
    odb: *raw.git_odb,

    /// Close an open object database.
    pub fn deinit(self: *GitOdb) void {
        log.debug("GitOdb.deinit called", .{});

        raw.git_odb_free(self.odb);
        self.* = undefined;

        log.debug("GitOdb freed successfully", .{});
    }

    /// Create a "fake" repository to wrap an object database
    ///
    /// Create a repository object to wrap an object database to be used with the API when all you have is an object database. 
    /// This doesn't have any paths associated with it, so use with care.
    pub fn repositoryOpen(self: GitOdb) !GitRepository {
        log.debug("GitOdb.repositoryOpen called", .{});

        var repo: ?*raw.git_repository = undefined;

        try wrapCall("git_repository_wrap_odb", .{ &repo, self.odb });

        log.debug("repository opened successfully", .{});

        return GitRepository{ .repo = repo.? };
    }

    comptime {
        std.testing.refAllDecls(@This());
    }
};

/// A data buffer for exporting data from libgit2
pub const GitBuf = struct {
    buf: raw.git_buf,

    fn zero() GitBuf {
        return .{ .buf = std.mem.zeroInit(raw.git_buf, .{}) };
    }

    pub fn slice(self: GitBuf) [:0]const u8 {
        return self.buf.ptr[0..self.buf.size :0];
    }

    /// Free the memory referred to by the GitBuf.
    pub fn deinit(self: *GitBuf) void {
        log.debug("GitBuf.deinit called", .{});

        raw.git_buf_dispose(&self.buf);
        self.* = undefined;

        log.debug("GitBuf freed successfully", .{});
    }

    comptime {
        std.testing.refAllDecls(@This());
    }
};

pub const GitError = error{
    /// Generic error
    GenericError,
    /// Requested object could not be found
    NotFound,
    /// Object exists preventing operation
    Exists,
    /// More than one object matches
    Ambiguous,
    /// Output buffer too short to hold data
    BufferTooShort,
    /// A special error that is never generated by libgit2 code.  You can return it from a callback (e.g to stop an iteration)
    /// to know that it was generated by the callback and not by libgit2.
    User,
    /// Operation not allowed on bare repository
    BareRepo,
    /// HEAD refers to branch with no commits
    UnbornBranch,
    /// Merge in progress prevented operation
    Unmerged,
    /// Reference was not fast-forwardable
    NonFastForwardable,
    /// Name/ref spec was not in a valid format
    InvalidSpec,
    /// Checkout conflicts prevented operation
    Conflict,
    /// Lock file prevented operation
    Locked,
    /// Reference value does not match expected
    Modifed,
    /// Authentication error
    Auth,
    /// Server certificate is invalid
    Certificate,
    /// Patch/merge has already been applied
    Applied,
    /// The requested peel operation is not possible
    Peel,
    /// Unexpected EOF
    EndOfFile,
    /// Invalid operation or input
    Invalid,
    /// Uncommitted changes in index prevented operation
    Uncommited,
    /// The operation is not valid for a directory
    Directory,
    /// A merge conflict exists and cannot continue
    MergeConflict,
    /// A user-configured callback refused to act
    Passthrough,
    /// Signals end of iteration with iterator
    IterOver,
    /// Internal only
    Retry,
    /// Hashsum mismatch in object
    Mismatch,
    /// Unsaved changes in the index would be overwritten
    IndexDirty,
    /// Patch application failed
    ApplyFail,
};

pub const GitDetailedError = struct {
    e: *const raw.git_error,

    pub const ErrorClass = enum(c_int) {
        NONE = 0,
        NOMEMORY,
        OS,
        INVALID,
        REFERENCE,
        ZLIB,
        REPOSITORY,
        CONFIG,
        REGEX,
        ODB,
        INDEX,
        OBJECT,
        NET,
        TAG,
        TREE,
        INDEXER,
        SSL,
        SUBMODULE,
        THREAD,
        STASH,
        CHECKOUT,
        FETCHHEAD,
        MERGE,
        SSH,
        FILTER,
        REVERT,
        CALLBACK,
        CHERRYPICK,
        DESCRIBE,
        REBASE,
        FILESYSTEM,
        PATCH,
        WORKTREE,
        SHA1,
        HTTP,
        INTERNAL,
    };

    pub fn message(self: GitDetailedError) [:0]const u8 {
        return std.mem.sliceTo(self.e.message, 0);
    }

    pub fn errorClass(self: GitDetailedError) ErrorClass {
        return @intToEnum(ErrorClass, self.e.klass);
    }

    comptime {
        std.testing.refAllDecls(@This());
    }
};

inline fn wrapCall(comptime name: []const u8, args: anytype) GitError!void {
    checkForError(@call(.{}, @field(raw, name), args)) catch |err| {

        // We dont want to output log messages in tests, as the error might be expected
        if (!std.builtin.is_test) {
            if (getDetailedLastError()) |detailed| {
                log.err(name ++ " failed with error {s}/{s} - {s}", .{
                    @errorName(err),
                    @tagName(detailed.errorClass()),
                    detailed.message(),
                });
            } else {
                log.err(name ++ " failed with error {s}", .{@errorName(err)});
            }
        }

        return err;
    };
}

inline fn wrapCallWithReturn(
    comptime name: []const u8,
    args: anytype,
) GitError!@typeInfo(@TypeOf(@field(raw, name))).Fn.return_type.? {
    const value = @call(.{}, @field(raw, name), args);
    checkForError(value) catch |err| {

        // We dont want to output log messages in tests, as the error might be expected
        if (!std.builtin.is_test) {
            if (getDetailedLastError()) |detailed| {
                log.err(name ++ " failed with error {s}/{s} - {s}", .{
                    @errorName(err),
                    @tagName(detailed.errorClass()),
                    detailed.message(),
                });
            } else {
                log.err(name ++ " failed with error {s}", .{@errorName(err)});
            }
        }
        return err;
    };
    return value;
}

fn checkForError(value: raw.git_error_code) GitError!void {
    if (value >= 0) return;
    return switch (value) {
        raw.GIT_ERROR => GitError.GenericError,
        raw.GIT_ENOTFOUND => GitError.NotFound,
        raw.GIT_EEXISTS => GitError.Exists,
        raw.GIT_EAMBIGUOUS => GitError.Ambiguous,
        raw.GIT_EBUFS => GitError.BufferTooShort,
        raw.GIT_EUSER => GitError.User,
        raw.GIT_EBAREREPO => GitError.BareRepo,
        raw.GIT_EUNBORNBRANCH => GitError.UnbornBranch,
        raw.GIT_EUNMERGED => GitError.Unmerged,
        raw.GIT_ENONFASTFORWARD => GitError.NonFastForwardable,
        raw.GIT_EINVALIDSPEC => GitError.InvalidSpec,
        raw.GIT_ECONFLICT => GitError.Conflict,
        raw.GIT_ELOCKED => GitError.Locked,
        raw.GIT_EMODIFIED => GitError.Modifed,
        raw.GIT_EAUTH => GitError.Auth,
        raw.GIT_ECERTIFICATE => GitError.Certificate,
        raw.GIT_EAPPLIED => GitError.Applied,
        raw.GIT_EPEEL => GitError.Peel,
        raw.GIT_EEOF => GitError.EndOfFile,
        raw.GIT_EINVALID => GitError.Invalid,
        raw.GIT_EUNCOMMITTED => GitError.Uncommited,
        raw.GIT_EDIRECTORY => GitError.Directory,
        raw.GIT_EMERGECONFLICT => GitError.MergeConflict,
        raw.GIT_PASSTHROUGH => GitError.Passthrough,
        raw.GIT_ITEROVER => GitError.IterOver,
        raw.GIT_RETRY => GitError.Retry,
        raw.GIT_EMISMATCH => GitError.Mismatch,
        raw.GIT_EINDEXDIRTY => GitError.IndexDirty,
        raw.GIT_EAPPLYFAIL => GitError.ApplyFail,
        else => {
            log.emerg("encountered unknown libgit2 error: {}", .{value});
            unreachable;
        },
    };
}

fn formatWithoutFields(value: anytype, options: std.fmt.FormatOptions, writer: anytype, comptime blacklist: []const []const u8) !void {
    // This ANY const is a workaround for: https://github.com/ziglang/zig/issues/7948
    const ANY = "any";

    const T = @TypeOf(value);

    switch (@typeInfo(T)) {
        .Struct => |info| {
            try writer.writeAll(@typeName(T));
            try writer.writeAll("{");
            comptime var i = 0;
            outer: inline for (info.fields) |f| {
                inline for (blacklist) |blacklist_item| {
                    if (comptime std.mem.indexOf(u8, f.name, blacklist_item) != null) continue :outer;
                }

                if (i == 0) {
                    try writer.writeAll(" .");
                } else {
                    try writer.writeAll(", .");
                }

                try writer.writeAll(f.name);
                try writer.writeAll(" = ");
                try std.fmt.formatType(@field(value, f.name), ANY, options, writer, std.fmt.default_max_depth - 1);

                i += 1;
            }
            try writer.writeAll(" }");
        },
        else => {
            @compileError("Unimplemented for: " ++ @typeName(T));
        },
    }
}

comptime {
    std.testing.refAllDecls(@This());
}