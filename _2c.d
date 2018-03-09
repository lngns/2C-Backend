module _2c;
import std.stdio;
import std.conv;
import std.uni : toLower;

private:
string strTimes(string str, uint nbr)
{
    string res;
    foreach(i; 0..nbr)
        res ~= str;
    return res;
}
string enumToString(T)(T obj) if(is(T == enum))
{
    final switch(obj)
    {
    static foreach(Member; __traits(allMembers, T))
        mixin("case " ~ T.stringof ~ "." ~ Member ~ ": return \"" ~ Member ~ "\";");
    }
}
string basicAttributeEmitterBuilder(string Begin, string End)(CAttribute[] attrs)
{
    if(!attrs.length)
        return "";
    string buffer = Begin ~ attrs[0].name;
    if(attrs[0].arguments.length)
    {
        buffer ~= "(" ~ attrs[0].arguments[0];
        foreach(arg; attrs[0].arguments[1..$])
            buffer ~= ", " ~ arg;
        buffer ~= ")";
    }
    foreach(attr; attrs[1..$])
    {
        buffer ~= ", " ~ attr.name;
        if(attr.arguments.length)
        {
            buffer ~= "(" ~ attr.arguments[0];
            foreach(arg; attr.arguments[1..$])
                buffer ~= ", " ~ arg;
            buffer ~= ")";
        }
    }
    return buffer ~ End;
}

public:

alias CGCCAttributeEmitter = basicAttributeEmitterBuilder!("__attribute__((", "))");
alias CMSVCAttributeEmitter = basicAttributeEmitterBuilder!("__declspec(", ")");

interface CNode { string toString(); }
interface CUpperNode : CNode { string toString(const CModule); }
class CAttribute { string name; string[] arguments; }
alias CAttributeEmitter = string function(CAttribute[]);
class CModule
{
    CUpperNode[] tree;
    string name;
    CAttributeEmitter attributeEmitter;

    this(string n, CAttributeEmitter attrman = null)
    {
        name = n;
        attributeEmitter = attrman;
    }
    void opOpAssign(string s)(CUpperNode node) if(s == "~")
    {
        tree ~= node;
    }
    override string toString()
    {
        string buffer = "";
        foreach(node; tree)
            buffer ~= node.toString(this) ~ ";\r\n";
        return buffer;
    }
}
class CCppDirective : CUpperNode
{
    string directive;
    string args;

    this(string d, string a)
    {
        directive = d;
        args = a;
    }
    override string toString(const CModule)
    {
        return "#" ~ directive ~ " " ~ args;
    }
}
class CFunction(Ret, Args...) : CUpperNode
{
    string name;
    string[Args.length] args;
    CStatement[] body;

    this(string n, string[Args.length] a...)
    {
        name = n;
        args[] = a;
    }
    void opOpAssign(string s)(CStatement node) if(s == "~")
    {
        body ~= node;
    }
    override string toString(const CModule m)
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
                buffer ~= node.toString(4, m) ~ "\r\n";
            else
                buffer ~= "    " ~ node.toString(4, m) ~ "\r\n";
        }
        buffer ~= "}";
        return buffer;
    }
}
enum CStorageClass { Auto, Static, Register, Extern }
class CVariableDeclaration : CUpperNode
{
    CType type;
    string identifier;
    CExpression initializer;
    CStorageClass storageClass;
    CAttribute[] attributes;

    this(CType t, string id, CExpression init = null, CStorageClass cl = CStorageClass.Auto, CAttribute[] attrs = null)
    {
        type = t;
        identifier = id;
        initializer = init;
        storageClass = cl;
        attributes = attrs;
    }
    string toString(const CModule m)
    {
        string buffer = "";
        if(m.attributeEmitter !is null)
            buffer ~= m.attributeEmitter(attributes) ~ " ";
        buffer ~= enumToString(storageClass).toLower() ~ " ";
        if(cast(CBasicType) type || cast(CUnresolvedType) type)
            buffer ~= type.toString() ~ " " ~ identifier;
        if(auto arrtype = cast(CArrayType) type)
            buffer ~= arrtype.underliningType.toString() ~ " " ~ identifier ~ "[" ~ (arrtype.length ? to!string(arrtype.length) : "*" ) ~ "]";
        return buffer ~ (initializer !is null ? " = " ~ initializer.toString() : "");
    }
}
class CConstantDeclaration : CVariableDeclaration
{
    this(CType t, string id, CExpression init = null, CStorageClass cl = CStorageClass.Auto, CAttribute[] attrs = null)
    {
        super(t, id, init, cl, attrs);
    }
    override string toString(const CModule m)
    {
        string buffer = "";
        if(m.attributeEmitter !is null)
            buffer ~= m.attributeEmitter(attributes) ~ " ";
        buffer ~= enumToString(storageClass).toLower() ~ " const ";
        if(cast(CBasicType) type)
            buffer ~= type.toString() ~ " " ~ identifier;
        if(auto arrtype = cast(CArrayType) type)
            buffer ~= arrtype.underliningType.toString() ~ " " ~ identifier ~ "[" ~ (arrtype.length ? to!string(arrtype.length) : "*" ) ~ "]";
        return buffer ~ (initializer !is null ? " = " ~ initializer.toString() : "");
    }
}

interface CStatement : CNode { string toString(uint, const CModule); }
class CNullStatement : CStatement
{
    override string toString(uint, const CModule)
    {
        return ";";
    }
}
class CDeclarationStatement : CStatement
{
    CVariableDeclaration declaration;

    this(CVariableDeclaration decl)
    {
        declaration = decl;
    }
    string toString(uint, const CModule m)
    {
        return declaration.toString(m) ~ ";";
    }
}
class CBlockStatement : CStatement
{
    CStatement[] body;

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
    string toString(uint indent, const CModule m)
    {
        string buffer = "{\r\n";
        foreach(stmt; body)
        {
            if(cast(CLabelStatement) stmt)
                buffer ~= strTimes(" ", indent);
            else
                buffer ~= strTimes(" ", indent + 4);
            buffer ~= stmt.toString(indent + 4, m) ~ "\r\n";
        }
        buffer ~= strTimes(" ", indent) ~ "}";
        return buffer;
    }
}
class CExpressionStatement : CStatement
{
    CExpression expr;

    this(CExpression e)
    {
        expr = e;
    }
    override string toString(uint indent, const CModule)
    {
        return expr.toString() ~ ";";
    }
}
class CIfStatement : CStatement
{
    CExpression test;
    CStatement then, otherwise;

    this(CExpression cond, CStatement t, CStatement o = null)
    {
        test = cond;
        then = t;
        otherwise = o;
    }
    override string toString(uint indent, const CModule m)
    {
        string buffer = "if(" ~ test.toString() ~ ")\r\n";
        if(cast(CBlockStatement) then)
            buffer ~= strTimes(" ", indent) ~ then.toString(indent, m);
        else
            buffer ~= strTimes(" ", indent + 4) ~ then.toString(indent + 4, m);
        if(otherwise !is null)
        {
            buffer ~= "\r\n" ~ strTimes(" ", indent) ~ "else\r\n";
            if(cast(CBlockStatement) otherwise)
                buffer ~= strTimes(" ", indent) ~ otherwise.toString(indent, m);
            else
                buffer ~= strTimes(" ", indent + 4) ~ otherwise.toString(indent + 4, m);
        }
        return buffer;
    }
}
class CWhileStatement : CStatement
{
    CExpression test;
    CStatement body;

    this(CExpression cond, CStatement b)
    {
        test = cond;
        body = b;
    }
    override string toString(uint indent, const CModule m)
    {
        string buffer = "while(" ~ test.toString() ~ ")\r\n";
        if(cast(CBlockStatement) body)
            buffer ~= strTimes(" ", indent) ~ body.toString(indent, m);
        else
            buffer ~= strTimes(" ", indent + 4) ~ body.toString(indent + 4, m);
        return buffer;
    }
}
class CDoWhileStatement : CStatement
{
    CExpression test;
    CStatement body;

    this(CExpression cond, CStatement b)
    {
        test = cond;
        body = b;
    }
    override string toString(uint indent, const CModule m)
    {
        string buffer = "do\r\n";
        if(cast(CBlockStatement) body)
            buffer ~= strTimes(" ", indent) ~ body.toString(indent, m);
        else
            buffer ~= strTimes(" ", indent + 4) ~ body.toString(indent + 4, m);
        buffer ~= "\r\n" ~ strTimes(" ", indent) ~ "while(" ~ test.toString() ~ ");";
        return buffer;
    }
}
class CForStatement : CStatement
{
    CExpression init;
    CExpression test;
    CExpression incr;
    CStatement body;

    this(CExpression ini, CExpression cond, CExpression inc, CStatement b)
    {
        init = ini;
        test = cond;
        incr = inc;
        body = b;
    }
    override string toString(uint indent, const CModule m)
    {
        string buffer = "for(" ~ init.toString() ~ "; " ~ test.toString() ~ "; " ~ incr.toString() ~ ")\r\n";
        if(cast(CBlockStatement) body)
            buffer ~= strTimes(" ", indent) ~ body.toString(indent, m);
        else
            buffer ~= strTimes(" ", indent + 4) ~ body.toString(indent + 4, m);
        return buffer;
    }
}
class CSwitchStatement : CStatement
{
    CExpression test;
    CBlockStatement body;

    this(CExpression t, CBlockStatement b)
    {
        test = t;
        body = b;
    }
    override string toString(uint indent, const CModule m)
    {
        return "switch(" ~ test.toString() ~ ")\r\n" ~ strTimes(" ", indent) ~ body.toString(indent, m);
    }
}
class CLabelStatement : CStatement
{
    CStatement labelee;
    string name;

    this(string n, CStatement l)
    {
        name = n;
        labelee = l;
    }
    override string toString(uint indent, const CModule m)
    {
        return name ~ ":\r\n" ~ strTimes(" ", indent) ~ labelee.toString(indent, m);
    }
}
class CCaseStatement : CLabelStatement
{
    CExpression expr;

    this(CExpression e, CStatement l)
    {
        expr = e;
        super(e.toString(), l);
    }
    override string toString(uint indent, const CModule m)
    {
        if(cast(CLabelStatement) labelee)
            return "case " ~ name ~ ":\r\n" ~ strTimes(" ", indent - 4) ~ labelee.toString(indent, m);
        else
            return "case " ~ name ~ ":\r\n" ~ strTimes(" ", indent) ~ labelee.toString(indent, m);
    }
}
class CDefaultStatement : CLabelStatement
{
    this(CStatement stmt)
    {
        super("default", stmt);
    }
}
class CGotoStatment : CStatement
{
    string label;

    this(string name)
    {
        label = name;
    }
    override string toString(uint, const CModule)
    {
        return "goto " ~ label ~ ";";
    }
}
class CReturnStatement : CStatement
{
    CExpression expr;

    this(CExpression e = null)
    {
        expr = e;
    }
    override string toString(uint, const CModule)
    {
        return "return" ~ (expr !is null ? " " ~ expr.toString() : "") ~ ";";
    }
}
class CContinueStatement : CStatement
{
    override string toString(uint, const CModule)
    {
        return "continue;";
    }
}
class CBreakStatement : CStatement
{
    override string toString(uint, const CModule)
    {
        return "break;";
    }
}

interface CExpression : CNode {}
class CValueExpression : CExpression
{
    string representation;

    this(string r)
    {
        representation = r;
    }
    this(T)(T r) if(__traits(compiles, to!string(r)))
    {
        representation = to!string(r);
    }
    override string toString()
    {
        return representation;
    }
}
class CUnaryExpression : CExpression
{
    CExpression operand;
    string operator;
    bool suffix;

    this(CExpression expr, string op, bool s = false)
    {
        operand = expr;
        operator = op;
        suffix = s;
    }
    override string toString()
    {
        if((operator == "++" || operator == "--") && suffix)
            return operand.toString() ~ operator;
        else
            return operator ~ operand.toString();
    }
}
class CBinaryExpression : CExpression
{
    CExpression left, right;
    string operator;

    this(CExpression lhs, string op, CExpression rhs)
    {
        left = lhs;
        right = rhs;
        operator = op;
    }
    override string toString()
    {
        return left.toString() ~ " " ~ operator ~ " " ~ right.toString();
    }
}
class CTernaryExpression : CExpression
{
    CExpression test, then, otherwise;

    this(CExpression op0, CExpression op1, CExpression op2)
    {
        test = op0;
        then = op1;
        otherwise = op2;
    }
    override string toString()
    {
        return test.toString() ~ " ? " ~ then.toString() ~ " : " ~ otherwise.toString();
    }
}
class CGroupingExpression : CExpression
{
    CExpression expression;

    this(CExpression expr)
    {
        expression = expr;
    }
    override string toString()
    {
        return "(" ~ expression.toString() ~ ")";
    }
}
class CCallExpression : CExpression
{
    CExpression callee;
    CExpression[] arguments;

    this(CExpression c, CExpression[] args...)
    {
        callee = c;
        arguments = new CExpression[args.length];
        arguments[] = args;
    }
    override string toString()
    {
        string buffer = callee.toString() ~ "(";
        if(arguments.length > 0)
        {
            buffer ~= arguments[0].toString();
            foreach(i; 1..arguments.length)
                buffer ~= ", " ~ arguments[i].toString();
        }
        buffer ~= ")";
        return buffer;
    }
}
class CCommaExpression : CExpression
{
    CExpression[] subexprs;

    this() {}
    this(CExpression[] args...)
    {
        subexprs = new CExpression[args.length];
        subexprs[] = args;
    }
    override string toString()
    {
        string buffer;
        if(subexprs.length > 0)
        {
            buffer ~= subexprs[0].toString();
            foreach(i; 1..subexprs.length)
                buffer ~= ", " ~ subexprs[i].toString();
        }
        return buffer;
    }
}
class CSubscriptExpression : CExpression
{
    CExpression left, right;

    this(CExpression lhs, CExpression rhs)
    {
        left = lhs;
        right = rhs;
    }
    override string toString()
    {
        return left.toString() ~ "[" ~ right.toString() ~ "]";
    }
}
enum CMemberAccessKind { Object, Pointer };
class CMemberAccessExpression : CExpression
{
    CMemberAccessKind operator;
    CExpression operand;
    string field;

    this(CExpression expr, CMemberAccessKind op, string prop)
    {
        operand = expr;
        operator = op;
        field = prop;
    }
    override string toString()
    {
        string buffer = operand.toString();
        final switch(operator)
        {
        case CMemberAccessKind.Object: buffer ~= "."; break;
        case CMemberAccessKind.Pointer: buffer ~= "->"; break;
        }
        return buffer ~ field;
    }
}
/*class CRandomMemberAccessExpression : CExpression
{
    CMemberAccessKind operator;
    CExpression lhs;
    CExpression rhs;

    this(CExpression expr, CMemberAccessKind op, CExpression prop)
    {
        lhs = expr;
        operator = op;
        rhs = prop;
    }
    override string toString()
    {
        string buffer = lhs.toString();
        final switch(operator)
        {
        case CMemberAccessKind.Object: buffer ~= ".*"; break;
        case CMemberAccessKind.Pointer: buffer ~= "->*"; break;
        }
        return buffer ~ rhs.toString();
    }
}*/
class CCastExpression : CExpression
{
    CExpression operand;
    CType type;

    this(CExpression op, CType t)
    {
        operand = op;
        type = t;
    }
    override string toString()
    {
        return "(" ~ type.toString() ~ ") " ~ operand.toString();
    }
}
class CAssignmentExpression : CExpression
{
    CExpression left, right;

    this(CExpression lhs, CExpression rhs)
    {
        left = lhs;
        right = rhs;
    }
    override string toString()
    {
        return left.toString() ~ " = " ~ right.toString();
    }
}
class CCompoundAssignmentExpression : CAssignmentExpression
{
    string operator;

    this(CExpression lhs, string operator, CExpression rhs)
    {
        super(lhs, rhs);
    }
    override string toString()
    {
        return left.toString ~ " " ~ operator ~ "= " ~ right.toString();
    }
}
class CEqualityExpression : CCompoundAssignmentExpression
{
    this(CExpression lhs, CExpression rhs)
    {
        super(lhs, "=", rhs);
    }
}
class CInequalityExpression : CCompoundAssignmentExpression
{
    this(CExpression lhs, CExpression rhs)
    {
        super(lhs, "!", rhs);
    }
}

interface CType
{
    string toString();
}
class CUnresolvedType : CType { override string toString() { return "UNRESOLVED_TYPE"; } }
enum CBType { Int, UInt, Short, UShort, Char, UChar, Long, ULong, LongLong, ULongLong, Float, UFloat, Double, UDouble }
class CBasicType : CType
{
    CBType type;

    this(CBType t)
    {
        type = t;
    }
    override string toString()
    {
        string str = enumToString(type);
        if(str == "LongLong")
            return "long long";
        if(str == "ULongLong")
            return "unsigned long long";
        else if(str[0] == 'U')
            return "unsigned " ~ str[1..$].toLower();
        return str.toLower();
    }
}
class CArrayType : CType
{
    CType underliningType;
    uint length;

    this(CType type, uint len = 0)
    {
        underliningType = type;
        length = len;
    }
    override string toString()
    {
        return underliningType.toString ~ "[" ~ (length ? to!string(length) : "*") ~ "]";
    }
}
