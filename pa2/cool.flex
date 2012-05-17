/*
 *  The scanner definition for COOL.
 */

/*
 *  Stuff enclosed in %{ %} in the first section is copied verbatim to the
 *  output, so headers and global definitions are placed here to be visible
 * to the code in the file.  Don't remove anything that was here initially
 */
%{
#include <cool-parse.h>
#include <stringtab.h>
#include <utilities.h>

/* The compiler assumes these identifiers. */
#define yylval cool_yylval
#define yylex  cool_yylex

/* Max size of string constants */
#define MAX_STR_CONST 1025
#define YY_NO_UNPUT   /* keep g++ happy */

extern FILE *fin; /* we read from this file */

/* define YY_INPUT so we read from the FILE fin:
 * This change makes it possible to use this scanner in
 * the Cool compiler.
 */
#undef YY_INPUT
#define YY_INPUT(buf,result,max_size) \
	if ( (result = fread( (char*)buf, sizeof(char), max_size, fin)) < 0) \
		YY_FATAL_ERROR( "read() in flex scanner failed");

char string_buf[MAX_STR_CONST]; /* to assemble string constants */
char *string_buf_ptr;

extern int curr_lineno;
extern int verbose_flag;

extern YYSTYPE cool_yylval;

/*
 *  Add Your own definitions here
 */

#define NEWLINE curr_lineno++

// text buffer
void append_to_text_token_buffer(char *text, int len);
char *last_text_token = NULL;
int last_text_token_len = 0;
int last_text_token_buffer_size = 0;

bool suppress_string_for_error = false;

int comment_nesting_level = 0;


%}

/*
 * Define names for regular expressions here.
 */

SPACE           [ \r\f\t\v]+
SELF            [:@,;(){}=<~/\-\*\+\.]

/* States */

%s comment
%s string
%s s_esc

%%

 /*
  *  Nested comments
  */

<INITIAL>\(\*           { comment_nesting_level++; BEGIN(comment); }
<comment>\(\*           { comment_nesting_level++; }
<comment>\*\)           { comment_nesting_level--; if (comment_nesting_level < 1) { BEGIN(0); } }
<comment>\n             { NEWLINE; }
<comment><<EOF>>        { cool_yylval.error_msg = "EOF in comment"; BEGIN(0); return ERROR; }
<comment>.              { /* no-op, ignore everything in comment */ }
<INITIAL>\*\)           { cool_yylval.error_msg = "Unmatched *)"; return ERROR; }

<INITIAL>--.*           { /* no-op, comment to EOL */ }

 /*
  *  The multiple-character operators.
  */
<INITIAL>=>     		{ return DARROW; }
<INITIAL><=     		{ return LE; }
<INITIAL><-     		{ return ASSIGN; }

 /*
  * Keywords are case-insensitive except for the values true and false,
  * which must begin with a lower-case letter.
  */

<INITIAL>(?i:class)      { return CLASS; }
<INITIAL>(?i:else)       { return ELSE; }
<INITIAL>(?i:fi)         { return FI; }
<INITIAL>(?i:if)         { return IF; }
<INITIAL>(?i:in)         { return IN; }
<INITIAL>(?i:inherits)   { return INHERITS; }
<INITIAL>(?i:let)        { return LET; }
<INITIAL>(?i:loop)       { return LOOP; }
<INITIAL>(?i:pool)       { return POOL; }
<INITIAL>(?i:then)       { return THEN; }
<INITIAL>(?i:while)      { return WHILE; }
<INITIAL>(?i:case)       { return CASE; }
<INITIAL>(?i:esac)       { return ESAC; }
<INITIAL>(?i:of)         { return OF; }
<INITIAL>(?i:new)        { return NEW; }
<INITIAL>(?i:isvoid)     { return ISVOID; }
<INITIAL>(?i:not)        { return NOT; }

<INITIAL>f(?i:alse)      {
                    cool_yylval.boolean = 0;
                    return BOOL_CONST;
                }
<INITIAL>t(?i:rue)       {
                    cool_yylval.boolean = 1;
                    return BOOL_CONST;
                }

<INITIAL>[a-z][a-zA-Z0-9_]* { cool_yylval.symbol = inttable.add_string(yytext); return OBJECTID; }
<INITIAL>[A-Z][a-zA-Z0-9_]* { cool_yylval.symbol = inttable.add_string(yytext); return TYPEID; }

<INITIAL>{SELF}         { return *(yytext); /* shady as hell, but seems to be what's expected, so wtf. */ }

 /*
  *  String constants (C syntax)
  *  Escape sequence \c is accepted for all characters c. Except for 
  *  \n \t \b \f, the result is c.
  *
  */

<INITIAL>[0-9]+          {
                    cool_yylval.symbol = inttable.add_string(yytext);
                    return INT_CONST;
                }

<INITIAL>\"     {
                    BEGIN(string);
                }
<string>[^\\"\n\x00]  { append_to_text_token_buffer(yytext, yyleng); /* should always be 1 byte but w/e */ }
<string>\n      {
                    BEGIN(0);
                    cool_yylval.error_msg = "Unterminated string constant";
                    NEWLINE;
                    if (last_text_token != NULL) free(last_text_token);
                    last_text_token = NULL;
                    last_text_token_len = 0; last_text_token_buffer_size = 0;
                    return ERROR; }
<string>\"      {
                    BEGIN(0);
                    if (suppress_string_for_error) {
                        if (last_text_token != NULL) free(last_text_token);
                        last_text_token = NULL;
                        last_text_token_len = 0; last_text_token_buffer_size = 0;
                    } else {
                        if (last_text_token == NULL) {
                            cool_yylval.symbol = inttable.add_string(""); // empty buffer means empty string, which is fine
                        } else {
                            cool_yylval.symbol = inttable.add_string(last_text_token);
                            free(last_text_token); last_text_token = NULL;
                            last_text_token_len = 0; last_text_token_buffer_size = 0;
                        }
                        return STR_CONST;
                    }
                }
<string,s_esc><<EOF>> { cool_yylval.error_msg = "EOF in string constant"; BEGIN(0); return ERROR; }
<string>\x00    { suppress_string_for_error = true; cool_yylval.error_msg = "String contains null character."; return ERROR; }
<s_esc>\x00    { suppress_string_for_error = true; cool_yylval.error_msg = "String contains escaped null character."; return ERROR; }
                
   /* deal with escapes */
<string>\\      { BEGIN(s_esc); }
<s_esc>\n       { NEWLINE; append_to_text_token_buffer("\n", 1); BEGIN(string); }
<s_esc>n        { append_to_text_token_buffer("\n", 1); BEGIN(string); }
<s_esc>t        { append_to_text_token_buffer("\t", 1); BEGIN(string); }
<s_esc>b        { append_to_text_token_buffer("\b", 1); BEGIN(string); }
<s_esc>f        { append_to_text_token_buffer("\f", 1); BEGIN(string); }
<s_esc>\\       { append_to_text_token_buffer("\\", 1); BEGIN(string); }
<s_esc>.        { append_to_text_token_buffer(yytext, yyleng); BEGIN(string); }

                /*{
                    cool_yylval.symbol = inttable.add_string(yytext);
                    return STR_CONST;
                }*/

<INITIAL>{SPACE} { /* do nothing */ }
<INITIAL>\n     { NEWLINE; }
.               { cool_yylval.error_msg = yytext; return ERROR; }

%%

void append_to_text_token_buffer(char *text, int len) {
    // TODO: figure out how to not leak memory
    // allocate memory if necessary
    if (last_text_token == NULL) {
        last_text_token_buffer_size = 1024;
        last_text_token = (char *)calloc(1, 1024);
    }
    // reallocate memory if necessary
    if ((last_text_token_len + len) >= last_text_token_buffer_size) { // >= to make sure there's always at least 1 byte padding for null termination
        last_text_token_buffer_size += 1024;
        last_text_token = (char *)realloc(last_text_token, last_text_token_buffer_size);
    }
    *(last_text_token + last_text_token_len) = *text; // write data
    //for (int i = 0; i <= len; i++) {
    //    *(last_text_token + last_text_token_len + i) = *(text+i);
    //}
    last_text_token_len += len;
}





