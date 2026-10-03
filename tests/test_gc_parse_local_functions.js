/* Regression: a compacting GC while a nested function is being parsed.
   js_parse_local_functions must keep the child function rooted across its
   parse (upstream's JS_PUSH_VALUE). The port did not, so a GC there left a
   stale function on the parser stack, and compute_stack_size read a null
   byte_code and segfaulted. Run under a small --memory-limit so GCs land
   inside the parse; each source differs so nothing is cached. */
var junk = [];
var total = 0;
for (var i = 0; i < 300; i++) {
    /* keep the heap busy so allocations during parsing trigger GCs */
    junk.push({ a: i, b: "s" + i, c: [i, i + 1, i + 2] });
    if (junk.length > 200)
        junk = [];
    var src = "(function () {" +
        " function f1(x) { function g(y) { return y + " + i + "; } return g(x) * 2; }" +
        " function f2(x) { var h = function (z) { return z - 1; }; return h(x) + f1(x); }" +
        " function f3() { return [1, 2, 3].map(function (v) { return v * " + (i % 7) + "; }).length; }" +
        " return f1(1) + f2(2) + f3();" +
        " })()";
    total += (1, eval)(src);   /* indirect: mquickjs has no direct eval */
}
/* f1(1) = 2*(1+i), f2(2) = 1 + 2*(2+i), f3() = 3 */
var expect = 0;
for (var i = 0; i < 300; i++)
    expect += 2 * (1 + i) + 1 + 2 * (2 + i) + 3;
if (total !== expect) {
    throw Error("total " + total + ", expected " + expect);
}
print("test_gc_parse_local_functions: ok");
