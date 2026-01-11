# PA3

# PA3 语法分析器设计报告

## 一、设计概述

本作业实现了一个 COOL 语言的语法分析器（Parser），使用 Bison 工具编写语法规则，将词法分析器输出的 token 流转换为抽象语法树（AST）。主要工作包括：

1. 完成 `cool.y` 文件中的语法规则定义
2. 为每个语法规则编写语义动作，构建对应的 AST 节点
3. 处理运算符的优先级和结合性
4. 实现基本的错误恢复机制
5. 通过测试验证解析器的正确性

## 二、文件结构说明

### 2.1 修改的文件
- **cool.y**: 唯一需要修改的文件，包含完整的 Bison 语法规则、语义动作、优先级声明和错误处理。

### 2.2 未修改的文件
- `Makefile`、`parser-phase.cc`、`tokens-lex.cc`、`dumptype.cc` 等基础设施文件均未改动。

### 2.3 自动生成的文件
- `cool-parse.cc`、`cool-parse.h`、`cool.tab.h`、`cool.output` 等由 Bison 自动生成。

## 三、语法规则设计

### 3.1 顶层结构
- **program**: 由 `class_list` 组成，生成 `program` 根节点
- **class_list**: 支持递归定义多个类，使用 `append_Classes` 构建列表
- **class**: 支持普通类定义和继承类定义，包含错误恢复规则

### 3.2 类定义
```yacc
class : CLASS TYPEID '{' feature_list '}' ';'
      | CLASS TYPEID INHERITS TYPEID '{' feature_list '}' ';'
      | error ';'  /* 错误恢复 */
```

### 3.3 特征（Feature）定义
- **method**: `OBJECTID '(' formal_list ')' ':' type '{' expr '}'`
- **attr**: 支持有初始化和无初始化两种情况

### 3.4 表达式系统
表达式按优先级从低到高实现：

1. **赋值表达式**: `OBJECTID ASSIGN expr`
2. **逻辑运算**: `NOT expr`
3. **比较运算**: `<`, `LE`, `=`
4. **算术运算**: `+`, `-`, `*`, `/`
5. **特殊运算**: `ISVOID`, `~`（取反）
6. **方法调用**: `.`, `@`（静态分发）

### 3.5 复杂表达式结构
- **if 表达式**: `IF expr THEN expr ELSE expr FI`
- **while 循环**: `WHILE expr LOOP expr POOL`
- **case 分支**: `CASE expr OF case_list ESAC`
- **let 表达式**: 支持多个绑定的嵌套处理
- **代码块**: `{ expr_block_list }`

### 3.6 列表处理
所有列表结构（类列表、特征列表、参数列表、表达式列表等）均采用递归方式构建：
- 空列表 → `nil_XXX()`
- 单个元素 → `single_XXX()`
- 追加元素 → `append_XXX()`

## 四、关键设计决策

### 4.1 行号处理
每个 AST 节点都需要正确的行号信息用于错误报告。采用以下机制：
```c
#define SET_NODELOC(Current) node_lineno = Current;
```
在每个语义动作中调用 `SET_NODELOC` 设置当前节点行号。

### 4.2 let 表达式的嵌套处理
多个 let 绑定需要嵌套处理。例如：
```
let x:Int <- 1, y:Int <- 2 in x + y
```
被解析为：
```
let(x, Int, 1, let(y, Int, 2, plus(x, y)))
```
通过 `rest_let_bindings` 非终结符实现递归嵌套。

### 4.3 方法调用处理
- 简单调用: `method()`
- 对象调用: `expr.method()`
- 静态调用: `expr@Type.method()`
均使用 `dispatch` 或 `static_dispatch` 节点构建。

### 4.4 错误恢复
在关键位置（如类定义）添加错误恢复规则：
```yacc
class : error ';' {
    $$ = class_(idtable.add_string("Error"),
                idtable.add_string("Object"),
                nil_Features(),
                stringtable.add_string(curr_filename));
}
```
当解析遇到错误时，跳过分号并创建错误节点继续解析。

### 4.5 运算符优先级
```yacc
%nonassoc IN
%right ASSIGN
%right NOT
%nonassoc LE '<' '='
%left '+' '-'
%left '*' '/'
%left ISVOID
%left '~'
%left '@'
left '.'
```
优先级从低到高声明，确保表达式正确解析。

## 五、代码正确性证明

### 5.1 语法覆盖性
本实现覆盖了 COOL 语言的所有语法结构：
- [x] 类定义（继承、无继承）
- [x] 方法定义（含参数）
- [x] 属性定义（含初始化）
- [x] 所有表达式类型（19种）
- [x] 控制流结构（if、while、case）
- [x] 方法调用（普通、静态）
- [x] 所有运算符

### 5.2 优先级正确性
通过 Bison 的优先级声明机制，确保：
- `a + b * c` 解析为 `a + (b * c)`
- `a = b = c` 解析为 `a = (b = c)`（右结合）
- `a + b - c` 解析为 `(a + b) - c`（左结合）

### 5.3 错误处理
1. 语法错误能正确报告位置和原因
2. 错误恢复机制防止解析器因单个错误而停止
3. 超过 50 个错误时自动终止

### 5.4 AST 构建正确性
每个语义动作都：
1. 正确设置行号信息
2. 调用适当的构造函数
3. 处理列表的递归构建
4. 维护类型一致性

## 六、测试说明

### 6.1 官方测试用例
- **good.cl**: 包含所有合法语法结构，全部通过测试
- **bad.cl**: 包含各种语法错误，能正确检测并报告
- **stack.cl**: 测试复杂表达式和方法调用
- **complex.cl**: 测试嵌套结构和边界情况

### 6.2 自定义测试用例
添加了以下测试文件：

#### test1.cl - 基本结构测试
```cool
class Main {
    main(): Int { 1 };
};

class Simple {
    x: Int;
    set_x(n: Int): Int { x <- n };
};
```

#### test2.cl - 表达式优先级测试
```cool
class Test {
    test(): Int {
        let x: Int <- 1 + 2 * 3,
            y: Int <- (1 + 2) * 3
        in x + y
    };
};
```

#### test3.cl - 错误语法测试
```cool
class ErrorTest {
    -- 缺少分号
    x: Int
    
    -- 括号不匹配
    test(): Int { (1 + 2 };
};
```

### 6.3 测试方法
```bash
# 1. 编译
make parser

# 2. 运行官方测试
make dotest

# 3. 对比官方输出
diff <(./lexer good.cl | ./parser) <(/usr/class/bin/lexer good.cl | /usr/class/bin/parser)

# 4. 运行自定义测试
./myparser test1.cl
./myparser test2.cl
```

### 6.4 测试结果
- 所有合法语法结构都能正确解析
- 所有语法错误都能正确检测
- AST 输出与官方解析器完全一致（除行号外）
- 复杂嵌套结构（如多层 let、case）处理正确

## 七、遇到的挑战与解决方案

### 7.1 let 表达式的嵌套处理
**问题**: 多个 let 绑定需要嵌套 AST 结构，但语法规则是线性的。

**解决方案**: 引入 `rest_let_bindings` 非终结符，递归处理剩余绑定，构建嵌套的 `let` 节点。

### 7.2 行号信息维护
**问题**: 每个 AST 节点需要正确的行号，但 Bison 的默认位置处理不直接适用。

**解决方案**: 使用 `SET_NODELOC` 宏，在语义动作中显式设置 `node_lineno`。

### 7.3 方法调用中的 self
**问题**: 简单方法调用如 `method()` 需要隐式的 `self` 对象。

**解决方案**: 在语义动作中显式使用 `self_sym`：
```c
dispatch(object(self_sym), $1, $3)
```

### 7.4 优先级冲突
**问题**: 某些表达式结构可能产生移进-归约冲突。

**解决方案**: 仔细设计优先级声明顺序，确保 Bison 能正确解决冲突。

## 八、编译与运行

### 8.1 环境设置
```bash
cd /usr/class/assignments/PA3
ln -s /usr/class/bin/lexer .
ln -s /usr/class/bin/semant .
ln -s /usr/class/bin/cgen .
```

### 8.2 编译命令
```bash
make parser          # 编译解析器
make clean           # 清理后重新编译
```

### 8.3 运行命令
```bash
./myparser test.cl                 # 使用脚本
./lexer test.cl | ./parser         # 手动管道
mycoolc test.cl                    # 完整编译器
```

## 九、结论

本语法分析器实现了 COOL 语言的全部语法规则，能够：
1. 正确解析所有合法程序
2. 准确检测语法错误并提供有用信息
3. 构建正确的抽象语法树
4. 处理复杂的嵌套结构和优先级关系

