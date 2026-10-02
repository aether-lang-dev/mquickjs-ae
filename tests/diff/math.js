/* Differential corpus: Math functions and arithmetic over awkward doubles
   (exercises libm.c). Output must match upstream C bit for bit. */
var seed = 0x9E3779B9;
function rnd32() {
    seed ^= seed << 13; seed >>>= 0;
    seed ^= seed >>> 17;
    seed ^= seed << 5;  seed >>>= 0;
    return seed;
}
var buf = new ArrayBuffer(8), f64 = new Float64Array(buf), u32 = new Uint32Array(buf);
function rnd_double() { u32[0] = rnd32(); u32[1] = rnd32(); return f64[0]; }
function rnd_range() { return ((rnd32() / 4294967296) - 0.5) * Math.pow(2, (rnd32() % 80) - 20); }
function hex(x) { f64[0] = x; return u32[1].toString(16) + ":" + u32[0].toString(16); }

var fns1 = ["abs", "floor", "ceil", "round", "trunc", "sqrt", "sin", "cos", "tan",
            "asin", "acos", "atan", "exp", "log", "log2", "log10", "fround", "sign",
            "clz32"];
var fns2 = ["atan2", "pow", "max", "min", "imul"];
var specials = [0, -0, 1, -1, 0.5, -0.5, 1.5, -1.5, 2.5, -2.5, Math.PI, Math.E,
    1e-300, -1e-300, 5e-324, 1e300, 1e22, 1e23, 2147483648, -2147483649,
    Infinity, -Infinity, NaN, 0.49999999999999994, 4503599627370496.5,
    709.782712893384, -745.1332191019411, 1e-8];
var i, k, x, y, xs = specials.slice();
for (i = 0; i < 1500; i++)
    xs.push(i & 1 ? rnd_double() : rnd_range());
for (i = 0; i < xs.length; i++) {
    x = xs[i];
    var line = "x " + hex(x);
    for (k = 0; k < fns1.length; k++) {
        if (typeof Math[fns1[k]] == "function")
            line += " " + fns1[k] + "=" + hex(Math[fns1[k]](x));
    }
    y = xs[(i * 7 + 3) % xs.length];
    for (k = 0; k < fns2.length; k++) {
        if (typeof Math[fns2[k]] == "function")
            line += " " + fns2[k] + "=" + hex(Math[fns2[k]](x, y));
    }
    line += " add=" + hex(x + y) + " mul=" + hex(x * y) + " div=" + hex(x / y) +
            " mod=" + hex(x % y) + " i32=" + (x | 0) + " u32=" + (x >>> 0);
    console.log(line);
}
