module _2c_optimizer;
import std.string;
import std.conv;
import _2c;

public:

class CEvalException : Exception
{
    this(lazy string message)
    {
        super(message);
    }
}

enum Ternary { True, False, Maybe }
Ternary evalToBool(CExpression e)
{
    if(auto val = cast(CValueExpression) e)
    {
        string rep = val.representation;
        if(rep == "true")
            return Ternary.True;
        else if(rep == "false")
            return Ternary.False;
        if(rep.isNumeric())
        {
            if(parse!int(rep) == 0)
                return Ternary.False;
            else
                return Ternary.True;
        }
    }
    else if(auto expr = cast(CUnaryExpression) e)
    {
        if((expr.operator == "++" || expr.operator == "--"))
        {
            try
            {
                int result = evalArithmetic(expr.operand);
                if(!expr.suffix)
                {
                    if(expr.operator == "++")
                        ++result;
                    else
                        --result;
                }
                if(result == 0)
                    return Ternary.False;
                else
                    return Ternary.True;
            }
            catch(CEvalException)
            {
                return Ternary.Maybe;
            }
        }
        else
        {
            try
            {
                if(evalArithmetic(expr))
                    return Ternary.True;
                else
                    return Ternary.False;
            }
            catch(CEvalException)
            {
                return Ternary.Maybe;
            }
        }
    }
    return Ternary.Maybe;
}
int evalArithmetic(CExpression e)
{
    if(auto expr = cast(CValueExpression) e)
    {
        if(expr.representation.isNumeric())
            return parse!int(expr.representation);
    }
    else if(auto expr = cast(CUnaryExpression) e)
    {
        int result = evalArithmetic(expr.operand);
        switch(expr.operator)
        {
        case "+": return +result;
        case "-": return -result;
        case "~": return ~result;
        case "!": return !result;
        default:  break;
        }
    }
    else if(auto expr = cast(CBinaryExpression) e)
    {
        int lhs, rhs;
        bool success = false;
        try
        {
            lhs = evalArithmetic(expr.left);
            expr.left = new CValueExpression(lhs);
            success = true;
        }
        catch(CEvalException) {}
        rhs = evalArithmetic(expr.right);
        expr.right = new CValueExpression(rhs);

        if(success)
        {
            switch(expr.operator)
            {
            static foreach(op; ["+", "-", "*", "/", "%", "&", "|", "^", "&&", "||", "<", "<=", ">", ">=", "==", "!=", "<<", ">>"])
                case op: mixin("return lhs " ~ op ~ " rhs;");
            default: break;
            }
        }
    }
    else if(auto expr = cast(CGroupingExpression) e)
    {
        return evalArithmetic(expr.expression);
    }
    throw new CEvalException("Cannot evaluate this expression.");
}

CStatement eliminateDeadCode(CStatement s)
{
    if(auto stmt = cast(CIfStatement) s)
    {
        Ternary tryBool = evalToBool(stmt.test);
        if(tryBool == Ternary.True)
            return stmt.then;
        else if(tryBool == Ternary.False)
            return stmt.otherwise;
    }
    else if(auto stmt = cast(CSwitchStatement) s)
    {
        int first = 0;
        foreach(i, ss; stmt.body.body)
        {
            auto substmt = cast(CCaseStatement) ss;
            if(substmt !is null)
                break;
            ++first;
        }
        if(first)
        {
            auto newstmt = new CBlockStatement();
            newstmt.body.length = stmt.body.body.length - first;
            newstmt.body[] = stmt.body.body[first..$];
            stmt.body = newstmt;
        }
        try
        {
            int defaultstmtPos;
            CDefaultStatement defaultstmt;
            int result = evalArithmetic(stmt.test);
            stmt.test = new CValueExpression(result);
            foreach(i, ss; stmt.body.body)
            {
                if(auto substmt = cast(CCaseStatement) ss)
                {
                    try
                    {
                        int res = evalArithmetic(substmt.expr);
                        if(result == res)
                        {
                            auto newstmt = new CBlockStatement();
                            newstmt.body.length = stmt.body.body.length - i;
                            newstmt.body[0] = substmt.labelee;
                            newstmt.body[1..$] = stmt.body.body[i + 1..$];
                            foreach(j, morestmt; newstmt.body)
                            {
                                //removing following case statements but keeping their contents
                                //TODO: analyze chosen case to know if keeping the following ones is necessary
                                if(auto casestmt = cast(CCaseStatement) morestmt)
                                    newstmt.body[j] = casestmt.labelee;
                                else if(auto casestmt = cast(CDefaultStatement) morestmt)
                                    newstmt.body[j] = casestmt.labelee;
                            }
                            return newstmt;
                        }
                    }
                    catch(CEvalException) {}
                }
                else if(auto substmt = cast(CDefaultStatement) ss)
                {
                    defaultstmt = substmt;
                    defaultstmtPos = i;
                }
            }
            //else, if there is a DefaultStatement
            if(defaultstmt !is null)
            {
                auto newstmt = new CBlockStatement();
                newstmt.body.length = stmt.body.body.length - defaultstmtPos;
                newstmt.body[0] = defaultstmt.labelee;
                newstmt.body[1..$] = stmt.body.body[defaultstmtPos + 1..$];
                foreach(j, morestmt; newstmt.body)
                {
                    if(auto casestmt = cast(CCaseStatement) morestmt)
                        newstmt.body[j] = casestmt.labelee;
                }
                return newstmt;
            }
            //else, there are no handlers
            return null;
        }
        catch(CEvalException) {}
    }
    return s;
}
CFunction!(Ts) eliminateDeadCode(Ts...)(CFunction!(Ts) func)
{
    CStatement[] newbody;
    foreach(i, stmt; func.body)
    {
        auto optimized = eliminateDeadCode(stmt);
        if(optimized !is null)
            newbody ~= optimized;
    }
    func.body = newbody;
    return func;
}

CStatement resolveArithmetic(CStatement s)
{
    try
    {
        if(auto stmt = cast(CExpressionStatement) s)
        {
            int result = evalArithmetic(stmt.expr);
            stmt.expr = new CValueExpression(result);
        }
        else if(auto stmt = cast(CBlockStatement) s)
        {
            foreach(i, substmt; stmt.body)
                stmt.body[i] = resolveArithmetic(substmt);
        }
        else if(auto stmt = cast(CIfStatement) s)
        {
            int result = evalArithmetic(stmt.test);
            stmt.test = new CValueExpression(result);
        }
        else if(auto stmt = cast(CWhileStatement) s)
        {
            int result = evalArithmetic(stmt.test);
            stmt.test = new CValueExpression(result);
        }
        else if(auto stmt = cast(CDoWhileStatement) s)
        {
            int result = evalArithmetic(stmt.test);
            stmt.test = new CValueExpression(result);
        }
        else if(auto stmt = cast(CForStatement) s)
        {

        }
    }
    catch(CEvalException) {}
    return s;
}
CFunction!(Ts) resolveArithmetic(Ts...)(CFunction!(Ts) func)
{
    foreach(i, stmt; func.body)
        func.body[i] = resolveArithmetic(stmt);
    return func;
}
