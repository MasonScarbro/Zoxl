const Scanner = @import("./scanner.zig").Scanner;
const std = @import("std");
const TokenType = @import("./scanner.zig").TokenType;
const Token = @import("./scanner.zig").Token;
const Chunk = @import("./chunk.zig").Chunk;
const OpCode = @import("./chunk.zig").OpCode;
const Value = @import("./value.zig").Value;
const disassembleChunk = @import("./debugging.zig").disassembleChunk;

const stderr = std.io.getStdErr().writer();

const CompileError = error{
    CompileErr,
    ScannerErr,
};

const Precedence = enum {
    NONE,
    ASSIGNMENT, // =
    OR, // or
    AND, // and
    EQUALITY, // == !=
    COMPARISON, // < > <= >=
    TERM, // + -
    FACTOR, // * /
    UNARY, //-
    CALL, // . ()  // !
    PRIMARY,
};

const ParseFn = *const fn (parser: *Parser) void;

const ParseRule = struct {
    prefix: ?ParseFn,
    infix: ?ParseFn,
    precedence: Precedence,

    pub fn init(prefix: ?ParseFn, infix: ?ParseFn, precedence: Precedence) ParseRule {
        return .{
            .prefix = prefix,
            .infix = infix,
            .precedence = precedence,
        };
    }
};

pub fn compile(src: []const u8, chunk: *Chunk) CompileError!void {
    const scanner = Scanner.init(src);
    const compiler = Compiler.init(&chunk);
    const parser = Parser.init(&scanner, &compiler);
    parser.advance(); //Kick off parser
    if (parser.hadErr == true) return CompileError.ScannerErr;
    parser.expr();
    parser.consume(TokenType.EOF, "Expected End Of Expression");
}

pub const Parser = struct {
    const Self = @This();

    current: Token,
    previous: Token,
    scanner: *Scanner,
    compiler: *Compiler,
    hadErr: bool = false,
    panicMode: bool = false,

    pub fn init(scanner: *Scanner, compiler: *Compiler) Self {
        return Self{
            .scanner = scanner,
            .compiler = compiler,
            .current = undefined,
            .previous = undefined,
        };
    }

    pub fn advance(self: *Self) void {
        self.previous = self.current;

        while (true) {
            self.current = self.scanner.scanToken();
            if (self.current.token_type != TokenType.ERROR) break;
            //else
            self.errAtCurrent(self.current.lexeme);
        }
    }

    pub fn consume(self: *Self, ttype: TokenType, msg: []const u8) void {
        if (self.current.token_type == ttype) {
            self.advance();
            return;
        }
        //else

        self.errAtCurrent(msg);
    }

    pub fn expr(self: *Self) void {
        self.parsePrecedence(Precedence.ASSIGNMENT);
    }

    pub fn grouping(self: *Self) void {
        self.expr();
        self.consume(TokenType.RIGHTPAREN, "Expected ')' after expression");
    }

    pub fn unary(self: *Self) void {
        const operType = self.previous.token_type;

        //compile the operand
        self.parsePrecedence(Precedence.UNARY);
        switch (operType) {
            .MINUS => self.compiler.emitByte(OpCode.op_negate.toU8(), self.scanner.line),
            else => return, //unreachable
        }
    }

    pub fn binary(self: *Self) void {
        const operType = self.previous.token_type;
        const rule = getRule(operType);
        self.parsePrecedence(rule.precedence + 1); //this is shifting the byte by one

        switch (operType) {
            .PLUS => self.compiler.emitByte(OpCode.op_add.toU8(), self.scanner.line),
            .MINUS => self.compiler.emitByte(OpCode.op_subtract.toU8(), self.scanner.line),
            .STAR => self.compiler.emitByte(OpCode.op_mult.toU8(), self.scanner.line),
            .SLASH => self.compiler.emitByte(OpCode.op_divide.toU8(), self.scanner.line),
            else => return, //unreachable

        }
    }

    pub fn parsePrecedence(self: *Self, precedence: Precedence) void {
        self.advance();
        const prefixRule = getRule(self.previous.token_type).prefix;
        if (prefixRule == null) {
            self.err("Expexect expression.");
            return;
        }
        prefixRule(self);

        while (@intFromEnum(precedence) <= @intFromEnum(getRule(self.current.token_type).precedence)) {
            self.advance();
            const infixRule = getRule(self.previous.token_type).infix;
            infixRule(self);
        }
    }

    //---------------- ERRHANDLING --------------------------//
    pub fn errAtCurrent(self: *Self, msg: []const u8) void {
        self.errAt(&self.current, msg);
    }

    pub fn err(self: *Self, msg: []const u8) void {
        self.errAt(&self.previous, msg);
    }

    pub fn errAt(self: *Self, token: *Token, msg: []const u8) void {
        if (self.panicMode) return;
        self.panicMode = true;
        stderr.print("[line {d}] Error\n", .{token.line});

        if (token.token_type == TokenType.EOF) {
            stderr.print("Err at end", .{});
        } else if (token.token_type == TokenType.ERROR) {
            //NOTHING FOR NOW
        } else {
            stderr.print(" at '{s}'", .{token.lexeme});
        }

        stderr.print(": {s}\n", .{msg});
        self.hadErr = true;
    }
    //---------------------------------------------------------//
};

pub fn getRule(ttype: TokenType) ParseRule {
    const rule = switch (ttype) {
        .LEFTPAREN => comptime ParseRule.init(Parser.grouping, null, Precedence.NONE),
        .RIGHTPAREN => comptime ParseRule.init(null, null, Precedence.NONE),
        .LEFTBRACE => comptime ParseRule.init(null, null, Precedence.NONE),
        .RIGHTBRACE => comptime ParseRule.init(null, null, Precedence.NONE),
        .COMMA => comptime ParseRule.init(null, null, Precedence.NONE),
        .DOT => comptime ParseRule.init(null, null, Precedence.NONE),
        .MINUS => comptime ParseRule.init(Parser.unary, Parser.binary, Precedence.TERM),
        .PLUS => comptime ParseRule.init(null, Parser.binary, Precedence.TERM),
        .SEMICOLON => comptime ParseRule.init(null, null, Precedence.NONE),
        .SLASH => comptime ParseRule.init(null, Parser.binary, Precedence.FACTOR),
        .STAR => comptime ParseRule.init(null, Parser.binary, Precedence.FACTOR),
        .BANG => comptime ParseRule.init(Parser.unary, null, Precedence.NONE),
        .BANG_EQUAL => comptime ParseRule.init(null, Parser.binary, Precedence.EQUALITY),
        .EQUAL => comptime ParseRule.init(null, null, Precedence.NONE),
        .EQUAL_EQUAL => comptime ParseRule.init(null, Parser.binary, Precedence.EQUALITY),
        .GREATER => comptime ParseRule.init(null, Parser.binary, Precedence.COMPARISON),
        .GREATER_EQUAL => comptime ParseRule.init(null, Parser.binary, Precedence.COMPARISON),
        .LESS => comptime ParseRule.init(null, Parser.binary, Precedence.COMPARISON),
        .LESS_EQUAL => comptime ParseRule.init(null, Parser.binary, Precedence.COMPARISON),
        .IDENTIFIER => comptime ParseRule.init(Parser.variable, null, Precedence.NONE),
        .STRING => comptime ParseRule.init(Parser.string, null, Precedence.NONE),
        .NUMBER => comptime ParseRule.init(Parser.number, null, Precedence.NONE),
        .AND => comptime ParseRule.init(null, Parser.logical_and, Precedence.AND),
        .CLASS => comptime ParseRule.init(null, null, Precedence.NONE),
        .ELSE => comptime ParseRule.init(null, null, Precedence.NONE),
        .FALSE => comptime ParseRule.init(Parser.literal, null, Precedence.NONE),
        .FOR => comptime ParseRule.init(null, null, Precedence.NONE),
        .FUN => comptime ParseRule.init(null, null, Precedence.NONE),
        .IF => comptime ParseRule.init(null, null, Precedence.NONE),
        .NIL => comptime ParseRule.init(Parser.literal, null, Precedence.NONE),
        .OR => comptime ParseRule.init(null, Parser.logical_or, Precedence.OR),
        .PRINT => comptime ParseRule.init(null, null, Precedence.NONE),
        .RETURN => comptime ParseRule.init(null, null, Precedence.NONE),
        .SUPER => comptime ParseRule.init(Parser.super, null, Precedence.NONE),
        .THIS => comptime ParseRule.init(Parser.this, null, Precedence.NONE),
        .TRUE => comptime ParseRule.init(Parser.literal, null, Precedence.NONE),
        .VAR => comptime ParseRule.init(null, null, Precedence.NONE),
        .WHILE => comptime ParseRule.init(null, null, Precedence.NONE),
        .ERROR => comptime ParseRule.init(null, null, Precedence.NONE),
        .EOF => comptime ParseRule.init(null, null, Precedence.NONE),
    };
    return rule;
}

pub const Compiler = struct {
    const Self = @This();

    compilingChunk: *Chunk = undefined,

    pub fn init(chunk: *Chunk) Self {
        return Self{
            .compilingChunk = chunk,
        };
    }

    pub fn emitByte(self: *Self, byte: u8, line: usize) void {
        try self.currentChunk().writeChunk(byte, line);
    }

    pub fn currentChunk(self: *Self) *Chunk {
        return self.compilingChunk;
    }

    pub fn endCompiler(self: *Self) void {
        self.emitReturn();
    }

    pub fn emitReturn(self: *Self, hadErr: bool, line: usize) void {
        self.emitByte(OpCode.op_return.toU8(), line);
        if (!hadErr) {
            disassembleChunk(self.currentChunk(), "code");
        }
    }

    pub fn emitConstant(self: *Self, value: Value, line: usize) void {
        // we dont need to check for the constant exceeding the amount
        // since writeConstant does that for us
        self.currentChunk().writeConstant(value, line);
    }

    pub fn emitBytes(self: *Self, byte1: u8, byte2: u8, line: usize) void {
        self.emitByte(byte1, line);
        self.emitByte(byte2, line);
    }
};
