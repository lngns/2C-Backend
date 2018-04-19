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

class CAstException : Exception
{
    this(lazy string message)
    {
        super(message);
    }
}

interface CNode { string toString(); }
interface CUpperNode : CNode { string toString(const CModule); }
class CAttribute { string name; string[] arguments; }
alias CAttributeEmitter = string function(CAttribute[]);
class CModule
{
    CUpperNode[] tree;
    string name;
    CAttributeEmitter attributeEmitter;
    bool computedGotoWarning;

    this(string n, CAttributeEmitter attrman = null)
    {
        name = n;
        attributeEmitter = attrman;
        computedGotoWarning = true;
    }
    CModule opOpAssign(string s)(CUpperNode node) if(s == "~")
    {
        tree ~= node;
        return this;
    }
    override string toString()
    {
        string buffer = "";
        foreach(node; tree)
            buffer ~= node.toString(this) ~ (!cast(CCppDirective) node ? ";\r\n" : "\r\n");
        return buffer;
    }
}
class CExtensionDeclaration : CUpperNode
{
    abstract CUpperNode toCUpperNode();
    final override string toString(const CModule m)
    {
        return toCUpperNode().toString(m);
    }
}
class CMultipleUpperNodes : CUpperNode
{
    CUpperNode[] body;

    this() {}
    this(CUpperNode[] segment...)
    {
        body = segment;
    }
    CMultipleUpperNodes opOpAssign(string s)(CUpperNode stmt) if(s == "~")
    {
        body ~= stmt;
        return this;
    }
    override string toString(const CModule m)
    {
        string buffer;
        foreach(node; body)
            buffer ~= node.toString(m) ~ (!cast(CCppDirective) node ? ";\r\n" : "\r\n");
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
class CFunction : CUpperNode
{
    import std.variant;

    string name;
    CType returnType;
    Algebraic!(CStatement, CCppDirective)[] body;
    CValueDeclaration[] parameters;

    this(string n, CType ret, CValueDeclaration[] params...)
    {
        name = n;
        returnType = ret;
        parameters[] = params;
    }
    CFunction opOpAssign(string s)(CStatement node) if(s == "~")
    {
        body ~= Algebraic!(CStatement, CCppDirective)(node);
        return this;
    }
    CFunction opOpAssign(string s)(CCppDirective node) if(s == "~")
    {
        body ~= node;
        return this;
    }
    override string toString(const CModule m)
    {
        string buffer = returnType.toString() ~ " " ~ name ~ "(";
        if(parameters.length == 0)
            buffer ~= "void";
        else
        {
            buffer ~= parameters[0].toString(m);
            foreach(param; parameters[1..$])
                buffer ~= ", " ~ param.toString(m);
        }
        buffer ~= ")\r\n{\r\n";
        foreach(node; body)
        {
            if(node.peek!CStatement)
            {
                auto n = node.get!CStatement;
                if(cast(CLabelStatement) n)
                    buffer ~= n.toString(4, m) ~ "\r\n";
                else
                    buffer ~= "    " ~ n.toString(4, m) ~ "\r\n";
            }
            else if(node.peek!CCppDirective)
            {
                auto n = node.get!CCppDirective;
                buffer ~= n.toString(m) ~ "\r\n";
            }
        }
        buffer ~= "}";
        return buffer;
    }
}
enum CStorageClass { Auto, Static, Register, Extern }
class CValueDeclaration : CUpperNode
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
        string buffer;
        if(m.attributeEmitter !is null && attributes !is null)
            buffer ~= m.attributeEmitter(attributes) ~ " ";
        buffer ~= enumToString(storageClass).toLower() ~ " ";
        CType t = type;
        if(auto tt = cast(CExtensionType) type)
            t = tt.toCType();
        if(auto fptype = cast(CFunctionPointerType) t)
        {
            buffer ~= fptype.returnType.toString() ~ "(*" ~ (fptype.qualifier != CQualifier.None ? enumToString(fptype.qualifier).toLower() ~ " " : "") ~ identifier ~ ")(";
            if(fptype.argumentsTypes.length == 0)
                buffer ~= "void)";
            else
            {
                buffer ~= fptype.argumentsTypes[0].toString();
                foreach(CType tt; fptype.argumentsTypes[1..$])
                    buffer ~= ", " ~ tt.toString();
                buffer ~= ")";
            }
        }
        else
        {
            if(type.qualifier != CQualifier.None)
                buffer ~= enumToString(type.qualifier).toLower() ~ " ";
            if(cast(CBasicType) t || cast(CPointerType) t || cast(CRemoteStructType) t)
                buffer ~= t.toString() ~ " " ~ identifier;
            else if(auto arrtype = cast(CArrayType) t)
                buffer ~= arrtype.underliningType.toString() ~ " " ~ identifier ~ "[" ~ (arrtype.length ? to!string(arrtype.length) : "*") ~ "]";
        }
        return buffer ~ (initializer !is null ? " = " ~ initializer.toString() : "");
    }
}
enum CAggregateKind { Struct, Enum }
class CAggregateDeclaration : CUpperNode
{
    private uint indent = 0;

    string identifier;
    CAggregateKind kind;
    CUpperNode[] members;
    CAttribute[] attributes;

    this(CAggregateKind k, string i = null, CUpperNode[] m = null, CAttribute[] a = null)
    {
        identifier = i;
        members = m;
        attributes = a;
        kind = k;
    }
    uint setIndent(uint i)
    {
        return indent = i;
    }
    override string toString(const CModule m)
    {
        string buffer = "";
        if(m.attributeEmitter !is null)
            buffer ~= m.attributeEmitter(attributes) ~ " ";
        buffer ~= enumToString(kind).toLower() ~ " " ~ (identifier !is null ? identifier ~ " " : "") ~ "\r\n" ~ strTimes(" ", indent) ~ "{\r\n";
        foreach(member; members)
        {
            if(!cast(CCppDirective) member)
                buffer ~= strTimes(" ", indent);
            if(auto mem = cast(CAggregateDeclaration) member)
                mem.setIndent(indent + 4);
            buffer ~= member.toString(m) ~ "\r\n";
        }
        return buffer ~ strTimes(" ", indent) ~ "}";
    }
}

interface CStatement : CNode { string toString(uint, const CModule); }
class CExtensionStatement : CStatement
{
    abstract CStatement toCStatement();
    final override string toString(uint i, const CModule m)
    {
        return toCStatement().toString(i, m);
    }
}
class CNullStatement : CStatement
{
    override string toString(uint, const CModule)
    {
        return ";";
    }
}
class CDeclarationStatement : CStatement
{
    CValueDeclaration declaration;

    this(CValueDeclaration decl)
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
    CBlockStatement opOpAssign(string s)(CStatement stmt) if(s == "~")
    {
        body ~= stmt;
        return this;
    }
    CBlockStatement opBinary(string s)(CStatement stmt) if(s == "~")
    {
        return new CBlockStatement(body ~ stmt);
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
            buffer ~= strTimes(" ", indent) ~ body.toString(indent, m) ~ " ";
        else
            buffer ~= strTimes(" ", indent + 4) ~ body.toString(indent + 4, m) ~ "\r\n" ~ strTimes(" ", indent);
        buffer ~= "while(" ~ test.toString() ~ ");";
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
        string buffer = "for(" ~ (init !is null ? init.toString() : "") ~ "; " ~ (test !is null ? test.toString() : "") ~ "; " ~ (incr !is null ? incr.toString() : "") ~ ")\r\n";
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
class CGotoStatement : CStatement
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
class CComputedGotoStatement : CStatement
{
    CExpression expr;

    this(CExpression e)
    {
        expr = e;
    }
    override string toString(uint, const CModule m)
    {
        if(m.attributeEmitter != &CGCCAttributeEmitter && m.computedGotoWarning)
            writeln("[WARNING] Computed Gotos require GCC.");
        return "goto *(" ~ expr.toString() ~ ");";
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
class CExtensionExpression : CExpression
{
    abstract CExpression toCExpression();
    final override string toString()
    {
        return toCExpression().toString();
    }
}
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

    this(CExpression expr, string op, bool s = true)
    {
        operand = expr;
        operator = op;
        suffix = s;
    }
    this(string op, CExpression expr, bool s = false)
    {
        this(expr, op, s);
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
class CAssignmentExpression : CBinaryExpression
{
    CExpression left, right;

    this(CExpression lhs, CExpression rhs)
    {
        super(lhs, "=", rhs);
    }
}
class CCompoundAssignmentExpression : CBinaryExpression
{
    this(CExpression lhs, string operator, CExpression rhs)
    {
        super(lhs, operator ~ "=", rhs);
    }
}
class CEqualityExpression : CBinaryExpression
{
    this(CExpression lhs, CExpression rhs)
    {
        super(lhs, "==", rhs);
    }
}
class CInequalityExpression : CBinaryExpression
{
    this(CExpression lhs, CExpression rhs)
    {
        super(lhs, "!=", rhs);
    }
}

enum CQualifier { Const, Volatile, Restrict, None }
class CType
{
    CQualifier qualifier = CQualifier.None;
    abstract override string toString();
}
class CExtensionType : CType
{
    abstract CType toCType();
    override string toString()
    {
        return toCType().toString();
    }
}
enum CBType { Void, Int, UInt, Short, UShort, Char, UChar, Long, ULong, LongLong, ULongLong, Float, UFloat, Double, UDouble }
class CBasicType : CType
{
    CBType type;

    this(CBType t)
    {
        type = t;
    }
    this(CQualifier q, CBType t)
    {
        type = t;
        qualifier = q;
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
    this(CQualifier q, CType type, uint len = 0)
    {
        underliningType = type;
        qualifier = q;
        length = len;
    }
    override string toString()
    {
        return underliningType.toString ~ "[" ~ (length ? to!string(length) : "") ~ "]";
    }
}
class CPointerType : CType
{
    CType underliningType;

    this(CType type)
    {
        underliningType = type;
    }
    this(CQualifier q, CType type)
    {
        underliningType = type;
        qualifier = q;
    }
    override string toString()
    {
        return underliningType.toString() ~ "*";
    }
}
class CFunctionPointerType : CType
{
    CType returnType;
    CType[] argumentsTypes;

    this(CType ret, CType[] args...)
    {
        returnType = ret;
        argumentsTypes = args;
    }
    this(CQualifier q, CType ret, CType[] args...)
    {
        qualifier = q;
        returnType = ret;
        argumentsTypes = args;
    }
    override string toString()
    {
        string buffer = returnType.toString() ~ "(" ~ (qualifier != CQualifier.None ? enumToString(qualifier).toLower() : "") ~ "*)(";
        if(argumentsTypes.length == 0)
            return buffer ~ "void)";
        buffer ~= argumentsTypes[0].toString();
        foreach(CType t; argumentsTypes[1..$])
            buffer ~= ", " ~ t.toString();
        return buffer ~ ")";
    }
}
class CRemoteStructType : CType
{
    string identifier;

    this(string id)
    {
        identifier = id;
    }
    override string toString()
    {
        return "struct " ~ identifier;
    }
}
class CRemoteEnumType : CType
{
    string identifier;

    this(string id)
    {
        identifier = id;
    }
    override string toString()
    {
        return "enum " ~ identifier;
    }
}
