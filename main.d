module main;
import std.stdio;
import _2c;
import _2c_optimizer;

void main()
{
    auto m = new CModule("HelloWorld");
    m ~= new CCppDirective("include", "<stdio.h>");

    auto cmain = new CFunction("main", new CBasicType(CBType.Int));
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
            "--",
            new CValueExpression("1")
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
    cmain ~= new CExpressionStatement(
        new CBinaryExpression(
            new CGroupingExpression(
                new CBinaryExpression(
                    new CValueExpression(40),
                    "+",
                    new CValueExpression(2)
                )
            ),
            "*",
            new CValueExpression("8")
        )
    );
    cmain ~= new CSwitchStatement(
        new CValueExpression("foo"),
        new CBlockStatement(
            new CExpressionStatement(
                new CCallExpression(
                    new CValueExpression("puts"),
                    new CValueExpression("\"Should not be called\"")
                )
            ),
            new CCaseStatement(
                new CValueExpression("28"),
                new CExpressionStatement(
                    new CBinaryExpression(
                        new CValueExpression("foo"),
                        "+=",
                        new CValueExpression(15)
                    )
                )
            )
        )
    );
    cmain ~= new CSwitchStatement(
        new CValueExpression(2),
        new CBlockStatement(
            new CCaseStatement(
                new CValueExpression(4),
                new CExpressionStatement(
                    new CCallExpression(
                        new CValueExpression("puts"),
                        new CValueExpression("\"Should not be called\"")
                    )
                )
            ),
            new CBreakStatement,
            new CCaseStatement(
                new CValueExpression(5),
                new CExpressionStatement(
                    new CCallExpression(
                        new CValueExpression("puts"),
                        new CValueExpression("\"Should not be called\"")
                    )
                )
            ),
            new CBreakStatement,
            new CCaseStatement(
                new CBinaryExpression(
                    new CValueExpression(1),
                    "*",
                    new CValueExpression(2)
                ),
                new CExpressionStatement(
                    new CCallExpression(
                        new CValueExpression("puts"),
                        new CValueExpression("\"Hello World!\"")
                    )
                )
            ),
            new CCaseStatement(
                new CValueExpression(7),
                new CExpressionStatement(
                    new CCallExpression(
                        new CValueExpression("puts"),
                        new CValueExpression("\"Fall through!\"")
                    )
                )
            )
        )
    );
    cmain ~= new CSwitchStatement(
        new CBinaryExpression(
            new CValueExpression(5),
            "*",
            new CValueExpression(3)
        ),
        new CBlockStatement(
            new CCaseStatement(
                new CValueExpression(4),
                new CExpressionStatement(
                    new CCallExpression(
                        new CValueExpression("puts"),
                        new CValueExpression("\"Should not be called\"")
                    )
                )
            ),
            new CCaseStatement(
                new CValueExpression(2),
                new CExpressionStatement(
                    new CCallExpression(
                        new CValueExpression("puts"),
                        new CValueExpression("\"Should not be called\"")
                    )
                )
            ),
            new CBreakStatement,
            new CDefaultStatement(
                new CExpressionStatement(
                    new CCallExpression(
                        new CValueExpression("puts"),
                        new CValueExpression("\"Hello World!\"")
                    )
                )
            )
        )
    );
    cmain ~= new CSwitchStatement(
        new CBinaryExpression(
            new CValueExpression(5),
            "*",
            new CValueExpression(3)
        ),
        new CBlockStatement(
            new CCaseStatement(
                new CValueExpression(4),
                new CExpressionStatement(
                    new CCallExpression(
                        new CValueExpression("puts"),
                        new CValueExpression("\"Should not be called\"")
                    )
                )
            ),
            new CBreakStatement,
            new CCaseStatement(
                new CValueExpression(2),
                new CExpressionStatement(
                    new CCallExpression(
                        new CValueExpression("puts"),
                        new CValueExpression("\"Should not be called\"")
                    )
                )
            )
        )
    );
    m ~= cmain;

    writeln("Unoptimized Code:\r\n");
    writeln(m.toString());


    cmain = eliminateDeadCode(cmain);
    cmain = resolveArithmetic(cmain);

    writeln("\r\nOptimized Code:\r\n");
    writeln(m.toString());

    writeln("\r\n\r\n-----------\r\n");

    CModule m2 = new CModule("DeclarationTest", &CGCCAttributeEmitter);
    m2 ~= new CValueDeclaration(new CBasicType(CBType.UInt), "foo");

    auto func = new CFunction("func", new CBasicType(CBType.Int));
    func ~= new CDeclarationStatement(new CValueDeclaration(new CBasicType(CQualifier.Const, CBType.ULongLong), "bar", null, CStorageClass.Static));
    func ~= new CDeclarationStatement(new CValueDeclaration(new CPointerType(new CBasicType(CBType.Void)), "baz"));
    func ~= new CDeclarationStatement(new CValueDeclaration(new CFunctionPointerType(CQualifier.Const, new CBasicType(CBType.Int), new CBasicType(CBType.Int), new CBasicType(CBType.Int)), "qux"));

    m2 ~= func;
    writeln(m2);
}
