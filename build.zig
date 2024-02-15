const std = @import("std");
const fs = std.fs;

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});

    const optimize = b.standardOptimizeOption(.{});

    const step = b.step("get-metal", "this will copy the necessary frameworks for Metal");
    step.makeFn = &getMetalFrameworks;
    step.dependOn(b.default_step);

    const lib = b.addStaticLibrary(.{
        .name = "metal-frameworks",
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    const macos_path = "libs/system-sdk/macos";
    lib.addFrameworkPath(.{ .path = macos_path ++ "/Frameworks" });
    lib.addSystemIncludePath(.{ .path = macos_path ++ "/include" });
    lib.addLibraryPath(.{ .path = macos_path ++ "/lib" });

    // This declares intent for the library to be installed into the standard
    // location when the user invokes the "install" step (the default step when
    // running `zig build`).
    b.installArtifact(lib);

    // Creates a step for unit testing. This only builds the test executable
    // but does not run it.
    const main_tests = b.addTest(.{
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    const run_main_tests = b.addRunArtifact(main_tests);

    // This creates a build step. It will be visible in the `zig build --help` menu,
    // and can be selected like this: `zig build test`
    // This will evaluate the `test` step rather than the default, which is "install".
    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&run_main_tests.step);
}

fn getMetalFrameworks(_: *std.Build.Step, _: *std.Progress.Node) anyerror!void {
    const cwd = fs.cwd();
    const dst_macos_path = "libs/system-sdk/macos";
    try cwd.deleteTree(dst_macos_path);
    try cwd.makeDir(dst_macos_path);
    try cwd.makeDir(dst_macos_path ++ "/Frameworks");
    try cwd.makeDir(dst_macos_path ++ "/include");
    try cwd.makeDir(dst_macos_path ++ "/lib");

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer if (gpa.deinit() == .leak) {
        @panic("Leaked memory");
    };

    const sdk_path = "/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX14.2.sdk";
    const src_path = sdk_path ++ "/System/Library/Frameworks";
    const dst_path = dst_macos_path ++ "/Frameworks";
    try walkFramework(gpa.allocator(), src_path ++ "/Foundation.framework", dst_path ++ "/Foundation.framework");
    try walkFramework(gpa.allocator(), src_path ++ "/Metal.framework", dst_path ++ "/Metal.framework");
    try walkFramework(gpa.allocator(), src_path ++ "/MetalKit.framework", dst_path ++ "/MetalKit.framework");
    try walkFramework(gpa.allocator(), src_path ++ "/QuartzCore.framework", dst_path ++ "/QuartzCore.framework");

    const src_includes = try cwd.openDir(sdk_path ++ "/usr/include", .{});
    const dst_includes = try cwd.openDir(dst_macos_path ++ "/include", .{});
    src_includes.copyFile("libDER/libDER_config.h", dst_includes, "libDER_config.h", .{}) catch |err| std.debug.print("Error copying libDER_config.h: {}\n", .{err});
    src_includes.copyFile("libDER/DERItem.h", dst_includes, "DERItem.h", .{}) catch |err| std.debug.print("Error copying DERItem.h: {}\n", .{err});

    const lib_path = sdk_path ++ "/usr/lib";
    const src_lib = try cwd.openDir(lib_path, .{});
    const dst_lib = try cwd.openDir(dst_macos_path ++ "/lib", .{});
    src_lib.copyFile("libobjc.tbd", dst_lib, "libobjc.tbd", .{}) catch |err| std.debug.print("Error copying libobjc.tbd: {}\n", .{err});
    src_lib.copyFile("libobjc.A.tbd", dst_lib, "libobjc.A.tbd", .{}) catch |err| std.debug.print("Error copying libobjc.A.tbd: {}\n", .{err});
}

fn walkFramework(alloc: std.mem.Allocator, src_path: []const u8, dst_path: []const u8) anyerror!void {
    const cwd = fs.cwd();

    var framework = cwd.openIterableDir(src_path, .{}) catch |err| {
        std.debug.print("Error opening source directory {s}: {}\n", .{ src_path, err });
        return error.UnexpectedEntryKind;
    };
    defer framework.close();

    try cwd.makeDir(dst_path);
    var dst_dir = cwd.openDir(dst_path, .{}) catch |err| {
        std.debug.print("Error opening destination directory {s}: {}\n", .{ dst_path, err });
        return error.FileNotFound;
    };
    defer dst_dir.close();

    var walker = try framework.walk(alloc);
    defer walker.deinit();

    while (try walker.next()) |entry| {
        switch (entry.kind) {
            .file => {
                entry.dir.copyFile(entry.basename, dst_dir, entry.path, .{}) catch |err| std.debug.print("Error copying {s}: {}\n", .{ entry.path, err });
            },
            .directory => {
                var new_dst_path = try std.fmt.allocPrint(alloc, "{s}/{s}", .{ dst_path, entry.path });
                defer alloc.free(new_dst_path);

                cwd.makeDir(new_dst_path) catch |err| std.debug.print("Error creating directory {s}: {}\n", .{ new_dst_path, err });
            },
            .sym_link => {
                std.debug.print("Symlinks are not supported\n", .{});
            },
            else => {
                std.debug.print("Unexpected entry kind: {}\n", .{entry.kind});
            },
        }
    }
}
