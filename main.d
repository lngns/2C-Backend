module main;
import std.stdio;
import _2c;
import _2c_optimizer;

void main()
{
    auto m = new CModule("HelloWorld");
    m ~= new CCppDirective("include", "<stdio.h>");

    auto cmain = new CFunction!int("main");
    cmain ~= new CIfStatement(
        new CValueExpression("true"),
        new CExpressionStatement(
            new CCallExpression(
                new CValueExpression("puts"),
                new CValueExpression("\"Hello World!\"")
            )
        ),
        new CExpressionStatement(
            new CCallExpression(
                new CValueExpression("puts"),
                new CValueExpression("\"Should not be called\"")
            )
        )
    );
    cmain ~= new CIfStatement(
        new CUnaryExpression(
            new CValueExpression("1"),
            "--"
        ),
        new CExpressionStatement(
            new CCallExpression(
                new CValueExpression("puts"),
                new CValueExpression("\"Should not be called\"")
            )
        ),
        new CExpressionStatement(
            new CCallExpression(
                new CValueExpression("puts"),
                new CValueExpression("\"Hello World!\"")
            )
        )
    );
    cmain ~= new CExpressionStatement(
        new CBinaryExpression(
            new CValueExpression(40),
            "+",
            new CValueExpression(2)
        )
    );
    m ~= cmain;

    writeln("Unoptimized Code:\r\n");
    writeln(m.toString());


    cmain = eliminateDeadCode(cmain);

    writeln("\r\nOptimized Code:\r\n");
    writeln(m.toString());
}
