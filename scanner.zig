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
        if (isAtEnd()) return self.createToken(TokenType.EOF);
        //do stuff
        const c = self.advance();

        switch (c) {
            '(' => return createToken(TokenType.LEFTPAREN),
            ')' => return createToken(TokenType.RIGHTPAREN),
            '{' => return createToken(TokenType.LEFTBRACE),
            '}' => return createToken(TokenType.RIGHTBRACE),
            ';' => return createToken(TokenType.SEMICOLON),
            ',' => return createToken(TokenType.COMMA),
            '.' => return createToken(TokenType.DOT),
            '-' => return createToken(TokenType.MINUS),
            '+' => return createToken(TokenType.PLUS),
            '/' => return createToken(TokenType.SLASH),
            '*' => return createToken(TokenType.STAR),
            '!' => {
                return createToken(if (self.match('=')) TokenType.BANGEQUAL else TokenType.BANG);
            },
            '=' => {
                return createToken(if (self.match('=')) TokenType.EQUALEQUAL else TokenType.EQUAL);
            },
            '<' => {
                return createToken(if (self.match('=')) TokenType.LESSEQUAL else TokenType.LESS);
            },
            '>' => {
                return createToken(if (self.match('=')) TokenType.GREATEREQUAL else TokenType.GREATER);
            },
            '"' => return handleString(),
        }
        return self.createErrToken("Unexpected Char");
    }

    pub inline fn handleString(self: *Self) Token {
        while (self.peek() != '"' and !isAtEnd()) {
            if (peek() == '\n') self.line += 1;
            _ = advance();
        }
        if (isAtEnd()) return createErrToken("Unterminated string.");

        _ = advance();
        return createToken(TokenType.STRING);
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
        if (isAtEnd()) return false;
        if (self.src[self.current] != expected) return false;
        self.current += 1;
        return true;
    }

    pub inline fn skipWhiteSpace(self: *Self) void {
        while (!self.isAtEnd()) {
            const c: u8 = self.peek();
            switch (c) {
                ' ', '\r', '\t' => _ = advance(),
                '\n' => {
                    self.line += 1;
                    _ = advance();
                },
                '/' => {
                    if (self.peekAt(self.current + 1) == '/') {
                        while (peek() != '\n' and !isAtEnd()) {
                            _ = advance();
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
        return self.src[self.current];
    }

    pub inline fn peekAt(self: *Self, idx: usize) u8 {
        return self.src[idx];
    }
    pub inline fn peekBack(self: *Self, idx: usize) u8 {
        return self.src[self.current + (idx)];
    }
};
