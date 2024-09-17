const std = @import("std");
const Scanner = @import("./scanner.zig").Scanner;
const TokenType = @import("./scanner.zig").TokenType;

test "scanner should correctly tokenize only keywords" {
    const src = "var if else class fun return while for and or print super this true false nil";
    var scanner = Scanner.init(src);

    var token = scanner.scanToken();
    std.debug.print("\nExpected: {}, Got: {}, lexeme: {s}\n", .{ TokenType.VAR, token.token_type, token.lexeme });
    try std.testing.expect(token.token_type == TokenType.VAR);
    try std.testing.expectEqualStrings("var", token.lexeme);

    token = scanner.scanToken();
    std.debug.print("\nExpected: {}, Got: {}, lexeme: {s}\n", .{ TokenType.IF, token.token_type, token.lexeme });
    try std.testing.expect(token.token_type == TokenType.IF);
    try std.testing.expectEqualStrings("if", token.lexeme);

    token = scanner.scanToken();
    std.debug.print("\nExpected: {}, Got: {}, lexeme: {s}\n", .{ TokenType.ELSE, token.token_type, token.lexeme });
    try std.testing.expect(token.token_type == TokenType.ELSE);
    try std.testing.expectEqualStrings("else", token.lexeme);

    token = scanner.scanToken();
    std.debug.print("\nExpected: {}, Got: {}, lexeme: {s}\n", .{ TokenType.CLASS, token.token_type, token.lexeme });
    try std.testing.expect(token.token_type == TokenType.CLASS);
    try std.testing.expectEqualStrings("class", token.lexeme);

    token = scanner.scanToken();
    std.debug.print("\nExpected: {}, Got: {}, lexeme: {s}\n", .{ TokenType.FUN, token.token_type, token.lexeme });
    try std.testing.expect(token.token_type == TokenType.FUN);
    try std.testing.expectEqualStrings("fun", token.lexeme);

    token = scanner.scanToken();
    std.debug.print("\nExpected: {}, Got: {}, lexeme: {s}\n", .{ TokenType.RETURN, token.token_type, token.lexeme });
    try std.testing.expect(token.token_type == TokenType.RETURN);
    try std.testing.expectEqualStrings("return", token.lexeme);

    token = scanner.scanToken();
    std.debug.print("\nExpected: {}, Got: {}, lexeme: {s}\n", .{ TokenType.WHILE, token.token_type, token.lexeme });
    try std.testing.expect(token.token_type == TokenType.WHILE);
    try std.testing.expectEqualStrings("while", token.lexeme);

    token = scanner.scanToken();
    std.debug.print("\nExpected: {}, Got: {}, lexeme: {s}\n", .{ TokenType.FOR, token.token_type, token.lexeme });
    try std.testing.expect(token.token_type == TokenType.FOR);
    try std.testing.expectEqualStrings("for", token.lexeme);

    token = scanner.scanToken();
    std.debug.print("\nExpected: {}, Got: {}, lexeme: {s}\n", .{ TokenType.AND, token.token_type, token.lexeme });
    try std.testing.expect(token.token_type == TokenType.AND);
    try std.testing.expectEqualStrings("and", token.lexeme);

    token = scanner.scanToken();
    std.debug.print("\nExpected: {}, Got: {}, lexeme: {s}\n", .{ TokenType.OR, token.token_type, token.lexeme });
    try std.testing.expect(token.token_type == TokenType.OR);
    try std.testing.expectEqualStrings("or", token.lexeme);

    token = scanner.scanToken();
    std.debug.print("\nExpected: {}, Got: {}, lexeme: {s}\n", .{ TokenType.PRINT, token.token_type, token.lexeme });
    try std.testing.expect(token.token_type == TokenType.PRINT);
    try std.testing.expectEqualStrings("print", token.lexeme);

    token = scanner.scanToken();
    std.debug.print("\nExpected: {}, Got: {}, lexeme: {s}\n", .{ TokenType.SUPER, token.token_type, token.lexeme });
    try std.testing.expect(token.token_type == TokenType.SUPER);
    try std.testing.expectEqualStrings("super", token.lexeme);

    token = scanner.scanToken();
    std.debug.print("\nExpected: {}, Got: {}, lexeme: {s}\n", .{ TokenType.THIS, token.token_type, token.lexeme });
    try std.testing.expect(token.token_type == TokenType.THIS);
    try std.testing.expectEqualStrings("this", token.lexeme);

    token = scanner.scanToken();
    std.debug.print("\nExpected: {}, Got: {}, lexeme: {s}\n", .{ TokenType.TRUE, token.token_type, token.lexeme });
    try std.testing.expect(token.token_type == TokenType.TRUE);
    try std.testing.expectEqualStrings("true", token.lexeme);

    token = scanner.scanToken();
    std.debug.print("\nExpected: {}, Got: {}, lexeme: {s}\n", .{ TokenType.FALSE, token.token_type, token.lexeme });
    try std.testing.expect(token.token_type == TokenType.FALSE);
    try std.testing.expectEqualStrings("false", token.lexeme);

    token = scanner.scanToken();
    std.debug.print("\nExpected: {}, Got: {}, lexeme: {s}\n", .{ TokenType.NIL, token.token_type, token.lexeme });
    try std.testing.expect(token.token_type == TokenType.NIL);
    try std.testing.expectEqualStrings("nil", token.lexeme);

    token = scanner.scanToken();
    try std.testing.expect(token.token_type == TokenType.EOF);
}

test "scanner should correctly tokenize source code" {
    const src = "var x = 10;";
    var scanner = Scanner.init(src);

    var token = scanner.scanToken();
    std.debug.print("Expected: {}, Got: {}\n", .{ TokenType.VAR, token.token_type });
    try std.testing.expect(token.token_type == TokenType.VAR);
    try std.testing.expectEqualStrings("var", token.lexeme);

    token = scanner.scanToken();
    std.debug.print("Expected: {}, Got: {}\n", .{ TokenType.IDENTIFIER, token.token_type });
    try std.testing.expect(token.token_type == TokenType.IDENTIFIER);
    try std.testing.expectEqualStrings("x", token.lexeme);

    token = scanner.scanToken();
    std.debug.print("Expected: {}, Got: {}\n", .{ TokenType.EQUAL, token.token_type });
    try std.testing.expect(token.token_type == TokenType.EQUAL);
    try std.testing.expectEqualStrings("=", token.lexeme);

    token = scanner.scanToken();
    std.debug.print("Expected: {}, Got: {}\n", .{ TokenType.NUMBER, token.token_type });
    try std.testing.expect(token.token_type == TokenType.NUMBER);
    try std.testing.expectEqualStrings("10", token.lexeme);

    token = scanner.scanToken();
    std.debug.print("Expected: {}, Got: {}\n", .{ TokenType.SEMICOLON, token.token_type });
    try std.testing.expect(token.token_type == TokenType.SEMICOLON);
    try std.testing.expectEqualStrings(";", token.lexeme);

    token = scanner.scanToken();
    std.debug.print("Expected: {}, Got: {}\n", .{ TokenType.EOF, token.token_type });
    try std.testing.expect(token.token_type == TokenType.EOF);
}
