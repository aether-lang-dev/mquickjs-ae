/* Differential corpus: number <-> string conversions. Deterministic output,
   compared line-for-line between this build and upstream C mquickjs by
   scripts/diff-upstream.sh. Exercises dtoa.c (formatting, all radices,
   fixed/precision/exponential modes) and atod (parsing). */
var seed = 0x2545F491;
function rnd32() {               /* xorshift32, deterministic */
    seed ^= seed << 13; seed >>>= 0;
    seed ^= seed >>> 17;
    seed ^= seed << 5;  seed >>>= 0;
    return seed;
}
var buf = new ArrayBuffer(8), f64 = new Float64Array(buf), u32 = new Uint32Array(buf);
function rnd_double() {          /* any bit pattern: subnormals, huge, tiny */
    u32[0] = rnd32(); u32[1] = rnd32();
    return f64[0];
}
function rnd_nice() {            /* "human" numbers with few digits */
    var m = (rnd32() % 2000001) - 1000000, e = (rnd32() % 41) - 20;
    return m * Math.pow(10, e);
}
function out(s) { console.log(s); }

var specials = [0, -0, 1, -1, 0.1, 0.2, 0.3, 1/3, 2/3, 0.5, 1.5, 2.5, -2.5,
    123.456, 1e21, 1e-7, 1e-6, 123e-20, 5e-324, 2.2250738585072014e-308,
    1.7976931348623157e308, 9007199254740991, 9007199254740993, 4294967295,
    4294967296, 2147483647, -2147483648, Infinity, -Infinity, NaN,
    0.000001, 1e300, 1.0000000000000002, 0.9999999999999999, 100, 1e100];

var i, j, x, radix, n;
for (i = 0; i < specials.length + 3000; i++) {
    x = i < specials.length ? specials[i] : (i & 1 ? rnd_double() : rnd_nice());
    out("v " + x + " | " + String(x) + " | " + JSON.stringify(x));
    for (radix = 2; radix <= 36; radix += (radix < 10 ? 1 : 7))
        out("r" + radix + " " + x.toString(radix));
    if (isFinite(x) && Math.abs(x) < 1e21) {
        for (n = 0; n <= 20; n += 5)
            out("f" + n + " " + x.toFixed(n));
    }
    if (isFinite(x)) {
        for (n = 1; n <= 21; n += 4)
            out("p" + n + " " + x.toPrecision(n) + " e" + (n - 1) + " " + x.toExponential(n - 1));
        out("e " + x.toExponential());
    }
    /* parsing round trips */
    out("rt " + (Number(String(x)) === x || (x !== x)) + " " + parseFloat(x.toString()));
}

var strs = ["", " ", "0", "-0", "00", "0x1f", "0X1F", "0b101", "0o17", "017",
    "1e3", "1E-3", ".5", "5.", "+.5e+2", "-.5e-2", "1_000", "Infinity", "-Infinity",
    "infinity", "NaN", "1e1000", "-1e1000", "1e-1000", "  12  ", "\t\n12\n", "12abc",
    "abc", "0.0000000000000000000000000000001", "123456789012345678901234567890",
    "9007199254740993", "4.9406564584124654e-324", "2.4703282292062327e-324",
    "2.4703282292062328e-324", "1.7976931348623158e308", "1.7976931348623159e308"];
for (i = 0; i < strs.length; i++) {
    x = strs[i];
    out("s " + JSON.stringify(x) + " N=" + Number(x) + " pF=" + parseFloat(x) +
        " pI=" + parseInt(x) + " pI16=" + parseInt(x, 16) + " pI2=" + parseInt(x, 2) +
        " pI36=" + parseInt(x, 36));
}
for (i = 0; i < 500; i++) {          /* random digit strings */
    var s = "", len = 1 + rnd32() % 25;
    for (j = 0; j < len; j++)
        s += "0123456789.e-+"[rnd32() % 14];
    out("g " + s + " " + Number(s) + " " + parseFloat(s));
}
