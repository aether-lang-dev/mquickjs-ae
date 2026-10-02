/* Regression: writing a property of a built-in object whose properties live
   in the stdlib ROM (read-only memory) must go through the slow path that
   copies them to RAM. The VM's put_field fast path lacked upstream's
   JS_IS_ROM_PTR check and wrote in place -> SIGSEGV (Octane's base.js does
   Math.random = ...). */
function check(cond, msg) {
    if (!cond)
        throw Error("test_rom_write: " + msg);
}
function f() { return 42; }
Math.random = f;
check(Math.random() === 42, "Math.random override");
Math.PI2 = 6;                       /* add to a ROM object */
check(Math.PI2 === 6, "add prop to ROM object");
JSON.foo = 1; JSON.foo = 2;         /* create then overwrite (fast path) */
check(JSON.foo === 2, "overwrite after ROM->RAM");
var i, o = Object;
for (i = 0; i < 1000; i++)
    o.keys2 = i;                    /* repeated fast-path writes */
check(Object.keys2 === 999, "repeated writes");
check(typeof Math.floor === "function" && Math.floor(2.5) === 2, "other ROM props intact");
