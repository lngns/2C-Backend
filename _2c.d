module _2c;
import std.stdio;
import std.conv;

string strTimes(string str, uint nbr)
{
    string res;
    foreach(i; 0..nbr)
        res ~= str;
    return res;
}
T instanceof(T)(Object o) if(is(T == class))
{
    return cast(T) o;
}

public:

interface CNode
{
    string toString(uint indent);
}
class CModule
{
    CNode[] tree;
    string name;

public:
    this(string n)
    {
        name = n;
    }
    void opOpAssign(string s)(CNode node) if(s == "~")
    {
        tree ~= node;
    }
    override string toString()
    {
        string buffer;
        foreach(node; tree)
            buffer ~= node.toString(0) ~ "\r\n";
        return buffer;
    }
}
class CCppDirective : CNode
{
    string directive;
    string args;

public:
    this(string d, string a)
    {
        directive = d;
        args = a;
    }
    override string toString(uint)
    {
        return "#" ~ directive ~ " " ~ args;
    }
}
class CFunction(Ret, Args...) : CNode
{
    string name;
    string[Args.length] args;
    CStatement[] body;

public:
    this(string n, string[Args.length] a...)
    {
        name = n;
        args[] = a;
    }
    void opOpAssign(string s)(CStatement node) if(s == "~")
    {
        body ~= node;
    }
    override string toString(uint)
    {
        string buffer = Ret.stringof ~ " " ~ name ~ "(";
        static if(Args.length == 0)
            buffer ~= "void";
        else
        {
            buffer ~= Args[0].stringof ~ " " ~ args[0];
            static foreach(i; 1..Args.length)
                buffer ~= ", " ~ Args[i].stringof ~ " " ~ args[i];
        }
        buffer ~= ")\r\n{\r\n";
        foreach(node; body)
        {
            if(cast(CLabelStatement) node)
                buffer ~= node.toString(4) ~ "\r\n";
            else
                buffer ~= "    " ~ node.toString(4) ~ "\r\n";
        }
        buffer ~= "}";
        return buffer;
    }
}

interface CStatement : CNode {}
class CNullStatement : CStatement
{
public:
    override string toString(uint)
    {
        return ";";
    }
}
class CBlockStatement : CStatement
{
    CStatement[] body;

public:
    this() {}
    this(CStatement[] tree...)
    {
        body = new CStatement[tree.length];
        body[] = tree;
    }
    void opOpAssign(string s)(CStatement stmt) if(s == "~")
    {
        body ~= stmt;
    }
    string toString(uint indent)
    {
        string buffer = "{\r\n";
        foreach(stmt; body)
        {
            if(cast(CLabelStatement) stmt)
                buffer ~= strTimes(" ", indent);
            else
                buffer ~= strTimes(" ", indent + 4);
            buffer ~= stmt.toString(indent + 4) ~ "\r\n";
        }
        buffer ~= strTimes(" ", indent) ~ "}";
        return buffer;
    }
}
class CExpressionStatement : CStatement
{
    CExpression expr;

public:
    this(CExpression e)
    {
        expr = e;
    }
    override string toString(uint indent)
    {
        return expr.toString(0) ~ ";";
    }
}
class CIfStatement : CStatement
{
    CExpression test;
    CStatement then, otherwise;

public:
    this(CExpression cond, CStatement t, CStatement o = null)
    {
        test = cond;
        then = t;
        otherwise = o;
    }
    override string toString(uint indent)
    {
        string buffer = "if(" ~ test.toString(0) ~ ")\r\n";
        if(cast(CBlockStatement) then)
            buffer ~= strTimes(" ", indent) ~ then.toString(indent);
        else
            buffer ~= strTimes(" ", indent + 4) ~ then.toString(indent + 4);
        if(otherwise !is null)
        {
            buffer ~= "\r\n" ~ strTimes(" ", indent) ~ "else\r\n";
            if(cast(CBlockStatement) otherwise)
                buffer ~= strTimes(" ", indent) ~ otherwise.toString(indent);
            else
                buffer ~= strTimes(" ", indent + 4) ~ otherwise.toString(indent + 4);
        }
        return buffer;
    }
}
class CWhileStatement : CStatement
{
    CExpression test;
    CStatement body;

public:
    this(CExpression cond, CStatement b)
    {
        test = cond;
        body = b;
    }
    override string toString(uint indent)
    {
        string buffer = "while(" ~ test.toString(0) ~ ")\r\n";
        if(cast(CBlockStatement) body)
            buffer ~= strTimes(" ", indent) ~ body.toString(indent);
        else
            buffer ~= strTimes(" ", indent + 4) ~ body.toString(indent + 4);
        return buffer;
    }
}
class CDoWhileStatement : CStatement
{
    CExpression test;
    CStatement body;

public:
    this(CExpression cond, CStatement b)
    {
        test = cond;
        body = b;
    }
    override string toString(uint indent)
    {
        string buffer = "do\r\n";
        if(cast(CBlockStatement) body)
            buffer ~= strTimes(" ", indent) ~ body.toString(indent);
        else
            buffer ~= strTimes(" ", indent + 4) ~ body.toString(indent + 4);
        buffer ~= "\r\n" ~ strTimes(" ", indent) ~ "while(" ~ test.toString(0) ~ ");";
        return buffer;
    }
}
class CForStatement : CStatement
{
    CExpression init;
    CExpression test;
    CExpression incr;
    CStatement body;

public:
    this(CExpression ini, CExpression cond, CExpression inc, CStatement b)
    {
        init = ini;
        test = cond;
        incr = inc;
        body = b;
    }
    override string toString(uint indent)
    {
        string buffer = "for(" ~ init.toString(0) ~ "; " ~ test.toString(0) ~ "; " ~ incr.toString(0) ~ ")\r\n";
        if(cast(CBlockStatement) body)
            buffer ~= strTimes(" ", indent) ~ body.toString(indent);
        else
            buffer ~= strTimes(" ", indent + 4) ~ body.toString(indent + 4);
        return buffer;
    }
}
class CSwitchStatement : CStatement
{
    CExpression test;
    CBlockStatement body;

public:
    this(CExpression t, CBlockStatement b)
    {
        test = t;
        body = b;
    }
    override string toString(uint indent)
    {
        return "switch(" ~ test.toString(0) ~ ")\r\n" ~ strTimes(" ", indent) ~ body.toString(indent);
    }
}
class CLabelStatement : CStatement
{
    CStatement labelee;
    string name;

public:
    this(string n, CStatement l)
    {
        name = n;
        labelee = l;
    }
    override string toString(uint indent)
    {
        return name ~ ":\r\n" ~ strTimes(" ", indent) ~ labelee.toString(indent);
    }
}
class CCaseStatement : CLabelStatement
{
public:
    this(CValueExpression n, CStatement l)
    {
        super(n.toString(0), l);
    }
    override string toString(uint indent)
    {
        if(cast(CLabelStatement) labelee)
            return "case " ~ name ~ ":\r\n" ~ strTimes(" ", indent - 4) ~ labelee.toString(indent);
        else
            return "case " ~ name ~ ":\r\n" ~ strTimes(" ", indent) ~ labelee.toString(indent);
    }
}
class CDefaultStatement : CLabelStatement
{
public:
    this(CStatement stmt)
    {
        super("default", stmt);
    }
}
class CGotoStatment : CStatement
{
    string label;

public:
    this(string name)
    {
        label = name;
    }
    override string toString(uint)
    {
        return "goto " ~ label ~ ";";
    }
}
class CReturnStatement : CStatement
{
    CExpression expr;

public:
    this(CExpression e = null)
    {
        expr = e;
    }
    override string toString(uint)
    {
        return "return" ~ (expr !is null ? " " ~ expr.toString(0) : "") ~ ";";
    }
}
class CContinueStatement : CStatement
{
public:
    override string toString(uint)
    {
        return "continue;";
    }
}
class CBreakStatement : CStatement
{
public:
    override string toString(uint)
    {
        return "break;";
    }
}

interface CExpression : CNode {}
class CValueExpression : CExpression
{
    string representation;

public:
    this(string r)
    {
        representation = r;
    }
    this(T)(T r) if(__traits(compiles, to!string(r)))
    {
        representation = to!string(r);
    }
    override string toString(uint)
    {
        return representation;
    }
}
class CUnaryExpression : CExpression
{
    CExpression operand;
    string operator;
    bool suffix;

public:
    this(CExpression expr, string op, bool s = false)
    {
        operand = expr;
        operator = op;
        suffix = s;
    }
    override string toString(uint)
    {
        if((operator == "++" || operator == "--") && suffix)
            return operand.toString(0) ~ operator;
        else
            return operator ~ operand.toString(0);
    }
}
class CBinaryExpression : CExpression
{
    CExpression left, right;
    string operator;

public:
    this(CExpression lhs, string op, CExpression rhs)
    {
        left = lhs;
        right = rhs;
        operator = op;
    }
    override string toString(uint)
    {
        return left.toString(0) ~ " " ~ operator ~ " " ~ right.toString(0);
    }
}
class CTernaryExpression : CExpression
{
    CExpression test, then, otherwise;

public:
    this(CExpression op0, CExpression op1, CExpression op2)
    {
        test = op0;
        then = op1;
        otherwise = op2;
    }
    override string toString(uint)
    {
        return test.toString(0) ~ " ? " ~ then.toString(0) ~ " : " ~ otherwise.toString(0);
    }
}
class CGroupingExpression : CExpression
{
    CExpression expression;

public:
    this(CExpression expr)
    {
        expression = expr;
    }
    override string toString(uint)
    {
        return "(" ~ expression.toString(0) ~ ")";
    }
}
class CCallExpression : CExpression
{
    CExpression callee;
    CExpression[] arguments;

public:
    this(CExpression c, CExpression[] args...)
    {
        callee = c;
        arguments = new CExpression[args.length];
        arguments[] = args;
    }
    override string toString(uint)
    {
        string buffer = callee.toString(0) ~ "(";
        if(arguments.length > 0)
        {
            buffer ~= arguments[0].toString(0);
            foreach(i; 1..arguments.length)
                buffer ~= ", " ~ arguments[i].toString(0);
        }
        buffer ~= ")";
        return buffer;
    }
}
class CCommaExpression : CExpression
{
    CExpression[] subexprs;

public:
    this() {}
    this(CExpression[] args...)
    {
        subexprs = new CExpression[args.length];
        subexprs[] = args;
    }
    override string toString(uint)
    {
        string buffer;
        if(subexprs.length > 0)
        {
            buffer ~= subexprs[0].toString(0);
            foreach(i; 1..subexprs.length)
                buffer ~= ", " ~ subexprs[i].toString(0);
        }
        return buffer;
    }
}
class CSubscriptExpression : CExpression
{
    CExpression left, right;

public:
    this(CExpression lhs, CExpression rhs)
    {
        left = lhs;
        right = rhs;
    }
    override string toString(uint)
    {
        return left.toString(0) ~ "[" ~ right.toString(0) ~ "]";
    }
}
class CMemberAccessExpression : CExpression
{
    CExpression operand;
    string operator, field;

public:
    this(CExpression expr, string op, string prop)
    {
        operand = expr;
        operator = op;
        field = prop;
    }
    override string toString(uint)
    {
        return operand.toString(0) ~ operator ~ field;
    }
}
class CCastExpression : CExpression
{
    CExpression operand;
    CType type;

public:
    this(CExpression op, CType t)
    {
        operand = op;
        type = t;
    }
    override string toString(uint)
    {
        return "(" ~ type.toString() ~ ") " ~ operand.toString(0);
    }
}

interface CType
{
    string toString();
}
