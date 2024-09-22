const Scanner = @import("./scanner.zig").Scanner;
const std = @import("std");
const TokenType = @import("./scanner.zig").TokenType;
const Token = @import("./scanner.zig").Token;
const Chunk = @import("./chunk.zig").Chunk;
const OpCode = @import("./chunk.zig").OpCode;
const Value = @import("./value.zig").Value;

const stderr = std.io.getStdErr().writer();

const CompileError = error{
    CompileErr,
    ScannerErr,
};

pub fn compile(src: []const u8, chunk: *Chunk) CompileError!void {
    const scanner = Scanner.init(src);
    const compiler = Compiler.init(&chunk);
    const parser = Parser.init(&scanner, &compiler);
    parser.advance(); //Kick off parser
    if (parser.hadErr == true) return CompileError.ScannerErr;
    //self.expr(); no use yet we'll get there!
    //consume(TokenType.EOF, "Expected End Of Expression");
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

    pub fn expr() void {}

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

    pub fn emitReturn(self: *Self, line: usize) void {
        self.emitByte(OpCode.op_return.toU8(), line);
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
