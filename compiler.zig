const Scanner = @import("./scanner.zig").Scanner;
const std = @import("std");
const TokenType = @import("./scanner.zig").TokenType;
const Token = @import("./scanner.zig").Token;

pub fn compile(src: []const u8) void {
    const scanner = Scanner.init(src);
    var line = -1;
    while (true) {
        const token = scanner.scanToken();
        if (token.line != line) {
            std.debug.print("{:4d}", .{token.line});
            line = token.line;
        } else {
            std.debug.print("   | ");
        }
        std.debug.print("{:2d} '{:s}'\n", .{ token.token_type, token.length, token.start });
        if (token.type == TokenType.EOF) break;
    }
}
