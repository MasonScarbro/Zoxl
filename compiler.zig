const Scanner = @import("./scanner.zig").Scanner;
const std = @import("std");
const TokenType = @import("./scanner.zig").TokenType;
const Token = @import("./scanner.zig").Token;
const Chunk = @import("./chunk.zig").Chunk;
const OpCode = @import("./chunk.zig").OpCode;
const Value = @import("./value.zig").Value;
const printStack = @import("debugging.zig").printStack;
const Object = @import("./object.zig");
const Vm = @import("./vm.zig").Vm;
const disassembleChunk = @import("./debugging.zig").disassembleChunk;
const initStdErr = @import("./main.zig").initStdErr();
const Allocator = std.mem.Allocator;
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

const Local = struct {
    name: Token,
    depth: ?usize = null,
};

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

pub fn compile(vm: *Vm, src: []const u8, chunk: *Chunk, allocator: Allocator) CompileError!void {
    var scanner = Scanner.init(src);
    std.debug.print("Scanner Done", .{});
    var compiler = Compiler.init(chunk, allocator);
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

        //std.debug.print("\nInside Resolve Named Var", .{});

        var getOp: OpCode = undefined;
        var setOp: OpCode = undefined;
        var arg: u8 = undefined;

        if (self.resolveLocal(name)) |local| {
            arg = local;

            getOp = OpCode.op_get_local;
            setOp = OpCode.op_set_local;
        } else {
            arg = self.identifierConst(name);
            getOp = OpCode.op_get_global;
            setOp = OpCode.op_set_global;
        }

        if (canAssign and self.match(TokenType.EQUAL)) {
            self.expr();
            self.compiler.emitBytes(setOp.toU8(), arg, self.previous.line);
        } else {
            self.compiler.emitBytes(getOp.toU8(), arg, self.previous.line);
        }
    }

    pub fn resolveLocal(self: *Self, name: Token) ?u8 {

        //std.debug.print("\nInside Resolve Local", .{});

        var i: usize = self.compiler.localCount;
        while (i > 0) {
            i -= 1;
            const local = self.compiler.locals.items[@as(usize, @intCast(i))];
            if (self.identifiersEqual(name, local.name)) {
                if (local.depth == null) {
                    self.err("Can't read local variable in its own initializer.");
                }
                return @as(u8, @intCast(i));
            }
        }

        //else not a local
        return null;
    }

    pub fn number(self: *Self, canAssign: bool) void {
        _ = canAssign;
        const value = std.fmt.parseFloat(f64, self.previous.lexeme) catch unreachable;
        self.compiler.emitConstant(Value.NumberValue(value), self.previous.line);
    }

    pub fn expr(self: *Self) void {
        self.parsePrecedence(Precedence.ASSIGNMENT);
    }

    pub fn block(self: *Self) void {
        while (!self.check(TokenType.RIGHTBRACE) and !self.check(TokenType.EOF)) {
            self.declaration();
        }

        self.consume(TokenType.RIGHTBRACE, "Expected '}' after block");
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
        } else if (self.match(TokenType.IF)) {
            self.ifStatement();
        } else if (self.match(TokenType.SWITCH)) {
            self.switchStatement();
        } else if (self.match(TokenType.FOR)) {
            self.forStatement();
        } else if (self.match(TokenType.WHILE)) {
            self.whileStatement();
        } else if (self.match(TokenType.LEFTBRACE)) {
            self.compiler.beginScope();
            self.block();
            self.compiler.endScope(self.previous.line);
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

    pub fn forStatement(self: *Self) void {
        self.compiler.beginScope(); // manually begin the scope to scope the variable only to the for body
        self.consume(TokenType.LEFTPAREN, "Expected '(' after 'for'");
        if (self.match(TokenType.SEMICOLON)) {
            //No initializer
        } else if (self.match(TokenType.VAR)) {
            //defined in paren
            self.varDeclaration();
        } else {
            //defined outside or other
            self.exprStatement();
        }

        const loopStart = self.compiler.currentChunk().code.count;
        var exitJump: ?usize = null;
        //optional clause
        if (!self.match(TokenType.SEMICOLON)) {
            self.expr();
            self.consume(TokenType.SEMICOLON, "Expect ';' after loop condition.");

            //Jump out of loop when condition is false
            exitJump = self.compiler.emitJump(OpCode.op_jump_if_false.toU8(), self.previous.line);
            self.compiler.emitByte(OpCode.op_pop.toU8(), self.previous.line); // pop the condition
        }

        // we can’t compile the increment clause later,
        // since our compiler only makes a single pass over the code.
        // Instead, we’ll jump over the increment, run the body,
        // jump back up to the increment, run it, and then go to the next iteration.
        if (!self.match(TokenType.RIGHTPAREN)) {
            const bodyJump = self.compiler.emitJump(OpCode.op_jump.toU8(), self.previous.line); // emit an unconditional jump that hops over the increment clause’s code to the body of the loop.
            const incrementStart = self.compiler.currentChunk().code.count; // location of increment
            self.expr(); // compile the increment expression itself.

            self.compiler.emitByte(OpCode.op_pop.toU8(), self.previous.line); // discard the increment expr in vm
            self.consume(TokenType.RIGHTPAREN, "Expected ')' after clauses");

            // when we emit the loop instruction after the body statement,
            // this will cause it to jump up to the increment expression instead of the top of the loop
            // like it does when there is no increment.
            self.compiler.emitLoop(loopStart, self.previous.line); // main loop to go to top of the for loop
            loopStart = incrementStart; // loop start point at offset where the increment begins
            self.compiler.patchJump(bodyJump); //
        }

        self.statement();
        self.compiler.emitLoop(loopStart, self.previous.line);

        // if the codition clause exist patch the jump (no jump to patch otherwise)
        if (exitJump) {
            self.compiler.patchJump(exitJump.?);
            self.compiler.emitByte(OpCode.op_pop.toU8(), self.previous.line);
        }

        self.compiler.endScope(self.previous.line);
    }

    pub fn switchStatement(self: *Self) void {
        self.consume(TokenType.LEFTPAREN, "Expected '(' after switch");
        self.expr();
        self.consume(TokenType.RIGHTPAREN, "Expected ')' after condition");
        self.consume(TokenType.LEFTBRACE, "Expected '{' after Switch case");

        var state: usize = 0; // 0: before all cases, 1: In a case, 2: after default.
        var caseEnds = std.ArrayList(usize).init(self.compiler.allocator);
        var caseCount: usize = 0;
        var fallthroughAllowed = false;
        var previousCaseSkip: ?usize = null;

        while (!self.match(TokenType.RIGHTBRACE) and !self.match(TokenType.EOF)) {
            if (self.match(TokenType.CASE) or self.match(TokenType.DEFAULT)) {
                const caseType = self.previous.token_type;

                if (state == 2) self.err("Cant have another case or default after default");

                if (state == 1) {
                    // At the end of the previous case, jump over the others.
                    const didFall = fallthroughAllowed; // capture state of fallthrough
                    if (!didFall) {
                        if (caseEnds.append(self.compiler.emitJump(OpCode.op_jump.toU8(), self.previous.line))) |*_| {
                            caseCount += 1;
                        } else |_| {
                            std.debug.print("\nERR: Failed appending for fucks sake Zig fix this", .{});
                            self.hadErr = true;
                        }
                    }
                    // Patch its condition to jump to the next case (this one)
                    if (previousCaseSkip) |skip| {
                        self.compiler.patchJump(skip);
                        if (!didFall) { //dont pop if falling through
                            self.compiler.emitByte(OpCode.op_pop.toU8(), self.previous.line);
                        }
                    }
                    fallthroughAllowed = false; // reset to false or next case
                }
                if (caseType == TokenType.CASE) {
                    state = 1;
                    //std.debug.print("\nSTACK PRINTED: \n", .{});
                    //printStack(&self.vm.stack);
                    self.compiler.emitByte(OpCode.op_duplicate.toU8(), self.previous.line);
                    self.expr();

                    self.consume(TokenType.LAMBDA, "Expected '=>' after case value");

                    self.compiler.emitByte(OpCode.op_equal.toU8(), self.previous.line);
                    previousCaseSkip = self.compiler.emitJump(OpCode.op_jump_if_false.toU8(), self.previous.line);

                    self.compiler.emitByte(OpCode.op_pop.toU8(), self.previous.line);

                    if (self.match(TokenType.NOBREAK)) {
                        //std.debug.print("NO BREAK ENCOUNTERED", .{});
                        fallthroughAllowed = true;
                        if (!self.check(TokenType.LEFTBRACE)) {
                            self.consume(TokenType.SEMICOLON, "Expected ';' after 'nobreak'");
                        }
                    }
                } else {
                    state = 2;
                    //PlaceHolder for colon
                    self.consume(TokenType.LAMBDA, "Expected '=>' after default");
                    previousCaseSkip = null;
                }
            } else {
                if (state == 0) {
                    self.err("Cant have statements before any case");
                }
                self.statement();
            }
        }
        // If we ended without a default case, patch its condition jump.
        if (state == 1) {
            if (previousCaseSkip) |skip| {
                self.compiler.patchJump(skip);
                if (!fallthroughAllowed) { //dont pop if falling through
                    self.compiler.emitByte(OpCode.op_pop.toU8(), self.previous.line);
                }
            }
        }

        for (caseEnds.items) |jumpOffset| {
            self.compiler.patchJump(jumpOffset);
        }

        // Dont ask why this works
        if (caseCount > 1) {
            self.compiler.emitByte(OpCode.op_pop.toU8(), self.previous.line);
        }
        caseEnds.deinit();
    }

    pub fn whileStatement(self: *Self) void {
        const loopStart = self.compiler.currentChunk().code.count;
        self.consume(TokenType.LEFTPAREN, "Expected '(' after while");
        self.expr();
        self.consume(TokenType.RIGHTPAREN, "Expected ')' after while");

        const exitJump = self.compiler.emitJump(OpCode.op_jump_if_false.toU8(), self.previous.line);
        self.compiler.emitByte(OpCode.op_pop.toU8(), self.previous.line);
        self.statement();
        self.compiler.emitLoop(loopStart, self.previous.line);

        self.compiler.patchJump(exitJump);
        self.compiler.emitByte(OpCode.op_pop.toU8(), self.previous.line);
    }

    pub fn ifStatement(self: *Self) void {
        self.consume(TokenType.LEFTPAREN, "Expected '(' after if");
        self.expr();
        self.consume(TokenType.RIGHTPAREN, "Expected ')' after condition");

        const thenJump = self.compiler.emitJump(OpCode.op_jump_if_false.toU8(), self.previous.line);
        //When the condition is truthy, we pop it right before the code inside the then branch.
        self.compiler.emitByte(OpCode.op_pop.toU8(), self.previous.line);

        self.statement();

        const elseJump = self.compiler.emitJump(OpCode.op_jump.toU8(), self.previous.line);

        self.compiler.patchJump(thenJump);
        //Otherwise, we pop it at the beginning of the else branch.
        self.compiler.emitByte(OpCode.op_pop.toU8(), self.previous.line);

        if (self.match(TokenType.ELSE)) self.statement();

        self.compiler.patchJump(elseJump);
    }

    pub fn varDeclaration(self: *Self) void {
        //std.debug.print("\nInside varDeclaration\n", .{});
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
        //std.debug.print("\nInside parseVariable\n", .{});
        self.declareVar();
        if (self.compiler.scopeDepth > 0) return 0;

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

    inline fn declareVar(self: *Self) void {
        std.debug.print("\nInside declareVar\n", .{});
        if (self.compiler.scopeDepth == 0) return; //global just bail

        var i = self.compiler.localCount;

        while (i > 0) {
            i -= 1;
            std.debug.print("\nunreachable\n", .{});
            const local = self.compiler.locals.items[@as(usize, @intCast(i))];
            if (local.depth != null and local.depth.? < self.compiler.scopeDepth) {
                break;
            }
            if (self.identifiersEqual(self.previous, local.name)) {
                self.err("Already a variable with this name in this scope.");
            }
        }
        self.compiler.addLocal(self.previous);
    }

    fn identifiersEqual(self: *Self, a: Token, b: Token) bool {
        _ = self;
        return std.mem.eql(u8, a.lexeme, b.lexeme);
    }

    inline fn defineVar(self: *Self, global: u8) void {
        if (self.compiler.scopeDepth > 0) {
            self.markInitialized();
            return;
        }
        self.compiler.emitBytes(OpCode.op_define_global.toU8(), global, self.previous.line);
    }

    inline fn markInitialized(self: *Self) void {
        self.compiler.locals.items[self.compiler.localCount - 1].depth = self.compiler.scopeDepth;
    }

    pub fn logical_and(self: *Self, canAssign: bool) void {
        _ = canAssign;
        // jump if falsey
        const endJump = self.compiler.emitJump(OpCode.op_jump_if_false.toU8(), self.previous.line);
        // otherwise discard left
        self.compiler.emitByte(OpCode.op_pop.toU8(), self.previous.line);

        self.parsePrecedence(Precedence.AND);
        //patch jump
        self.compiler.patchJump(endJump);
    }

    pub fn logical_or(self: *Self, canAssign: bool) void {
        _ = canAssign;
        // if falsey tiny jump to other expression
        const elseJump = self.compiler.emitJump(OpCode.op_jump_if_false.toU8(), self.previous.line);

        const endJump = self.compiler.emitJump(OpCode.op_jump.toU8(), self.previous.line);

        self.compiler.patchJump(elseJump);
        self.compiler.emitByte(OpCode.op_pop.toU8(), self.previous.line);

        self.parsePrecedence(Precedence.OR);
        self.compiler.patchJump(endJump);
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
        .AND => comptime ParseRule.init(null, Parser.logical_and, Precedence.AND),
        .LAMBDA => comptime ParseRule.init(null, null, Precedence.NONE),
        //.CLASS => comptime ParseRule.init(null, null, Precedence.NONE),
        //.ELSE => comptime ParseRule.init(null, null, Precedence.NONE),
        .FALSE => comptime ParseRule.init(Parser.literal, null, Precedence.NONE),
        .FOR => comptime ParseRule.init(null, null, Precedence.NONE),
        //.FUN => comptime ParseRule.init(null, null, Precedence.NONE),
        .IF => comptime ParseRule.init(null, null, Precedence.NONE),
        .CASE => comptime ParseRule.init(null, null, Precedence.NONE),
        .NOBREAK => comptime ParseRule.init(null, null, Precedence.NONE),
        .SWITCH => comptime ParseRule.init(null, null, Precedence.NONE),
        .NIL => comptime ParseRule.init(Parser.literal, null, Precedence.NONE),
        .OR => comptime ParseRule.init(null, Parser.logical_or, Precedence.OR),
        .PRINT => comptime ParseRule.init(null, null, Precedence.NONE),
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
    allocator: Allocator,
    hadErr: bool = false,
    locals: std.ArrayList(Local),
    localCount: usize = 0,
    scopeDepth: usize = 0,

    pub fn init(chunk: *Chunk, allocator: Allocator) Self {
        std.debug.print("\nIniting Compiler", .{});
        return Self{ .compilingChunk = chunk, .allocator = allocator, .locals = std.ArrayList(Local).init(allocator) };
    }

    pub fn addLocal(self: *Self, name: Token) void {
        std.debug.print("\nTrying to make new local", .{});
        const newLocal = Local{
            .name = name,
            .depth = 0,
        };

        if (self.locals.append(newLocal)) |*_| {
            self.localCount += 1;
        } else |_| {
            std.debug.print("\nERR: Failed appending newLocal????", .{});
            self.hadErr = true;
        }
    }

    pub fn deinit(self: *Self) void {
        self.locals.deinit();
    }

    pub fn beginScope(self: *Self) void {
        std.debug.print("\nBeginning Scope", .{});
        self.scopeDepth += 1;
    }

    pub fn endScope(self: *Self, line: usize) void {
        self.scopeDepth -= 1;
        while (self.localCount > 0 and self.locals.items[self.localCount - 1].depth.? > self.scopeDepth) {
            self.emitByte(OpCode.op_pop.toU8(), line);
            self.localCount -= 1;
        }
        std.debug.print("\nEnding Scope", .{});
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

    pub fn emitJump(self: *Self, instruction: u8, line: usize) usize {
        self.emitByte(instruction, line);
        self.emitByte(0xff, line);
        self.emitByte(0xff, line);
        return self.currentChunk().code.count - 2;
    }

    pub fn patchJump(self: *Self, offset: usize) void {
        // -2 to adjusty for the bytecode for the jump offset itself
        const jump = self.currentChunk().code.count - offset - 2;

        self.currentChunk().code.items[offset] = @as(u8, @truncate(jump >> 8)) & 0xff;
        self.currentChunk().code.items[offset + 1] = @as(u8, @truncate(jump)) & 0xff;
    }

    // jumps backwards by a given offset
    pub fn emitLoop(self: *Self, loopStart: usize, line: usize) void {
        self.emitByte(OpCode.op_loop.toU8(), line); // emit the instruction (jumps back)

        const offset = self.currentChunk().code.count - loopStart + 2; //  The + 2 is to take into account the size of the OP_LOOP

        // Patches the jump
        self.emitByte(@as(u8, @truncate(offset >> 8)) & 0xff, line);
        self.emitByte(@as(u8, @truncate(offset)) & 0xff, line);
    }
};
