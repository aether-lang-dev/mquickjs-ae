/* Regression: enough allocation to make the compacting GC move objects
   (including the running function's bytecode) while the VM is inside a
   slow-path call. The VM must re-derive b/pc after such calls (upstream's
   SAVE()/RESTORE()); before the fix these loops segfaulted or hit
   "unported opcode 0". Throws, so mqjs exits non-zero, on any mismatch. */

function check(cond, msg) {
    if (!cond)
        throw Error("test_gc_relocation: " + msg);
}

function named_props(n) {
    var o, j;
    for (j = 0; j < n; j++) {
        o = {};
        o.a = 1; o.b = 2; o.c = 3; o.d = 4; o.e = 5;
    }
    check(o.a + o.b + o.c + o.d + o.e == 15, "named props");
}

function indexed_props(n) {
    var o, i, j;
    for (j = 0; j < n; j++) {
        o = {};
        for (i = 0; i < 10; i++)
            o[i] = i;
    }
    check(o[9] == 9, "indexed props");
}

function delete_props(n) {
    var o, j;
    for (j = 0; j < n; j++) {
        o = { a: 1, b: 2, c: 3 };
        delete o.a;
        delete o.b;
    }
    check(o.c == 3 && o.a === undefined, "delete props");
}

function string_build(n) {
    var s = "", j;
    for (j = 0; j < n; j++)
        s += "x";
    check(s.length == n, "string build");
}

function for_in(n) {
    var o = { a: 1, b: 2, c: 3 }, k, j, cnt = 0;
    for (j = 0; j < n; j++) {
        for (k in o)
            cnt++;
    }
    check(cnt == 3 * n, "for in");
}

named_props(200000);
indexed_props(200000);
delete_props(200000);
string_build(100000);
for_in(100000);
