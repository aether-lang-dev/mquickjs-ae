/* Regression: the VM stores short-int results zero-extended (upstream does
   `sp[1] = (uint32_t)r`), so every decode must truncate to int before the
   arithmetic shift (JS_VALUE_GET_INT). coerce, typed-array stores, array
   indexing and for-of decoded with a 64-bit shift, turning v-5 into
   2147483643 (wrong typed-array data, Octane NavierStokes/Mandreel). */
function check(cond, msg) {
    if (!cond)
        throw Error("test_tagged_int: " + msg);
}
var z = 0, n = z - 5;                 /* a computed (not literal) negative int */
var i32 = new Int32Array(1), f64 = new Float64Array(1), f32 = new Float32Array(1);
var i16 = new Int16Array(1), u8 = new Uint8Array(1);
i32[0] = n; check(i32[0] === -5, "Int32Array store " + i32[0]);
f64[0] = n; check(f64[0] === -5, "Float64Array store " + f64[0]);
f32[0] = n; check(f32[0] === -5, "Float32Array store " + f32[0]);
i16[0] = n; check(i16[0] === -5, "Int16Array store " + i16[0]);
u8[0] = n;  check(u8[0] === 251, "Uint8Array store wraps " + u8[0]);
check((z - 1) * 3 === -3 && -(z + 7) === -7, "arith");
check(Math.max(n, -9) === -5 && Math.min(n, 9) === -5, "Math.max/min");
check(String(n) === "-5" && n.toString(2) === "-101", "toString");
check((n >>> 0) === 4294967291 && (n | 0) === -5, "ToUint32/ToInt32");
check(n.toFixed(1) === "-5.0", "toFixed");
var a = [10, 20, 30];
check(a[z - 1] === undefined && a[z + 1] === 20, "array index");
check("abc".charAt(z + 1) === "b" && "abc".substring(z - 2, z + 2) === "ab", "string index");
check(parseInt("ff", z + 16) === 255, "radix arg");
var s = 0, x;
for (x of [z - 1, z - 2]) s += x;
check(s === -3, "for-of");

/* Negative indices: idx is uint32_t upstream, so a negative index must never
   reach tab[idx] (the port read/wrote the word before the array: a[-1]
   returned header garbage and a[-1] = v corrupted the heap). Reads give
   undefined; writes throw "invalid array subscript", as upstream. */
function subscript_throws(f) {
    try { f(); } catch (e) { return ("" + e).indexOf("invalid array subscript") >= 0; }
    return false;
}
var b = [10, 20, 30], t = new Int8Array(2), m = z - 1;
check(b[-1] === undefined && b[m] === undefined && b[m - 5] === undefined, "negative array read");
check(t[-1] === undefined && t[m] === undefined, "negative typed array read");
check(subscript_throws(function () { b[-1] = 99; }), "literal negative array write throws");
check(subscript_throws(function () { b[m] = 99; }), "computed negative array write throws");
check(subscript_throws(function () { t[m] = 5; }), "negative typed array write throws");
check(JSON.stringify(b) === "[10,20,30]" && b.length === 3, "array untouched");
check(t[0] === 0 && t[1] === 0, "typed array untouched");
