const Scanner = @import("./scanner.zig").Scanner;
const std = @import("std");
const TokenType = @import("./scanner.zig").TokenType;
const Token = @import("./scanner.zig").Token;
const Chunk = @import("./chunk.zig").Chunk;
const OpCode = @import("./chunk.zig").OpCode;
const Value = @import("./value.zig").Value;
const Object = @import("./object.zig");
const Vm = @import("./vm.zig").Vm;
const disassembleChunk = @import("./debugging.zig").disassembleChunk;
const initStdErr = @import("./main.zig").initStdErr();

const debug_parse_rule = true;

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

const ParseFn = *const fn (parser: *Parser, canAssign: bool) void;

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

pub fn compile(vm: *Vm, src: []const u8, chunk: *Chunk) CompileError!void {
    var scanner = Scanner.init(src);
    var compiler = Compiler.init(chunk);
    var parser = Parser.init(vm, &scanner, &compiler);
    parser.advance(); //Kick off parser
    if (parser.hadErr == true) return CompileError.ScannerErr;
    while (!parser.match(TokenType.EOF)) {
        parser.declaration();
    }
    parser.consume(.EOF, "Expect end of expression");
    compiler.endCompiler(parser.previous.line);
}

pub const Parser = struct {
    const Self = @This();

    current: Token,
    previous: Token,
    scanner: *Scanner,
    compiler: *Compiler,
    hadErr: bool = false,
    panicMode: bool = false,
    vm: *Vm,

    pub fn init(vm: *Vm, scanner: *Scanner, compiler: *Compiler) Self {
        return Self{
            .scanner = scanner,
            .compiler = compiler,
            .current = undefined,
            .previous = undefined,
            .vm = vm,
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

    pub fn string(self: *Self, canAssign: bool) void {
        _ = canAssign;
        const strObj = Object.StringObj.copyStr(self.vm, self.previous.lexeme);
        self.compiler.emitConstant(Value.ObjectValue(&strObj.obj), self.previous.line);
    }

    pub fn variable(self: *Self, canAssign: bool) void {
        self.namedVar(self.previous, canAssign);
    }

    pub fn namedVar(self: *Self, name: Token, canAssign: bool) void {
        const arg = self.identifierConst(name);
        if (canAssign and self.match(TokenType.EQUAL)) {
            self.expr();
            self.compiler.emitBytes(OpCode.op_set_global.toU8(), arg, self.previous.line);
        } else {
            self.compiler.emitBytes(OpCode.op_get_global.toU8(), arg, self.previous.line);
        }
    }

    pub fn number(self: *Self, canAssign: bool) void {
        _ = canAssign;
        const value = std.fmt.parseFloat(f64, self.previous.lexeme) catch unreachable;
        self.compiler.emitConstant(Value.NumberValue(value), self.previous.line);
    }

    pub fn expr(self: *Self) void {
        self.parsePrecedence(Precedence.ASSIGNMENT);
    }

    pub fn declaration(self: *Self) void {
        if (self.match(TokenType.VAR)) {
            self.varDeclaration();
        } else {
            self.statement();
        }
        if (self.panicMode) self.sync();
    }

    pub fn statement(self: *Self) void {
        if (self.match(TokenType.PRINT)) {
            self.printStatement();
        } else {
            self.exprStatement();
        }
    }

    pub fn exprStatement(self: *Self) void {
        self.expr();
        self.consume(TokenType.SEMICOLON, "Expected ';' after expression");
        self.compiler.emitByte(OpCode.op_pop.toU8(), self.previous.line);
    }

    pub fn printStatement(self: *Self) void {
        self.expr();
        self.consume(TokenType.SEMICOLON, "Expected ';' after value.");
        self.compiler.emitByte(OpCode.op_print.toU8(), self.previous.line);
    }

    pub fn varDeclaration(self: *Self) void {
        const global = self.parseVariable("Expected variable Name");

        if (self.match(TokenType.EQUAL)) {
            self.expr();
        } else {
            self.compiler.emitByte(OpCode.op_nil.toU8(), self.previous.line);
        }

        self.consume(TokenType.SEMICOLON, "Expected ';' after variable declaration.");
        self.defineVar(global);
    }

    inline fn parseVariable(self: *Self, errmsg: []const u8) u8 {
        self.consume(TokenType.IDENTIFIER, errmsg);
        return self.identifierConst(self.previous);
    }

    inline fn identifierConst(self: *Self, tok: Token) u8 {
        const identifier = Object.StringObj.copyStr(self.vm, tok.lexeme);
        return self.makeConstant(Value.ObjectValue(&identifier.obj));
    }

    inline fn makeConstant(self: *Self, val: Value) u8 {
        const constant = self.compiler.currentChunk().addConstant(val);
        return @as(u8, @truncate(constant));
    }

    inline fn defineVar(self: *Self, global: u8) void {
        self.compiler.emitBytes(OpCode.op_define_global.toU8(), global, self.previous.line);
    }

    pub fn grouping(self: *Self, canAssign: bool) void {
        _ = canAssign;
        self.expr();
        self.consume(TokenType.RIGHTPAREN, "Expected ')' after expression");
    }

    pub fn literal(self: *Self, canAssign: bool) void {
        _ = canAssign;
        switch (self.previous.token_type) {
            .FALSE => self.compiler.emitByte(OpCode.op_false.toU8(), self.previous.line),
            .TRUE => self.compiler.emitByte(OpCode.op_true.toU8(), self.previous.line),
            .NIL => self.compiler.emitByte(OpCode.op_nil.toU8(), self.previous.line),
            else => unreachable,
        }
    }

    pub fn unary(self: *Self, canAssign: bool) void {
        _ = canAssign;
        const operType = self.previous.token_type;

        //compile the operand
        self.parsePrecedence(Precedence.UNARY);
        switch (operType) {
            .BANG => self.compiler.emitByte(OpCode.op_not.toU8(), self.previous.line),
            .MINUS => self.compiler.emitByte(OpCode.op_negate.toU8(), self.previous.line),
            else => return, //unreachable
        }
    }

    pub fn binary(self: *Self, canAssign: bool) void {
        _ = canAssign;
        const operType = self.previous.token_type;
        const rule = getRule(operType);
        self.parsePrecedence(@enumFromInt(@intFromEnum(rule.precedence) + 1)); //this is shifting the byte by one

        switch (operType) {
            .PLUS => self.compiler.emitByte(OpCode.op_add.toU8(), self.previous.line),
            .MINUS => self.compiler.emitByte(OpCode.op_subtract.toU8(), self.previous.line),
            .STAR => self.compiler.emitByte(OpCode.op_mult.toU8(), self.previous.line),
            .SLASH => self.compiler.emitByte(OpCode.op_divide.toU8(), self.previous.line),
            .BANGEQUAL => self.compiler.emitBytes(OpCode.op_equal.toU8(), OpCode.op_not.toU8(), self.previous.line),
            .EQUALEQUAL => self.compiler.emitByte(OpCode.op_equal.toU8(), self.previous.line),
            .GREATER => self.compiler.emitByte(OpCode.op_greater.toU8(), self.previous.line),
            .GREATEREQUAL => self.compiler.emitBytes(OpCode.op_less.toU8(), OpCode.op_not.toU8(), self.previous.line),
            .LESS => self.compiler.emitByte(OpCode.op_less.toU8(), self.previous.line),
            .LESSEQUAL => self.compiler.emitBytes(OpCode.op_greater.toU8(), OpCode.op_not.toU8(), self.previous.line),
            else => unreachable,
        }
    }

    pub fn parsePrecedence(self: *Self, precedence: Precedence) void {
        self.advance();
        const prefixRule = getRule(self.previous.token_type).prefix orelse {
            self.err("Expected expression.");
            return;
        };

        const canAssign = @intFromEnum(precedence) <= @intFromEnum(Precedence.ASSIGNMENT);
        prefixRule(self, canAssign);

        while (@intFromEnum(precedence) <= @intFromEnum(getRule(self.current.token_type).precedence)) {
            self.advance();
            const infixRule = getRule(self.previous.token_type).infix orelse {
                self.err("Expected expression.");
                return;
            };
            infixRule(self, canAssign);
        }
        if (canAssign and self.match(TokenType.EQUAL)) {
            self.err("Invalid assignment target");
        }
    }

    //------- Proceedings and Checkings ------- //

    pub fn match(self: *Self, ttype: TokenType) bool {
        if (!self.check(ttype)) return false;
        self.advance();
        return true;
    }

    pub fn check(self: *Self, ttype: TokenType) bool {
        return self.current.token_type == ttype;
    }

    //---------------- ERRHANDLING --------------------------//

    inline fn sync(self: *Self) void {
        self.panicMode = false;

        while (self.current.token_type != TokenType.EOF) {
            if (self.previous.token_type == TokenType.SEMICOLON) return;
            switch (self.current.token_type) {
                .CLASS, .FUN, .VAR, .FOR, .IF, .WHILE, .PRINT, .RETURN => {
                    return;
                },
                else => {
                    // Do noting!
                },
            }
            self.advance();
        }
    }

    pub fn errAtCurrent(self: *Self, msg: []const u8) void {
        self.errAt(&self.current, msg);
    }

    pub fn err(self: *Self, msg: []const u8) void {
        self.errAt(&self.previous, msg);
    }

    pub fn errAt(self: *Self, token: *Token, msg: []const u8) void {
        const stderr = std.io.getStdErr().writer();
        if (self.panicMode) return;
        self.panicMode = true;
        stderr.print("[line {d}] Error\n", .{token.line}) catch unreachable;

        if (token.token_type == TokenType.EOF) {
            stderr.print("Err at end", .{}) catch unreachable;
        } else if (token.token_type == TokenType.ERROR) {
            //NOTHING FOR NOW
        } else {
            stderr.print(" at '{s}'", .{token.lexeme}) catch unreachable;
        }

        stderr.print(": {s}\n", .{msg}) catch unreachable;
        self.hadErr = true;
        self.compiler.hadErr = true;
    }
    //---------------------------------------------------------//
};

pub fn getRule(ttype: TokenType) ParseRule {
    if (comptime debug_parse_rule) {
        std.debug.print("{}\n", .{ttype});
    }
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
        .BANGEQUAL => comptime ParseRule.init(null, Parser.binary, Precedence.EQUALITY),
        .EQUAL => comptime ParseRule.init(null, null, Precedence.NONE),
        .EQUALEQUAL => comptime ParseRule.init(null, Parser.binary, Precedence.EQUALITY),
        .GREATER => comptime ParseRule.init(null, Parser.binary, Precedence.COMPARISON),
        .GREATEREQUAL => comptime ParseRule.init(null, Parser.binary, Precedence.COMPARISON),
        .LESS => comptime ParseRule.init(null, Parser.binary, Precedence.COMPARISON),
        .LESSEQUAL => comptime ParseRule.init(null, Parser.binary, Precedence.COMPARISON),
        .IDENTIFIER => comptime ParseRule.init(Parser.variable, null, Precedence.NONE),
        .STRING => comptime ParseRule.init(Parser.string, null, Precedence.NONE),
        .NUMBER => comptime ParseRule.init(Parser.number, null, Precedence.NONE),
        //.AND => comptime ParseRule.init(null, Parser.logical_and, Precedence.AND),
        //.CLASS => comptime ParseRule.init(null, null, Precedence.NONE),
        //.ELSE => comptime ParseRule.init(null, null, Precedence.NONE),
        .FALSE => comptime ParseRule.init(Parser.literal, null, Precedence.NONE),
        //.FOR => comptime ParseRule.init(null, null, Precedence.NONE),
        //.FUN => comptime ParseRule.init(null, null, Precedence.NONE),
        //.IF => comptime ParseRule.init(null, null, Precedence.NONE),
        .NIL => comptime ParseRule.init(Parser.literal, null, Precedence.NONE),
        //.OR => comptime ParseRule.init(null, Parser.logical_or, Precedence.OR),
        //.PRINT => comptime ParseRule.init(null, null, Precedence.NONE),
        //.RETURN => comptime ParseRule.init(null, null, Precedence.NONE),
        //.SUPER => comptime ParseRule.init(Parser.super, null, Precedence.NONE),
        //.THIS => comptime ParseRule.init(Parser.this, null, Precedence.NONE),
        .TRUE => comptime ParseRule.init(Parser.literal, null, Precedence.NONE),
        //.VAR => comptime ParseRule.init(null, null, Precedence.NONE),
        //.WHILE => comptime ParseRule.init(null, null, Precedence.NONE),
        //.ERROR => comptime ParseRule.init(null, null, Precedence.NONE),
        .EOF => comptime ParseRule.init(null, null, Precedence.NONE),
        else => unreachable,
    };
    if (comptime debug_parse_rule) {
        std.debug.print("{}\n", .{rule});
    }
    return rule;
}

pub const Compiler = struct {
    const Self = @This();

    compilingChunk: *Chunk = undefined,
    hadErr: bool = false,

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

    pub fn endCompiler(self: *Self, line: usize) void {
        self.emitReturn(line);
    }

    pub fn emitReturn(self: *Self, line: usize) void {
        self.emitByte(OpCode.op_return.toU8(), line);
        if (!self.hadErr) {
            _ = try disassembleChunk(self.currentChunk(), "code");
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
