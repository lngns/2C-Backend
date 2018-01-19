# 2C-Backend

**2C-Backend** is a simple and lightweight C transpiler backend written in D.
**2C-Optimizer** is an overly complex AST optimizer based on the 2C-Backend API.

Currently, the backend only supports a subset of C99, but full compliance is to be expected soon.
Plus it is optimistic and quite unsafe: it expects you to not mess with the API, meaning you can easily make it emit illegal code.
But thanks to the simple C syntax, it would be easy to port the project to other languages, such as ones that don't have a default optimizer.

What is planned:
- Full C99 Support
- Safer API with more checks
- CTFE Engine
- JS Backend

Currently, only simple expressions are evaluated by the optimizer.
A CTFE - *Compile-Time Function Execution* - Engine will allow for full interpretation of pure functions.
Lastly and less importantly, but as mentioned, I will maybe make it target more platforms, such as JS, PHP, C++, etc..

To have a full toolchain, I'll write some frontends, surely for C and a Lisp dialect.
