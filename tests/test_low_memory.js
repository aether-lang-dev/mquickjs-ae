/* Low-memory / out-of-memory behaviour. Run with a small heap, e.g.
   mqjs --memory-limit 32k tests/test_low_memory.js
   Running out of memory must raise a catchable InternalError (never crash),
   and the engine must keep working once the garbage is released.
   The first public upstream release (ebae6ce) failed this: it could not
   recover after a caught OOM. 7ea5399 (the port's upstream base) passes. */
function check(cond, msg) {
    if (!cond)
        throw Error("test_low_memory: " + msg);
}

function exhaust(make) {
    var keep = [], err = null;
    try {
        for (;;)
            keep.push(make(keep.length));
    } catch (e) {
        err = e;
    }
    var n = keep.length;
    keep = null;                /* release everything for the next round */
    return { err: err, n: n };
}

function is_oom(e) {
    return e instanceof InternalError && ("" + e).indexOf("out of memory") >= 0;
}

var kinds = [
    function (i) { return { a: i, b: i + 1 }; },          /* objects */
    function (i) { return [i, i, i, i]; },                 /* arrays */
    function (i) { return "s" + i + "-" + i; },            /* strings */
    function (i) { return function () { return i; }; },    /* closures */
    function (i) { return i + 0.5; },                      /* boxed floats */
];

var round, k, r, first = [];
for (round = 0; round < 3; round++) {
    for (k = 0; k < kinds.length; k++) {
        r = exhaust(kinds[k]);
        check(is_oom(r.err), "kind " + k + " round " + round + ": got " + r.err);
        check(r.n > 0, "kind " + k + " allocated nothing");
        if (round == 0)
            first[k] = r.n;
        /* after a full release we must get roughly as far again: a leak
           would shrink the reachable count round after round */
        check(r.n * 2 > first[k], "kind " + k + " round " + round +
              ": only " + r.n + " vs " + first[k] + " (leak?)");
    }
}

/* one huge string allocation fails cleanly */
var big = "x", err = null;
try {
    for (;;)
        big = big + big;
} catch (e2) {
    err = e2;
}
check(is_oom(err), "string doubling: " + err);
big = null;

/* deep recursion fails cleanly (stack overflow or out of memory) */
function rec(n) { return n == 0 ? 0 : 1 + rec(n - 1); }
err = null;
try {
    rec(1000000);
} catch (e3) {
    err = e3;
}
check(err instanceof InternalError, "deep recursion: " + err);

/* still fully functional afterwards */
var s = 0, i;
for (i = 0; i < 1000; i++)
    s += [i, i * 2].length;
check(s == 2000, "post-OOM arithmetic");
check(JSON.stringify({ a: [1, "b"] }) == '{"a":[1,"b"]}', "post-OOM JSON");
