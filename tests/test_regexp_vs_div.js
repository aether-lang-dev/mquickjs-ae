/* Regression: after ++/-- a '/' is division; after *= or /= a regexp may
   start. The port once had TOK_DEC/TOK_INC wrong (132/133 = *=, /=). */
function check(cond, msg) {
    if (!cond)
        throw Error("test_regexp_vs_div: " + msg);
}
var a = 4, b, x = 2;
b = a++ / 2;
check(b === 2 && a === 5, "a++ / 2");
b = a-- / 5;
check(b === 1 && a === 4, "a-- / 5");
x *= /ab/.source.length;
check(x === 4, "x *= /re/");
x /= /abcd/.source.length;
check(x === 1, "x /= /re/");
