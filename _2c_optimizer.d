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
    else if(auto expr = cast(CTernaryExpression) e)
    {
        Ternary res = evalToBool(expr.test);
        if(res == Ternary.True)
            return evalArithmetic(expr.then);
        else if(res == Ternary.False)
            return evalArithmetic(expr.otherwise);
    }
    else if(auto expr = cast(CGroupingExpression) e)
    {
        return evalArithmetic(expr.expression);
    }
    throw new CEvalException("Cannot evaluate this expression.");
}

CStatement simplifyBlock(CStatement s)
{
    if(auto stmt = cast(CBlockStatement) s)
    {
        if(stmt.body.length == 0)
            return null;
        else if(stmt.body.length == 1)
        {
            if(auto decl = cast(CDeclarationStatement) stmt.body[0])
            {
                if(decl.declaration.initializer !is null)
                {
                    if(auto init = cast(CCallExpression) decl.declaration.initializer)
                        return new CExpressionStatement(init);
                }
                return null;
            }
            else if(auto inner = cast(CBlockStatement) stmt.body[0])
            {
                return simplifyBlock(inner);
            }
            return stmt.body[0];
        }
    }
    return s;
}
CStatement eliminateDeadCode(CStatement s)
{
    if(auto stmt = cast(CExtensionStatement) s)
    {
        return eliminateDeadCode(stmt.toCStatement());
    }
    else if(auto stmt = cast(CBlockStatement) s)
    {
        if(stmt.body.length == 0)
            return null;
        else if(stmt.body.length == 1)
            return simplifyBlock(eliminateDeadCode(stmt.body[0]));
        CStatement[] newbody;
        foreach(ss; stmt.body)
        {
            auto optimized = simplifyBlock(eliminateDeadCode(ss));
            if(optimized !is null)
                newbody ~= optimized;
        }
        stmt.body = newbody;
        return stmt;
    }
    else if(auto stmt = cast(CIfStatement) s)
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
            auto substmt = cast(CLabelStatement) ss;
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
    else if(auto stmt = cast(CExpressionStatement) s)
    {
        if(auto expr = cast(CTernaryExpression) stmt.expr)
        {
            Ternary res = evalToBool(expr.test);
            if(res == Ternary.True)
                stmt.expr = expr.then;
            else if(res == Ternary.False)
                stmt.expr = expr.otherwise;
        }
        try
        {
            evalArithmetic(stmt.expr); //if it's evaluatable it doesn't have side-effects, so we can remove it
            return null;
        }
        catch(CEvalException) {}
    }
    return s;
}
CFunction eliminateDeadCode(CFunction func)
{
    import std.variant;

    Algebraic!(CStatement, CCppDirective)[] newbody;
    foreach(i, stmt; func.body)
    {
        if(stmt.peek!CStatement)
        {
            auto optimized = simplifyBlock(eliminateDeadCode(stmt.get!CStatement));
            if(optimized !is null)
                newbody ~= Algebraic!(CStatement, CCppDirective)(optimized);
        }
        else
            newbody ~= Algebraic!(CStatement, CCppDirective)(stmt.get!CCppDirective);
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
            stmt.then = resolveArithmetic(stmt.then);
            int result = evalArithmetic(stmt.test);
            stmt.test = new CValueExpression(result);
        }
        else if(auto stmt = cast(CWhileStatement) s)
        {
            stmt.body = resolveArithmetic(stmt.body);
            int result = evalArithmetic(stmt.test);
            stmt.test = new CValueExpression(result);
        }
        else if(auto stmt = cast(CDoWhileStatement) s)
        {
            stmt.body = resolveArithmetic(stmt.body);
            int result = evalArithmetic(stmt.test);
            stmt.test = new CValueExpression(result);
        }
        else if(auto stmt = cast(CForStatement) s)
        {
            stmt.body = resolveArithmetic(stmt.body);
        }
    }
    catch(CEvalException) {}
    return s;
}
CFunction resolveArithmetic(CFunction func)
{
    foreach(i, stmt; func.body)
    {
        if(stmt.peek!CStatement)
            func.body[i] = resolveArithmetic(stmt.get!CStatement);
        else
            func.body[i] = stmt.get!CCppDirective;
    }
    return func;
}
