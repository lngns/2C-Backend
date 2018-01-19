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
        default:  break;
        }
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
    return s;
}
CFunction!(Ts) eliminateDeadCode(Ts...)(CFunction!(Ts) func)
{
    foreach(i, stmt; func.body)
        func.body[i] = eliminateDeadCode(stmt);
    return func;
}
