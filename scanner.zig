const std = @import("std");

pub const TokenType = enum {
    // Single-character tokens.
    LEFTPAREN,
    RIGHTPAREN,
    LEFTBRACE,
    RIGHTBRACE,
    COMMA,
    DOT,
    MINUS,
    PLUS,
    SEMICOLON,
    SLASH,
    STAR,

    // One or two character tokens.
    BANG,
    BANGEQUAL,
    EQUAL,
    EQUALEQUAL,
    GREATER,
    GREATEREQUAL,
    LESS,
    LESSEQUAL,

    // Literals.
    IDENTIFIER,
    STRING,
    NUMBER,

    // Keywords.
    AND,
    CLASS,
    ELSE,
    FALSE,
    FOR,
    FUN,
    IF,
    NIL,
    OR,
    PRINT,
    RETURN,
    SUPER,
    THIS,
    TRUE,
    VAR,
    WHILE,
    ERROR,
    EOF,
};

pub const Token = struct {
    token_type: TokenType,
    lexeme: []const u8,
    line: usize,
};

pub const Scanner = struct {
    const Self = @This();

    src: []const u8,
    start: usize = 0,
    current: usize = 0,
    line: usize = 1,

    pub fn init(src: []const u8) Self {
        return Self{ .src = src, .start = 0, .current = 0, .line = 1 };
    }

    pub fn scanToken(self: *Self) Token {
        self.skipWhiteSpace();
        self.start = self.current;
        if (self.isAtEnd()) return self.createToken(TokenType.EOF);
        //do stuff
        //std.debug.print("\n start = {c}", .{self.src[self.start]});
        //std.debug.print("\n current = {c}\n", .{self.src[self.current]});
        const c = self.advance();
        //std.debug.print("\n c = {c}\n", .{c});
        if (isDigit(c)) return self.handleNumber();
        if (isAlpha(c)) return self.handleIdentifier();

        switch (c) {
            '(' => return self.createToken(TokenType.LEFTPAREN),
            ')' => return self.createToken(TokenType.RIGHTPAREN),
            '{' => return self.createToken(TokenType.LEFTBRACE),
            '}' => return self.createToken(TokenType.RIGHTBRACE),
            ';' => return self.createToken(TokenType.SEMICOLON),
            ',' => return self.createToken(TokenType.COMMA),
            '.' => return self.createToken(TokenType.DOT),
            '-' => return self.createToken(TokenType.MINUS),
            '+' => return self.createToken(TokenType.PLUS),
            '/' => return self.createToken(TokenType.SLASH),
            '*' => return self.createToken(TokenType.STAR),
            '!' => {
                return self.createToken(if (self.match('=')) TokenType.BANGEQUAL else TokenType.BANG);
            },
            '=' => {
                return self.createToken(if (self.match('=')) TokenType.EQUALEQUAL else TokenType.EQUAL);
            },
            '<' => {
                return self.createToken(if (self.match('=')) TokenType.LESSEQUAL else TokenType.LESS);
            },
            '>' => {
                return self.createToken(if (self.match('=')) TokenType.GREATEREQUAL else TokenType.GREATER);
            },
            '"' => return self.handleString(),
            else => return self.createErrToken("Unexpected Char"),
        }
    }

    pub inline fn handleString(self: *Self) Token {
        while (self.peek() != '"' and !self.isAtEnd()) {
            if (self.peek() == '\n') self.line += 1;
            _ = self.advance();
        }
        if (self.isAtEnd()) return self.createErrToken("Unterminated string.");

        _ = self.advance();
        return self.createToken(TokenType.STRING);
    }

    pub inline fn handleNumber(self: *Self) Token {
        while (isDigit(self.peek())) _ = self.advance();

        if (self.peek() == '.' and isDigit(self.peekNext())) {
            _ = self.advance();
            while (isDigit(self.peek())) _ = self.advance();
        }

        return self.createToken(TokenType.NUMBER);
    }

    pub inline fn handleIdentifier(self: *Self) Token {
        std.debug.print("\nINSIDE handleIdentifier\n", .{});
        while (isAlpha(self.peek()) or isDigit(self.peek())) _ = self.advance();
        return self.createToken(self.identifierType());
    }

    pub inline fn isAtEnd(self: *Self) bool {
        return self.current >= self.src.len;
    }

    pub inline fn createToken(self: *Self, ttype: TokenType) Token {
        return Token{
            .token_type = ttype,
            .line = self.line,
            .lexeme = self.src[self.start..self.current],
        };
    }

    pub inline fn createErrToken(self: *Self, msg: []const u8) Token {
        return Token{ .token_type = TokenType.ERROR, .lexeme = msg, .line = self.line };
    }

    pub inline fn advance(self: *Self) u8 {
        self.current += 1;
        return self.src[self.current - 1];
    }

    pub inline fn match(self: *Self, expected: u8) bool {
        if (self.isAtEnd()) return false;
        if (self.src[self.current] != expected) return false;
        self.current += 1;
        return true;
    }

    pub inline fn identifierType(self: *Self) TokenType {
        std.debug.print("\n INSIDE IDENTIFIERTYPE", .{});
        std.debug.print("\n self.src[self.start] = {c}", .{self.src[self.start]});
        switch (self.src[self.start]) {
            'a' => return self.checkKeyword(1, 2, "nd", TokenType.AND),
            'c' => return self.checkKeyword(1, 4, "lass", TokenType.CLASS),
            'e' => return self.checkKeyword(1, 3, "lse", TokenType.ELSE),
            'i' => return self.checkKeyword(1, 1, "f", TokenType.IF),
            'n' => return self.checkKeyword(1, 2, "il", TokenType.NIL),
            'o' => return self.checkKeyword(1, 1, "r", TokenType.OR),
            'p' => return self.checkKeyword(1, 4, "rint", TokenType.PRINT),
            'r' => return self.checkKeyword(1, 5, "eturn", TokenType.RETURN),
            's' => return self.checkKeyword(1, 4, "uper", TokenType.SUPER),
            'v' => return self.checkKeyword(1, 2, "ar", TokenType.VAR),
            'w' => return self.checkKeyword(1, 4, "hile", TokenType.WHILE),
            'f' => {
                if (self.current - self.start > 1) {
                    std.debug.print("\n 'f' case looking for next: {c}", .{self.src[self.start + 1]});
                    return switch (self.src[self.start + 1]) {
                        'a' => return self.checkKeyword(2, 3, "lse", TokenType.FALSE),
                        'o' => return self.checkKeyword(2, 1, "r", TokenType.FOR),
                        'u' => return self.checkKeyword(2, 1, "n", TokenType.FUN),
                        else => return TokenType.IDENTIFIER,
                    };
                }
            },
            't' => {
                if (self.current - self.start > 1) {
                    std.debug.print("\n 't' case looking for next: {c}", .{self.src[self.start + 1]});
                    return switch (self.src[self.start + 1]) {
                        'h' => return self.checkKeyword(2, 2, "is", TokenType.THIS),
                        'r' => return self.checkKeyword(2, 2, "ue", TokenType.TRUE),
                        else => return TokenType.IDENTIFIER,
                    };
                }
            },
            else => return TokenType.IDENTIFIER,
        }
        return TokenType.IDENTIFIER;
    }

    // pub inline fn checkKeyword(self: *Self, keyword: []const u8, ttype: TokenType) TokenType {
    //     std.debug.print("\n INSIDE CHECKKEYWORD ", .{});
    //     std.debug.print("\n keyword: {s} self.src[self.start..self.current]: {s}\n", .{ keyword, self.src[self.start..self.current] });
    //     if (std.mem.eql(u8, keyword, self.src[self.start..self.current])) {
    //         return ttype;
    //     }
    //     return TokenType.IDENTIFIER;
    // }

    pub inline fn checkKeyword(self: *Self, start: usize, len: usize, rest: []const u8, ttype: TokenType) TokenType {
        const lexeme_len = self.current - self.start;
        std.debug.print("\n INSIDE CHECKKEYWORD ", .{});
        std.debug.print("\n rest: {s} self.src[self.start + start .. self.start + start + len]: {s}\n", .{ rest, self.src[self.start + start .. self.start + start + len] });
        // Check if the length of the current lexeme matches the keyword's length
        if (lexeme_len == start + len) {
            // Compare the substring from start to current with the expected keyword
            if (std.mem.eql(u8, self.src[self.start + start .. self.start + start + len], rest)) {
                return ttype;
            }
        }

        return TokenType.IDENTIFIER;
    }

    pub inline fn isDigit(c: u8) bool {
        return c >= '0' and c <= '9';
    }

    pub inline fn isAlpha(c: u8) bool {
        return (c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z') or (c == '_');
    }

    pub inline fn skipWhiteSpace(self: *Self) void {
        while (!self.isAtEnd()) {
            const c: u8 = self.peek();
            switch (c) {
                ' ', '\r', '\t' => _ = self.advance(),
                '\n' => {
                    self.line += 1;
                    _ = self.advance();
                },
                '/' => {
                    if (self.peekAt(self.current + 1) == '/') {
                        while (self.peek() != '\n' and !self.isAtEnd()) {
                            _ = self.advance();
                        }
                    } else {
                        return;
                    }
                },
                else => return,
            }
        }
    }

    pub inline fn peek(self: *Self) u8 {
        if (self.isAtEnd()) return 0;
        return self.src[self.current];
    }

    pub inline fn peekNext(self: *Self) u8 {
        if (self.current + 1 >= self.src.len) return 0;
        return self.src[self.current + 1];
    }
    pub inline fn peekAt(self: *Self, idx: usize) u8 {
        return self.src[idx];
    }
    pub inline fn peekBack(self: *Self, idx: usize) u8 {
        return self.src[self.current + (idx)];
    }
};
