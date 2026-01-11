/*
*  cool.y
*              Parser definition for the COOL language.
*
*/
%{
  #include <iostream>
  #include "cool-tree.h"
  #include "stringtab.h"
  #include "utilities.h"
  
  extern char *curr_filename;
  
  /* Locations */
  #define YYLTYPE int              /* the type of locations */
  #define cool_yylloc curr_lineno  /* use the curr_lineno from the lexer
  for the location of tokens */
    
  extern int node_lineno;          /* set before constructing a tree node
  to whatever you want the line number
  for the tree node to be */
    
  #define YYLLOC_DEFAULT(Current, Rhs, N)         \
  Current = Rhs[1];                             \
  node_lineno = Current;
    
  /* 使用模板中的SET_NODELOC定义 */
  #define SET_NODELOC(Current)  \
  node_lineno = Current;
    
  void yyerror(char *s);        /*  defined below; called for each parse error */
  extern int yylex();           /*  the entry point to the lexer  */
    
  /************************************************************************/
  /*                DONT CHANGE ANYTHING IN THIS SECTION                  */
  
  Program ast_root;	      /* the result of the parse  */
  Classes parse_results;        /* for use in semantic analysis */
  int omerrs = 0;               /* number of errors in lexing and parsing */
  
  /* 只声明，不定义！这些变量在其他文件中定义 */
  extern int curr_lineno;   /* 在lexer中定义 */
  extern int node_lineno;   /* 在parser-phase.cc或其他文件中定义 */
  extern Symbol self_sym;   /* 需要在文件末尾定义 */
  %}
  
  /* A union of all the types that can be the result of parsing actions. */
  %union {
    Boolean boolean;
    Symbol symbol;
    Program program;
    Class_ class_;
    Classes classes;
    Feature feature;
    Features features;
    Formal formal;
    Formals formals;
    Case case_;        /* 修改：Case 而不是 Case_ */
    Cases cases;
    Expression expression;
    Expressions expressions;
    char *error_msg;
  }
  
  /* 
  Declare the terminals; a few have types for associated lexemes.
  The token ERROR is never used in the parser; thus, it is a parse
  error when the lexer returns it.
  
  The integer following token declaration is the numeric constant used
  to represent that token internally.  Typically, Bison generates these
  on its own, but we give explicit numbers to prevent version parity
  problems (bison 1.25 and earlier start at 258, later versions -- at
  257)
  */
  %token CLASS 258 ELSE 259 FI 260 IF 261 IN 262 
  %token INHERITS 263 LET 264 LOOP 265 POOL 266 THEN 267 WHILE 268
  %token CASE 269 ESAC 270 OF 271 DARROW 272 NEW 273 ISVOID 274
  %token <symbol>  STR_CONST 275 INT_CONST 276 
  %token <boolean> BOOL_CONST 277
  %token <symbol>  TYPEID 278 OBJECTID 279 
  %token ASSIGN 280 NOT 281 LE 282 ERROR 283

  /* 单字符token */
  %token '+' '-' '*' '/' '=' '<' '.' '~' ';' ':' ',' '(' ')' '@' '{' '}'
  
  /* DON'T CHANGE ANYTHING ABOVE THIS LINE, OR YOUR PARSER WONT WORK       */
  /**************************************************************************/
  
  /* Complete the nonterminal list below, giving a type for the semantic
  value of each non terminal. (See section 3.6 in the bison 
  documentation for details). */
  
  /* Declare types for the grammar's non-terminals. */
  %type <program> program
  %type <classes> class_list
  %type <class_> class
  %type <features> feature_list
  %type <feature> feature
  %type <formals> formal_list
  %type <formal> formal
  %type <cases> case_list
  %type <case_> case_branch  /* 修改：应为case_，模板中是case_ */
  %type <expression> expr let_expr
  %type <expressions> expr_list expr_block_list
  %type <symbol> type
  %type <expression> rest_let_bindings

  /* 运算符优先级 */
  %nonassoc IN
  %right ASSIGN
  %right NOT
  %nonassoc LE '<' '='
  %left '+' '-'
  %left '*' '/'
  %left ISVOID
  %left '~'
  %left '@'
  %left '.'
  
  %start program
  
  %%
  /* 
  Save the root of the abstract syntax tree in a global variable.
  */
  program : class_list	
    { 
      ast_root = program($1); 
    }
  ;
  
  class_list
    : class			/* single class */
    { 
      $$ = single_Classes($1);
      parse_results = $$; 
    }
    | class_list class	/* several classes */
    { 
      $$ = append_Classes($1,single_Classes($2)); 
      parse_results = $$; 
    }
  ;
  
  /* If no parent is specified, the class inherits from the Object class. */
  class : CLASS TYPEID '{' feature_list '}' ';'
    { 
      SET_NODELOC(@1);
      $$ = class_($2, idtable.add_string("Object"), $4,
                  stringtable.add_string(curr_filename)); 
    }
    | CLASS TYPEID INHERITS TYPEID '{' feature_list '}' ';'
    { 
      SET_NODELOC(@1);
      $$ = class_($2, $4, $6, stringtable.add_string(curr_filename)); 
    }
    | error ';'  /* 错误恢复 */
    {
      SET_NODELOC(@1);
      $$ = class_(idtable.add_string("Error"),
                  idtable.add_string("Object"),
                  nil_Features(),
                  stringtable.add_string(curr_filename));
    }
  ;

  /* 类型 */
  type : TYPEID
    {
      $$ = $1;
    }
  ;
  
  /* Feature list may be empty, but no empty features in list. */
  feature_list : /* empty */
    { 
      $$ = nil_Features(); 
    }
    | feature_list feature ';'
    {
      $$ = append_Features($1, single_Features($2));
    }
  ;

  /* 特征定义 */
  feature 
    : OBJECTID '(' formal_list ')' ':' type '{' expr '}'
    {
      SET_NODELOC(@1);
      $$ = method($1, $3, $6, $8);
    }
    | OBJECTID ':' type
    {
      SET_NODELOC(@1);
      $$ = attr($1, $3, no_expr());
    }
    | OBJECTID ':' type ASSIGN expr
    {
      SET_NODELOC(@1);
      $$ = attr($1, $3, $5);
    }
  ;

  /* 形式参数列表 */
  formal_list
    : /* empty */
    {
      $$ = nil_Formals();
    }
    | formal
    {
      $$ = single_Formals($1);
    }
    | formal_list ',' formal
    {
      $$ = append_Formals($1, single_Formals($3));
    }
  ;

  /* 单个形式参数 */
  formal : OBJECTID ':' type
    {
      SET_NODELOC(@1);
      $$ = formal($1, $3);
    }
  ;

  /* 表达式 - 重要修正：赋值表达式的左值必须是OBJECTID */
  expr
    : OBJECTID ASSIGN expr
    {
      SET_NODELOC(@2);
      $$ = assign($1, $3);
    }
    | let_expr
    {
      $$ = $1;
    }
    | expr '+' expr
    {
      SET_NODELOC(@2);
      $$ = plus($1, $3);
    }
    | expr '-' expr
    {
      SET_NODELOC(@2);
      $$ = sub($1, $3);
    }
    | expr '*' expr
    {
      SET_NODELOC(@2);
      $$ = mul($1, $3);
    }
    | expr '/' expr
    {
      SET_NODELOC(@2);
      $$ = divide($1, $3);
    }
    | expr '<' expr
    {
      SET_NODELOC(@2);
      $$ = lt($1, $3);
    }
    | expr LE expr
    {
      SET_NODELOC(@2);
      $$ = leq($1, $3);
    }
    | expr '=' expr
    {
      SET_NODELOC(@2);
      $$ = eq($1, $3);
    }
    | NOT expr
    {
      SET_NODELOC(@1);
      $$ = comp($2);
    }
    | ISVOID expr
    {
      SET_NODELOC(@1);
      $$ = isvoid($2);
    }
    | '~' expr
    {
      SET_NODELOC(@1);
      $$ = neg($2);
    }
    | NEW type
    {
      SET_NODELOC(@1);
      $$ = new_($2);
    }
    | '{' expr_block_list '}'
    {
      SET_NODELOC(@1);
      $$ = block($2);
    }
    | IF expr THEN expr ELSE expr FI
    {
      SET_NODELOC(@1);
      $$ = cond($2, $4, $6);
    }
    | WHILE expr LOOP expr POOL
    {
      SET_NODELOC(@1);
      $$ = loop($2, $4);
    }
    | CASE expr OF case_list ESAC
    {
      SET_NODELOC(@1);
      $$ = typcase($2, $4);
    }
    | OBJECTID
    {
      SET_NODELOC(@1);
      $$ = object($1);
    }
    | INT_CONST
    {
      SET_NODELOC(@1);
      $$ = int_const($1);
    }
    | STR_CONST
    {
      SET_NODELOC(@1);
      $$ = string_const($1);
    }
    | BOOL_CONST
    {
      SET_NODELOC(@1);
      $$ = bool_const($1);
    }
    | '(' expr ')'
    {
      $$ = $2;
    }
    | OBJECTID '(' expr_list ')'  /* 简单方法调用 */
    {
      SET_NODELOC(@1);
      $$ = dispatch(object(self_sym), $1, $3);
    }
    | expr '.' OBJECTID '(' expr_list ')'
    {
      SET_NODELOC(@2);
      $$ = dispatch($1, $3, $5);
    }
    | expr '@' type '.' OBJECTID '(' expr_list ')'
    {
      SET_NODELOC(@2);
      $$ = static_dispatch($1, $3, $5, $7);
    }
  ;

 /* let表达式 - 支持多个绑定 */
let_expr
    : LET OBJECTID ':' type IN expr
    {
      SET_NODELOC(@1);
      $$ = let($2, $4, no_expr(), $6);
    }
    | LET OBJECTID ':' type ASSIGN expr IN expr
    {
      SET_NODELOC(@1);
      $$ = let($2, $4, $6, $8);
    }
    | LET OBJECTID ':' type ',' rest_let_bindings
    {
      SET_NODELOC(@1);
      $$ = let($2, $4, no_expr(), $6);
    }
    | LET OBJECTID ':' type ASSIGN expr ',' rest_let_bindings
    {
      SET_NODELOC(@1);
      $$ = let($2, $4, $6, $8);
    }
    ;

/* 处理剩余的let绑定 */
rest_let_bindings
    : OBJECTID ':' type IN expr
    {
      SET_NODELOC(@1);
      $$ = let($1, $3, no_expr(), $5);
    }
    | OBJECTID ':' type ASSIGN expr IN expr
    {
      SET_NODELOC(@1);
      $$ = let($1, $3, $5, $7);
    }
    | OBJECTID ':' type ',' rest_let_bindings
    {
      SET_NODELOC(@1);
      $$ = let($1, $3, no_expr(), $5);
    }
    | OBJECTID ':' type ASSIGN expr ',' rest_let_bindings
    {
      SET_NODELOC(@1);
      $$ = let($1, $3, $5, $7);
    }
    ;

  /* 表达式列表 */
  expr_list
    : /* empty */
    {
      $$ = nil_Expressions();
    }
    | expr
    {
      $$ = single_Expressions($1);
    }
    | expr_list ',' expr
    {
      $$ = append_Expressions($1, single_Expressions($3));
    }
  ;

  /* 表达式块列表 */
  expr_block_list
    : expr ';'
    {
      $$ = single_Expressions($1);
    }
    | expr_block_list expr ';'
    {
      $$ = append_Expressions($1, single_Expressions($2));
    }
  ;

  /* case分支列表 */
  case_list
    : case_branch
    {
      $$ = single_Cases($1);
    }
    | case_list case_branch
    {
      $$ = append_Cases($1, single_Cases($2));
    }
  ;

  /* 单个case分支 */
  case_branch : OBJECTID ':' type DARROW expr ';'
    {
      SET_NODELOC(@1);
      $$ = branch($1, $3, $5);
    }
  ;
  
  %%
  
  /* This function is called automatically when Bison detects a parse error. */
  void yyerror(char *s)
  {
    extern int curr_lineno;
    
    cerr << "\"" << curr_filename << "\", line " << curr_lineno << ": " \
    << s << " at or near ";
    print_cool_token(yychar);
    cerr << endl;
    omerrs++;
    
    if(omerrs>50) {fprintf(stdout, "More than 50 errors\n"); exit(1);}
  }

  /* 在文件末尾定义必要的全局变量 */
  Symbol self_sym = idtable.add_string("self");
  